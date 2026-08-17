// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AvilaVoice",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        // Parakeet TDT v3 (Core ML / ANE) — optional quality STT engine
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.0"),
    ],
    targets: [
        .executableTarget(
            name: "AvilaVoice",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/AvilaVoice",
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/en.lproj"),
                .copy("Resources/de.lproj")
            ]
        )
    ]
)
