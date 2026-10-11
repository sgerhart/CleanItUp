// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CleanItUp",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CleanItUp", targets: ["CleanItUp"]),
    ],
    targets: [
        .target(name: "CleanItUpCore"),
        .executableTarget(name: "CleanItUp", dependencies: ["CleanItUpCore"]),
        .testTarget(name: "CleanItUpCoreTests", dependencies: ["CleanItUpCore"]),
    ]
)
