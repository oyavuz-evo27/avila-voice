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
    /// Fired when capture is genuinely lost (device gone, rebuild failed).
    var onConfigurationChange: (@Sendable () -> Void)?

    private(set) var currentFileURL: URL?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false)!

    /// Ask the output for our target format directly — no converter needed when
    /// the capture stack honors it (it resamples internally).
    private static func makeOutputSettings() -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
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
        if session != nil { _ = stop() }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avila-\(UUID().uuidString).wav")
        file = try AVAudioFile(forWriting: url,
                               settings: Self.targetFormat.settings,
                               commonFormat: .pcmFormatFloat32,
                               interleaved: false)
        currentFileURL = url
        converter = nil

        do {
            try buildAndStartSession()
        } catch {
            file = nil
            currentFileURL = nil
            try? FileManager.default.removeItem(at: url)
            throw error
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

    private func buildAndStartSession() throws {
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
        newSession.startRunning()
        DebugLog.log("recording started — capture device '\(device.localizedName)'")
    }

    /// Stops the recording and returns (file, duration in seconds).
    func stop() -> (url: URL, duration: Double)? {
        teardown()
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

    private func teardown() {
        stallTimer?.invalidate()
        stallTimer = nil
        if let session {
            self.session = nil
            // Detach the delegate synchronously so no stray buffer can reach a
            // future recording's file, then stop on a background queue —
            // stopRunning blocks for hundreds of ms and would freeze the pill's
            // shrink animation if run on the main thread.
            for output in session.outputs {
                (output as? AVCaptureAudioDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            }
            DispatchQueue.global(qos: .userInitiated).async {
                session.stopRunning()
            }
        }
        if startedAt != nil {
            DebugLog.log("recording stopped — buffers: \(bufferCount), peak level: \(String(format: "%.3f", peakLevel))")
        }
    }

    // MARK: - Stall watchdog

    private func checkStall() {
        guard file != nil, let startedAt else { return }
        stallTicks += 1
        if stallTicks % 4 == 0 {
            DebugLog.log("capture status — buffers: \(bufferCount), peak level: \(String(format: "%.3f", peakLevel)), session running: \(session?.isRunning == true)")
        }
        let reference = lastBufferAt ?? startedAt
        guard Date.now.timeIntervalSince(reference) > 1.2 else { return }
        DebugLog.log("audio input stalled (\(lastBufferAt == nil ? "no buffers since start" : "buffers stopped"), session running: \(session?.isRunning == true))")
        if !didAttemptRecovery {
            didAttemptRecovery = true
            session?.stopRunning()
            session = nil
            if (try? buildAndStartSession()) != nil {
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
        lastBufferAt = .now
        bufferCount += 1
        publishLevel(of: buffer)
        append(buffer)
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
        guard let file else { return }
        // Fast path: the capture output already delivers our target format.
        if buffer.format.sampleRate == Self.targetFormat.sampleRate,
           buffer.format.channelCount == 1,
           buffer.format.commonFormat == .pcmFormatFloat32 {
            try? file.write(from: buffer)
            return
        }
        if converter == nil {
            converter = AVAudioConverter(from: buffer.format, to: Self.targetFormat)
        }
        guard let converter else { return }
        let ratio = Self.targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: Self.targetFormat,
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
