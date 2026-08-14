import Foundation
import FoundationModels

/// Apple's on-device system LLM (macOS 26+). Zero app RAM cost, instant availability.
/// Limits: ~4k token window, non-configurable guardrails.
/// An actor keeping ONE prewarmed spare session for the active mode — creating and
/// warming a session per dictation cost noticeable latency.
actor FoundationModelsEngine: EnhancementEngine {
    nonisolated let displayName = "Apple Foundation Models"

    /// The system model has a ~4,096-token window (input + output). Longer dictations
    /// are returned raw instead of risking a truncated or failed rewrite.
    static let maxTranscriptLength = 3500

    private var spare: (modeID: UUID, instructions: String, session: LanguageModelSession)?

    func isAvailable() async -> Bool {
        SystemLanguageModel.default.availability == .available
    }

    func prewarm(mode: Mode) async {
        guard SystemLanguageModel.default.availability == .available else { return }
        guard spare?.modeID != mode.id || spare?.instructions != mode.systemPrompt else { return }
        let session = LanguageModelSession(instructions: mode.systemPrompt)
        session.prewarm()
        spare = (mode.id, mode.systemPrompt, session)
    }

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

        // Use the prewarmed session when it matches; sessions are single-use here so
        // no context bleeds between dictations.
        let session: LanguageModelSession
        if let spare, spare.modeID == mode.id, spare.instructions == mode.systemPrompt {
            session = spare.session
            self.spare = nil
        } else {
            session = LanguageModelSession(instructions: mode.systemPrompt)
        }

        let prompt = PromptBuilder.userPrompt(transcript: transcript,
                                              dictionary: dictionary,
                                              context: context)
        let response = try await session.respond(to: prompt)

        // Warm the next session for this mode in the background.
        Task { await self.prewarm(mode: mode) }

        let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? transcript : text
    }
}
