// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Garakuta",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "Garakuta",
            dependencies: ["GarakutaCore", "MenuBarKit", "NotchKit", "WindowSwitcherKit"]
        ),
        .target(name: "GarakutaCore"),
        // C target: dlsym loader for private SkyLight symbols. No C++.
        .target(name: "PrivateAPIs"),
        .target(name: "MenuBarKit", dependencies: ["GarakutaCore"]),
        .target(name: "NotchKit", dependencies: ["GarakutaCore"]),
        .target(name: "WindowSwitcherKit", dependencies: ["GarakutaCore", "PrivateAPIs"]),
        .testTarget(name: "GarakutaCoreTests", dependencies: ["GarakutaCore"]),
        .testTarget(name: "PrivateAPIsTests", dependencies: ["PrivateAPIs"]),
    ]
)
