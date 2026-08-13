import AppKit
import Carbon.HIToolbox

/// The user's chosen trigger: a keyboard key or an extra mouse button.
enum HotkeyBinding: Codable, Equatable {
    case modifierKey(keyCode: Int64)          // e.g. right Command (54), right Option (61)
    case key(keyCode: Int64, modifiers: UInt64)
    case mouseButton(number: Int64)           // button 3, 4, 5 … (MX Master side buttons)

    static let `default` = HotkeyBinding.modifierKey(keyCode: 54) // right Command

    var displayName: String {
        switch self {
        case .modifierKey(54): return "Right ⌘"
        case .modifierKey(61): return "Right ⌥"
        case .modifierKey(let code): return "Modifier \(code)"
        case .key(let code, _): return "Key \(code)"
        case .mouseButton(let n): return "Mouse \(n + 1)"
        }
    }
}

/// Listens system-wide (CGEventTap) for the configured hotkey on keyboard or mouse.
/// Press-and-hold = push-to-talk, short tap = toggle. Needs Input Monitoring permission.
final class HotkeyManager: @unchecked Sendable {
    /// Below this press duration (seconds) a press counts as a tap (toggle mode).
    static let tapThreshold: TimeInterval = 0.35

    var binding: HotkeyBinding = .default

    /// Callbacks arrive on the main thread.
    var onPressDown: (@MainActor @Sendable () -> Void)?
    var onPressUp: (@MainActor @Sendable (_ heldFor: TimeInterval) -> Void)?

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressStartedAt: Date?

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

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable if the system disabled the tap (timeout).
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch (binding, type) {
        case (.modifierKey(let code), .flagsChanged):
            guard event.getIntegerValueField(.keyboardEventKeycode) == code else { break }
            // flagsChanged fires for both press and release; deviceKeyDown state is in flags.
            let isDown = pressStartedAt == nil
            dispatch(isDown: isDown)
            return nil // consume

        case (.key(let code, let mods), .keyDown), (.key(let code, let mods), .keyUp):
            guard event.getIntegerValueField(.keyboardEventKeycode) == code,
                  event.flags.rawValue & mods == mods else { break }
            if type == .keyDown, event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return nil // swallow autorepeat while held
            }
            dispatch(isDown: type == .keyDown)
            return nil

        case (.mouseButton(let n), .otherMouseDown), (.mouseButton(let n), .otherMouseUp):
            guard event.getIntegerValueField(.mouseEventButtonNumber) == n else { break }
            dispatch(isDown: type == .otherMouseDown)
            return nil

        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func dispatch(isDown: Bool) {
        if isDown {
            pressStartedAt = .now
            DispatchQueue.main.async { [onPressDown] in
                MainActor.assumeIsolated { onPressDown?() }
            }
        } else {
            let held = pressStartedAt.map { Date.now.timeIntervalSince($0) } ?? 0
            pressStartedAt = nil
            DispatchQueue.main.async { [onPressUp] in
                MainActor.assumeIsolated { onPressUp?(held) }
            }
        }
    }
}
