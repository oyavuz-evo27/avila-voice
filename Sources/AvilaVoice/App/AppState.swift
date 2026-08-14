import AppKit
import AVFAudio
import Combine
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

    @Published var phase: DictationPhase = .idle {
        didSet { hotkeys.recordingActive = (phase == .recording) }
    }
    @Published var audioLevel: Float = 0
    @Published var modes: [Mode] = Mode.builtins
    @Published var selectedModeID: UUID = Mode.standard.id
    @Published var dictionaryWords: [String] = []
    @Published var pttBinding: HotkeyBinding?
    @Published var handsFreeBinding: HotkeyBinding?
    @Published var hotkeysActive = false

    let history = HistoryStore()
    let stats = StatsStore()

    private let recorder = AudioRecorder()
    private let hotkeys = HotkeyManager()
    private let sttEngine: TranscriptionEngine = SpeechAnalyzerEngine()
    private let llmEngine: EnhancementEngine = FoundationModelsEngine()

    /// True while a push-to-talk hold is in progress (started on key down).
    private var pushToTalkActive = false
    /// Invalidates stale pipeline tasks: only the task with the current generation
    /// may publish results — a later recording can never be overwritten by an
    /// earlier, still-running pipeline.
    private var pipelineGeneration = 0
    private var pipelineTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()

    var selectedMode: Mode {
        modes.first { $0.id == selectedModeID } ?? .standard
    }

    private init() {
        loadModes()
        loadDictionary()
        loadBindings()
        // Forward nested store changes so views observing AppState refresh live.
        history.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        stats.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    // MARK: - Lifecycle

    func startServices() {
        recorder.onLevel = { [weak self] level in
            DispatchQueue.main.async { self?.audioLevel = level }
        }
        recorder.onConfigurationChange = { [weak self] in
            DispatchQueue.main.async {
                guard let self, case .recording = self.phase else { return }
                self.recorder.cancel()
                self.pushToTalkActive = false
                self.setError(L("error.deviceChanged"))
            }
        }
        syncBindingsToManager()
        hotkeys.onPTTDown = { [weak self] in self?.hotkeyDown() }
        hotkeys.onPTTUp = { [weak self] held in self?.hotkeyUp(heldFor: held) }
        hotkeys.onHandsFreeToggle = { [weak self] in self?.handsFreeToggle() }
        hotkeys.onEscapeCancel = { [weak self] in self?.cancelRecording() }
        hotkeys.onStatusChange = { [weak self] active in self?.hotkeysActive = active }
        hotkeys.start()
        Task.detached { [sttEngine] in await sttEngine.warmUp() }
    }

    // MARK: - Hotkey bindings

    func setBinding(_ binding: HotkeyBinding?, for role: HotkeyRole) {
        switch role {
        case .pushToTalk:
            if binding != nil && binding == handsFreeBinding { handsFreeBinding = nil }
            pttBinding = binding
        case .handsFree:
            if binding != nil && binding == pttBinding { pttBinding = nil }
            handsFreeBinding = binding
        }
        persistBindings()
        syncBindingsToManager()
    }

    /// Arms the recorder: the next key/mouse press becomes the binding for `role`.
    func captureBinding(for role: HotkeyRole,
                        completion: @escaping @MainActor (Bool) -> Void) {
        hotkeys.setCaptureHandler { [weak self] captured in
            if let captured { self?.setBinding(captured, for: role) }
            completion(captured != nil)
        }
    }

    func cancelCapture() {
        hotkeys.setCaptureHandler(nil)
    }

    private func syncBindingsToManager() {
        hotkeys.pttBinding = pttBinding
        hotkeys.handsFreeBinding = handsFreeBinding
    }

    private func loadBindings() {
        pttBinding = Self.decodeBinding(key: "hotkeys.ptt") ?? .defaultPushToTalk
        handsFreeBinding = Self.decodeBinding(key: "hotkeys.handsFree") ?? .defaultHandsFree
        // An explicitly cleared binding is stored as empty data.
        if let data = UserDefaults.standard.data(forKey: "hotkeys.ptt"), data.isEmpty {
            pttBinding = nil
        }
        if let data = UserDefaults.standard.data(forKey: "hotkeys.handsFree"), data.isEmpty {
            handsFreeBinding = nil
        }
    }

    private func persistBindings() {
        Self.encodeBinding(pttBinding, key: "hotkeys.ptt")
        Self.encodeBinding(handsFreeBinding, key: "hotkeys.handsFree")
    }

    private static func decodeBinding(key: String) -> HotkeyBinding? {
        guard let data = UserDefaults.standard.data(forKey: key), !data.isEmpty else {
            return nil
        }
        return try? JSONDecoder().decode(HotkeyBinding.self, from: data)
    }

    private static func encodeBinding(_ binding: HotkeyBinding?, key: String) {
        if let binding, let data = try? JSONEncoder().encode(binding) {
            UserDefaults.standard.set(data, forKey: key)
        } else {
            UserDefaults.standard.set(Data(), forKey: key)
        }
    }

    // MARK: - Hotkey semantics

    /// Push-to-talk key: hold = record while held, short tap = toggle.
    private func hotkeyDown() {
        switch phase {
        case .recording, .processing:
            break // recording: tap-up decides; processing: ignore
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

    /// Hands-free key: every press toggles.
    private func handsFreeToggle() {
        switch phase {
        case .recording:
            pushToTalkActive = false
            finishRecording()
        case .processing:
            break
        default:
            startRecording()
        }
    }

    // MARK: - Pipeline

    func startRecording() {
        // Never start while recording or while a pipeline is still delivering —
        // a second recorder start would corrupt state (and leak the audio tap).
        guard phase != .recording, phase != .processing else { return }
        PillPanel.shared.reposition() // jump to the screen the user is working on
        do {
            try recorder.start()
            phase = .recording
            Sounds.playStart()
        } catch {
            setError(LF("error.microphone", error.localizedDescription))
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
        pipelineGeneration += 1
        let generation = pipelineGeneration

        pipelineTask = Task { [sttEngine, llmEngine] in
            defer { try? FileManager.default.removeItem(at: url) }
            do {
                // A dead capture chain produces an (almost) empty file — fail fast
                // instead of feeding it to the STT engine.
                let file = try AVAudioFile(forReading: url)
                guard Double(file.length) / file.processingFormat.sampleRate >= 0.3 else {
                    self.setError(L("error.noSpeech"))
                    return
                }
                let context: DictationContext? = mode.context.any
                    ? await ContextCollector.collect(mode.context)
                    : nil
                let raw = try await sttEngine.transcribe(fileURL: url)
                guard !Task.isCancelled else { return }
                // The LLM step must never lose a successful transcript: any
                // enhancement failure (guardrails, context window) falls back to raw.
                var final = raw
                if await llmEngine.isAvailable() {
                    do {
                        final = try await llmEngine.enhance(transcript: raw, mode: mode,
                                                            dictionary: dictionary,
                                                            context: context)
                    } catch {
                        NSLog("AvilaVoice: enhancement failed, using raw transcript — \(error.localizedDescription)")
                    }
                }
                guard !Task.isCancelled, self.pipelineGeneration == generation,
                      case .processing = self.phase else { return }
                self.deliver(raw: raw, final: final, mode: mode, duration: duration)
            } catch {
                guard !Task.isCancelled, self.pipelineGeneration == generation,
                      case .processing = self.phase else { return }
                self.setError(error.localizedDescription)
            }
        }

        // Watchdog: a hung model download or LLM call must not freeze the app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            guard let self, self.pipelineGeneration == generation,
                  case .processing = self.phase else { return }
            self.pipelineTask?.cancel()
            self.setError(L("error.timeout"))
        }
    }

    func cancelRecording() {
        guard case .recording = phase else { return }
        recorder.cancel()
        pushToTalkActive = false
        phase = .idle
    }

    func cancelProcessing() {
        guard case .processing = phase else { return }
        pipelineGeneration += 1 // invalidate the running task's delivery
        pipelineTask?.cancel()
        pipelineTask = nil
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

    /// Shows an error in the pill and clears it automatically.
    private func setError(_ message: String) {
        phase = .error(message)
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if case .error = self?.phase { self?.phase = .idle }
        }
    }

    func copyLastResult() {
        guard let last = history.last else { return }
        TextInserter.copyToClipboard(last.finalText)
    }

    // MARK: - Modes & dictionary persistence

    func loadModes() {
        if let data = UserDefaults.standard.data(forKey: "modes.all"),
           let stored = try? JSONDecoder().decode([Mode].self, from: data) {
            var result = stored
            var insertIndex = 0
            for builtin in Mode.builtins {
                if !result.contains(where: { $0.id == builtin.id }) {
                    result.insert(builtin, at: min(insertIndex, result.count))
                }
                insertIndex += 1
            }
            modes = result
        } else if let data = UserDefaults.standard.data(forKey: "modes.custom"),
                  let custom = try? JSONDecoder().decode([Mode].self, from: data) {
            modes = Mode.builtins + custom // migrate from the old storage key
            saveModes()
        }
    }

    func saveModes() {
        if let data = try? JSONEncoder().encode(modes) {
            UserDefaults.standard.set(data, forKey: "modes.all")
        }
    }

    func addCustomMode() -> UUID {
        let mode = Mode(name: L("New mode"), systemPrompt: "")
        modes.append(mode)
        saveModes()
        return mode.id
    }

    func deleteMode(id: UUID) {
        guard let mode = modes.first(where: { $0.id == id }), !mode.isBuiltin else { return }
        modes.removeAll { $0.id == id }
        if selectedModeID == id { selectedModeID = Mode.standard.id }
        saveModes()
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
    static func playStart() { play("Tink") }
    static func playStop() { play("Pop") }

    private static func play(_ name: String) {
        guard enabled, let sound = NSSound(named: name) else { return }
        sound.volume = 0.25 // subtle — a confirmation, not an alert
        sound.play()
    }
}
