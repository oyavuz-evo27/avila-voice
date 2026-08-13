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
        .frame(width: 480, height: 360)
    }
}

struct GeneralSettings: View {
    @AppStorage("sounds.enabled") private var soundsEnabled = true
    @AppStorage("stt.locale") private var sttLocale = "de-DE"

    var body: some View {
        Form {
            Picker(L("Dictation language"), selection: $sttLocale) {
                Text(L("German")).tag("de-DE")
                Text(L("English")).tag("en-US")
            }
            Toggle(L("Play sounds on start/stop"), isOn: $soundsEnabled)
            LabeledContent(L("Hotkey"), value: L(HotkeyBinding.default.displayName))
            Text(L("hotkey.hint"))
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
                            Text(mode.displayName).font(.headline)
                            if mode.isBuiltin {
                                Text(L("built-in"))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            if mode.useContext {
                                Image(systemName: "eye")
                                    .font(.caption2)
                                    .help(L("context.help"))
                            }
                        }
                        Text(mode.systemPrompt)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            Text(L("modes.hint"))
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
