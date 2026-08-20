import AppKit
import Carbon.HIToolbox

/// A trigger the user can bind: a modifier key (optionally combined with further
/// held modifiers, e.g. Fn+⌘), a regular key (with modifiers), or an extra mouse button.
public enum HotkeyBinding: Equatable, Sendable {
    /// `extraFlags`: generic CGEventFlags that must additionally be held (0 = none).
    case modifierKey(keyCode: Int64, extraFlags: UInt64 = 0)
    case key(keyCode: Int64, modifiers: UInt64)
    case mouseButton(number: Int64)           // button 3, 4, 5 … (MX Master side buttons)

    public static let defaultPushToTalk = HotkeyBinding.modifierKey(keyCode: 54)  // right ⌘
    public static let defaultHandsFree = HotkeyBinding.modifierKey(keyCode: 61)   // right ⌥

    /// Every component is joined with " + " (e.g. "⌥ + K", "Fn + Rechte ⌘").
    public var displayName: String {
        switch self {
        case .modifierKey(let code, let extra):
            let name = Self.modifierNames[code].map { L($0) } ?? LF("Key %d", Int(code))
            return (Self.flagSymbols(CGEventFlags(rawValue: extra)) + [name])
                .joined(separator: " + ")
        case .key(let code, let mods):
            let name = Self.keyNames[code] ?? LF("Key %d", Int(code))
            return (Self.flagSymbols(CGEventFlags(rawValue: mods)) + [name])
                .joined(separator: " + ")
        case .mouseButton(let n):
            return LF("Mouse %d", Int(n) + 1)
        }
    }

    private static func flagSymbols(_ flags: CGEventFlags) -> [String] {
        var parts: [String] = []
        if flags.contains(.maskSecondaryFn) { parts.append("Fn") }
        if flags.contains(.maskControl) { parts.append("⌃") }
        if flags.contains(.maskAlternate) { parts.append("⌥") }
        if flags.contains(.maskShift) { parts.append("⇧") }
        if flags.contains(.maskCommand) { parts.append("⌘") }
        return parts
    }

    public static let modifierNames: [Int64: String] = [
        54: "Right ⌘", 55: "⌘", 56: "⇧", 57: "⇪", 58: "⌥",
        59: "⌃", 60: "Right ⇧", 61: "Right ⌥", 62: "Right ⌃", 63: "Fn",
    ]

    /// The device-independent flag a modifier key code controls.
    public static func modifierMask(for keyCode: Int64) -> CGEventFlags? {
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

    /// The device-specific flag bit for a modifier key code (distinguishes left/right),
    /// so releasing right ⌘ is not confused with left ⌘ still being held.
    public static func deviceMask(for keyCode: Int64) -> UInt64? {
        switch keyCode {
        case 59: return 0x0001      // left Control
        case 56: return 0x0002      // left Shift
        case 60: return 0x0004      // right Shift
        case 55: return 0x0008      // left Command
        case 54: return 0x0010      // right Command
        case 58: return 0x0020      // left Option
        case 61: return 0x0040      // right Option
        case 62: return 0x2000      // right Control
        default: return nil
        }
    }

    /// Whether the modifier belonging to `keyCode` is currently pressed in `flags`.
    public static func modifierIsDown(keyCode: Int64, flags: CGEventFlags) -> Bool {
        if let device = deviceMask(for: keyCode) {
            return flags.rawValue & device != 0
        }
        if let mask = modifierMask(for: keyCode) {
            return flags.contains(mask)
        }
        return false
    }

    // MARK: Codable — hand-written so older stored bindings (without extraFlags)
    // keep decoding after the enum gained the combo support.

    private enum CaseKeys: String, CodingKey { case modifierKey, key, mouseButton }
    private enum ModKeys: String, CodingKey { case keyCode, extraFlags }
    private enum KeyKeys: String, CodingKey { case keyCode, modifiers }
    private enum MouseKeys: String, CodingKey { case number }

    public static let keyNames: [Int64: String] = [
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

extension HotkeyBinding: Codable {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CaseKeys.self)
        if c.contains(.modifierKey) {
            let sub = try c.nestedContainer(keyedBy: ModKeys.self, forKey: .modifierKey)
            self = .modifierKey(keyCode: try sub.decode(Int64.self, forKey: .keyCode),
                                extraFlags: try sub.decodeIfPresent(UInt64.self,
                                                                    forKey: .extraFlags) ?? 0)
        } else if c.contains(.key) {
            let sub = try c.nestedContainer(keyedBy: KeyKeys.self, forKey: .key)
            self = .key(keyCode: try sub.decode(Int64.self, forKey: .keyCode),
                        modifiers: try sub.decode(UInt64.self, forKey: .modifiers))
        } else if c.contains(.mouseButton) {
            let sub = try c.nestedContainer(keyedBy: MouseKeys.self, forKey: .mouseButton)
            self = .mouseButton(number: try sub.decode(Int64.self, forKey: .number))
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                                                    debugDescription: "unknown binding case"))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CaseKeys.self)
        switch self {
        case .modifierKey(let keyCode, let extraFlags):
            var sub = c.nestedContainer(keyedBy: ModKeys.self, forKey: .modifierKey)
            try sub.encode(keyCode, forKey: .keyCode)
            try sub.encode(extraFlags, forKey: .extraFlags)
        case .key(let keyCode, let modifiers):
            var sub = c.nestedContainer(keyedBy: KeyKeys.self, forKey: .key)
            try sub.encode(keyCode, forKey: .keyCode)
            try sub.encode(modifiers, forKey: .modifiers)
        case .mouseButton(let number):
            var sub = c.nestedContainer(keyedBy: MouseKeys.self, forKey: .mouseButton)
            try sub.encode(number, forKey: .number)
        }
    }
}

