import AVFAudio
import AudioToolbox
import Foundation

/// Captures microphone audio with AVAudioEngine, publishes the input level for the
/// waveform, and returns the recording as a 16 kHz mono WAV file for the STT engines.
final class AudioRecorder: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var startedAt: Date?

    /// Called on an audio thread with the current input level (0…1).
    var onLevel: (@Sendable (Float) -> Void)?

    private(set) var currentFileURL: URL?

    static let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                            sampleRate: 16_000,
                                            channels: 1,
                                            interleaved: false)!

    func start() throws {
        let input = engine.inputNode
        applyPreferredDevice(to: input)
        let inputFormat = input.outputFormat(forBus: 0)

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
            self.publishLevel(of: buffer)
            self.append(buffer)
        }

        engine.prepare()
        try engine.start()
        startedAt = .now
    }

    /// Stops the recording and returns (file, duration in seconds).
    func stop() -> (url: URL, duration: Double)? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
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
