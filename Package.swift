// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Helpwing",
    platforms: [.iOS(.v15), .macOS(.v12)],
    products: [
        .library(name: "Helpwing", targets: ["Helpwing"]),
    ],
    targets: [
        .target(name: "Helpwing"),
        .testTarget(name: "HelpwingTests", dependencies: ["Helpwing"]),
    ]
)