public enum HotkeyRole: String {
    case pushToTalk
    case handsFree
}

/// Listens system-wide (CGEventTap) for the configured triggers.
/// Push-to-talk: hold to record (a short tap toggles instead). Hands-free: tap toggles.
/// Also provides a capture mode for the settings hotkey recorder.
/// Needs Input Monitoring / Accessibility permission — creation is retried until the
/// user has granted it, so no app restart is required after granting.
public final class HotkeyManager: NSObject, @unchecked Sendable {
    /// Below this press duration (seconds) a press counts as a tap.
    public static let tapThreshold: TimeInterval = 0.35

    public var pttBinding: HotkeyBinding?
    public var handsFreeBinding: HotkeyBinding?

    /// True while the event tap is installed and listening.
    private(set) var isActive = false
    public var onStatusChange: (@MainActor @Sendable (Bool) -> Void)?

    /// Callbacks arrive on the main thread.
    public var onPTTDown: (@MainActor @Sendable () -> Void)?
    public var onPTTUp: (@MainActor @Sendable (_ heldFor: TimeInterval) -> Void)?
    public var onHandsFreeToggle: (@MainActor @Sendable () -> Void)?
    /// Esc pressed while a recording is active — cancel without transcribing.
    public var onEscapeCancel: (@MainActor @Sendable () -> Void)?
    /// Kept in sync by AppState; read on the event-tap thread.
    public var recordingActive = false

    private var captureHandler: (@MainActor @Sendable (HotkeyBinding?) -> Void)?
    /// Modifier keys currently held during capture, in press order — a combo like
    /// Fn+⌘ is finalized when the first of them is released.
    private var captureHeldModifiers: [Int64] = []

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var retryTimer: Timer?
    private var pttPressedAt: Date?
    private var handsFreeDown = false

    /// Arms the capture mode (nil disarms). A previously armed handler is completed
    /// with nil so its UI can reset — no capture is ever left dangling.
    public func setCaptureHandler(_ handler: (@MainActor @Sendable (HotkeyBinding?) -> Void)?) {
        let old = captureHandler
        captureHandler = handler
        captureHeldModifiers = []
        if let old {
            dispatch { old(nil) }
        }
    }

