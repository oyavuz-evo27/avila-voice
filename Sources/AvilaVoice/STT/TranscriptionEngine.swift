import Foundation

enum TranscriptionError: Error, LocalizedError {
    case engineUnavailable(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason): return reason
        case .emptyResult: return L("error.noSpeech")
        }
    }
}

/// A speech-to-text backend. Implementations: Apple SpeechAnalyzer, NVIDIA Parakeet v3.
protocol TranscriptionEngine: Sendable {
    var displayName: String { get }
    /// Prepare models so the first dictation has no cold start. Safe to call repeatedly.
    func warmUp() async
    /// Transcribes a 16 kHz mono WAV file into text.
    func transcribe(fileURL: URL) async throws -> String
}
