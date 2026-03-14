// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyScreen",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MyScreen", targets: ["MyScreen"]),
    ],
    targets: [
        .executableTarget(
            name: "MyScreen"
        ),
        .testTarget(
            name: "MyScreenTests",
            dependencies: ["MyScreen"]
        ),
    ]
)
