// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ColorCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ColorCore", targets: ["ColorCore"]),
    ],
    targets: [
        .target(name: "ColorCore"),
        .testTarget(
            name: "ColorCoreTests",
            dependencies: ["ColorCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
