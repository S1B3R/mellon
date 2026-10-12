// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MellonCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MellonCore", targets: ["MellonCore"]),
    ],
    targets: [
        .target(name: "MellonCore"),
        .testTarget(name: "MellonCoreTests", dependencies: ["MellonCore"]),
    ]
)
