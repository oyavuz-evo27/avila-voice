import AppKit
import AvilaKit
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
    /// Tri-state focus verdict (issue #14): the AX write path needs a settable
    /// element, but the Cmd+V paste path does NOT — an AXWebArea (Electron/web
    /// views) takes paste just fine. Only secure fields, known non-text controls
    /// and "no focused element at all" block insertion entirely.
    enum FocusAccess { case editable, pasteOnly, blocked }

    nonisolated static func focusProbe() -> (access: FocusAccess, detail: String) {
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        guard AXIsProcessTrusted() else { return (.blocked, "\(app): AX not trusted") }
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(systemWide,
                                                kAXFocusedUIElementAttribute as CFString,
                                                &focused)
        guard err == .success, let element = focused else {
            return (.blocked, "\(app): no focused element (AXError \(err.rawValue))")
        }
        let axElement = element as! AXUIElement

        var subroleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXSubroleAttribute as CFString, &subroleRef)
        if subroleRef as? String == "AXSecureTextField" {
            return (.blocked, "\(app): secure text field")
        }

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(axElement, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String
        if let role, ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"].contains(role) {
            return (.editable, "\(app): \(role)")
        }
        if let role, Self.nonTextRoles.contains(role) {
            return (.blocked, "\(app): non-text role \(role)")
        }
        var settable = DarwinBoolean(false)
        AXUIElementIsAttributeSettable(axElement, kAXValueAttribute as CFString, &settable)
        if settable.boolValue {
            return (.editable, "\(app): role \(role ?? "?"), value settable")
        }
        // Not AX-writable, but focused and not secure (e.g. AXWebArea): the paste
        // path works there — a wasted paste is harmless, the clipboard restore is
        // changeCount-guarded.
        return (.pasteOnly, "\(app): role \(role ?? "?"), paste only")
    }

    /// Inserts `text` at the caret of the frontmost app. Primary path: set the
    /// focused element's AXSelectedText directly (exact paste semantics — replaces
    /// the selection, inserts at the caret) with NO clipboard involvement, so the
    /// restore race of issue #2 cannot occur. Fallback: clipboard + Cmd+V.
    static func insert(_ text: String, axAllowed: Bool = true) -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
        if axAllowed, axInsert(text) {
            DebugLog.log("insert method: ax → \(app) (value change verified)")
            return true
        }
        DebugLog.log("insert method: paste → \(app) (dispatched, restore in 2 s)")
        return pasteInsert(text)
    }

    /// Direct Accessibility insertion. A .success return from the set call is NOT
    /// proof — several apps (Electron, some web views) answer .success and change
    /// nothing (observed 20.08.: dictations silently vanished). The insertion only
    /// counts if the element's VALUE verifiably changed; everything else falls
    /// through to the paste path, which these apps handle correctly.
    private static func axInsert(_ text: String) -> Bool {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide,
                                            kAXFocusedUIElementAttribute as CFString,
                                            &focused) == .success,
              let focused else { return false }
        let element = focused as! AXUIElement
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element,
                                             kAXSelectedTextAttribute as CFString,
                                             &settable) == .success,
              settable.boolValue else { return false }
        // Verification requires a readable, reasonably sized value snapshot.
        guard let before = stringValue(of: element),
              before.utf16.count < 500_000 else { return false }
        guard AXUIElementSetAttributeValue(element,
                                           kAXSelectedTextAttribute as CFString,
                                           text as CFString) == .success else { return false }
        guard let after = stringValue(of: element), after != before else { return false }
        return true
    }

    private static func stringValue(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString,
                                            &value) == .success else { return nil }
        return value as? String
    }

    /// Clipboard + Cmd+V. The old clipboard is restored after 2 s (was 0.6 s — on a
    /// swapping machine the target app lost that race and pasted the OLD clipboard,
    /// issue #2); changeCount-guarded so a newer user copy is never destroyed.
    private static func pasteInsert(_ text: String) -> Bool {
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
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
