// swift-tools-version: 6.2
import PackageDescription

/// The panels both surfaces share.
///
/// A Navigator, a character's thread through the script, the title page, the
/// writing-assistance settings: these are the same views on a phone and on a
/// Mac, because they answer the same questions about the same document. What
/// differs is the chrome around them — a sheet with a nav bar here, a sidebar
/// there — and that difference is held in small shims rather than in two
/// copies of a list.
///
/// SwiftUI only. Anything that needs UIKit or AppKit belongs to a surface, not
/// here. See docs/SHARED-ARCHITECTURE.md.
let uiSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self)
]

let package = Package(
    name: "EDraftUI",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "EDraftUI", targets: ["EDraftUI"])
    ],
    dependencies: [
        .package(path: "../eDraftEngine"),
        .package(path: "../EDraftCore")
    ],
    targets: [
        .target(
            name: "EDraftUI",
            dependencies: [
                .product(name: "EDraftEngine", package: "eDraftEngine"),
                .product(name: "EDraftCore", package: "EDraftCore")
            ],
            swiftSettings: uiSettings
        ),
        // Not main-actor by default: XCTestCase's inherited initialisers are
        // nonisolated and a main-actor class cannot override them.
        .testTarget(
            name: "EDraftUITests",
            dependencies: ["EDraftUI"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
