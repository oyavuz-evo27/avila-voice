import AvilaKit
import Foundation

/// Returns the localized string for `key` from the package resource bundle.
/// Keys are the English texts; missing translations fall back to the key itself.
/// Resolved via ResourceBundle — Bundle.module fatalErrors inside a packaged app
/// on any machine but the one that built it (issue #5).
private let stringsBundle: Bundle = {
    let bundle = ResourceBundle.named("AvilaVoice_AvilaVoice") ?? Bundle.module
    DebugLog.log("strings bundle: \(bundle.bundlePath) — localizations \(bundle.localizations), preferred \(bundle.preferredLocalizations), probe '\(bundle.localizedString(forKey: "Start Dictation", value: "MISS", table: nil))'")
    return bundle
}()

func L(_ key: String) -> String {
    stringsBundle.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string, e.g. `LF("%d words", 12)`.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
