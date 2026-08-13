import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label(L("General"), systemImage: "gearshape") }
            ModesSettings()
                .tabItem { Label(L("Modes"), systemImage: "wand.and.stars") }
            DictionarySettings()
                .tabItem { Label(L("Dictionary"), systemImage: "character.book.closed") }
            StatsSettings()
                .tabItem { Label(L("Statistics"), systemImage: "chart.bar") }
        }
        .frame(width: 560, height: 440)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @AppStorage("sounds.enabled") private var soundsEnabled = true
    @AppStorage("stt.locale") private var sttLocale = "de-DE"
    @AppStorage("audio.inputDeviceUID") private var micUID = ""
    @State private var devices: [AudioInputDevice] = []

    var body: some View {
        Form {
            Section {
                Picker(L("Microphone"), selection: $micUID) {
                    Text(L("System default")).tag("")
                    ForEach(devices) { device in
                        Text(device.name).tag(device.uid)
                    }
                }
                Picker(L("Dictation language"), selection: $sttLocale) {
                    Text(L("German")).tag("de-DE")
                    Text(L("English")).tag("en-US")
                }
                Toggle(L("Play sounds on start/stop"), isOn: $soundsEnabled)
            }
            Section {
                HotkeyRecorderRow(title: L("Push-to-talk"), role: .pushToTalk)
                HotkeyRecorderRow(title: L("Hands-free"), role: .handsFree)
                Text(L("hotkey.hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { devices = AudioDeviceManager.inputDevices() }
    }
}

/// One row of the hotkey recorder: shows the current binding; clicking arms capture,
/// the next key or extra mouse button becomes the new binding (Esc cancels).
struct HotkeyRecorderRow: View {
    let title: String
    let role: HotkeyRole
    @EnvironmentObject var state: AppState
    @State private var capturing = false

    private var binding: HotkeyBinding? {
        role == .pushToTalk ? state.pttBinding : state.handsFreeBinding
    }

    var body: some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Button {
                    if capturing {
                        state.cancelCapture()
                        capturing = false
                    } else {
                        capturing = true
                        state.captureBinding(for: role) { _ in capturing = false }
                    }
                } label: {
                    Text(capturing
                         ? L("Press key…")
                         : binding.map { L($0.displayName) } ?? L("None"))
                        .frame(minWidth: 110)
                }
                if binding != nil && !capturing {
                    Button {
                        state.setBinding(nil, for: role)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                }
            }
        }
    }
}

// MARK: - Modes

struct ModesSettings: View {
    @EnvironmentObject var state: AppState
    @State private var selection: UUID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(state.modes) { mode in
                        Text(mode.displayName).tag(mode.id)
                    }
                }
                .listStyle(.sidebar)
                HStack(spacing: 8) {
                    Button {
                        selection = state.addCustomMode()
                    } label: {
                        Image(systemName: "plus")
                    }
                    Button {
                        if let selection { state.deleteMode(id: selection) }
                        selection = nil
                    } label: {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedMode?.isBuiltin != false)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(width: 150)

            Divider()

            if let index = state.modes.firstIndex(where: { $0.id == selection }) {
                ModeEditor(mode: $state.modes[index])
                    .id(selection)
            } else {
                Text(L("modes.select"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { if selection == nil { selection = state.modes.first?.id } }
        .onChange(of: state.modes) { _, _ in state.saveModes() }
    }

    private var selectedMode: Mode? {
        state.modes.first { $0.id == selection }
    }
}

struct ModeEditor: View {
    @Binding var mode: Mode

    var body: some View {
        Form {
            Section {
                TextField(L("Name"), text: $mode.name)
                    .disabled(mode.isBuiltin)
            }
            Section(L("AI instruction")) {
                TextEditor(text: $mode.systemPrompt)
                    .font(.system(size: 11))
                    .frame(minHeight: 120)
                    .disabled(mode.isBuiltin)
                if mode.isBuiltin {
                    Text(L("builtin.readonly"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section(L("Context")) {
                Toggle(L("Active app"), isOn: $mode.context.activeApp)
                Toggle(L("Selected text"), isOn: $mode.context.selectedText)
                Toggle(L("Clipboard"), isOn: $mode.context.clipboard)
                Toggle(L("Screen text (screenshot OCR)"), isOn: $mode.context.screenshotOCR)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dictionary

struct DictionarySettings: View {
    @EnvironmentObject var state: AppState
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text(L("dictionary.hint"))
                .font(.caption)
            List {
                ForEach(state.dictionaryWords, id: \.self) { word in
                    Text(word)
                }
                .onDelete { offsets in
                    state.dictionaryWords.remove(atOffsets: offsets)
                    state.saveDictionary()
                }
            }
            HStack {
                TextField(L("dictionary.placeholder"), text: $newWord)
                    .onSubmit(addWord)
                Button(L("Add"), action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding()
    }

    private func addWord() {
        let word = newWord.trimmingCharacters(in: .whitespaces)
        guard !word.isEmpty, !state.dictionaryWords.contains(word) else { return }
        state.dictionaryWords.append(word)
        state.saveDictionary()
        newWord = ""
    }
}

// MARK: - Statistics

struct StatsSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            statsRow(L("Today"), state.stats.today)
            statsRow(L("Last 7 days"), state.stats.thisWeek)
            statsRow(L("Last 30 days"), state.stats.thisMonth)
            Section {
                TypingSpeedField()
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    @ViewBuilder
    private func statsRow(_ label: String, _ summary: StatsStore.Summary) -> some View {
        LabeledContent(label) {
            VStack(alignment: .trailing) {
                Text(LF("%d words", summary.words))
                Text(LF("saved %d min", Int(summary.savedSeconds / 60)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct TypingSpeedField: View {
    @EnvironmentObject var state: AppState
    @State private var wpm: Double = 40

    var body: some View {
        HStack {
            Text(L("Assumed typing speed"))
            Slider(value: $wpm, in: 20...90, step: 5)
            Text(LF("%d wpm", Int(wpm)))
                .monospacedDigit()
        }
        .onAppear { wpm = state.stats.typingWordsPerMinute }
        .onChange(of: wpm) { _, newValue in
            state.stats.typingWordsPerMinute = newValue
        }
    }
}
