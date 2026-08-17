import Foundation

/// A downloadable on-device model (weights live under Application Support).
struct ModelDescriptor: Identifiable, Equatable {
    enum Kind { case speech, language }
    let id: String
    let kind: Kind
    let displayName: String
    let sizeDescription: String
    /// Hugging Face repo id (weights are fetched by the engine's own loader).
    let repoID: String
}

extension ModelDescriptor {
    static let parakeetV3 = ModelDescriptor(
        id: "parakeet-tdt-0.6b-v3", kind: .speech,
        displayName: "NVIDIA Parakeet TDT 0.6B v3",
        sizeDescription: "≈ 1,2 GB",
        repoID: "FluidInference/parakeet-tdt-0.6b-v3-coreml")

    static let all: [ModelDescriptor] = [.parakeetV3]
}

/// Tracks which optional models are installed and where they live.
/// Downloads are performed by the engines' loaders (they know their formats);
/// this store owns paths, presence checks, and progress reporting for the UI.
@MainActor
final class ModelStore: ObservableObject {
    static let shared = ModelStore()

    nonisolated static let root: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/AvilaVoice/Models", isDirectory: true)

    @Published private(set) var progress: [String: Double] = [:]   // 0…1 while downloading
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var installedIDs: Set<String> = []

    private init() {
        try? FileManager.default.createDirectory(at: Self.root, withIntermediateDirectories: true)
        refresh()
    }

    func directory(for model: ModelDescriptor) -> URL {
        Self.root.appendingPathComponent(model.id, isDirectory: true)
    }

    func isInstalled(_ model: ModelDescriptor) -> Bool {
        installedIDs.contains(model.id)
    }

    func isDownloading(_ model: ModelDescriptor) -> Bool {
        progress[model.id] != nil
    }

    /// Engines call this while fetching; the marker file makes presence checks cheap.
    func setProgress(_ value: Double?, for model: ModelDescriptor) {
        progress[model.id] = value
    }

    func markInstalled(_ model: ModelDescriptor) {
        let marker = directory(for: model).appendingPathComponent(".installed")
        try? FileManager.default.createDirectory(at: directory(for: model),
                                                 withIntermediateDirectories: true)
        try? Data().write(to: marker)
        errors[model.id] = nil
        progress[model.id] = nil
        refresh()
    }

    func markFailed(_ model: ModelDescriptor, error: Error) {
        errors[model.id] = error.localizedDescription
        progress[model.id] = nil
    }

    func remove(_ model: ModelDescriptor) {
        try? FileManager.default.removeItem(at: directory(for: model))
        refresh()
    }

    func refresh() {
        var found: Set<String> = []
        for model in ModelDescriptor.all {
            let marker = directory(for: model).appendingPathComponent(".installed")
            if FileManager.default.fileExists(atPath: marker.path) { found.insert(model.id) }
        }
        installedIDs = found
    }
}
