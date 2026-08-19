import Foundation
import AvilaKit

/// Detects main-thread stalls: the main run loop refreshes a timestamp every 100 ms;
/// a background queue checks it and logs ONCE per stall (when it resolves, with the
/// total duration) whenever the main thread fell behind by more than 150 ms.
/// Uses a monotonic clock, so system sleep never produces a bogus multi-hour stall.
final class MainThreadWatchdog: @unchecked Sendable {
    static let shared = MainThreadWatchdog()

    private let lock = NSLock()
    private var lastPong = ContinuousClock.now
    private var stallStart: ContinuousClock.Instant?
    private let queue = DispatchQueue(label: "avila.watchdog", qos: .userInteractive)

    func start() {
        pong()
        schedulePing()
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.check() }
    }

    private func pong() {
        lock.lock(); lastPong = .now; lock.unlock()
    }

    private func schedulePing() {
        DispatchQueue.main.async { [weak self] in
            self?.pong()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self?.schedulePing() }
        }
    }

    private func check() {
        lock.lock(); let last = lastPong; lock.unlock()
        let gap = last.duration(to: .now)
        let seconds = Double(gap.components.seconds) + Double(gap.components.attoseconds) / 1e18
        if seconds > 0.15 {
            if stallStart == nil { stallStart = last }          // stall began
        } else if let started = stallStart {                    // stall resolved
            let total = started.duration(to: .now)
            let ms = Double(total.components.seconds) * 1000 + Double(total.components.attoseconds) / 1e15
            // Ignore implausible gaps (system sleep resumes here too).
            if ms < 30_000 { DebugLog.log(String(format: "MAIN THREAD STALL %.0f ms", ms)) }
            stallStart = nil
        }
        queue.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.check() }
    }
}
