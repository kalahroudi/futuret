// swift-tools-version:6.0
import PackageDescription

// No third-party dependencies: keeps the binary small and the memory footprint low.
let package = Package(
    name: "futuret",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "FutureT", targets: ["FutureT"]),
        .executable(name: "futuret-mcp", targets: ["futuret-mcp"]),
        .library(name: "FutureTKit", targets: ["FutureTKit"]),
    ],
    targets: [
        // UI-free core: everything that touches the system, parses output or decides something. Unit tested.
        .target(name: "FutureTKit"),
        // The menu bar + Dock app.
        .executableTarget(name: "FutureT", dependencies: ["FutureTKit"]),
        // Model Context Protocol server (stdio) so agents can drive the app's capabilities.
        .executableTarget(name: "futuret-mcp", dependencies: ["FutureTKit"]),
        .testTarget(name: "FutureTKitTests", dependencies: ["FutureTKit"]),
    ],
    swiftLanguageModes: [.v5]
)
