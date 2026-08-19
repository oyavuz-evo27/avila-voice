import AppKit
import AVFoundation
import IOKit.hid
import ServiceManagement
import SwiftUI
import AvilaKit

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

    private var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }

    var body: some View {
        Group {
            Text("Avila Voice v\(version)")

            Divider()

            switch state.phase {
            case .recording:
                Button(L("Stop Dictation")) { state.finishRecording() }
                Button(L("Cancel Dictation")) { state.cancelRecording() }
            case .processing:
                Button(L("Cancel Dictation")) { state.cancelProcessing() }
            default:
                Button(L("Start Dictation")) { state.startRecording() }
            }

            Picker(L("Mode"), selection: $state.selectedModeID) {
                ForEach(state.modes) { mode in
                    Text(mode.displayName).tag(mode.id)
                }
            }

            if !state.history.records.isEmpty {
                Menu(L("History")) {
                    ForEach(state.history.records) { record in
                        Button(preview(of: record)) {
                            TextInserter.copyToClipboard(record.finalText)
                        }
                    }
                    Divider()
                    Button(L("Clear History")) { state.history.clear() }
                }
            }

            Divider()

            Button(L("Settings…")) { openSettings() }
            Button(L("Check for Updates…")) {
                NSWorkspace.shared.open(
                    URL(string: "https://github.com/oyavuz-evo27/avila-voice/releases")!)
            }

            Divider()

            Button(L("Quit Avila Voice")) { NSApp.terminate(nil) }
        }
    }

    private func preview(of record: DictationRecord) -> String {
        let text = record.finalText.replacingOccurrences(of: "\n", with: " ")
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { @MainActor in
            AppState.shared.startServices()
            PillPanel.shared.show()
            PermissionRequester.requestOnFirstLaunch()
            registerLoginItemOnFirstLaunch()
            DebugHooks.install()
            MainThreadWatchdog.shared.start()
        }
    }

    /// Launch at login defaults to ON (per project decision) — registered once;
    /// afterwards the settings toggle is the single source of truth.
    @MainActor
    private func registerLoginItemOnFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: "launchAtLogin.initialized") else { return }
        UserDefaults.standard.set(true, forKey: "launchAtLogin.initialized")
        try? SMAppService.mainApp.register()
    }
}

@MainActor
enum PermissionRequester {
    static func requestOnFirstLaunch() {
        // Microphone: request EXPLICITLY. Relying on the implicit first-recording
        // prompt fails silently when a stale TCC entry exists — the engine then
        // runs but never delivers a single buffer.
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DebugLog.log("mic permission prompt answered: \(granted ? "granted" : "DENIED")")
            }
        case .denied, .restricted:
            DebugLog.log("mic permission DENIED — enable it in System Settings → Privacy & Security → Microphone")
        case .authorized:
            break
        @unknown default:
            break
        }
        // Accessibility (text insertion + hotkeys) must be granted manually:
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
        // Input Monitoring (global event tap):
        if IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) != kIOHIDAccessTypeGranted {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        }
        DebugLog.log("startup permissions — mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue), accessibility: \(AXIsProcessTrusted()), input monitoring: \(IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted)")
    }

    static func openPrivacySettings() {
        let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
