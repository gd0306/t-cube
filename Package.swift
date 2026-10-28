// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TCube",
    platforms: [.macOS(.v15)],
    products: [.library(name: "CubeCore", targets: ["CubeCore"]), .executable(name: "TCube", targets: ["TCube"])],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")
    ],
    targets: [
        .target(name: "CubeCore"),
        .executableTarget(
            name: "TCube",
            dependencies: ["CubeCore", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "CubeCoreTests", dependencies: ["CubeCore"]),
        .testTarget(name: "TCubeTests", dependencies: ["TCube", "CubeCore"])
    ]
)
