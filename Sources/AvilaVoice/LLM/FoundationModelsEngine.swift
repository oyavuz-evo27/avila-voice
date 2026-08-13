import Foundation
import FoundationModels

/// Apple's on-device system LLM (macOS 26+). Zero app RAM cost, instant availability.
/// Limits: ~4k token window, non-configurable guardrails.
final class FoundationModelsEngine: EnhancementEngine {
    let displayName = "Apple Foundation Models"

    func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    func enhance(transcript: String,
                 mode: Mode,
                 dictionary: [String],
                 context: DictationContext?) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else {
            throw EnhancementError.engineUnavailable(
                "Apple Intelligence is not available on this Mac. " +
                "Enable it in System Settings → Apple Intelligence & Siri.")
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
