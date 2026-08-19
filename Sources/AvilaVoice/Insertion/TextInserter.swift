import AppKit
import ApplicationServices

/// Inserts text at the cursor of the frontmost app. Strategy: if a text element has
/// focus, paste via Cmd+V (preserving the user's clipboard); otherwise report failure so
/// the text stays available in the pill.
@MainActor
enum TextInserter {

    /// Controls whose value is settable but that cannot take pasted text — the
    /// settable-fallback must not "insert" into these.
    nonisolated private static let nonTextRoles: Set<String> = [
        "AXSlider", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXIncrementor", "AXButton", "AXDisclosureTriangle", "AXValueIndicator",
    ]

    /// True if the frontmost app has a focused element that accepts text.
    /// Secure fields are excluded: a dictated password must never be pasted, logged
    /// to history, or counted in statistics.
    nonisolated static func hasEditableFocus() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide,
                                                kAXFocusedUIElementAttribute as CFString,
                                                &focused)
        guard err == .success, let element = focused else { return false }
        let axElement = element as! AXUIElement

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRef)
        if subroleRef as? String == "AXSecureTextField" {
            return false
        }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String
        if let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) {
            return true
        }
        if let role, Self.nonTextRoles.contains(role) {
            return false
        }
        // Many apps (browsers, Electron) expose editable areas differently — accept any
        // remaining element whose value is settable.
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)
        return settable.boolValue
    }

    /// Pastes `text` into the frontmost app via Cmd+V, restoring the clipboard afterwards.
    static func insert(_ text: String) -> Bool {
        guard AXIsProcessTrusted() else { return false }

        let pasteboard = NSPasteboard.general
        let savedItems = pasteboard.pasteboardItems?.compactMap { item -> [NSPasteboard.PasteboardType: Data]? in
            var copy: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) { copy[type] = data }
            }
            return copy.isEmpty ? nil : copy
        } ?? []

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let ourChangeCount = pasteboard.changeCount

        let source = CGEventSource(stateID: .combinedSessionState)
        let vDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)  // V
        let vUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        vDown?.flags = .maskCommand
        vUp?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        vUp?.post(tap: .cghidEventTap)

        // Restore the clipboard after the paste has been processed — but only if the
        // board still holds our text. If the user (or an app) wrote to it meanwhile,
        // restoring would destroy their newer content.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            guard pasteboard.changeCount == ourChangeCount else { return }
            pasteboard.clearContents()
            var restored: [NSPasteboardItem] = []
            for itemData in savedItems {
                let item = NSPasteboardItem()
                for (type, data) in itemData { item.setData(data, forType: type) }
                restored.append(item)
            }
            if !restored.isEmpty {
                pasteboard.writeObjects(restored)
            }
        }
        return true
    }

    /// Copies text to the clipboard (used by the pill's copy button).
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
