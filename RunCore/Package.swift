// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "RunCore", targets: ["RunCore"])
    ],
    targets: [
        .target(name: "RunCore"),
        .testTarget(name: "RunCoreTests", dependencies: ["RunCore"])
    ]
)
