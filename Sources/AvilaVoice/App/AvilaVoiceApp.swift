import AppKit
import SwiftUI

@main
struct AvilaVoiceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var state = AppState.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(state)
        } label: {
            menuBarIcon
        }

        Settings {
            SettingsView()
                .environmentObject(state)
        }
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        switch state.phase {
        case .recording:
            Image(systemName: "waveform.circle.fill")
        case .processing:
            Image(systemName: "hourglass.circle")
        default:
            if let icon = Self.brandIcon {
                Image(nsImage: icon)
            } else {
                Image(systemName: "waveform.circle")
            }
        }
    }

    /// The Amosia waveform logo as a template image (adapts to the menu bar theme).
    static let brandIcon: NSImage? = {
        guard let url = Bundle.module.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        return image
    }()
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if case .recording = state.phase {
                Button("Stop Dictation") { state.finishRecording() }
                Button("Cancel Dictation") { state.cancelRecording() }
            } else {
                Button("Start Dictation") { state.startRecording() }
            }

            Divider()

            Picker("Mode", selection: $state.selectedModeID) {
                ForEach(state.modes) { mode in
                    Text(mode.name).tag(mode.id)
                }
            }

            Divider()

            if let last = state.history.last {
                Button("Copy Last Dictation") { state.copyLastResult() }
                    .help(last.finalText)
            }

            Button("Settings…") { openSettings() }

            Divider()

            Button("Check for Updates…") {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/oyavuz-evo27/avila-voice/releases")!)
            }
            Button("Quit Avila Voice") { NSApp.terminate(nil) }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppState.shared.startServices()
            PillPanel.shared.show()
            PermissionRequester.requestOnFirstLaunch()
        }
    }
}

@MainActor
enum PermissionRequester {
    static func requestOnFirstLaunch() {
        // Microphone permission is requested automatically on first recording.
        // Accessibility (text insertion + hotkeys) must be granted manually:
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
