import Foundation

/// Package-internal localization (AvilaKit ships its own small string table).
/// Resolved via ResourceBundle — Bundle.module fatalErrors inside a packaged app
/// on any machine but the one that built it (issue #5).
private let stringsBundle: Bundle = {
    let bundle = ResourceBundle.named("AvilaVoice_AvilaKit") ?? Bundle.module
    DebugLog.log("strings bundle (kit): \(bundle.bundlePath) — probe '\(bundle.localizedString(forKey: "error.noSpeech", value: "MISS", table: nil))'")
    return bundle
}()

func L(_ key: String) -> String {
    stringsBundle.localizedString(forKey: key, value: key, table: nil)
}

func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
