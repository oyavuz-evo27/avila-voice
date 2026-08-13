import AppKit
import Carbon.HIToolbox

/// A trigger the user can bind: a modifier key, a regular key (with modifiers),
/// or an extra mouse button.
enum HotkeyBinding: Codable, Equatable {
    case modifierKey(keyCode: Int64)          // e.g. right Command (54), right Option (61)
    case key(keyCode: Int64, modifiers: UInt64)
    case mouseButton(number: Int64)           // button 3, 4, 5 … (MX Master side buttons)

    static let defaultPushToTalk = HotkeyBinding.modifierKey(keyCode: 54)  // right ⌘
    static let defaultHandsFree = HotkeyBinding.modifierKey(keyCode: 61)   // right ⌥

    var displayName: String {
        switch self {
        case .modifierKey(let code):
            return Self.modifierNames[code] ?? "Modifier \(code)"
        case .key(let code, let mods):
            let flags = CGEventFlags(rawValue: mods)
            var parts = ""
            if flags.contains(.maskControl) { parts += "⌃" }
            if flags.contains(.maskAlternate) { parts += "⌥" }
            if flags.contains(.maskShift) { parts += "⇧" }
            if flags.contains(.maskCommand) { parts += "⌘" }
            return parts + (Self.keyNames[code] ?? "Key \(code)")
        case .mouseButton(let n):
            return "Mouse \(n + 1)"
        }
    }

    static let modifierNames: [Int64: String] = [
        54: "Right ⌘", 55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥",
        59: "⌃", 60: "Right ⇧", 61: "Right ⌥", 62: "Right ⌃", 63: "Fn",
    ]

    /// The device-independent flag a modifier key code controls.
    static func modifierMask(for keyCode: Int64) -> CGEventFlags? {
        switch keyCode {
        case 54, 55: return .maskCommand
        case 56, 60: return .maskShift
        case 57: return .maskAlphaShift
        case 58, 61: return .maskAlternate
        case 59, 62: return .maskControl
        case 63: return .maskSecondaryFn
        default: return nil
        }
    }

    static let keyNames: [Int64: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2",
        20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "↩", 37: "L",
        38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M",
        47: ".", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12", 113: "F15",
        118: "F4", 120: "F2", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]
}

enum HotkeyRole: String {
    case pushToTalk
    case handsFree
}

/// Listens system-wide (CGEventTap) for the configured triggers.
/// Push-to-talk: hold to record (a short tap toggles instead). Hands-free: tap toggles.
/// Also provides a capture mode for the settings hotkey recorder.
/// Needs Input Monitoring / Accessibility permission.
final class HotkeyManager: @unchecked Sendable {
    /// Below this press duration (seconds) a press counts as a tap.
    static let tapThreshold: TimeInterval = 0.35

    var pttBinding: HotkeyBinding?
    var handsFreeBinding: HotkeyBinding?

    /// Callbacks arrive on the main thread.
    var onPTTDown: (@MainActor @Sendable () -> Void)?
    var onPTTUp: (@MainActor @Sendable (_ heldFor: TimeInterval) -> Void)?
    var onHandsFreeToggle: (@MainActor @Sendable () -> Void)?
    /// When set, the next key or mouse press is captured instead of dispatched
    /// (nil = cancelled with Esc). Cleared automatically after one capture.
    var captureHandler: (@MainActor @Sendable (HotkeyBinding?) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pttPressedAt: Date?

    func start() {
        guard tap == nil else { return }
        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.keyDown.rawValue) |
            (1 << CGEventType.keyUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon!).takeUnretainedValue()
            return manager.handle(type: type, event: event)
        }

        tap = CGEvent.tapCreate(tap: .cgSessionEventTap,
                                place: .headInsertEventTap,
                                options: .defaultTap,
                                eventsOfInterest: mask,
                                callback: callback,
                                userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let tap else {
            NSLog("AvilaVoice: could not create event tap — missing Input Monitoring permission?")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        // Capture mode for the settings recorder.
        if captureHandler != nil {
            return handleCapture(type: type, event: event)
        }

        // Push-to-talk binding.
        if let binding = pttBinding, let edge = edge(of: binding, type: type, event: event) {
            switch edge {
            case .down:
                if pttPressedAt == nil {
                    pttPressedAt = .now
                    dispatch { [onPTTDown] in onPTTDown?() }
                }
            case .up:
                let held = pttPressedAt.map { Date.now.timeIntervalSince($0) } ?? 0
                pttPressedAt = nil
                dispatch { [onPTTUp] in onPTTUp?(held) }
            case .swallow:
                break
            }
            return nil // consume
        }

        // Hands-free binding: toggles on press.
        if let binding = handsFreeBinding, let edge = edge(of: binding, type: type, event: event) {
            if edge == .down {
                dispatch { [onHandsFreeToggle] in onHandsFreeToggle?() }
            }
            return nil // consume press and release
        }

        return Unmanaged.passUnretained(event)
    }

    private enum Edge { case down, up, swallow }

    /// Whether the event is this binding's press or release. nil = not this binding.
    private func edge(of binding: HotkeyBinding, type: CGEventType, event: CGEvent) -> Edge? {
        switch binding {
        case .modifierKey(let code):
            guard type == .flagsChanged,
                  event.getIntegerValueField(.keyboardEventKeycode) == code,
                  let mask = HotkeyBinding.modifierMask(for: code) else { return nil }
            return event.flags.contains(mask) ? .down : .up

        case .key(let code, let mods):
            guard type == .keyDown || type == .keyUp,
                  event.getIntegerValueField(.keyboardEventKeycode) == code,
                  event.flags.rawValue & mods == mods else { return nil }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return .swallow
            }
            return type == .keyDown ? .down : .up

        case .mouseButton(let n):
            guard type == .otherMouseDown || type == .otherMouseUp,
                  event.getIntegerValueField(.mouseEventButtonNumber) == n else { return nil }
            return type == .otherMouseDown ? .down : .up
        }
    }

    private func handleCapture(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            if code == 53 { // Esc cancels
                finishCapture(with: nil)
                return nil
            }
            let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
            let mods = event.flags.rawValue & relevant.rawValue
            finishCapture(with: .key(keyCode: code, modifiers: mods))
            return nil

        case .flagsChanged:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard let mask = HotkeyBinding.modifierMask(for: code),
                  event.flags.contains(mask) else { return nil } // only the press
            finishCapture(with: .modifierKey(keyCode: code))
            return nil

        case .otherMouseDown:
            let n = event.getIntegerValueField(.mouseEventButtonNumber)
            finishCapture(with: .mouseButton(number: n))
            return nil

        case .keyUp, .otherMouseUp:
            return nil // swallow releases while capturing

        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func finishCapture(with binding: HotkeyBinding?) {
        let handler = captureHandler
        captureHandler = nil
        pttPressedAt = nil
        dispatch { handler?(binding) }
    }

    private func dispatch(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }
}
