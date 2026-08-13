// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AvilaVoice",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "AvilaVoice",
            path: "Sources/AvilaVoice",
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/en.lproj"),
                .copy("Resources/de.lproj")
            ]
        )
    ]
)
