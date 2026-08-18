import Foundation
import Speech
import AVFAudio

/// Apple's on-device SpeechAnalyzer (macOS 26+). System-managed models: near-zero RAM
/// cost for the app. Best German quality for clean speech.
/// An actor so the per-locale asset preparation cache is race-free.
public actor SpeechAnalyzerEngine: TranscriptionEngine {
    public init() {}
    public nonisolated let displayName = "Apple SpeechAnalyzer"

    /// Locales whose model assets are verified installed — the (potentially slow)
    /// AssetInventory check runs once per locale, not once per dictation.
    private var preparedLocales: Set<String> = []
    /// supportedLocales is an async system query — cached after the first call.
    private var supportedLocaleIDs: Set<String>?

    public func warmUp() async {
        for identifier in ["de-DE", "en-US"] {
            _ = try? await makeTranscriber(locale: Locale(identifier: identifier))
        }
        // The asset check alone leaves the model cold (~150–300 ms penalty on the
        // first dictation) — a short silent run actually loads it.
        await warmModelWithSilence()
    }

    private func warmModelWithSilence() async {
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000,
                                   channels: 1, interleaved: false)!
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avila-warmup.wav")
        defer { try? FileManager.default.removeItem(at: url) }
        guard let file = try? AVAudioFile(forWriting: url, settings: format.settings,
                                          commonFormat: .pcmFormatFloat32,
                                          interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8_000) else {
            return
        }
        buffer.frameLength = 8_000 // 0.5 s of silence
        try? file.write(from: buffer)
        let started = Date()
        _ = try? await transcribe(fileURL: url) // throws emptyResult — model is warm now
        DebugLog.log(String(format: "stt model warm-up took %.0f ms",
                            Date().timeIntervalSince(started) * 1000))
    }

    public func transcribe(fileURL: URL) async throws -> String {
        let locale = Locale(identifier: UserDefaults.standard.string(forKey: "stt.locale") ?? "de-DE")
        let transcriber = try await makeTranscriber(locale: locale)
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        let file = try AVAudioFile(forReading: fileURL)
        if let lastSample = try await analyzer.analyzeSequence(from: file) {
            try await analyzer.finalizeAndFinish(through: lastSample)
        } else {
            await analyzer.cancelAndFinishNow()
        }

        var text = ""
        for try await result in transcriber.results where result.isFinal {
            text += String(result.text.characters)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TranscriptionError.emptyResult }
        return trimmed
    }

    private func makeTranscriber(locale: Locale) async throws -> SpeechTranscriber {
        let transcriber = SpeechTranscriber(locale: locale,
                                            transcriptionOptions: [],
                                            reportingOptions: [],
                                            attributeOptions: [])
        if supportedLocaleIDs == nil {
            supportedLocaleIDs = Set(await SpeechTranscriber.supportedLocales
                .map { $0.identifier(.bcp47) })
        }
        guard supportedLocaleIDs?.contains(locale.identifier(.bcp47)) == true else {
            throw TranscriptionError.engineUnavailable(L("error.sttLocale"))
        }
        if !preparedLocales.contains(locale.identifier) {
            if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
                try await request.downloadAndInstall()
            }
            preparedLocales.insert(locale.identifier)
        }
        return transcriber
    }
}
