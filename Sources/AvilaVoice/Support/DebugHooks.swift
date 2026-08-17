import AppKit
import CoreGraphics
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Development-only instrumentation, triggered via distributed notifications:
///   avila.debug.animate — fakes an idle→recording→idle phase flip while capturing
///   a burst of screenshots of the pill region to ~/Library/Logs/AvilaVoicePill/.
/// Lets the animation be inspected frame by frame without a human eye.
@MainActor
enum DebugHooks {
    static func install() {
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("avila.debug.animate"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await runAnimationProbe()
            }
        }
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("avila.debug.dictate"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                await runRealDictationProbe()
            }
        }
        // avila.debug.installParakeet — kick off the Parakeet download exactly as
        // the Settings button would.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("avila.debug.installParakeet"), object: nil, queue: .main
        ) { _ in
            Task { @MainActor in
                DebugLog.log("debug: parakeet install requested")
                do {
                    try await AppState.shared.parakeetSTT.install()
                    DebugLog.log("debug: parakeet install finished")
                } catch {
                    DebugLog.log("debug: parakeet install FAILED — \(error.localizedDescription)")
                }
            }
        }
    }

    /// Same as the animation probe, but through the REAL pipeline — including the
    /// recorder start/stop, whose main-thread cost the fake flip cannot show.
    private static func runRealDictationProbe() async {
        DebugLog.log("debug: real dictation probe started")
        let outDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AvilaVoicePill")
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(100))
            AppState.shared.startRecording()
            try? await Task.sleep(for: .milliseconds(900))
            AppState.shared.finishRecording()
        }

        for index in 0..<30 {
            await snapshotPill(to: outDir.appendingPathComponent(String(format: "frame-%02d.png", index)))
            try? await Task.sleep(for: .milliseconds(40))
        }
        DebugLog.log("debug: real dictation probe finished")
    }

    private static func runAnimationProbe() async {
        DebugLog.log("debug: animation probe started")
        let outDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/AvilaVoicePill")
        try? FileManager.default.removeItem(at: outDir)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            AppState.shared.setPhase(.recording)   // same path as real dictation
            try? await Task.sleep(for: .milliseconds(700))
            AppState.shared.setPhase(.idle)        // covers the SHRINK too
        }

        for index in 0..<26 {
            await snapshotPill(to: outDir.appendingPathComponent(String(format: "frame-%02d.png", index)))
            try? await Task.sleep(for: .milliseconds(40))
        }
        DebugLog.log("debug: animation probe finished")
    }

    private static func snapshotPill(to url: URL) async {
        let panel = PillPanel.shared
        guard let screen = panel.screen ?? NSScreen.main,
              let displayID = screen.deviceDescription[
                  NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let display = content.displays.first(where: { $0.displayID == displayID }) else { return }
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter,
                                                                   configuration: config)
            // Crop to the panel region (Cocoa bottom-left → pixel top-left).
            let scale = CGFloat(image.width) / screen.frame.width
            let frame = panel.frame
            let crop = CGRect(x: (frame.minX - screen.frame.minX) * scale,
                              y: (screen.frame.maxY - frame.maxY) * scale,
                              width: frame.width * scale,
                              height: frame.height * scale)
            guard let cropped = image.cropping(to: crop),
                  let destination = CGImageDestinationCreateWithURL(
                      url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
            CGImageDestinationAddImage(destination, cropped, nil)
            CGImageDestinationFinalize(destination)
        } catch {
            DebugLog.log("debug: snapshot failed — \(error.localizedDescription)")
        }
    }
}
