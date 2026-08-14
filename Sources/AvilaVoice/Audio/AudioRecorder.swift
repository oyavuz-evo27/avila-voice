import AVFAudio
import AudioToolbox
import Foundation

enum RecorderError: Error, LocalizedError {
    case noInputDevice

    var errorDescription: String? { L("error.noMicrophone") }
}

/// Captures microphone audio with AVAudioEngine, publishes the input level for the
/// waveform, and returns the recording as a 16 kHz mono WAV file for the STT engines.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var startedAt: Date?
    private var tapInstalled = false
    private var configObserver: NSObjectProtocol?
    private var lastBufferAt: Date?
    private var stallTimer: Timer?
    private var didAttemptRecovery = false

    /// Called on an audio thread with the current input level (0…1).
    var onLevel: (@Sendable (Float) -> Void)?
    /// Fired when the audio device configuration changes mid-recording
    /// (microphone unplugged/switched) — the engine stops silently in that case.
    var onConfigurationChange: (@Sendable () -> Void)?

    private(set) var currentFileURL: URL?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false)!

    func start() throws {
        // Defensive: never install a second tap (that would raise an ObjC exception).
        if tapInstalled || engine.isRunning {
            teardown()
        }

        let input = engine.inputNode
        applyPreferredDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice // no input device: 0 Hz format would crash installTap
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avila-\(UUID().uuidString).wav")
        let file = try AVAudioFile(forWriting: url,
                                   settings: Self.targetFormat.settings,
                                   commonFormat: .pcmFormatFloat32,
                                   interleaved: false)
        self.file = file
        self.currentFileURL = url
        self.converter = AVAudioConverter(from: inputFormat, to: Self.targetFormat)

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.lastBufferAt = .now
            self.publishLevel(of: buffer)
            self.append(buffer)
        }
        tapInstalled = true

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.handleConfigurationChange()
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            self.file = nil
            self.converter = nil
            self.currentFileURL = nil
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        startedAt = .now
        lastBufferAt = nil
        didAttemptRecovery = false
        NSLog("AvilaVoice: recording started — input %.0f Hz, %d ch, device UID '%@'",
              inputFormat.sampleRate, inputFormat.channelCount,
              UserDefaults.standard.string(forKey: "audio.inputDeviceUID") ?? "default")

        // Stall watchdog: an engine can keep claiming isRunning while the input
        // silently stops delivering (typical during Bluetooth profile switches).
        stallTimer?.invalidate()
        let timer = Timer(timeInterval: 0.7, repeats: true) { [weak self] _ in
            self?.checkStall()
        }
        RunLoop.main.add(timer, forMode: .common)
        stallTimer = timer
    }

    private func checkStall() {
        guard file != nil, let startedAt else { return }
        let reference = lastBufferAt ?? startedAt
        guard Date.now.timeIntervalSince(reference) > 1.2 else { return }
        NSLog("AvilaVoice: audio input stalled (%@, engine running: %d)",
              lastBufferAt == nil ? "no buffers since start" : "buffers stopped",
              engine.isRunning ? 1 : 0)
        if !didAttemptRecovery, rebuildCaptureChain() {
            didAttemptRecovery = true
            lastBufferAt = .now // give the rebuilt chain a fresh grace period
            return
        }
        onConfigurationChange?()
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

    /// Configuration changes fire for benign reasons (engine start-up, format
    /// renegotiation) and for real ones (AirPods dropping to HFP telephony mode,
    /// microphone unplugged). Strategy: if the engine stopped mid-recording, rebuild
    /// the capture chain once and keep appending to the same file — only when that
    /// fails is the recording declared lost.
    private func handleConfigurationChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.file != nil else { return }  // not recording
            NSLog("AvilaVoice: audio configuration changed (engine running: %d)",
                  self.engine.isRunning ? 1 : 0)
            if self.engine.isRunning { return }               // benign renegotiation
            if self.rebuildCaptureChain() {
                NSLog("AvilaVoice: capture chain rebuilt, recording continues")
                return
            }
            self.onConfigurationChange?()
        }
    }

    private func rebuildCaptureChain() -> Bool {
        let input = engine.inputNode
        if tapInstalled {
            input.removeTap(onBus: 0)
            tapInstalled = false
        }
        applyPreferredDevice(to: input)
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { return false }
        converter = AVAudioConverter(from: format, to: Self.targetFormat)
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, _ in
            guard let self else { return }
            self.publishLevel(of: buffer)
            self.append(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do {
            try engine.start()
            NSLog("AvilaVoice: rebuilt chain — input now %.0f Hz, %d ch",
                  format.sampleRate, format.channelCount)
            return true
        } catch {
            NSLog("AvilaVoice: capture chain rebuild failed — %@", error.localizedDescription)
            return false
        }
    }

    private func teardown() {
        stallTimer?.invalidate()
        stallTimer = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        if engine.isRunning {
            engine.stop()
        }
        if let configObserver {
            NotificationCenter.default.removeObserver(configObserver)
            self.configObserver = nil
        }
    }

    /// Routes the input node to the microphone chosen in settings (empty = system default).
    private func applyPreferredDevice(to input: AVAudioInputNode) {
        guard let uid = UserDefaults.standard.string(forKey: "audio.inputDeviceUID"),
              !uid.isEmpty,
              let deviceID = AudioDeviceManager.deviceID(forUID: uid),
              let unit = input.audioUnit else { return }
        var device = deviceID
        AudioUnitSetProperty(unit,
                             kAudioOutputUnitProperty_CurrentDevice,
                             kAudioUnitScope_Global, 0,
                             &device,
                             UInt32(MemoryLayout<AudioDeviceID>.size))
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
        onLevel?(level)
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let file, let converter else { return }
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
