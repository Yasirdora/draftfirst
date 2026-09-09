import Observation

/// Runs `apply` now, and again each time any `@Observable` property it read
/// changes — the bridge from a SwiftUI-era model to a toolbar item or a window
/// title that has to be told.
///
/// Observation stops on its own once `apply` reads nothing observable, which
/// is what happens after a `[weak self]` capture goes nil: there is then
/// nothing to track, and nothing to re-arm.
public func observeChanges(_ apply: @escaping @MainActor () -> Void) {
    withObservationTracking {
        apply()
    } onChange: {
        Task { @MainActor in observeChanges(apply) }
    }
}
