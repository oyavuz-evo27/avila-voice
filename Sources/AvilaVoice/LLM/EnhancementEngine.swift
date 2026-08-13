import Foundation

enum EnhancementError: Error, LocalizedError {
    case engineUnavailable(String)

    var errorDescription: String? {
        switch self {
        case .engineUnavailable(let reason): return reason
        }
    }
}

/// Context gathered around a dictation, fed to the LLM when the mode allows it.
struct DictationContext {
    var frontmostApp: String?
    var selectedText: String?
    var clipboardText: String?
    var screenText: String?

    var isEmpty: Bool {
        frontmostApp == nil && selectedText == nil && clipboardText == nil && screenText == nil
    }
}

/// A local LLM backend that rewrites a raw transcript according to a mode's instructions.
protocol EnhancementEngine: Sendable {
    var displayName: String { get }
    func isAvailable() async -> Bool
    func enhance(transcript: String,
                 mode: Mode,
                 dictionary: [String],
                 context: DictationContext?) async throws -> String
}

/// Builds the prompt shared by all engines.
enum PromptBuilder {
    static func userPrompt(transcript: String,
                           dictionary: [String],
                           context: DictationContext?) -> String {
        var parts: [String] = []
        if !dictionary.isEmpty {
            parts.append("Vocabulary (correct any misheard versions of these exact terms): "
                         + dictionary.joined(separator: ", "))
        }
        if let context, !context.isEmpty {
            var ctx = "Context (for reference only — do NOT include it in the output):"
            if let app = context.frontmostApp { ctx += "\n- Active app: \(app)" }
            if let sel = context.selectedText, !sel.isEmpty {
                ctx += "\n- Selected text: \(sel.prefix(1000))"
            }
            if let clip = context.clipboardText, !clip.isEmpty {
                ctx += "\n- Clipboard: \(clip.prefix(1000))"
            }
            if let screen = context.screenText, !screen.isEmpty {
                ctx += "\n- Visible screen text: \(screen.prefix(1500))"
            }
            parts.append(ctx)
        }
        parts.append("Dictated text:\n\(transcript)")
        return parts.joined(separator: "\n\n")
    }
}

/// Fallback engine: returns the transcript unchanged (used when no LLM is available).
struct PassthroughEngine: EnhancementEngine {
    let displayName = "None (raw transcript)"
    func isAvailable() async -> Bool { true }
    func enhance(transcript: String, mode: Mode, dictionary: [String],
                 context: DictationContext?) async throws -> String {
        transcript
    }
}
