import AppKit
import AVFAudio
import Combine
import SwiftUI
import AvilaKit

enum DictationPhase: Equatable {
    case idle
    case recording
    case processing      // transcribing + enhancing
    case result(inserted: Bool)
    case error(String)
    /// Silent dictation: subtle yellow marker, message only on hover, 2 s.
    case noSpeech
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

    // Engines: Apple (system, zero download) and the optional quality tier.
    let appleSTT = SpeechAnalyzerEngine()
    let parakeetSTT = ParakeetEngine()
    let appleLLM = FoundationModelsEngine()
    let ollamaLLM = OllamaEngine()

    /// Selected engines (persisted). Fall back to Apple when the optional model
    /// is not installed, so a dictation never fails because of a settings choice.
    @Published var sttChoice: String = UserDefaults.standard.string(forKey: "engine.stt") ?? "apple" {
        didSet { UserDefaults.standard.set(sttChoice, forKey: "engine.stt") }
    }
    @Published var llmChoice: String = UserDefaults.standard.string(forKey: "engine.llm") ?? "apple" {
        didSet {
            UserDefaults.standard.set(llmChoice, forKey: "engine.llm")
            let mode = selectedMode
            Task { [llmEngine] in await llmEngine.prewarm(mode: mode) }
        }
    }

    var sttEngine: TranscriptionEngine {
        sttChoice == "parakeet" && ParakeetEngine.isInstalled() ? parakeetSTT : appleSTT
    }
    var llmEngine: EnhancementEngine {
        llmChoice == "ollama" ? ollamaLLM : appleLLM
    }
    /// The live (streaming) transcriber only exists for Apple's engine.
    var liveTranscriptionAvailable: Bool { !(sttChoice == "parakeet" && ParakeetEngine.isInstalled()) }

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
        Sounds.preload()
        Task.detached { [appleSTT] in await appleSTT.warmUp() }
        if sttChoice == "parakeet" { Task.detached { [parakeetSTT] in await parakeetSTT.warmUp() } }
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
        do {
            livePreview = ""
            liveActive = false
            // Live transcription: start the analyzer session first so even the
            // pre-roll buffers reach it. Failure is non-fatal (file STT fallback).
            let locale = Locale(identifier: UserDefaults.standard.string(forKey: "stt.locale") ?? "de-DE")
            if liveTranscriptionAvailable {
                let transcriber = liveTranscriber
                Task {
                    do {
                        try await transcriber.start(locale: locale)
                        await MainActor.run { self.liveActive = true }
                    } catch {
                        DebugLog.log("live stt unavailable — file fallback: \(error.localizedDescription)")
                    }
                }
            }
            try recorder.start()
            setPhase(.recording)
            Sounds.playStart()
            let mode = selectedMode
            // Prewarm the LLM WHILE the user speaks — free warm-up time that covers
            // exactly the demand (issue #3: every dictation after the first ran on a
            // cold session, ~2x latency).
            Task { [llmEngine] in await llmEngine.prewarm(mode: mode) }
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
        // Visual feedback FIRST: the pill switches to processing in the very same
        // run-loop turn as the key release — recorder teardown, sound and pipeline
        // setup follow. (Previously the pill kept its recording look for the
        // ~0.5 s of synchronous stop work, which read as a hang.)
        setPhase(.processing)
        streamingPreview = ""
        guard let (url, duration) = recorder.stop() else {
            setPhase(.idle)
            return
        }
        Sounds.playStop()
        let useLive = liveActive
        liveActive = false
        if !useLive { liveTranscriber.cancel() }
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
                    self.showNoSpeech()
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
                // The AX focus probe is blocking IPC into the target app — off the
                // main thread. Re-validate AFTER it resolves: a cancel, a new recording
                // or the watchdog may have moved the phase while we were suspended.
                let editable = await Task.detached(priority: .userInitiated) {
                    TextInserter.hasEditableFocus()
                }.value
                guard !Task.isCancelled, self.pipelineGeneration == generation,
                      case .processing = self.phase else { return }
                self.deliver(raw: raw, final: final, mode: mode, duration: duration,
                             editable: editable)
            } catch {
                DebugLog.log(String(format: "timing: pipeline failed after %.0f ms — %@",
                                    Date().timeIntervalSince(pipelineStarted) * 1000,
                                    error.localizedDescription))
                guard !Task.isCancelled, self.pipelineGeneration == generation,
                      case .processing = self.phase else { return }
                self.handlePipelineError(error)
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

    /// Synchronous on purpose: no suspension between the final generation/phase
    /// check and the paste, so a cancel can never slip in between.
    private func deliver(raw: String, final: String, mode: Mode, duration: Double,
                         editable: Bool) {
        streamingPreview = ""
        livePreview = ""
        let insertStarted = Date()
        let inserted = editable && TextInserter.insert(final)
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
        // Brief confirmation, then back to idle (the copy circle keeps the text
        // reachable at any time).
        autoReset(after: 2) { if case .result = $0 { return true }; return false }
    }

    /// Returns the pill to idle after `seconds` — unless the phase moved on meanwhile.
    private func autoReset(after seconds: Double,
                           while matches: @escaping @Sendable (DictationPhase) -> Bool) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { [weak self] in
            guard let self, matches(self.phase) else { return }
            self.setPhase(.idle)
        }
    }

