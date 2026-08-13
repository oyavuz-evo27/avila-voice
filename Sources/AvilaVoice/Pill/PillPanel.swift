import AppKit
import SwiftUI

/// Borderless, non-activating floating panel that hosts the pill at the bottom center
/// of the main screen. Never steals focus from the app the user is dictating into.
@MainActor
final class PillPanel: NSPanel {
    static let shared = PillPanel()

    private init() {
        super.init(contentRect: .zero,
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

        let host = NSHostingView(rootView: PillView().environmentObject(AppState.shared))
        host.translatesAutoresizingMaskIntoConstraints = false
        contentView = host
    }

    func show() {
        reposition()
        orderFrontRegardless()
    }

    /// Bottom center of the screen with the mouse (fallback: main screen).
    func reposition() {
        guard let screen = NSScreen.screens.first(where: {
            NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
        }) ?? NSScreen.main else { return }
        let size = NSSize(width: 360, height: 160)
        setContentSize(size)
        let x = screen.frame.midX - size.width / 2
        let y = screen.frame.minY + 12
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
