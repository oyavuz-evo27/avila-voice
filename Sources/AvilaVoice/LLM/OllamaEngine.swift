import AvilaKit
import Foundation

/// Open-weights LLM (Gemma 4, Qwen3.x, …) served by a LOCAL Ollama instance
/// (http://localhost:11434). Ollama runs the model on Metal/MLX on this Mac —
/// nothing leaves the machine. Chosen over embedded MLX because SwiftPM cannot
/// compile MLX's Metal shaders without Xcode.
actor OllamaEngine: EnhancementEngine {
    nonisolated let displayName = "Ollama (lokal)"

    /// Server address — configurable (issue #16) so a low-memory Mac can hand the
    /// AI pass to another OWN Mac on the local network (e.g. Air → Mac mini).
    /// Default stays localhost; the settings UI shows an explicit notice for any
    /// remote address, and the cloud-model filter (#7) applies unchanged.
    static var baseURL: URL {
        let stored = UserDefaults.standard.string(forKey: "engine.ollama.host")?
            .trimmingCharacters(in: .whitespaces) ?? ""
        guard !stored.isEmpty else { return URL(string: "http://localhost:11434")! }
        let candidate = stored.contains("://") ? stored : "http://" + stored
        guard let url = URL(string: candidate), url.host != nil else {
            return URL(string: "http://localhost:11434")!
        }
        return url
    }

    /// True when dictations would leave this Mac (any non-loopback host).
    static var isRemoteHost: Bool {
        let host = baseURL.host?.lowercased() ?? "localhost"
        return !["localhost", "127.0.0.1", "::1"].contains(host)
    }
    /// Model tag chosen in settings (empty = first available).
    static var modelName: String {
        UserDefaults.standard.string(forKey: "engine.ollama.model") ?? ""
    }

    private var lastAvailability: (Date, Bool)?

    struct OllamaModel: Decodable, Identifiable, Sendable {
        let name: String
        let size: Int64
        /// Ollama CLOUD models ("-cloud") forward requests to this host — they do
        /// not run locally and are therefore never used (issue #7).
        let remoteHost: String?
        var id: String { name }
        var sizeGB: Double { Double(size) / 1e9 }
        var isCloud: Bool { remoteHost != nil }
        enum CodingKeys: String, CodingKey {
            case name, size
            case remoteHost = "remote_host"
        }
    }

    /// LOCAL models plus the number of hidden cloud models (for the settings hint).
    static func modelCatalog() async -> (local: [OllamaModel], cloudHidden: Int) {
        struct Tags: Decodable { let models: [OllamaModel] }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 2
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return ([], 0) }
        let cloud = tags.models.filter(\.isCloud)
        if !cloud.isEmpty {
            DebugLog.log("ollama: hiding \(cloud.count) cloud model(s): "
                         + cloud.map(\.name).joined(separator: ", "))
        }
        return (tags.models.filter { !$0.isCloud }.sorted { $0.name < $1.name }, cloud.count)
    }

    /// Lists installed LOCAL models (empty if Ollama is not running). Cloud models
    /// are excluded everywhere — picker, availability, fallback resolution — so a
    /// stored "-cloud" selection makes the engine unavailable and the app falls
    /// back to Apple instead of sending dictations to ollama.com.
    static func installedModels() async -> [OllamaModel] {
        await modelCatalog().local
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
    private var keepWarmTask: Task<Void, Never>?

    /// Loads the model AND primes Ollama's prompt cache with this mode's exact
    /// system prompt — measured: an uncached prompt costs 2–3 s of prefill, a
    /// cached one ~0 s. A background loop refreshes the cache every 4 minutes so
    /// the first dictation after a pause is as fast as the second.
    func prewarm(mode: Mode) async {
        guard await isAvailable() else { return }
        await primeCache(mode: mode)
        keepWarmTask?.cancel()
        keepWarmTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(240))
                guard !Task.isCancelled else { return }
                await self?.primeCache(mode: mode)
            }
        }
    }

    private func primeCache(mode: Mode) async {
        let model = await resolvedModel()
        guard !model.isEmpty else { return }
        let instructions = mode.systemPrompt + "\n\n" + PromptBuilder.policy
        // A tiny real chat call with the identical system prompt is what fills the
        // prefix cache; num_predict 1 keeps it nearly free.
        let body: [String: Any] = [
            "model": model, "stream": false, "keep_alive": "60m", "think": false,
            "options": ["num_predict": 1],
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": "Vocabulary (correct any misheard versions of these exact terms): "],
            ],
        ]
        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
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
        // num_predict scaled to the input: rewriting never needs more than ~1.5× the
        // transcript's tokens — a tight cap stops runaway generations early.
        let cap = max(200, min(1600, transcript.count / 2))
        let body: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": "60m",
            "think": false,          // Qwen3/Gemma reasoning off — rewriting wants speed
            "options": ["temperature": 0.1, "num_predict": cap, "top_k": 20],
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
