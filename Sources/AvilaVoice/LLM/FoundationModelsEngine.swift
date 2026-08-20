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

    private static func instructions(for mode: Mode) -> String {
        mode.systemPrompt + "\n\n" + PromptBuilder.policy
    }

    func prewarm(mode: Mode) async {
        guard SystemLanguageModel.default.availability == .available else { return }
        let combined = Self.instructions(for: mode)
        guard spare?.modeID != mode.id || spare?.instructions != combined else { return }
        let session = LanguageModelSession(instructions: combined)
        session.prewarm()
        spare = (mode.id, combined, session)
    }

    func enhance(transcript: String,
                 mode: Mode,
                 dictionary: [String],
                 context: DictationContext?) async throws -> String {
        try await enhance(transcript: transcript, mode: mode, dictionary: dictionary,
                          context: context, onPartial: { _ in })
    }

    func enhance(transcript: String,
                 mode: Mode,
                 dictionary: [String],
                 context: DictationContext?,
                 onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        guard SystemLanguageModel.default.availability == .available else {
            throw EnhancementError.engineUnavailable(L("error.appleIntelligence"))
        }
        guard transcript.count <= Self.maxTranscriptLength else {
            NSLog("AvilaVoice: transcript exceeds Foundation Models window, returning raw text")
            return transcript
        }

        // Use the prewarmed session when it matches; sessions are single-use here so
        // no context bleeds between dictations.
        let combined = Self.instructions(for: mode)
        let session: LanguageModelSession
        if let spare, spare.modeID == mode.id, spare.instructions == combined {
            session = spare.session
            self.spare = nil
        } else {
            session = LanguageModelSession(instructions: combined)
        }
        // Replenish the spare for the NEXT dictation right away (issue #3) — the
        // recording-start prewarm covers the common case, this covers rapid-fire
        // dictations in between.
        Task { await self.prewarm(mode: mode) }

        let prompt = PromptBuilder.userPrompt(transcript: transcript,
                                              dictionary: dictionary,
                                              context: context)
        // Stream so the pill can show progress while the model works (long
        // dictations take 1–3 s on the system model).
        var latest = ""
        for try await snapshot in session.streamResponse(to: prompt) {
            latest = snapshot.content
            onPartial(latest)
        }

        // Warm the next session for this mode in the background.
        Task { await self.prewarm(mode: mode) }

        let text = latest.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? transcript : text
    }
}
