// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "AvilaVoice",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        // Shared on-device building blocks (audio capture, STT engines, global hotkeys,
        // model store, Ollama client) — used by Avila Voice and Avila Projects.
        .library(name: "AvilaKit", targets: ["AvilaKit"]),
        .executable(name: "AvilaVoice", targets: ["AvilaVoice"]),
    ],
    dependencies: [
        // Parakeet TDT v3 (Core ML / ANE) — optional quality STT engine
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.12.0"),
    ],
    targets: [
        .target(
            name: "AvilaKit",
            dependencies: [
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/AvilaKit",
            resources: [
                .copy("Resources/en.lproj"),
                .copy("Resources/de.lproj")
            ]
        ),
        .executableTarget(
            name: "AvilaVoice",
            dependencies: ["AvilaKit"],
            path: "Sources/AvilaVoice",
            resources: [
                .copy("Resources/MenuBarIcon.png"),
                .copy("Resources/en.lproj"),
                .copy("Resources/de.lproj")
            ]
        )
    ]
)
