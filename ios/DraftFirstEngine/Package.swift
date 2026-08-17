// swift-tools-version: 6.2
import PackageDescription

/// The Swift-native Draft First screenplay engine.
///
/// Pure Foundation — no UIKit, no SwiftUI, no JavaScriptCore. The module
/// boundary is compiler-enforced so the engine can never entangle itself
/// with UI code, and the same package serves iOS, macOS, and CI.
///
/// Behavioural truth lives in the conformance corpus (`Fixtures/`), generated
/// from the TypeScript engine by `npm run engine:conformance`. Every public
/// function here must reproduce the corpus byte-for-byte.
let package = Package(
    name: "DraftFirstEngine",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "DraftFirstEngine", targets: ["DraftFirstEngine"])
    ],
    targets: [
        .target(
            name: "DraftFirstEngine",
            path: "Sources/DraftFirstEngine"
        ),
        .testTarget(
            name: "DraftFirstEngineTests",
            dependencies: ["DraftFirstEngine"],
            path: "Tests/DraftFirstEngineTests"
        )
    ]
)
