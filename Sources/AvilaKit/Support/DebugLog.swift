import Foundation

/// Lightweight file logger: ~/Library/Logs/<appName>.log (plus NSLog).
/// Exists because unified-log access proved unreliable for field debugging.
/// Each app sets `DebugLog.appName` once at launch (default keeps Avila Voice's file).
public enum DebugLog {
    nonisolated(unsafe) public static var appName = "AvilaVoice"

    private static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/\(appName).log")
    }
    private static let queue = DispatchQueue(label: "avila.debuglog")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    public static func log(_ message: String) {
        NSLog("%@: %@", appName, message)
        let line = "\(formatter.string(from: .now)) \(message)\n"
        let target = url
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: target) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: target)
            }
        }
    }
}
