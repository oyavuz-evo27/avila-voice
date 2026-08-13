import AppKit
import ApplicationServices

/// Gathers optional context around a dictation (per-mode opt-in): frontmost app,
/// selected text, clipboard. Screen text via Vision OCR follows in a later phase.
@MainActor
enum ContextCollector {

    static func collect() -> DictationContext {
        var context = DictationContext()
        context.frontmostApp = NSWorkspace.shared.frontmostApplication?.localizedName
        context.clipboardText = NSPasteboard.general.string(forType: .string)
        context.selectedText = selectedText()
        // TODO(phase 2): context.screenText via ScreenCaptureKit + Vision OCR
        return context
    }

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
}