    /// Silent dictation: a brief yellow marker (message on hover), no error bubble.
    private func showNoSpeech() {
        setPhase(.noSpeech)
        autoReset(after: 2) { $0 == .noSpeech }
    }

    /// Shows an error in the pill and clears it automatically.
    private func setError(_ message: String) {
        setPhase(.error(message))
        autoReset(after: 6) { if case .error = $0 { return true }; return false }
    }

    /// Routes pipeline errors: empty transcripts are typed (TranscriptionError.
    /// emptyResult), not string-matched — no coupling between two localization tables.
    private func handlePipelineError(_ error: Error) {
        if case TranscriptionError.emptyResult = error {
            showNoSpeech()
        } else {
            setError(error.localizedDescription)
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

/// Start/stop chimes. Played on a dedicated background queue: BOTH NSSound and
/// AVAudioPlayer block the calling thread for ~200–340 ms on play() (measured — the
/// audio output route is opened synchronously), which froze the pill at recording
/// start when called from the main thread.
enum Sounds {
    nonisolated(unsafe) private static var start: AVAudioPlayer?
    nonisolated(unsafe) private static var stop: AVAudioPlayer?
    private static let queue = DispatchQueue(label: "avila.sounds", qos: .userInteractive)

    static var enabled: Bool {
        UserDefaults.standard.object(forKey: "sounds.enabled") as? Bool ?? true
    }

    private static func makePlayer(_ name: String) -> AVAudioPlayer? {
        let url = URL(fileURLWithPath: "/System/Library/Sounds/\(name).aiff")
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.volume = 0.25 // subtle — a confirmation, not an alert
            player.prepareToPlay()
            return player
        } catch {
            DebugLog.log("sound '\(name)' unavailable — \(error.localizedDescription)")
            return nil
        }
    }

    /// Prepare both players (and open the output route once) off the main thread.
    static func preload() {
        guard enabled else { return }
        queue.async {
            start = makePlayer("Tink")
            stop = makePlayer("Pop")
        }
    }

    static func playStart() { play { start } }
    static func playStop() { play { stop } }

    private static func play(_ which: @escaping @Sendable () -> AVAudioPlayer?) {
        guard enabled else { return }
        queue.async {
            if start == nil && stop == nil { start = makePlayer("Tink"); stop = makePlayer("Pop") }
            guard let player = which() else { return }
            player.currentTime = 0
            player.play()
        }
    }
}
