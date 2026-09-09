// swift-tools-version: 6.2
import PackageDescription

/// The phone's — and the iPad's — writing surface.
///
/// Everything UIKit: the text view, the ghost drawn over it, the reveal mark,
/// the element control, the printed page. It lived in the iPhone's app target
/// for historical reasons, and `SHARED-ARCHITECTURE.md` has said for a while
/// that this was the better arrangement. iPadOS made it due: a second app
/// cannot link code that lives inside the first one's target.
///
/// The sibling of `EDraftMacSurface`, and held to the same rule — one surface
/// per platform, both reading the same rules out of `EDraftCore` and
/// `EDraftEngine`, neither deciding a screenplay question for itself.
let surfaceSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self)
]

let package = Package(
    name: "EDraftUIKitSurface",
    // macOS is declared only so dependency resolution is satisfied on a Mac
    // host. This package imports UIKit and never compiles for the desk; it is
    // built for iOS as a dependency of the app, and its behaviour is tested by
    // `eDraftTests` under the simulator, which is also where the document
    // plumbing those tests drive already lives. A package test target here
    // would be a path nobody could run.
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "EDraftUIKitSurface", targets: ["EDraftUIKitSurface"])
    ],
    dependencies: [
        .package(path: "../eDraftEngine"),
        .package(path: "../EDraftCore")
    ],
    targets: [
        .target(
            name: "EDraftUIKitSurface",
            dependencies: [
                .product(name: "EDraftEngine", package: "eDraftEngine"),
                .product(name: "EDraftCore", package: "EDraftCore")
            ],
            swiftSettings: surfaceSettings
        )
    ]
)
