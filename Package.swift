// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AvilaVoice",
    platforms: [
        .macOS("26.0")
    ],
    targets: [
        .executableTarget(
            name: "AvilaVoice",
            path: "Sources/AvilaVoice",
            resources: [
                .copy("Resources/MenuBarIcon.png")
            ]
        )
    ]
)
