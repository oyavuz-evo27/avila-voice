import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the pill at the bottom center
/// of the screen the mouse is on. Never steals focus from the app the user is dictating
/// into, stays above all windows and Spaces, and follows the active screen.
@MainActor
final class PillPanel: NSPanel {
    static let shared = PillPanel()
    static let panelSize = NSSize(width: 380, height: 240)

    private var followTimer: Timer?

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
        reposition()
        orderFrontRegardless()

        // Follow the screen the mouse is on (multi-monitor, like Wispr Flow).
        followTimer?.invalidate()
        let timer = Timer(timeInterval: 1.0, target: self,
                          selector: #selector(followTick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)
        followTimer = timer

        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    @objc private func followTick() {
        // Never jump between screens mid-dictation — the pill stays put until idle.
        switch AppState.shared.phase {
        case .recording, .processing: return
        default: reposition()
        }
    }

    @objc private func screensChanged() { reposition() }

    /// Bottom center of the screen with the mouse (fallback: main screen),
    /// above the Dock (visibleFrame).
    func reposition() {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }

        if frame.size != Self.panelSize {
            setContentSize(Self.panelSize)
        }
        let origin = NSPoint(x: screen.visibleFrame.midX - Self.panelSize.width / 2,
                             y: screen.visibleFrame.minY + 6)
        if frame.origin != origin {
            setFrameOrigin(origin)
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
