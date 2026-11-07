// swift-tools-version: 5.10
// FitnessCore: the app's data models and coaching logic, with no Apple Health
// or UI code, so it can be tested on its own (see scripts/test-core.sh).
import PackageDescription

let package = Package(
    name: "FitnessCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "FitnessCore", targets: ["FitnessCore"]),
    ],
    targets: [
        .target(name: "FitnessCore"),
        .testTarget(name: "FitnessCoreTests", dependencies: ["FitnessCore"]),
    ]
)
