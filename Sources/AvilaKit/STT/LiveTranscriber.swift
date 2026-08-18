import Foundation
import Speech
import AVFAudio

/// Streams microphone buffers into SpeechAnalyzer WHILE the user speaks.
/// Volatile results are published live for the pill; on stop the analyzer is
/// finalized and the finished transcript returned — the file-based STT is then
/// unnecessary (fallback only if the live session fails).
public final class LiveTranscriber: @unchecked Sendable {
    public init() {}
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var converter: AVAudioConverter?
    private var analyzerFormat: AVAudioFormat?
    private var finalizedText = ""
    private var volatileText = ""
    private let lock = NSLock()

    /// Called on an arbitrary thread with (finalized + volatile) text.
    public var onPartial: (@Sendable (String) -> Void)?

    /// Starts an analysis session for `locale`. Throws if the locale is unsupported.
    public func start(locale: Locale) async throws {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [.volatileResults],
                                            attributeOptions: [])
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: [transcriber]) else {
            throw TranscriptionError.engineUnavailable(L("error.sttLocale"))
        }
        analyzerFormat = format

        let (stream, continuation) = AsyncStream<AnalyzerInput>.makeStream()
        inputContinuation = continuation
        self.transcriber = transcriber
        self.analyzer = analyzer
        finalizedText = ""
        volatileText = ""

        resultsTask = Task { [weak self] in
            do {
                for try await result in transcriber.results {
                    guard let self else { return }
                    let text = String(result.text.characters)
                    let combined = self.lock.withLock { () -> String in
                        if result.isFinal {
                            self.finalizedText += text
                            self.volatileText = ""
                        } else {
                            self.volatileText = text
                        }
                        return self.finalizedText + self.volatileText
                    }
                    self.onPartial?(combined)
                }
            } catch {
                DebugLog.log("live stt results stream ended with error: \(error.localizedDescription)")
            }
        }
        try await analyzer.start(inputSequence: stream)
        DebugLog.log("live stt started (\(locale.identifier), \(Int(format.sampleRate)) Hz)")
    }

    /// Feed a captured buffer (any format — converted to the analyzer's format).
    public func append(_ buffer: AVAudioPCMBuffer) {
        guard let continuation = inputContinuation, let target = analyzerFormat else { return }
        let converted: AVAudioPCMBuffer
        if buffer.format == target {
            converted = buffer
        } else {
            if converter == nil || converter?.inputFormat != buffer.format {
                converter = AVAudioConverter(from: buffer.format, to: target)
            }
            guard let converter else { return }
            let ratio = target.sampleRate / buffer.format.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return }
            var fed = false
            converter.convert(to: out, error: nil) { _, status in
                if fed { status.pointee = .noDataNow; return nil }
                fed = true
                status.pointee = .haveData
                return buffer
            }
            guard out.frameLength > 0 else { return }
            converted = out
        }
        continuation.yield(AnalyzerInput(buffer: converted))
    }

    /// Finishes the session and returns the complete transcript.
    public func finish() async throws -> String {
        inputContinuation?.finish()
        inputContinuation = nil
        if let analyzer {
            try await analyzer.finalizeAndFinishThroughEndOfInput()
        }
        // The results stream ends after finalization; wait for the consumer task.
        await resultsTask?.value
        let text = lock.withLock {
            (finalizedText + volatileText).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cleanup()
        guard !text.isEmpty else { throw TranscriptionError.emptyResult }
        return text
    }

    public func cancel() {
        inputContinuation?.finish()
        inputContinuation = nil
        let analyzer = self.analyzer
        Task { await analyzer?.cancelAndFinishNow() }
        resultsTask?.cancel()
        cleanup()
    }

    private func cleanup() {
        analyzer = nil
        transcriber = nil
        resultsTask = nil
        converter = nil
        analyzerFormat = nil
    }
}
