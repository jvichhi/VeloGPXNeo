// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VeloGPX",
    platforms: [
        .iOS(.v17),
        .watchOS(.v10)
    ],
    products: [
        .library(name: "VeloGPXShared", targets: ["VeloGPXShared"])
    ],
    targets: [
        .target(name: "VeloGPXShared", path: "Shared"),
        .testTarget(name: "VeloGPXSharedTests", dependencies: ["VeloGPXShared"], path: "Tests")
    ]
)
