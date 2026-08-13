import Foundation
import Speech
import AVFAudio

/// Apple's on-device SpeechAnalyzer (macOS 26+). System-managed models: near-zero RAM
/// cost for the app. Best German quality for clean speech.
final class SpeechAnalyzerEngine: TranscriptionEngine {
    let displayName = "Apple SpeechAnalyzer"

    func warmUp() async {
        // Ensure the model assets for the preferred locales are installed.
        for identifier in ["de-DE", "en-US"] {
            let locale = Locale(identifier: identifier)
            guard let transcriber = try? await makeTranscriber(locale: locale) else { continue }
            _ = transcriber
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
            throw TranscriptionError.engineUnavailable(
                "SpeechAnalyzer does not support locale \(locale.identifier).")
        }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try await request.downloadAndInstall()
        }
        return transcriber
    }
}
