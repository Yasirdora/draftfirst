import AppKit
import EDraftCore
import XCTest
@testable import EDraftMacSurface

/// Is the glyph actually on the page, all of it?
///
/// Every earlier attempt at this question was answered by looking at a
/// screenshot, and looking was wrong twice: a crop that missed the top of the
/// glyph, then a colour threshold that under-measured its ink. So this draws
/// the real text view into a bitmap and measures the ink it painted, against
/// the same character drawn with nothing constraining it. Two numbers, no eyes.
@MainActor
final class GlyphIsNotClippedTests: XCTestCase {

    private let heading = "INT. LIVING ROOM - DAY 🔑"

    /// Rows containing warm-coloured ink — the emoji is gold, the Courier
    /// around it is grey, so "red clearly exceeds blue" isolates the glyph.
    private func inkRows(_ rep: NSBitmapImageRep) -> ClosedRange<Int>? {
        var top = Int.max, bottom = -1
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                guard c.alphaComponent > 0.2 else { continue }
                if c.redComponent - c.blueComponent > 0.20 {
                    top = min(top, y); bottom = max(bottom, y)
                    break
                }
            }
        }
        return bottom >= top ? top...bottom : nil
    }

    /// The glyph with nothing in its way: what "not clipped" measures.
    private func unconstrainedInkHeight() throws -> Int {
        let font = ScriptLayout.font(for: .scene)
        let size = NSSize(width: 120, height: 120)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor.black.setFill()
        NSRect(origin: .zero, size: size).fill()
        ("🔑" as NSString).draw(at: NSPoint(x: 40, y: 40), withAttributes: [.font: font])
        NSGraphicsContext.restoreGraphicsState()
        let rows = try XCTUnwrap(inkRows(rep), "the reference drew no glyph")
        return rows.count
    }

    func testTheFirstLinesEmojiIsPaintedWhole() throws {
        let surface = ScriptSurface(measure: 500)
        surface.scrollView.frame = NSRect(x: 0, y: 0, width: 700, height: 500)
        surface.render([ScriptElement(type: .scene, text: heading)])

        let view = surface.textView
        view.layoutManager?.ensureLayout(for: view.textContainer!)
        let bounds = view.bounds
        XCTAssertGreaterThan(bounds.height, 0)

        let rep = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: bounds))
        view.cacheDisplay(in: bounds, to: rep)

        let painted = try XCTUnwrap(
            inkRows(rep),
            "no glyph ink was painted at all — the emoji never reached the page"
        ).count
        let whole = try unconstrainedInkHeight()

        XCTAssertGreaterThanOrEqual(
            painted, whole - 1,
            "the emoji painted \(painted) rows of ink where an unclipped one is "
                + "\(whole) — the top is being cut by the view's own edge"
        )
    }
}
