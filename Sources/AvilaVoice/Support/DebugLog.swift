import Foundation

/// Lightweight file logger: ~/Library/Logs/AvilaVoice.log (plus NSLog).
/// Exists because unified-log access proved unreliable for field debugging.
enum DebugLog {
    private static let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Logs/AvilaVoice.log")
    private static let queue = DispatchQueue(label: "avila.debuglog")
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()

    static func log(_ message: String) {
        NSLog("AvilaVoice: %@", message)
        let line = "\(formatter.string(from: .now)) \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: url) {
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
    }
}
