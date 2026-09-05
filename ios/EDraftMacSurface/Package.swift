// swift-tools-version: 6.2
import PackageDescription

/// The Mac's writing surface.
///
/// Everything AppKit — the text view, its layout, the marks drawn over it —
/// lives here rather than in the app target, so it can be measured by
/// `swift test` instead of only by eye. The iPhone's surface is in its app
/// target for historical reasons; this is the better arrangement, and the one
/// the phone should eventually move to.
///
/// See docs/MACOS-EXECUTION.md, M1: the one genuine unknown in the port is
/// whether the Mac's text system gives the reveal the rectangles it needs.
/// That question is answered by tests in this package, not by a demo.
let surfaceSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self)
]

let package = Package(
    name: "EDraftMacSurface",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "EDraftMacSurface", targets: ["EDraftMacSurface"])
    ],
    dependencies: [
        .package(path: "../eDraftEngine"),
        .package(path: "../EDraftCore"),
        .package(path: "../EDraftUI")
    ],
    targets: [
        .target(
            name: "EDraftMacSurface",
            dependencies: [
                .product(name: "EDraftEngine", package: "eDraftEngine"),
                .product(name: "EDraftCore", package: "EDraftCore"),
                .product(name: "EDraftUI", package: "EDraftUI")
            ],
            swiftSettings: surfaceSettings
        ),
        .testTarget(
            name: "EDraftMacSurfaceTests",
            dependencies: ["EDraftMacSurface"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