    public func start() {
        createTap()
        if tap == nil {
            NSLog("AvilaVoice: event tap unavailable — waiting for Accessibility/Input Monitoring permission")
            let timer = Timer(timeInterval: 3.0, target: self,
                              selector: #selector(retryTick), userInfo: nil, repeats: true)
            RunLoop.main.add(timer, forMode: .common)
            retryTimer = timer
        }
    }

    @objc private func retryTick() {
        guard tap == nil else {
            retryTimer?.invalidate()
            retryTimer = nil
            return
        }
        createTap()
        if tap != nil {
            NSLog("AvilaVoice: event tap installed after permission grant")
            retryTimer?.invalidate()
            retryTimer = nil
        }
    }

    private func createTap() {
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
            setActive(false)
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        setActive(true)
    }

    public func stop() {
        retryTimer?.invalidate()
        retryTimer = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        setActive(false)
    }

    private func setActive(_ active: Bool) {
        guard isActive != active else { return }
        isActive = active
        dispatch { [onStatusChange] in onStatusChange?(active) }
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

        // Esc during a recording cancels it (and never reaches other apps).
        if recordingActive, type == .keyDown || type == .keyUp,
           event.getIntegerValueField(.keyboardEventKeycode) == 53 {
            if type == .keyDown {
                dispatch { [onEscapeCancel] in onEscapeCancel?() }
            }
            return nil
        }

        // Push-to-talk binding.
        if let binding = pttBinding,
           let edge = edge(of: binding, type: type, event: event, wasDown: pttPressedAt != nil) {
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
        if let binding = handsFreeBinding,
           let edge = edge(of: binding, type: type, event: event, wasDown: handsFreeDown) {
            switch edge {
            case .down:
                handsFreeDown = true
                dispatch { [onHandsFreeToggle] in onHandsFreeToggle?() }
            case .up:
                handsFreeDown = false
            case .swallow:
                break
            }
            return nil // consume press and release
        }

        return Unmanaged.passUnretained(event)
    }

    private enum Edge { case down, up, swallow }

    /// Whether the event is this binding's press or release. nil = not this binding.
    /// `wasDown` gates releases: a release only matches if we saw the press — otherwise
    /// unrelated key-ups (e.g. plain D while ⌥D is bound) would be swallowed.
    private func edge(of binding: HotkeyBinding, type: CGEventType, event: CGEvent,
                      wasDown: Bool) -> Edge? {
        switch binding {
        case .modifierKey(let code, let extra):
            guard type == .flagsChanged else { return nil }
            // React to changes of ANY component of the combo, so the press order
            // does not matter (Fn then ⌘ and ⌘ then Fn both work).
            let evCode = event.getIntegerValueField(.keyboardEventKeycode)
            let involvesBinding = evCode == code
                || (HotkeyBinding.modifierMask(for: evCode)
                        .map { $0.rawValue & extra != 0 } ?? false)
            guard involvesBinding else { return nil }
            let satisfied = HotkeyBinding.modifierIsDown(keyCode: code, flags: event.flags)
                && event.flags.rawValue & extra == extra
            if satisfied {
                return wasDown ? .swallow : .down
            }
            // Not (or no longer) fully pressed: an incomplete combo passes through
            // to other apps; a release after our press ends the trigger.
            return wasDown ? .up : nil

        case .key(let code, let mods):
            guard type == .keyDown || type == .keyUp,
                  event.getIntegerValueField(.keyboardEventKeycode) == code else { return nil }
            if type == .keyUp {
                // The user may release the modifier a tick before the key — match the
                // release on the key code alone, but only if the press was ours.
                return wasDown ? .up : nil
            }
            // Same modifier set as capture (incl. Fn) — an asymmetric mask made every
            // Fn-containing .key binding permanently dead (issue #1).
            let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl,
                                          .maskShift, .maskSecondaryFn]
            guard event.flags.rawValue & relevant.rawValue == mods else { return nil }
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 { return .swallow }
            return .down

        case .mouseButton(let n):
            guard type == .otherMouseDown || type == .otherMouseUp,
                  event.getIntegerValueField(.mouseEventButtonNumber) == n else { return nil }
            if type == .otherMouseUp {
                return wasDown ? .up : nil
            }
            return .down
        }
    }

    // MARK: - Capture mode

    private func handleCapture(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .keyDown:
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl,
                                          .maskShift, .maskSecondaryFn]
            let mods = event.flags.rawValue & relevant.rawValue
            captureHeldModifiers = []
            if code == 53 && mods == 0 { // bare Esc cancels
                finishCapture(with: nil)
                return nil
            }
            finishCapture(with: .key(keyCode: code, modifiers: mods))
            return nil

        case .flagsChanged:
            // Modifier-only bindings — including combos like Fn+⌘ — are taken when
            // the FIRST held modifier is released (without an intervening key).
            let code = event.getIntegerValueField(.keyboardEventKeycode)
            guard HotkeyBinding.modifierMask(for: code) != nil else { return nil }
            if HotkeyBinding.modifierIsDown(keyCode: code, flags: event.flags) {
                if !captureHeldModifiers.contains(code) {
                    captureHeldModifiers.append(code)
                }
            } else if captureHeldModifiers.contains(code) {
                let extras = captureHeldModifiers.filter { $0 != code }
                let extraFlags = extras
                    .compactMap { HotkeyBinding.modifierMask(for: $0)?.rawValue }
                    .reduce(0, |)
                finishCapture(with: .modifierKey(keyCode: code, extraFlags: extraFlags))
            }
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
        captureHeldModifiers = []
        pttPressedAt = nil
        handsFreeDown = false
        dispatch { handler?(binding) }
    }

    private func dispatch(_ body: @escaping @MainActor @Sendable () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { body() }
        }
    }
}
