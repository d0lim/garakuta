// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Garakuta",
    platforms: [.macOS(.v15)],
    products: [
        // Loaded into the system perl interpreter at runtime (see Sources/NowPlayingBridge); not linked by the app.
        .library(name: "NowPlayingBridge", type: .dynamic, targets: ["NowPlayingBridge"]),
    ],
    targets: [
        .executableTarget(
            name: "Garakuta",
            dependencies: ["GarakutaCore", "MenuBarKit", "NotchKit", "WindowSwitcherKit"]
        ),
        .target(name: "GarakutaCore"),
        // C target: dlsym loader for private SkyLight symbols. No C++.
        .target(name: "PrivateAPIs"),
        // C target: now-playing helper hosted by the system perl interpreter. No C++.
        .target(name: "NowPlayingBridge", linkerSettings: [.linkedFramework("CoreFoundation")]),
        .target(name: "MenuBarKit", dependencies: ["GarakutaCore"]),
        .target(name: "NotchKit", dependencies: ["GarakutaCore"]),
        .target(name: "WindowSwitcherKit", dependencies: ["GarakutaCore", "PrivateAPIs"]),
        .testTarget(name: "GarakutaCoreTests", dependencies: ["GarakutaCore"]),
        .testTarget(name: "PrivateAPIsTests", dependencies: ["PrivateAPIs"]),
    ]
)
