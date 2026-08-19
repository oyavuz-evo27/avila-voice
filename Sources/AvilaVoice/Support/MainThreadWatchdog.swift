import Foundation
import AvilaKit

/// Detects main-thread stalls: the main run loop refreshes a timestamp every 100 ms;
/// a background queue checks it and logs whenever the main thread fell behind by
/// more than 150 ms — with the stall duration, so a frozen pill can be matched to
/// what the app was doing at that moment.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let lock = NSLock()
    private var lastPong = Date()
    private let queue = DispatchQueue(label: "avila.watchdog", qos: .userInteractive)

    func start() {
        pong()
        schedulePing()
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.check() }
    }

    private func pong() {
        lock.lock(); lastPong = Date(); lock.unlock()
    }

    private func schedulePing() {
        DispatchQueue.main.async { [weak self] in
            self?.pong()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.schedulePing() }
        }
    }

    private func check() {
        lock.lock(); let last = lastPong; lock.unlock()
        let gap = Date().timeIntervalSince(last)
        if gap > 0.15 {
            DebugLog.log(String(format: "MAIN THREAD STALL %.0f ms", gap * 1000))
        }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.check() }
    }
}
