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
    @Published var selectedModeID: UUID = Mode.standard.id {
        didSet {
            let mode = selectedMode
            Task { [llmEngine] in await llmEngine.prewarm(mode: mode) }
        }
    }
    @Published var dictionaryWords: [String] = []
    @Published var pttBinding: HotkeyBinding?
    @Published var handsFreeBinding: HotkeyBinding?
    @Published var hotkeysActive = false
    /// Growing LLM output while processing — shown in the pill's bubble.
    @Published var streamingPreview: String = ""
    /// Live transcript while recording — shown above the pill as you speak.
    @Published var livePreview: String = ""

    private let liveTranscriber = LiveTranscriber()
    private var liveActive = false

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
    /// Context capture starts WITH the recording (screenshot OCR costs up to ~0.8 s —
    /// running it at stop time put it on the critical path).
    private var pendingContext: (modeID: UUID, task: Task<DictationContext?, Never>)?
    private var cancellables = Set<AnyCancellable>()

    var selectedMode: Mode {
        modes.first { $0.id == selectedModeID } ?? modes.first ?? .standard
    }

    /// The pill's growth animation MUST be driven at the source: value-based
    /// `.animation(value:)` modifiers are ignored in the hosting panel (verified
    /// frame-by-frame), while `withAnimation` transactions render fine.
    static let phaseSpring = Animation.interpolatingSpring(mass: 1, stiffness: 400, damping: 30)

    func setPhase(_ newPhase: DictationPhase) {
        withAnimation(Self.phaseSpring) {
            phase = newPhase
        }
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
        recorder.onBuffer = { [liveTranscriber] buffer in
            liveTranscriber.append(buffer)
        }
        liveTranscriber.onPartial = { [weak self] text in
            DispatchQueue.main.async {
                guard let self, case .recording = self.phase else { return }
                self.livePreview = text
            }
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
        let mode = selectedMode
        Task { [llmEngine] in await llmEngine.prewarm(mode: mode) }
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
            livePreview = ""
            liveActive = false
            // Live transcription: start the analyzer session first so even the
            // pre-roll buffers reach it. Failure is non-fatal (file STT fallback).
            let locale = Locale(identifier: UserDefaults.standard.string(forKey: "stt.locale") ?? "de-DE")
            let transcriber = liveTranscriber
            Task {
                do {
                    try await transcriber.start(locale: locale)
                    await MainActor.run { self.liveActive = true }
                } catch {
                    DebugLog.log("live stt unavailable — file fallback: \(error.localizedDescription)")
                }
            }
            try recorder.start()
            setPhase(.recording)
            Sounds.playStart()
            let mode = selectedMode
            if mode.context.any {
                let options = mode.context
                pendingContext = (mode.id, Task { await ContextCollector.collect(options) })
            } else {
                pendingContext = nil
            }
        } catch {
            setError(LF("error.microphone", error.localizedDescription))
        }
    }

    func finishRecording() {
        guard case .recording = phase else { return }
        guard let (url, duration) = recorder.stop() else {
            setPhase(.idle)
            return
        }
        Sounds.playStop()
        streamingPreview = ""
        let useLive = liveActive
        liveActive = false
        if !useLive { liveTranscriber.cancel() }
        setPhase(.processing)
        let mode = selectedMode
        let dictionary = dictionaryWords
        pipelineGeneration += 1
        let generation = pipelineGeneration

        let startedContext = pendingContext
        pendingContext = nil

        pipelineTask = Task { [sttEngine, llmEngine] in
            defer {
                // Keep the LAST recording for recognition-quality diagnosis.
                let keep = FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent("Library/Logs/AvilaVoice-last.wav")
                try? FileManager.default.removeItem(at: keep)
                try? FileManager.default.moveItem(at: url, to: keep)
                try? FileManager.default.removeItem(at: url)
            }
            let pipelineStarted = Date()
            do {
                // A dead capture chain produces an (almost) empty file — fail fast
                // instead of feeding it to the STT engine.
                let file = try AVAudioFile(forReading: url)
                guard Double(file.length) / file.processingFormat.sampleRate >= 0.3 else {
                    self.setError(L("error.noSpeech"))
                    return
                }
                let sttStarted = Date()
                // Prefer the live session's transcript (already computed while
                // speaking); fall back to the file-based engine if it failed.
                let raw: String
                if useLive, let live = try? await liveTranscriber.finish(), !live.isEmpty {
                    raw = live
                    DebugLog.log("stt source: live")
                } else {
                    raw = try await sttEngine.transcribe(fileURL: url)
                    DebugLog.log("stt source: file")
                }
                // Context was captured at recording START (what the user was looking
                // at); only a mid-recording mode switch requires a fresh collect.
                let context: DictationContext?
                if let startedContext, startedContext.modeID == mode.id {
                    context = await startedContext.task.value
                } else if mode.context.any {
                    context = await ContextCollector.collect(mode.context)
                } else {
                    context = nil
                }
                DebugLog.log(String(format: "timing: stt+context %.0f ms (%d Zeichen)",
                                    Date().timeIntervalSince(sttStarted) * 1000, raw.count))
                DebugLog.log("stt raw: \(raw)")
                guard !Task.isCancelled else { return }
                // The LLM step must never lose a successful transcript: any
                // enhancement failure (guardrails, context window) falls back to raw.
                var final = raw
                let words = raw.split { $0.isWhitespace || $0.isNewline }.count
                // Very short dictations skip the LLM: ~350 ms saved, and the system
                // model tends to mistranslate 2–3-word inputs.
                if words >= 4, await llmEngine.isAvailable() {
                    let llmStarted = Date()
                    do {
                        final = try await llmEngine.enhance(
                            transcript: raw, mode: mode, dictionary: dictionary,
                            context: context,
                            onPartial: { partial in
                                Task { @MainActor in
                                    guard self.pipelineGeneration == generation else { return }
                                    self.streamingPreview = partial
                                }
                            })
                    } catch {
                        NSLog("AvilaVoice: enhancement failed, using raw transcript — \(error.localizedDescription)")
                    }
                    DebugLog.log(String(format: "timing: llm %.0f ms",
                                        Date().timeIntervalSince(llmStarted) * 1000))
                    // Emergency brake: an output massively longer than the dictation
                    // means the model broke role (echoed context, wrote commentary).
                    if final.count > raw.count * 3 + 300 {
                        DebugLog.log("llm output REJECTED (\(final.count) chars vs raw \(raw.count)) — inserting raw transcript")
                        final = raw
                    }
                } else if words < 4 {
                    DebugLog.log("timing: llm skipped (short dictation, \(words) words)")
                }
                guard !Task.isCancelled, self.pipelineGeneration == generation,
                      case .processing = self.phase else { return }
                self.deliver(raw: raw, final: final, mode: mode, duration: duration)
            } catch {
                DebugLog.log(String(format: "timing: pipeline failed after %.0f ms — %@",
                                    Date().timeIntervalSince(pipelineStarted) * 1000,
                                    error.localizedDescription))
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
        liveTranscriber.cancel()
        liveActive = false
        livePreview = ""
        pushToTalkActive = false
        setPhase(.idle)
    }

    func cancelProcessing() {
        guard case .processing = phase else { return }
        pipelineGeneration += 1 // invalidate the running task's delivery
        pipelineTask?.cancel()
        pipelineTask = nil
        setPhase(.idle)
    }

    private func deliver(raw: String, final: String, mode: Mode, duration: Double) {
        streamingPreview = ""
        livePreview = ""
        let insertStarted = Date()
        let inserted = TextInserter.hasEditableFocus() && TextInserter.insert(final)
        DebugLog.log(String(format: "timing: insert %.0f ms (eingefügt: %@)",
                            Date().timeIntervalSince(insertStarted) * 1000,
                            inserted ? "ja" : "nein"))
        if !inserted {
            TextInserter.copyToClipboard(final)
        }
        let words = final.split { $0.isWhitespace || $0.isNewline }.count
        stats.record(words: words, speakingSeconds: duration)
        history.add(DictationRecord(rawTranscript: raw, finalText: final,
                                    modeName: mode.displayName, wasInserted: inserted,
                                    durationSeconds: duration))
        setPhase(.result(inserted: inserted))
        // Return to idle after a grace period (pill hover keeps the text reachable).
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            if case .result = self?.phase { self?.setPhase(.idle) }
        }
    }

    /// Shows an error in the pill and clears it automatically.
    private func setError(_ message: String) {
        withAnimation(Self.phaseSpring) { phase = .error(message) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
            if case .error = self?.phase { self?.setPhase(.idle) }
        }
    }

    func copyLastResult() {
        guard let last = history.last else { return }
        TextInserter.copyToClipboard(last.finalText)
    }

    // MARK: - Modes & dictionary persistence

    func loadModes() {
        let deletedBuiltins = Set(UserDefaults.standard
            .stringArray(forKey: "modes.deletedBuiltins") ?? [])
        if let data = UserDefaults.standard.data(forKey: "modes.all"),
           let stored = try? JSONDecoder().decode([Mode].self, from: data) {
            var result = stored
            var insertIndex = 0
            for builtin in Mode.builtins {
                // Missing builtins reappear only if the user did not delete them.
                if !result.contains(where: { $0.id == builtin.id }),
                   !deletedBuiltins.contains(builtin.id.uuidString) {
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
        if modes.isEmpty { modes = [.standard] }
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
        guard modes.count > 1, let mode = modes.first(where: { $0.id == id }) else { return }
        if mode.isBuiltin {
            var deleted = UserDefaults.standard.stringArray(forKey: "modes.deletedBuiltins") ?? []
            if !deleted.contains(id.uuidString) { deleted.append(id.uuidString) }
            UserDefaults.standard.set(deleted, forKey: "modes.deletedBuiltins")
        }
        modes.removeAll { $0.id == id }
        if selectedModeID == id, let first = modes.first {
            selectedModeID = first.id
        }
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
