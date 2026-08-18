import AVFAudio
import FluidAudio
import Foundation

/// NVIDIA Parakeet TDT 0.6B v3 via FluidAudio (Core ML, Apple Neural Engine).
/// 25 languages incl. German; strongest on spontaneous speech with fillers.
/// Models are downloaded once (~1.2 GB) into the app's model directory.
public actor ParakeetEngine: TranscriptionEngine {
    public init() {}
    public nonisolated let displayName = "NVIDIA Parakeet v3"

    private var manager: AsrManager?
    private var loading: Task<Void, Error>?

    /// True once the model files are present on disk (no network needed).
    public static func isInstalled() -> Bool {
        AsrModels.modelsExist(at: modelDirectory)
    }

    public static var modelDirectory: URL {
        ModelStore.root.appendingPathComponent(ModelDescriptor.parakeetV3.id, isDirectory: true)
    }

    public func warmUp() async {
        try? await ensureLoaded(allowDownload: false)
    }

    /// Downloads (if needed) and loads the models, reporting progress to the store.
    public func install() async throws {
        try await ensureLoaded(allowDownload: true)
    }

    private func ensureLoaded(allowDownload: Bool) async throws {
        if manager != nil { return }
        if let loading { return try await loading.value }
        let task = Task<Void, Error> {
            let dir = Self.modelDirectory
            if !AsrModels.modelsExist(at: dir) {
                guard allowDownload else { throw TranscriptionError.engineUnavailable(L("error.modelMissing")) }
                await MainActor.run { ModelStore.shared.setProgress(0, for: .parakeetV3) }
            }
            let started = Date()
            let models = try await AsrModels.downloadAndLoad(
                to: dir,
                version: .v3,
                progressHandler: { progress in
                    let fraction = progress.fractionCompleted
                    Task { @MainActor in
                        ModelStore.shared.setProgress(fraction, for: .parakeetV3)
                    }
                })
            let asr = AsrManager(config: .default)
            try await asr.loadModels(models)
            manager = asr
            await MainActor.run { ModelStore.shared.markInstalled(.parakeetV3) }
            DebugLog.log(String(format: "parakeet loaded in %.0f ms",
                                Date().timeIntervalSince(started) * 1000))
        }
        loading = task
        defer { loading = nil }
        do {
            try await task.value
        } catch {
            await MainActor.run { ModelStore.shared.markFailed(.parakeetV3, error: error) }
            throw error
        }
    }

    public func transcribe(fileURL: URL) async throws -> String {
        try await ensureLoaded(allowDownload: false)
        guard let manager else { throw TranscriptionError.engineUnavailable(L("error.modelMissing")) }

        let file = try AVAudioFile(forReading: fileURL)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(file.length)) else {
            throw TranscriptionError.emptyResult
        }
        try file.read(into: buffer)

        let localeID = UserDefaults.standard.string(forKey: "stt.locale") ?? "de-DE"
        let language: Language? = localeID.hasPrefix("de") ? .german
                                : localeID.hasPrefix("en") ? .english : nil
        var state = TdtDecoderState.make()
        let result = try await manager.transcribe(buffer, decoderState: &state, language: language)
        let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TranscriptionError.emptyResult }
        return text
    }
}
