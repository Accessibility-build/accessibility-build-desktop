// swift-tools-version: 5.10
import PackageDescription

// Pure, AppKit-free logic behind the app's tools: pixel geometry across
// displays, worst-case contrast search, finding text and the Markdown
// session export. Kept out of the app target so it is unit tested with
// `swift test` without launching a menu-bar app.
let package = Package(
    name: "AuditCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AuditCore", targets: ["AuditCore"]),
    ],
    dependencies: [
        .package(path: "../ColorCore"),
    ],
    targets: [
        .target(name: "AuditCore", dependencies: ["ColorCore"]),
        .testTarget(name: "AuditCoreTests", dependencies: ["AuditCore"]),
    ]
)
