import Foundation

/// Which context is gathered for a mode and handed to the LLM.
struct ContextOptions: Codable, Equatable {
    var activeApp = false
    var selectedText = false
    var clipboard = false
    var screenshotOCR = false

    var any: Bool { activeApp || selectedText || clipboard || screenshotOCR }
}

/// A dictation mode: how the raw transcript is post-processed by the local LLM.
struct Mode: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var systemPrompt: String
    var context: ContextOptions
    var isBuiltin: Bool

    /// Localized name for built-in modes — but a user rename always wins.
    var displayName: String {
        guard isBuiltin else { return name }
        switch id {
        case Mode.standard.id where name == Mode.standard.name: return L("mode.standard")
        case Mode.email.id where name == Mode.email.name: return L("mode.email")
        case Mode.translate.id where name == Mode.translate.name: return L("mode.translate")
        default: return name
        }
    }

    init(id: UUID = UUID(), name: String, systemPrompt: String,
         context: ContextOptions = ContextOptions(), isBuiltin: Bool = false) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.context = context
        self.isBuiltin = isBuiltin
    }

    // MARK: Codable (tolerates the legacy `useContext: Bool` field)

    private enum CodingKeys: String, CodingKey {
        case id, name, systemPrompt, context, isBuiltin, useContext
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        systemPrompt = try c.decode(String.self, forKey: .systemPrompt)
        isBuiltin = try c.decodeIfPresent(Bool.self, forKey: .isBuiltin) ?? false
        if let options = try c.decodeIfPresent(ContextOptions.self, forKey: .context) {
            context = options
        } else if (try c.decodeIfPresent(Bool.self, forKey: .useContext)) == true {
            context = ContextOptions(activeApp: true, selectedText: true,
                                     clipboard: true, screenshotOCR: false)
        } else {
            context = ContextOptions()
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(systemPrompt, forKey: .systemPrompt)
        try c.encode(context, forKey: .context)
        try c.encode(isBuiltin, forKey: .isBuiltin)
    }

    // MARK: Built-ins

    static let standard = Mode(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Standard",
        systemPrompt: """
        You clean up dictated text. Remove filler words, false starts, repetitions and \
        transcription artifacts (stray words that make no sense in context). Fix grammar \
        thoroughly: case endings, verb agreement, commas and punctuation. Keep the \
        language of the input (German stays German, English stays English). Do not change \
        the meaning, tone or wording more than necessary. Output only the cleaned text, \
        nothing else.
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
        context: ContextOptions(activeApp: true, selectedText: true,
                                clipboard: true, screenshotOCR: false),
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
