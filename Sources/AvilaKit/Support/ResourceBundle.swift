import Foundation

/// Locates SwiftPM resource bundles in a way that works INSIDE the packaged app.
///
/// SwiftPM's generated `Bundle.module` accessor only looks (a) next to
/// `Bundle.main.bundleURL` — the app-bundle ROOT, where codesign forbids payload —
/// and (b) at the absolute build path of the machine that compiled the target
/// (the CI runner). On any other machine it calls `fatalError`, killing the app at
/// launch (issue #5). `Scripts/make_app.sh` puts the bundles into
/// `Contents/Resources/`, which `Bundle.main.resourceURL` points to — and for a bare
/// `swift build` executable, `resourceURL` is the build directory, where SwiftPM
/// placed the bundles anyway. One lookup covers both worlds; `Bundle.module` is only
/// a (lazily evaluated) last resort for exotic layouts.
public enum ResourceBundle {
    public static func named(_ name: String) -> Bundle? {
        guard let url = Bundle.main.resourceURL?
            .appendingPathComponent("\(name).bundle") else { return nil }
        return Bundle(url: url)
    }
}
