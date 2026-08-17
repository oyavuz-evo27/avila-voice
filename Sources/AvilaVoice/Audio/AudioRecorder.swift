import AVFoundation
import CoreMedia
import Foundation

enum RecorderError: Error, LocalizedError {
    case noInputDevice

    var errorDescription: String? { L("error.noMicrophone") }
}

/// Captures microphone audio with AVCaptureSession — first-class device selection.
/// (AVAudioEngine's AUHAL rerouting proved unreliable on macOS 26: it reports
/// success on aggregate devices and then never delivers a single buffer.)
/// Publishes the input level for the waveform and writes a 16 kHz mono WAV for
/// the STT engines.
final class AudioRecorder: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private var session: AVCaptureSession?
    /// Device the warm session was built for ("" = system default).
    private var sessionDeviceUID: String?
    /// True only while a dictation writes to the file — the warm session between
    /// dictations drops every buffer unprocessed.
    private var isWriting = false
    private var idleTimer: Timer?
    /// Rolling buffer of the most recent audio while the session is warm but idle.
    /// Prepended to the next dictation so word ONSETS survive even when the user
    /// starts speaking at (or slightly before) the hotkey press. captureQueue only.
    private var preRoll: [AVAudioPCMBuffer] = []
    private var preRollSeconds: Double = 0
    static let preRollWindow: Double = 0.6
    /// How long the capture session stays warm after a dictation. Trade-off: the
    /// macOS microphone indicator stays on during this window, but the next
    /// dictation starts instantly and loses no word onsets to startRunning.
    static let warmWindow: TimeInterval = 25
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var startedAt: Date?
    private var lastBufferAt: Date?
    private var stallTimer: Timer?
    private var didAttemptRecovery = false
    private var bufferCount = 0
    private var peakLevel: Float = 0
    private var stallTicks = 0
    private var lastLevelEmit = Date.distantPast
    private let captureQueue = DispatchQueue(label: "avila.audio.capture")

    /// Called on an audio thread with the current input level (0…1).
    var onLevel: (@Sendable (Float) -> Void)?
    /// Called on the capture queue with every recorded buffer (incl. pre-roll) —
    /// feeds the live transcriber.
    var onBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?
    /// Fired when capture is genuinely lost (device gone, rebuild failed).
    var onConfigurationChange: (@Sendable () -> Void)?

    private(set) var currentFileURL: URL?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false)!

    /// Float32, but the device's NATIVE sample rate and channel count: forcing an
    /// early 16 kHz downsample before the STT threw away signal the engine's own
    /// (better) converter could have used — a measurable recognition-quality cost.
    private static func makeOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
        ]
    }

    private static func selectedDevice() -> AVCaptureDevice? {
        if let uid = UserDefaults.standard.string(forKey: "audio.inputDeviceUID"),
           !uid.isEmpty {
            if let device = AVCaptureDevice(uniqueID: uid) { return device }
            DebugLog.log("mic: selected device UID '\(uid)' not found — using default")
        }
        return AVCaptureDevice.default(for: .audio)
    }

    // MARK: - Lifecycle

    func start() throws {
        if isWriting { _ = stop() }
        idleTimer?.invalidate()
        idleTimer = nil

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avila-\(UUID().uuidString).wav")
        // The file is created lazily from the FIRST buffer's native format —
        // recordings keep the microphone's full quality end-to-end.
        file = nil
        currentFileURL = url
        converter = nil

        let wantedUID = UserDefaults.standard.string(forKey: "audio.inputDeviceUID") ?? ""
        if let existing = session, existing.isRunning, sessionDeviceUID == wantedUID {
            DebugLog.log("recording started — warm session reused")
        } else {
            shutdownSession()
            do {
                try buildAndStartSession(deviceUID: wantedUID)
            } catch {
                file = nil
                currentFileURL = nil
                try? FileManager.default.removeItem(at: url)
                throw error
            }
        }

        isWriting = true
        // Flush the pre-roll into the fresh file on the capture queue — it runs
        // BEFORE any newly arriving buffer (same serial queue).
        captureQueue.async { [weak self] in
            guard let self else { return }
            if !self.preRoll.isEmpty {
                DebugLog.log(String(format: "pre-roll: prepending %.2f s", self.preRollSeconds))
                for buffered in self.preRoll {
                    self.append(buffered)
                    self.onBuffer?(buffered)
                }
            }
            self.preRoll = []
            self.preRollSeconds = 0
        }
        startedAt = .now
        lastBufferAt = nil
        didAttemptRecovery = false
        bufferCount = 0
        peakLevel = 0
        stallTicks = 0

        stallTimer?.invalidate()
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.checkStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func buildAndStartSession(deviceUID: String) throws {
        guard let device = Self.selectedDevice() else {
            throw RecorderError.noInputDevice
        }
        let newSession = AVCaptureSession()
        let input = try AVCaptureDeviceInput(device: device)
        guard newSession.canAddInput(input) else { throw RecorderError.noInputDevice }
        newSession.addInput(input)

        let output = AVCaptureAudioDataOutput()
        output.audioSettings = Self.makeOutputSettings()
        output.setSampleBufferDelegate(self, queue: captureQueue)
        guard newSession.canAddOutput(output) else { throw RecorderError.noInputDevice }
        newSession.addOutput(output)

        session = newSession
        sessionDeviceUID = deviceUID
        newSession.startRunning()
        DebugLog.log("recording started — capture device '\(device.localizedName)' (cold start)")
    }

    /// Stops the recording and returns (file, duration in seconds).
    /// The capture session stays WARM for `warmWindow` seconds — the next dictation
    /// then starts instantly and loses no word onsets to startRunning.
    func stop() -> (url: URL, duration: Double)? {
        stallTimer?.invalidate()
        stallTimer = nil
        isWriting = false
        scheduleIdleShutdown()
        if startedAt != nil {
            DebugLog.log("recording stopped — buffers: \(bufferCount), peak level: \(String(format: "%.3f", peakLevel))")
        }
        defer {
            file = nil
            converter = nil
            currentFileURL = nil
            startedAt = nil
        }
        guard let url = currentFileURL else { return nil }
        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        return (url, duration)
    }

    func cancel() {
        if let (url, _) = stop() {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func scheduleIdleShutdown() {
        idleTimer?.invalidate()
        let timer = Timer(timeInterval: Self.warmWindow, repeats: false) { [weak self] _ in
            self?.idleShutdownFired()
        }
        RunLoop.main.add(timer, forMode: .common)
        idleTimer = timer
    }

    private func idleShutdownFired() {
        guard !isWriting else { return }
        shutdownSession()
        DebugLog.log("warm capture session released after \(Int(Self.warmWindow)) s idle")
    }

    /// Fully tears the session down. Delegate is detached synchronously so no stray
    /// buffer can reach a future recording's file; stopRunning blocks for hundreds
    /// of ms and therefore runs on a background queue.
    private func shutdownSession() {
        guard let session else { return }
        self.session = nil
        sessionDeviceUID = nil
        for output in session.outputs {
            (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
        }
        DispatchQueue.global(qos: .userInitiated).async {
            session.stopRunning()
        }
    }

    // MARK: - Stall watchdog

    private func checkStall() {
        guard isWriting, file != nil, let startedAt else { return }
        stallTicks += 1
        if stallTicks % 4 == 0 {
            DebugLog.log("capture status — buffers: \(bufferCount), peak level: \(String(format: "%.3f", peakLevel)), session running: \(session?.isRunning == true)")
        }
        let reference = lastBufferAt ?? startedAt
        guard Date.now.timeIntervalSince(reference) > 1.2 else { return }
        DebugLog.log("audio input stalled (\(lastBufferAt == nil ? "no buffers since start" : "buffers stopped"), session running: \(session?.isRunning == true))")
        if !didAttemptRecovery {
            didAttemptRecovery = true
            shutdownSession()
            let uid = UserDefaults.standard.string(forKey: "audio.inputDeviceUID") ?? ""
            if (try? buildAndStartSession(deviceUID: uid)) != nil {
                lastBufferAt = .now // fresh grace period for the rebuilt session
                DebugLog.log("capture session rebuilt")
                return
            }
        }
        onConfigurationChange?()
    }

    // MARK: - Sample delivery

    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let buffer = Self.pcmBuffer(from: sampleBuffer) else { return }
        guard isWriting else {
            // Warm idle window: keep a short rolling pre-roll, drop the rest.
            preRoll.append(buffer)
            preRollSeconds += Double(buffer.frameLength) / buffer.format.sampleRate
            while preRollSeconds > Self.preRollWindow, let first = preRoll.first {
                preRollSeconds -= Double(first.frameLength) / first.format.sampleRate
                preRoll.removeFirst()
            }
            return
        }
        lastBufferAt = .now
        bufferCount += 1
        publishLevel(of: buffer)
        append(buffer)
        onBuffer?(buffer)
    }

    private static func pcmBuffer(from sample: CMSampleBuffer) -> AVAudioPCMBuffer? {
        guard let description = CMSampleBufferGetFormatDescription(sample),
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description),
              let format = AVAudioFormat(streamDescription: asbd) else { return nil }
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
        guard frames > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else {
            return nil
        }
        buffer.frameLength = frames
        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            sample, at: 0, frameCount: Int32(frames),
            into: buffer.mutableAudioBufferList)
        return status == noErr ? buffer : nil
    }

    private func publishLevel(of buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }
        var sum: Float = 0
        for i in 0..<n { sum += data[i] * data[i] }
        let rms = sqrtf(sum / Float(n))
        // Map RMS (~0…0.3 for speech) into 0…1 with a soft curve.
        let level = min(1, powf(rms * 6, 0.7))
        if level > peakLevel { peakLevel = level }
        // Capture buffers can arrive every few ms — the waveform UI only needs
        // ~15 updates/s to look fluid rather than jittery.
        let now = Date.now
        if now.timeIntervalSince(lastLevelEmit) >= 0.06 {
            lastLevelEmit = now
            onLevel?(level)
        }
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        // Lazy file creation in the buffer's native format (capture queue only).
        if file == nil {
            guard let url = currentFileURL else { return }
            file = try? AVAudioFile(forWriting: url,
                                    settings: buffer.format.settings,
                                    commonFormat: buffer.format.commonFormat,
                                    interleaved: buffer.format.isInterleaved)
            if let file {
                DebugLog.log(String(format: "capture format: %.0f Hz, %d ch",
                                    file.processingFormat.sampleRate,
                                    file.processingFormat.channelCount))
            }
        }
        guard let file else { return }
        // Fast path: same format — no conversion, no quality loss.
        if buffer.format == file.processingFormat {
            try? file.write(from: buffer)
            return
        }
        // Fallback (format changed mid-recording after a session rebuild).
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: file.processingFormat)
        }
        guard let converter else { return }
        let ratio = file.processingFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                         frameCapacity: capacity) else { return }
        var fed = false
        converter.convert(to: out, error: nil) { _, status in
            if fed {
                status.pointee = .noDataNow
                return nil
            }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        if out.frameLength > 0 {
            try? file.write(from: out)
        }
    }
}
