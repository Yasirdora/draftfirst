import AppKit

/// Draws the completion with the same TextKit stack as the editor without ever
/// inserting prediction text into the real document. Matching containers and
/// paragraph attributes keep baselines, indents, and line wrapping identical.
///
/// The overlay's frame is the host *line*'s rect (plus a glyph overhang) —
/// never the document: a plain `draw(_:)` view's backing store is sized to its
/// bounds, so spanning a feature-length script would allocate hundreds of
/// megabytes to draw a dozen glyphs.
///
/// Text views are flipped, and so is this: a ghost whose coordinates ran the
/// other way would land as far below the line as it should be on it. See
/// `RevealHighlightViewMac`.
@MainActor
final class GhostTextOverlay: NSView {
    var onAccept: (() -> Void)?
    /// When false the overlay is decoration, not a click target — hint
    /// predictions must not be acceptable.
    var acceptsClicks = false

    private let storage = NSTextStorage()
    private let layoutManager = NSLayoutManager()
    private let textContainer = NSTextContainer(size: .zero)
    private var ghostGlyphRange = NSRange(location: 0, length: 0)
    private var ghostHitRect = CGRect.null
    private var drawingOrigin = CGPoint.zero
    private var hostLineRect = CGRect.null
    private var renderedKey: RenderKey?
    private var drawnColor: NSColor?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false
        isHidden = true

        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(textContainer)
        layoutManager.allowsNonContiguousLayout = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }

    /// A mark is not a button unless the prediction is actionable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, acceptsClicks, ghostHitRect.contains(point) else { return nil }
        return self
    }

    override func mouseDown(with event: NSEvent) {
        guard acceptsClicks, !isHidden else { return }
        onAccept?()
    }

    @discardableResult
    func present(
        in host: NSTextView,
        base: NSAttributedString,
        suffix: String,
        insertionLocation: Int,
        paragraphRange: NSRange,
        attributes: [NSAttributedString.Key: Any],
        revision: Int
    ) -> Bool {
        guard paragraphRange.location >= 0,
              NSMaxRange(paragraphRange) <= base.length,
              insertionLocation >= paragraphRange.location,
              insertionLocation <= NSMaxRange(paragraphRange) else {
            hide()
            return false
        }

        let scale = host.window?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor
            ?? 2
        let width = host.bounds.width
        let containerWidth = host.textContainer?.size.width ?? width
        let key = RenderKey(
            revision: revision,
            insertionLocation: insertionLocation,
            suffix: suffix,
            paragraphLocation: paragraphRange.location,
            paragraphLength: paragraphRange.length,
            pixelWidth: Int((width * scale).rounded()),
            pixelContainerWidth: Int((containerWidth * scale).rounded()),
            appearance: host.effectiveAppearance.name.rawValue,
            attributeDescription: String(describing: attributes)
        )

        guard key != renderedKey else {
            return !isHidden
        }

        textContainer.lineFragmentPadding = host.textContainer?.lineFragmentPadding ?? 0
        textContainer.lineBreakMode = host.textContainer?.lineBreakMode ?? .byWordWrapping
        textContainer.maximumNumberOfLines = host.textContainer?.maximumNumberOfLines ?? 0
        textContainer.exclusionPaths = []
        textContainer.size = CGSize(width: containerWidth, height: .greatestFiniteMagnitude)
        if let hostLayout = host.layoutManager {
            layoutManager.usesFontLeading = hostLayout.usesFontLeading
        }

        let localLocation = insertionLocation - paragraphRange.location
        // An empty screenplay element has no host glyph to anchor against.
        // Wait for the writer's first character instead of guessing a baseline.
        guard localLocation > 0 else {
            hide()
            return false
        }
        let paragraph = base.attributedSubstring(from: paragraphRange)
        storage.setAttributedString(paragraph)
        layoutManager.ensureLayout(forCharacterRange: NSRange(location: 0, length: storage.length))
        let originalLineY = lineOriginY(before: localLocation)

        let mirrored = NSMutableAttributedString(attributedString: paragraph)
        mirrored.insert(NSAttributedString(string: suffix, attributes: attributes), at: localLocation)
        storage.setAttributedString(mirrored)
        let ghostCharacterRange = NSRange(
            location: localLocation,
            length: (suffix as NSString).length
        )
        ghostGlyphRange = layoutManager.glyphRange(
            forCharacterRange: ghostCharacterRange,
            actualCharacterRange: nil
        )
        layoutManager.ensureLayout(forCharacterRange: ghostCharacterRange)

        let lineFragments = ghostLineFragments()
        let completedPrefixLineY = lineOriginY(before: localLocation)
        let prefixStayedOnLine: Bool
        if let originalLineY {
            prefixStayedOnLine = completedPrefixLineY.map {
                abs(originalLineY - $0) < 0.5
            } ?? false
        } else {
            prefixStayedOnLine = true
        }
        guard ghostGlyphRange.length > 0,
              lineFragments.count == 1,
              prefixStayedOnLine else {
            hide()
            return false
        }

        let ghostLine = lineFragments[0]
        let ghostStayedBesidePrefix = completedPrefixLineY.map {
            abs(ghostLine.usedRect.minY - $0) < 0.5
        } ?? (localLocation == 0)
        guard ghostStayedBesidePrefix else {
            hide()
            return false
        }

        guard let hostLineTop = hostLineTop(
            in: host,
            precedingCharacterAt: insertionLocation
        ) else {
            hide()
            return false
        }

        let mirrorInsertionX = ghostLine.lineRect.minX
            + layoutManager.location(forGlyphAt: ghostGlyphRange.location).x
        let insetX = host.textContainerInset.width
        // `firstRect(forCharacterRange:)` is in screen space and is junk
        // without a window. Skip the caret-alignment hide in that case and
        // trust the layout-manager checks that do not need a window. Do not
        // invent a caret.
        if let caretX = caretMinX(in: host, at: insertionLocation) {
            let expectedCaretX = insetX + mirrorInsertionX
            guard abs(expectedCaretX - caretX) < 1.5 else {
                // The completed candidate would reflow the already-typed prefix.
                // Hiding is safer than drawing a completion away from the caret.
                hide()
                return false
            }
            drawingOrigin = CGPoint(
                x: caretX - mirrorInsertionX,
                y: hostLineTop - ghostLine.usedRect.minY
            )
        } else {
            drawingOrigin = CGPoint(
                x: insetX,
                y: hostLineTop - ghostLine.usedRect.minY
            )
        }

        hostLineRect = ghostLine.lineRect
            .union(ghostLine.glyphRect)
            .offsetBy(dx: drawingOrigin.x, dy: drawingOrigin.y)
        updateFrame()
        let localVisibleRect = ghostLine.glyphRect
            .offsetBy(dx: drawingOrigin.x - frame.minX, dy: drawingOrigin.y - frame.minY)
        ghostHitRect = CGRect(
            x: localVisibleRect.minX,
            y: localVisibleRect.midY - 22,
            width: max(44, localVisibleRect.width),
            height: 44
        )
        drawnColor = attributes[.foregroundColor] as? NSColor
        renderedKey = key
        isHidden = false
        needsDisplay = true
        return true
    }

    func isPresenting(suffix: String, insertionLocation: Int, revision: Int) -> Bool {
        guard !isHidden, let renderedKey else { return false }
        return renderedKey.suffix == suffix
            && renderedKey.insertionLocation == insertionLocation
            && renderedKey.revision == revision
    }

    func hide() {
        guard !isHidden || renderedKey != nil else { return }
        isHidden = true
        renderedKey = nil
        drawnColor = nil
        ghostGlyphRange = NSRange(location: 0, length: 0)
        ghostHitRect = .null
        drawingOrigin = .zero
        hostLineRect = .null
        // Collapsing the frame releases the layer's backing store.
        frame = .zero
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !isHidden, ghostGlyphRange.length > 0 else { return }
        layoutManager.drawGlyphs(
            forGlyphRange: ghostGlyphRange,
            at: CGPoint(x: drawingOrigin.x - frame.minX, y: drawingOrigin.y - frame.minY)
        )
    }

    // MARK: - What a test can ask

    var presentedSuffix: String? { isHidden ? nil : renderedKey?.suffix }
    var hostLineRectForTests: CGRect { hostLineRect }
    var foregroundColorForTests: NSColor? { drawnColor }

    // MARK: - Layout

    private static let lineOverhangMargin = CGFloat(8)

    private func updateFrame() {
        guard !hostLineRect.isNull else {
            frame = .zero
            return
        }
        frame = hostLineRect.insetBy(dx: -2, dy: -Self.lineOverhangMargin)
    }

    private func ghostLineFragments() -> [LineFragment] {
        var fragments: [LineFragment] = []
        layoutManager.enumerateLineFragments(forGlyphRange: ghostGlyphRange) {
            lineRect, usedRect, container, lineGlyphRange, _ in
            let intersection = NSIntersectionRange(lineGlyphRange, self.ghostGlyphRange)
            guard intersection.length > 0 else { return }
            fragments.append(LineFragment(
                lineRect: lineRect,
                usedRect: usedRect,
                glyphRect: self.layoutManager.boundingRect(forGlyphRange: intersection, in: container)
            ))
        }
        return fragments
    }

    /// The real glyph line in the host text view's content coordinates.
    /// TextKit's used line rectangle is the source of truth for the screenplay
    /// baseline, so the completion shares the real glyph line at every scroll.
    private func hostLineTop(
        in host: NSTextView,
        precedingCharacterAt insertionLocation: Int
    ) -> CGFloat? {
        guard insertionLocation > 0,
              let layout = host.layoutManager,
              let storage = host.textStorage,
              insertionLocation <= storage.length,
              layout.numberOfGlyphs > 0 else { return nil }

        let characterRange = NSRange(location: insertionLocation - 1, length: 1)
        layout.ensureLayout(forCharacterRange: characterRange)
        let glyphIndex = layout.glyphIndexForCharacter(at: characterRange.location)
        guard glyphIndex < layout.numberOfGlyphs else { return nil }

        let usedRect = layout.lineFragmentUsedRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        )
        return host.textContainerInset.height + usedRect.minY
    }

    private func lineOriginY(before characterLocation: Int) -> CGFloat? {
        guard characterLocation > 0, layoutManager.numberOfGlyphs > 0 else { return nil }
        let characterIndex = min(characterLocation - 1, max(0, storage.length - 1))
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil).minY
    }

    /// Caret X in the text view's own coordinates, or nil when there is no
    /// window (or the text system will not say). Screen-space `firstRect` is
    /// not converted into a guess.
    private func caretMinX(in host: NSTextView, at location: Int) -> CGFloat? {
        guard host.window != nil else { return nil }
        var actual = NSRange()
        let screen = host.firstRect(
            forCharacterRange: NSRange(location: location, length: 0),
            actualRange: &actual
        )
        guard screen.height > 0, let window = host.window else { return nil }
        let inWindow = window.convertFromScreen(screen)
        let inHost = host.convert(inWindow, from: nil)
        guard inHost.height > 0 else { return nil }
        return inHost.minX
    }

    private struct LineFragment {
        let lineRect: CGRect
        let usedRect: CGRect
        let glyphRect: CGRect
    }

    private struct RenderKey: Equatable {
        let revision: Int
        let insertionLocation: Int
        let suffix: String
        let paragraphLocation: Int
        let paragraphLength: Int
        let pixelWidth: Int
        let pixelContainerWidth: Int
        let appearance: String
        let attributeDescription: String
    }
}
