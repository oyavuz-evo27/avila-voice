import Foundation

/// Minimal client for a local Ollama server (http://localhost:11434).
///
/// Generic building block shared by the Avila apps: lists installed models, checks
/// reachability and runs `/api/chat` with optional streaming and optional
/// structured output (`format` = JSON schema). App-specific prompting stays in
/// the apps — Avila Voice keeps its dictation `OllamaEngine`, Avila Projects builds
/// its task parser on top of this client.
public struct OllamaClient: Sendable {
    public static let defaultBaseURL = URL(string: "http://localhost:11434")!

    public struct Model: Decodable, Identifiable, Sendable, Equatable {
        public let name: String
        public let size: Int64
        public var id: String { name }
        public var sizeGB: Double { Double(size) / 1e9 }
        public init(name: String, size: Int64) { self.name = name; self.size = size }
    }

    public struct Message: Sendable, Equatable {
        public enum Role: String, Sendable { case system, user, assistant }
        public let role: Role
        public let content: String
        public init(_ role: Role, _ content: String) { self.role = role; self.content = content }
    }

    public struct Options: Sendable, Equatable {
        public var temperature: Double = 0.1
        public var numPredict: Int? = nil
        public var topK: Int? = 20
        public var think: Bool = false
        public var keepAlive: String = "60m"
        public var timeout: TimeInterval = 60
        public init() {}
    }

    public enum ClientError: Error, LocalizedError, Sendable {
        case unreachable
        case httpStatus(Int)
        case emptyResponse
        public var errorDescription: String? {
            switch self {
            case .unreachable: return "Ollama is not reachable."
            case .httpStatus(let code): return "Ollama answered with HTTP \(code)."
            case .emptyResponse: return "Ollama returned an empty response."
            }
        }
    }

    public let baseURL: URL

    public init(baseURL: URL = OllamaClient.defaultBaseURL) {
        self.baseURL = baseURL
    }

    /// Installed models via `/api/tags`; empty when the server is down.
    public func installedModels() async -> [Model] {
        struct Tags: Decodable { let models: [Model] }
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, _) = try? await URLSession.shared.data(for: request),
              let tags = try? JSONDecoder().decode(Tags.self, from: data) else { return [] }
        return tags.models
    }

    public func isReachable() async -> Bool {
        !(await installedModels()).isEmpty
    }

    /// Runs a chat completion. `format` may be a JSON-schema dictionary for structured
    /// output (Ollama constrains generation to it) or `nil` for free text. Streams
    /// tokens to `onPartial` (accumulated text) and returns the final text with any
    /// `<think>` block removed.
    public func chat(model: String,
                     messages: [Message],
                     format: [String: Any]? = nil,
                     options: Options = Options(),
                     onPartial: (@Sendable (String) -> Void)? = nil) async throws -> String {
        var opts: [String: Any] = ["temperature": options.temperature]
        if let n = options.numPredict { opts["num_predict"] = n }
        if let k = options.topK { opts["top_k"] = k }
        var body: [String: Any] = [
            "model": model,
            "stream": true,
            "keep_alive": options.keepAlive,
            "think": options.think,
            "options": opts,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
        ]
        if let format { body["format"] = format }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = options.timeout
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch {
            throw ClientError.unreachable
        }
        guard let http = response as? HTTPURLResponse else { throw ClientError.unreachable }
        guard http.statusCode == 200 else { throw ClientError.httpStatus(http.statusCode) }

        var output = ""
        for try await line in bytes.lines {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if let message = json["message"] as? [String: Any],
               let chunk = message["content"] as? String, !chunk.isEmpty {
                output += chunk
                onPartial?(output)
            }
            if json["done"] as? Bool == true { break }
        }
        let text = Self.stripThinking(output).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw ClientError.emptyResponse }
        return text
    }

    /// Fire-and-forget warm-up: loads the model into memory (empty prompt, keep_alive).
    public func warmUp(model: String, keepAlive: String = "60m") async {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "model": model, "stream": false, "keep_alive": keepAlive, "messages": [],
        ])
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }

    static func stripThinking(_ text: String) -> String {
        guard let close = text.range(of: "</think>") else { return text }
        return String(text[close.upperBound...])
    }
}
