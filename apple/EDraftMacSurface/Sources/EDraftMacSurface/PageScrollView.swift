import AppKit
import EDraftCore

/// The editor's scroll view, with the pinch gesture routed by hand.
///
/// AppKit's own handling of a magnify gesture scales the document around
/// the point under the cursor — and during the gesture it does so off the
/// bounds path entirely, so the clip view's centring is only consulted when
/// the gesture commits: cursor on the left, the page pulled left for the
/// whole pinch and snapped to the midline at the end. Routing the gesture
/// by hand puts every frame through `setMagnification(_:centeredAt:)`, a
/// bounds-path API the clip view constrains — so the page's midline owns
/// the horizontal anchor throughout, while the line under the fingers keeps
/// the vertical one.
///
/// The surface's gesture bookkeeping is fed the same notifications AppKit
/// would have posted, so the live readout, the settle and the drift cannot
/// tell the difference.
final class PageScrollView: NSScrollView {

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        widenLimitsForTheSpring()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("the editor's scroll view is built in code")
    }

    /// The scroll view's limits stand a spring's width past the page's own,
    /// so a pinch can pull into the band and be pulled back (`PageZoom`).
    /// Everything deliberate is clamped by `PageZoom` before it gets here.
    private func widenLimitsForTheSpring() {
        minMagnification = PageZoom.bandMinimum
        maxMagnification = PageZoom.bandMaximum
    }

    override func magnify(with event: NSEvent) {
        // Never `super`: that is the path being bypassed.
        handleMagnify(delta: event.magnification, phase: event.phase, at: event.locationInWindow)
    }

    /// One gesture event, routed. An unphased event — a mouse driver's idea
    /// of a pinch — is a self-contained nudge: applied, then settled.
    func handleMagnify(delta: CGFloat, phase: NSEvent.Phase, at windowPoint: NSPoint) {
        if phase.contains(.began) {
            NotificationCenter.default.post(
                name: NSScrollView.willStartLiveMagnifyNotification, object: self
            )
        }
        if phase.isEmpty || phase.contains(.changed) {
            applyMagnify(delta: delta, at: windowPoint)
        }
        if phase.isEmpty || phase.contains(.ended) || phase.contains(.cancelled) {
            NotificationCenter.default.post(
                name: NSScrollView.didEndLiveMagnifyNotification, object: self
            )
        }
    }

    /// The size the fingers asked for, resisted past the ends and anchored
    /// on the cursor's point in the document. The anchor keeps the vertical
    /// line under the fingers; the clip view's constraint answers the
    /// horizontal half with the page's midline.
    private func applyMagnify(delta: CGFloat, at windowPoint: NSPoint) {
        guard delta != 0, let document = documentView else { return }
        let target = PageZoom.resisted(magnification * (1 + delta))
        setMagnification(target, centeredAt: document.convert(windowPoint, from: nil))
    }
}
