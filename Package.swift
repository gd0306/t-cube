// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TCube",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CubeCore", targets: ["CubeCore"]), .executable(name: "TCube", targets: ["TCube"])],
    targets: [
        .target(name: "CubeCore"),
        .executableTarget(name: "TCube", dependencies: ["CubeCore"]),
        .testTarget(name: "CubeCoreTests", dependencies: ["CubeCore"]),
        .testTarget(name: "TCubeTests", dependencies: ["TCube", "CubeCore"])
    ]
)
