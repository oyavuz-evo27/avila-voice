import AppKit
import SwiftUI

enum DictationPhase: Equatable {
    case idle
    case recording
    case processing      // transcribing + enhancing
    case result(inserted: Bool)
    case error(String)
}

/// Central state and pipeline coordinator.
@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: DictationPhase = .idle
    @Published var audioLevel: Float = 0
    @Published var modes: [Mode] = Mode.builtins
    @Published var selectedModeID: UUID = Mode.standard.id
    @Published var dictionaryWords: [String] = []

    let history = HistoryStore()
    let stats = StatsStore()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyManager()
    private var sttEngine: TranscriptionEngine = SpeechAnalyzerEngine()
    private var llmEngine: EnhancementEngine = FoundationModelsEngine()

    /// True while a push-to-talk hold is in progress (started on key down).
    private var pushToTalkActive = false

    var selectedMode: Mode {
        modes.first { $0.id == selectedModeID } ?? .standard
    }

    private init() {
        loadCustomModes()
        loadDictionary()
    }

    // MARK: - Lifecycle

    func startServices() {
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.audioLevel = level }
        }
        hotkeys.onPressDown = { [weak self] in self?.hotkeyDown() }
        hotkeys.onPressUp = { [weak self] held in self?.hotkeyUp(heldFor: held) }
        hotkeys.start()
        Task.detached { [sttEngine] in await sttEngine.warmUp() }
    }

    // MARK: - Hotkey semantics (hold = push-to-talk, tap = toggle)

    private func hotkeyDown() {
        switch phase {
        case .recording:
            break // tap-up will decide
        default:
            pushToTalkActive = true
            startRecording()
        }
    }

    private func hotkeyUp(heldFor: TimeInterval) {
        if pushToTalkActive {
            pushToTalkActive = false
            if heldFor >= HotkeyManager.tapThreshold {
                finishRecording()      // held → push-to-talk ended
            }
            // else: it was a tap that just started toggle mode → keep recording
        } else if case .recording = phase {
            finishRecording()          // second tap ends toggle recording
        }
    }

    // MARK: - Pipeline

    func startRecording() {
        guard phase != .recording else { return }
        do {
            try recorder.start()
            phase = .recording
            Sounds.playStart()
        } catch {
            phase = .error(LF("error.microphone", error.localizedDescription))
        }
    }

    func finishRecording() {
        guard case .recording = phase else { return }
        guard let (url, duration) = recorder.stop() else {
            phase = .idle
            return
        }
        Sounds.playStop()
        phase = .processing
        let mode = selectedMode
        let dictionary = dictionaryWords
        let context = mode.useContext ? ContextCollector.collect() : nil

        Task { [sttEngine, llmEngine] in
            do {
                let raw = try await sttEngine.transcribe(fileURL: url)
                let final: String
                if await llmEngine.isAvailable() {
                    final = try await llmEngine.enhance(transcript: raw, mode: mode,
                                                        dictionary: dictionary, context: context)
                } else {
                    final = raw
                }
                try? FileManager.default.removeItem(at: url)
                self.deliver(raw: raw, final: final, mode: mode, duration: duration)
            } catch {
                try? FileManager.default.removeItem(at: url)
                self.phase = .error(error.localizedDescription)
            }
        }
    }

    func cancelRecording() {
        guard case .recording = phase else { return }
        recorder.cancel()
        pushToTalkActive = false
        phase = .idle
    }

    private func deliver(raw: String, final: String, mode: Mode, duration: Double) {
        let inserted = TextInserter.hasEditableFocus() && TextInserter.insert(final)
        if !inserted {
            TextInserter.copyToClipboard(final)
        }
        let words = final.split { $0.isWhitespace || $0.isNewline }.count
        stats.record(words: words, speakingSeconds: duration)
        history.add(DictationRecord(rawTranscript: raw, finalText: final,
                                    modeName: mode.displayName, wasInserted: inserted,
                                    durationSeconds: duration))
        phase = .result(inserted: inserted)
        // Return to idle after a grace period (pill hover keeps the text reachable).
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if case .result = self?.phase { self?.phase = .idle }
        }
    }

    func copyLastResult() {
        guard let last = history.last else { return }
        TextInserter.copyToClipboard(last.finalText)
    }

    // MARK: - Modes & dictionary persistence

    func loadCustomModes() {
        if let data = UserDefaults.standard.data(forKey: "modes.custom"),
           let custom = try? JSONDecoder().decode([Mode].self, from: data) {
            modes = Mode.builtins + custom
        }
    }

    func saveCustomModes() {
        let custom = modes.filter { !$0.isBuiltin }
        if let data = try? JSONEncoder().encode(custom) {
            UserDefaults.standard.set(data, forKey: "modes.custom")
        }
    }

    func loadDictionary() {
        dictionaryWords = UserDefaults.standard.stringArray(forKey: "dictionary.words") ?? []
    }

    func saveDictionary() {
        UserDefaults.standard.set(dictionaryWords, forKey: "dictionary.words")
    }
}

enum Sounds {
    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "sounds.enabled") as? Bool ?? true
    }
    static func playStart() { if enabled { NSSound(named: "Tink")?.play() } }
    static func playStop() { if enabled { NSSound(named: "Pop")?.play() } }
}
