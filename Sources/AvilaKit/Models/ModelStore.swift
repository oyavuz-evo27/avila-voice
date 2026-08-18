import Foundation

/// A downloadable on-device model (weights live under Application Support).
public struct ModelDescriptor: Identifiable, Equatable, Sendable {
    public enum Kind: Sendable { case speech, language }
    public let id: String
    public let kind: Kind
    public let displayName: String
    public let sizeDescription: String
    /// Hugging Face repo id (weights are fetched by the engine's own loader).
    public let repoID: String
}

extension ModelDescriptor {
    public static let parakeetV3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3", kind: .speech,
        displayName: "NVIDIA Parakeet TDT 0.6B v3",
        sizeDescription: "≈ 1,2 GB",
        repoID: "FluidInference/parakeet-tdt-0.6b-v3-coreml")

    public static let all: [ModelDescriptor] = [.parakeetV3]
}

/// Tracks which optional models are installed and where they live.
/// Downloads are performed by the engines' loaders (they know their formats);
/// this store owns paths, presence checks, and progress reporting for the UI.
@MainActor
public final class ModelStore: ObservableObject {
    public static let shared = ModelStore()

    public nonisolated static let root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AvilaVoice/Models", isDirectory: true)

    @Published public private(set) var progress: [String: Double] = [:]   // 0…1 while downloading
    @Published public private(set) var errors: [String: String] = [:]
    @Published public private(set) var installedIDs: Set<String> = []

    private init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        refresh()
    }

    public func directory(for model: ModelDescriptor) -> URL {
        Self.root.appendingPathComponent(model.id, isDirectory: true)
    }

    public func isInstalled(_ model: ModelDescriptor) -> Bool {
        installedIDs.contains(model.id)
    }

    public func isDownloading(_ model: ModelDescriptor) -> Bool {
        progress[model.id] != nil
    }

    /// Engines call this while fetching; the marker file makes presence checks cheap.
    public func setProgress(_ value: Double?, for model: ModelDescriptor) {
        progress[model.id] = value
    }

    public func markInstalled(_ model: ModelDescriptor) {
        let marker = directory(for: model).appendingPathComponent(".installed")
        try? FileManager.default.createDirectory(at: directory(for: model),
                                                 withIntermediateDirectories: true)
        try? Data().write(to: marker)
        errors[model.id] = nil
        progress[model.id] = nil
        refresh()
    }

    public func markFailed(_ model: ModelDescriptor, error: Error) {
        errors[model.id] = error.localizedDescription
        progress[model.id] = nil
    }

    public func remove(_ model: ModelDescriptor) {
        try? FileManager.default.removeItem(at: directory(for: model))
        refresh()
    }

    public func refresh() {
        var found: Set<String> = []
        for model in ModelDescriptor.all {
            let marker = directory(for: model).appendingPathComponent(".installed")
            if FileManager.default.fileExists(atPath: marker.path) { found.insert(model.id) }
        }
        installedIDs = found
    }
}
