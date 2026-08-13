import Foundation

/// Returns the localized string for `key` from the package resource bundle.
/// Keys are the English texts; missing translations fall back to the key itself.
func L(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: key, table: nil)
}

/// Localized format string, e.g. `LF("%d words", 12)`.
func LF(_ key: String, _ arguments: CVarArg...) -> String {
    String(format: L(key), arguments: arguments)
}
