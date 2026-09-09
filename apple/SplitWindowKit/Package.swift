// swift-tools-version: 6.2
import PackageDescription

/// An AppKit window that arranges SwiftUI columns under a unified toolbar.
///
/// App-agnostic on purpose: nothing here knows what a screenplay is. It exists
/// because on macOS 26 the toolbar's Liquid Glass items only adapt to the
/// content scrolling beneath them when the window is AppKit's — see
/// `SplitWindowController` — and every app that wants Pages' toolbar needs
/// the same forty lines of window plumbing. Copy the directory, or depend on
/// it by path.
let package = Package(
    name: "SplitWindowKit",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "SplitWindowKit", targets: ["SplitWindowKit"])
    ],
    targets: [
        .target(
            name: "SplitWindowKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .defaultIsolation(MainActor.self)
            ]
        )
    ]
)
