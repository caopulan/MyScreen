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
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", revision: "c9d57c8"),
    ],
    targets: [
        .executableTarget(
            name: "MyScreen"
        ),
        .testTarget(
            name: "MyScreenTests",
            dependencies: [
                "MyScreen",
                .product(name: "Testing", package: "swift-testing"),
            ]
        ),
    ]
)
