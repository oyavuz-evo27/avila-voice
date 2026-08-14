import AppKit
import ApplicationServices
import ScreenCaptureKit
import Vision

/// Gathers the context a mode has enabled: frontmost app, selected text, clipboard,
/// and screen text (screenshot → on-device Vision OCR). Everything stays local.
@MainActor
enum ContextCollector {

    static func collect(_ options: ContextOptions) async -> DictationContext {
        var context = DictationContext()
        if options.activeApp {
            context.frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName
        }
        if options.clipboard {
            context.clipboardText = NSPasteboard.general.string(forType: .string)
        }
        if options.selectedText {
            context.selectedText = selectedText()
        }
        if options.screenshotOCR {
            context.screenText = await screenText()
        }
        return context
    }

    // MARK: - Selected text (Accessibility)

    private static func selectedText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let element = focused else { return nil }
        let axElement = element as! AXUIElement
        var selected: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axElement,
                                            kAXSelectedTextAttribute as CFString,
                                            &selected) == .success else { return nil }
        return selected as? String
    }

    // MARK: - Screen text (ScreenCaptureKit screenshot + Vision OCR)

    /// Captures the main display and extracts its visible text on-device.
    /// Requires the Screen Recording permission (macOS asks on first use).
    private static func screenText() async -> String? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)
            guard let display = content.displays.first else { return nil }
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config)
            return try await recognizeText(in: image)
        } catch {
            NSLog("AvilaVoice: screen context failed — \(error.localizedDescription)")
            return nil
        }
    }

    /// `nonisolated` and free of completion closures: Vision invokes callbacks on its
    /// own background queue — a MainActor-bound closure there trips the Swift runtime
    /// isolation check and kills the app (SIGTRAP). perform() is synchronous, so the
    /// results are simply read afterwards on the worker queue.
    private nonisolated static func recognizeText(in image: CGImage) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .fast
                request.recognitionLanguages = ["de-DE", "en-US"]
                let handler = VNImageRequestHandler(cgImage: image)
                do {
                    try handler.perform([request])
                    let lines = (request.results ?? [])
                        .compactMap { $0.topCandidates(1).first?.string }
                    continuation.resume(returning: lines.isEmpty
                                        ? nil
                                        : lines.joined(separator: "\n"))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
