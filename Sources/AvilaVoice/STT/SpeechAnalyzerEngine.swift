import Foundation
import Speech
import AVFAudio

/// Apple's on-device SpeechAnalyzer (macOS 26+). System-managed models: near-zero RAM
/// cost for the app. Best German quality for clean speech.
/// An actor so the per-locale asset preparation cache is race-free.
actor SpeechAnalyzerEngine: TranscriptionEngine {
    nonisolated let displayName = "Apple SpeechAnalyzer"

    /// Locales whose model assets are verified installed — the (potentially slow)
    /// AssetInventory check runs once per locale, not once per dictation.
    private var preparedLocales: Set<String> = []

    func warmUp() async {
        for identifier in ["de-DE", "en-US"] {
            _ = try? await makeTranscriber(locale: Locale(identifier: identifier))
        }
    }

    func transcribe(fileURL: URL) async throws -> String {
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
        guard await SpeechTranscriber.supportedLocales.contains(where: {
            $0.identifier(.bcp47) == locale.identifier(.bcp47)
        }) else {
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
