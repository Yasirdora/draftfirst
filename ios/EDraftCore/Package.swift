// swift-tools-version: 6.2
import PackageDescription

/// The app's mind, shared by every eDraft surface.
///
/// Between `EDraftEngine` (the rules of the craft — parsing, pagination,
/// prediction, choreography) and the platform surfaces (UIKit on iPhone,
/// AppKit on the Mac) sits everything that is neither: what the writer has
/// selected, what undo means, how an edit is planned, what the Navigator
/// lists, how a document arrives.
///
/// It imports Foundation and Observation and nothing else, ever. That
/// restriction is the whole point: it is what lets one implementation of the
/// editor's behaviour serve both apps, and what stops a rule from being
/// re-decided inside a view. See docs/SHARED-ARCHITECTURE.md.
/// The app targets are built main-actor-by-default (Swift 6 language mode,
/// `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`). This code was written under
/// that assumption and must keep it: a package that defaulted to nonisolated
/// would demand annotations that say nothing true about the app, and the two
/// surfaces would drift apart in their concurrency, which is the one kind of
/// drift the compiler cannot warn a reader about.
let coreSettings: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .defaultIsolation(MainActor.self)
]

let package = Package(
    name: "EDraftCore",
    platforms: [
        .iOS(.v26),
        .macOS(.v26)
    ],
    products: [
        .library(name: "EDraftCore", targets: ["EDraftCore"])
    ],
    dependencies: [
        .package(path: "../eDraftEngine")
    ],
    targets: [
        .target(
            name: "EDraftCore",
            dependencies: [.product(name: "EDraftEngine", package: "eDraftEngine")],
            swiftSettings: coreSettings
        ),
        // Not main-actor by default: XCTestCase's inherited initialisers are
        // nonisolated, and a test class that defaults to the main actor cannot
        // override them. Tests that touch main-actor state say @MainActor on
        // the method, which is also how the app target's tests read.
        .testTarget(
            name: "EDraftCoreTests",
            dependencies: ["EDraftCore"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
