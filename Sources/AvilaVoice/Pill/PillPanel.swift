import AppKit
import ApplicationServices
import SwiftUI
import AvilaKit

/// Borderless, non-activating floating panel that hosts the pill at the bottom center
/// of the screen the mouse is on. Never steals focus from the app the user is dictating
/// into, stays above all windows and Spaces, and follows the active screen.
@MainActor
final class PillPanel: NSPanel {
    static let shared = PillPanel()
    static let panelSize = NSSize(width: 380, height: 240)


    private init() {
        super.init(contentRect: NSRect(origin: .zero, size: Self.panelSize),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovableByWindowBackground = false
        becomesKeyOnlyIfNeeded = true

        // Default autoresizing: the hosting view must track the window size.
        contentView = NSHostingView(rootView: PillView().environmentObject(AppState.shared))
    }

    func show() {
        reposition(force: true)
        orderFrontRegardless()

        // Follow rule (Onur, 18.08.2026): the pill lives on the screen the MOUSE
        // CURSOR is on — like Wispr Flow. Not the focused window, not the recording
        // start. It migrates only after the cursor has been on another screen for
        // `migrateAfter` seconds, and never during recording/processing.
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 0.5, target: self,
                          selector: #selector(followTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    private var followTimer: Timer?

    @objc private func followTick() {
        switch AppState.shared.phase {
        case .recording, .processing: return
        default: reposition()
        }
    }

    @objc private func screensChanged() { reposition(force: true) }

    /// Bottom center of the active screen, above the Dock (visibleFrame).
    /// "Active" = the screen with the focused window (where dictated text will go);
    /// fallbacks: mouse screen, then main screen.
    /// The screen the pill currently lives on; only a CHANGE of screen moves the pill.
    private var currentScreenID: CGDirectDisplayID?
    /// Candidate target screen and since when it has been the target — the pill
    /// only migrates once a new screen has been the focus target for a while.
    private var candidateScreenID: CGDirectDisplayID?
    private var candidateSince: Date?
    static let migrateAfter: TimeInterval = 1.0

    func reposition(force: Bool = false) {
        // Screen under the mouse cursor (Wispr-Flow behaviour).
        guard let screen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            })
            ?? NSScreen.main else { return }

        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID
        // Same screen as before → never touch the position (no jitter, no drift
        // from transient Dock/menu-bar geometry changes).
        if screenID == currentScreenID, isVisible {
            candidateScreenID = nil
            candidateSince = nil
            return
        }
        // Debounce screen changes: focus flickers between windows on different
        // monitors (⌘-Tab, dialogs, the target app activating) made the pill
        // ping-pong. Require the new target to be stable for `migrateAfter`.
        if !force, isVisible {
            if candidateScreenID != screenID {
                candidateScreenID = screenID
                candidateSince = Date()
                return
            }
            guard let since = candidateSince,
                  Date().timeIntervalSince(since) >= Self.migrateAfter else { return }
        }
        candidateScreenID = nil
        candidateSince = nil
        currentScreenID = screenID

        if frame.size != Self.panelSize {
            setContentSize(Self.panelSize)
        }
        // Horizontal center of the FULL screen (not visibleFrame — a left/right Dock
        // or a hidden/shown Dock would shift visibleFrame.midX and make the pill
        // slide sideways); vertical position respects the Dock.
        let origin = NSPoint(x: screen.frame.midX - Self.panelSize.width / 2,
                             y: screen.visibleFrame.minY + 6)
        if frame.origin != origin {
            setFrameOrigin(origin)
            DebugLog.log(String(format: "pill moved to screen %@ (x %.0f)",
                                screenID.map(String.init) ?? "?", origin.x))
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Screen containing the frontmost app's focused window (needs Accessibility).
    private static func focusedWindowScreen() -> NSScreen? {
        guard AXIsProcessTrusted(),
              let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXFocusedWindowAttribute as CFString,
                                            &windowRef) == .success,
              let windowRef else { return nil }
        let window = windowRef as! AXUIElement
        var positionRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, kAXPositionAttribute as CFString,
                                            &positionRef) == .success,
              let positionRef else { return nil }
        var topLeft = CGPoint.zero
        guard AXValueGetValue(positionRef as! AXValue, .cgPoint, &topLeft) else { return nil }
        // AX coordinates are global top-left origin; Cocoa screens are bottom-left.
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let cocoaPoint = NSPoint(x: topLeft.x + 1, y: primaryHeight - topLeft.y - 1)
        return NSScreen.screens.first { NSMouseInRect(cocoaPoint, $0.frame, false) }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
