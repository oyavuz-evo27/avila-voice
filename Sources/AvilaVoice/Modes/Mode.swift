import Foundation

/// A dictation mode: how the raw transcript is post-processed by the local LLM.
struct Mode: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var useContext: Bool
    var isBuiltin: Bool

    /// Localized name for built-in modes; custom modes keep the user's name.
    var displayName: String {
        guard isBuiltin else { return name }
        switch id {
        case Mode.standard.id: return L("mode.standard")
        case Mode.email.id: return L("mode.email")
        case Mode.translate.id: return L("mode.translate")
        default: return name
        }
    }

    init(id: UUID = UUID(), name: String, systemPrompt: String,
         useContext: Bool = false, isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.useContext = useContext
        self.isBuiltin = isBuiltin
    }

    static let standard = Mode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Standard",
        systemPrompt: """
        You clean up dictated text. Remove filler words, false starts and repetitions. \
        Fix grammar and punctuation. Keep the language of the input (German stays German, \
        English stays English). Do not change the meaning, tone or wording more than \
        necessary. Output only the cleaned text, nothing else.
        """,
        isBuiltin: true
    )

    static let email = Mode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        name: "E-Mail",
        systemPrompt: """
        You turn dictated text into a well-formed e-mail in the language of the input. \
        Add a suitable greeting and closing if missing. Use a professional, friendly tone \
        (formal "Sie" in German unless the dictation clearly addresses a friend). \
        Structure the body into short paragraphs. Output only the e-mail text, nothing else.
        """,
        useContext: true,
        isBuiltin: true
    )

    static let translate = Mode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        name: "Translate",
        systemPrompt: """
        You translate dictated text. If the input is German, translate it to natural, \
        idiomatic English. If the input is English, translate it to natural, idiomatic \
        German. First clean up filler words and false starts, then translate. \
        Output only the translation, nothing else.
        """,
        isBuiltin: true
    )

    static let builtins: [Mode] = [.standard, .email, .translate]
}
