import Foundation

/// Open-weights LLM (Gemma 4, Qwen3.x, …) served by a LOCAL Ollama instance
/// (http://localhost:11434). Ollama runs the model on Metal/MLX on this Mac —
/// nothing leaves the machine. Chosen over embedded MLX because SwiftPM cannot
/// compile MLX's Metal shaders without Xcode.
actor OllamaEngine: EnhancementEngine {
    nonisolated let displayName = "Ollama (lokal)"

    static let baseURL = URL(string: "http://localhost:11434")!
    /// Model tag chosen in settings (empty = first available).
    static var modelName: String {
        UserDefaults.standard.string(forKey: "engine.ollama.model") ?? ""
    }

    private var lastAvailability: (Date, Bool)?

    struct OllamaModel: Decodable, Identifiable, Sendable {
        let name: String
        let size: Int64
        var id: String { name }
        var sizeGB: Double { Double(size) / 1e9 }
    }

    /// Lists installed models (empty if Ollama is not running).
    static func installedModels() async -> [OllamaModel] {
        struct Tags: Decodable { let models: [OllamaModel] }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return [] }
        return tags.models.sorted { $0.name < $1.name }
    }

    func isAvailable() async -> Bool {
        if let (when, value) = lastAvailability, Date().timeIntervalSince(when) < 10 {
            return value
        }
        let models = await Self.installedModels()
        let name = Self.modelName
        let available = !models.isEmpty && (name.isEmpty || models.contains { $0.name == name })
        lastAvailability = (Date(), available)
        return available
    }

    /// Ask Ollama to load the model into memory (keep_alive) so the first
    /// dictation does not pay the cold start.
    func prewarm(mode: Mode) async {
        guard await isAvailable() else { return }
        let body: [String: Any] = ["model": await resolvedModel(), "keep_alive": "30m"]
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/generate"))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }

    private func resolvedModel() async -> String {
        let name = Self.modelName
        if !name.isEmpty { return name }
        return await Self.installedModels().first?.name ?? ""
    }

    func enhance(transcript: String, mode: Mode, dictionary: [String],
                 context: DictationContext?) async throws -> String {
        try await enhance(transcript: transcript, mode: mode, dictionary: dictionary,
                          context: context, onPartial: { _ in })
    }

    func enhance(transcript: String, mode: Mode, dictionary: [String],
                 context: DictationContext?,
                 onPartial: @escaping @Sendable (String) -> Void) async throws -> String {
        let model = await resolvedModel()
        guard !model.isEmpty else {
            throw EnhancementError.engineUnavailable(L("error.ollamaUnavailable"))
        }
        let instructions = mode.systemPrompt + "\n\n" + PromptBuilder.policy
        let prompt = PromptBuilder.userPrompt(transcript: transcript,
                                              dictionary: dictionary, context: context)
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": "30m",
            "think": false,          // Qwen3/Gemma reasoning off — rewriting wants speed
            "options": ["temperature": 0.2, "num_predict": 1200],
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt],
            ],
        ]
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 60
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw EnhancementError.engineUnavailable(L("error.ollamaUnavailable"))
        }
        var output = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let message = json["message"] as? [String: Any],
               let chunk = message["content"] as? String, !chunk.isEmpty {
                output += chunk
                onPartial(output)
            }
            if json["done"] as? Bool == true { break }
        }
        let text = Self.stripThinking(output).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? transcript : text
    }

    private static func stripThinking(_ text: String) -> String {
        guard let close = text.range(of: "</think>") else { return text }
        return String(text[close.upperBound...])
    }
}
