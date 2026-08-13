import Foundation
import FoundationModels

/// Apple's on-device system LLM (macOS 26+). Zero app RAM cost, instant availability.
/// Limits: ~4k token window, non-configurable guardrails.
final class FoundationModelsEngine: EnhancementEngine {
    let displayName = "Apple Foundation Models"

    func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// The system model has a ~4,096-token window (input + output). Longer dictations
    /// are returned raw instead of risking a truncated or failed rewrite.
    static let maxTranscriptLength = 3500

    func enhance(transcript: String,
                 mode: Mode,
                 dictionary: [String],
                 context: DictationContext?) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else {
            throw EnhancementError.engineUnavailable(L("error.appleIntelligence"))
        }
        guard transcript.count <= Self.maxTranscriptLength else {
            NSLog("AvilaVoice: transcript exceeds Foundation Models window, returning raw text")
            return transcript
        }
        let session = LanguageModelSession(instructions: mode.systemPrompt)
        let prompt = PromptBuilder.userPrompt(transcript: transcript,
                                              dictionary: dictionary,
                                              context: context)
        let response = try await session.respond(to: prompt)
        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? transcript : text
    }
}
