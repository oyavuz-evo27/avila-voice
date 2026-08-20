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

    /// The screen the pill currently lives on; only a CHANGE of screen migrates it.
    private var currentScreenID: CGDirectDisplayID?
    /// Candidate target screen and since when — the pill only migrates once the
    /// mouse has been on another screen for `migrateAfter` seconds.
    private var candidateScreenID: CGDirectDisplayID?
    private var candidateSince: Date?
    static let migrateAfter: TimeInterval = 1.0
    /// Pending VERTICAL anchor and since when — the height only changes once the
    /// new baseline has been stable for `anchorDebounce` seconds. Fullscreen
    /// transitions and Mission Control flicker the detection for a moment; without
    /// this the pill bounced 61 pt up and down (MacBook Air report, 20.08.).
    private var baselineCandidate: (y: CGFloat, since: Date)?
    static let anchorDebounce: TimeInterval = 1.5

    /// Bottom center of the screen under the MOUSE CURSOR (Onur's frozen rule).
    /// Vertical anchor (issue #6): the PHYSICAL bottom edge — raised above the Dock
    /// only while the Dock is actually visible there. visibleFrame alone reserves
    /// Dock space even in fullscreen, which left the pill hovering 61 pt too high.
    func reposition(force: Bool = false) {
        guard let screen = NSScreen.screens.first(where: {
                NSMouseInRect(NSEvent.mouseLocation, $0.frame, false)
            })
            ?? NSScreen.main else { return }

        let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
            as? CGDirectDisplayID
        let sameScreen = (screenID == currentScreenID)
        // Debounce SCREEN MIGRATION only (issue #4: this early-exit used to run
        // before the force check and also skipped same-screen re-anchoring, so Dock
        // and resolution changes were never picked up).
        if !sameScreen, isVisible, !force {
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
        // Horizontal center of the FULL screen (visibleFrame.midX shifts with a side
        // Dock and made the pill slide); vertical from the physical bottom edge.
        let (targetY, reason) = Self.baseline(for: screen)
        var origin = NSPoint(x: screen.frame.midX - Self.panelSize.width / 2, y: targetY)

        // Vertical re-anchoring is debounced on the SAME screen: adopt a new height
        // only after it has been the stable target for `anchorDebounce`.
        if sameScreen, isVisible, !force, abs(frame.origin.y - targetY) > 0.5 {
            if let candidate = baselineCandidate, abs(candidate.y - targetY) < 0.5 {
                if Date().timeIntervalSince(candidate.since) < Self.anchorDebounce {
                    origin.y = frame.origin.y // not stable yet — hold position
                } else {
                    baselineCandidate = nil   // stable — adopt below
                }
            } else {
                baselineCandidate = (targetY, Date())
                origin.y = frame.origin.y
            }
        } else if abs(frame.origin.y - targetY) <= 0.5 {
            baselineCandidate = nil
        }

        if frame.origin != origin {
            setFrameOrigin(origin)
            DebugLog.log(String(format: "pill moved to screen %@ (x %.0f, y %.0f — %@)",
                                screenID.map(String.init) ?? "?",
                                origin.x, origin.y, reason))
        }
        if !isVisible {
            orderFrontRegardless()
        }
    }

    /// Wispr-Flow rule: sit at the physical bottom edge; step above the Dock only
    /// while the Dock is actually shown on this screen right now.
    private static func baseline(for screen: NSScreen) -> (y: CGFloat, reason: String) {
        let bottomEdge = screen.frame.minY + 6
        let dockReserved = screen.visibleFrame.minY - screen.frame.minY
        // No bottom reservation (auto-hidden Dock, side Dock, other screen) → edge.
        guard dockReserved > 0 else { return (bottomEdge, "edge, no dock reservation") }
        // Reservation exists — but in a fullscreen Space the Dock is hidden while
        // its reservation stays → anchor to the edge like Wispr Flow.
        if hasFullscreenWindow(on: screen) { return (bottomEdge, "edge, fullscreen") }
        return (screen.visibleFrame.minY + 6,
                "above dock (\(Int(dockReserved)) pt)")
    }

    /// True if a regular (layer-0) window fills `screen` the way a fullscreen Space
    /// does: full width, reaching the physical bottom edge, and (nearly) full
    /// height. Compared with tolerance instead of exact frame equality — on notched
    /// MacBooks a fullscreen window stops below the camera housing, so an exact
    /// match never fired there. Only consulted while the Dock reserves space, so a
    /// merely maximized window (bounded by visibleFrame) can never reach the bottom.
    private static func hasFullscreenWindow(on screen: NSScreen) -> Bool {
        guard let info = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
            as? [[String: Any]] else { return false }
        let primaryHeight = NSScreen.screens.first?.frame.maxY ?? 0
        let left = screen.frame.minX
        let width = screen.frame.width
        let bottomCG = primaryHeight - screen.frame.minY // CG y of the bottom edge
        for window in info {
            guard window[kCGWindowLayer as String] as? Int == 0,
                  let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict) else { continue }
            let coversWidth = abs(bounds.minX - left) < 1 && abs(bounds.width - width) < 1
            let reachesBottom = abs(bounds.maxY - bottomCG) < 1
            let tallEnough = bounds.height >= screen.frame.height - 80 // notch strip
            if coversWidth && reachesBottom && tallEnough { return true }
        }
        return false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
