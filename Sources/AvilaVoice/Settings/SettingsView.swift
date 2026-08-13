import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ModesSettings()
                .tabItem { Label("Modes", systemImage: "wand.and.stars") }
            DictionarySettings()
                .tabItem { Label("Dictionary", systemImage: "character.book.closed") }
            StatsSettings()
                .tabItem { Label("Statistics", systemImage: "chart.bar") }
        }
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettings: View {
    @AppStorage("sounds.enabled") private var soundsEnabled = true
    @AppStorage("stt.locale") private var sttLocale = "de-DE"

    var body: some View {
        Form {
            Picker("Dictation language", selection: $sttLocale) {
                Text("German").tag("de-DE")
                Text("English").tag("en-US")
            }
            Toggle("Play sounds on start/stop", isOn: $soundsEnabled)
            LabeledContent("Hotkey", value: HotkeyBinding.default.displayName)
            Text("Hold to talk, tap to toggle. Custom hotkey configuration follows in a later build.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .padding()
    }
}

struct ModesSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading) {
            List {
                ForEach(state.modes) { mode in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(mode.name).font(.headline)
                            if mode.isBuiltin {
                                Text("built-in")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if mode.useContext {
                                Image(systemName: "eye")
                                    .font(.caption2)
                                    .help("Uses context (app, selection, clipboard)")
                            }
                        }
                        Text(mode.systemPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Text("Creating custom modes follows in a later build.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
        }
        .padding(.bottom)
    }
}

struct DictionarySettings: View {
    @EnvironmentObject var state: AppState
    @State private var newWord = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Technical terms and names that must be spelled correctly (applies to all modes):")
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
                TextField("New word (e.g. Navision)", text: $newWord)
                    .onSubmit(addWord)
                Button("Add", action: addWord)
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

struct StatsSettings: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        Form {
            statsRow("Today", state.stats.today)
            statsRow("Last 7 days", state.stats.thisWeek)
            statsRow("Last 30 days", state.stats.thisMonth)
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
                Text("\(summary.words) words")
                Text("saved \(Int(summary.savedSeconds / 60)) min")
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
            Text("Assumed typing speed")
            Slider(value: $wpm, in: 20...90, step: 5)
            Text("\(Int(wpm)) wpm")
                .monospacedDigit()
        }
        .onAppear { wpm = state.stats.typingWordsPerMinute }
        .onChange(of: wpm) { _, newValue in
            state.stats.typingWordsPerMinute = newValue
        }
    }
}
