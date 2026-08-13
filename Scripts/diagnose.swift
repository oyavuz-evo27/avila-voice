// Quick health check for the two Apple engines. Run: swift Scripts/diagnose.swift
import Foundation
import FoundationModels
import Speech

@main
struct Diagnose {
    static func main() async {
        // 1) Apple Foundation Models (LLM)
        switch SystemLanguageModel.default.availability {
        case .available:
            print("LLM: Apple Foundation Models — VERFÜGBAR")
        case .unavailable(let reason):
            print("LLM: NICHT verfügbar — \(reason)")
        }

        // 2) SpeechAnalyzer locales
        let supported = await SpeechTranscriber.supportedLocales
            .map { $0.identifier(.bcp47) }.sorted()
        let installed = await SpeechTranscriber.installedLocales
            .map { $0.identifier(.bcp47) }.sorted()
        print("STT unterstützt: \(supported.filter { $0.hasPrefix("de") || $0.hasPrefix("en") }.joined(separator: ", "))")
        print("STT installiert: \(installed.joined(separator: ", "))")
    }
}
