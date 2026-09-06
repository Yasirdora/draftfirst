# The Mac page is one long sheet, and it opens in the wrong place

Repo `/Users/x/Documents/edraft`, branch `rename/edraft`. Measure the floor at
start; do not quote these numbers back.

Three faults, all reported from the running Mac app by the owner, all in how
the page is *presented* rather than in what the document says. They are listed
in the order they should be fixed, because the third is cheap and the second
changes the geometry the third depends on.

---

## How to see them without a keyboard

This matters more than it sounds. Every one of these was missed by a green
suite, and the owner found all three by looking. The app can be driven with the
display awake and **without taking focus from whatever else is running**:

```bash
# Open a real screenplay. No focus stolen; the app is not activated.
open -g -a "$DERIVED/eDraft (macOS).app" some.fountain

# Menu items work through the accessibility API without frontmost:
osascript -e 'tell application "System Events" to tell process "eDraft (macOS)" \
  to perform action "AXPress" of (first menu item of menu 1 of \
  menu bar item "File" of menu bar 1 whose name is "New")'

# Capture just the app's window — screencapture -l <id>, id from the window list.
```

`scripts`-adjacent helper: a five-line Swift tool that prints eDraft's window
ids via `CGWindowListCopyWindowInfo`. `CGWindowListCreateImage` is gone in this
macOS, so `screencapture -l` does the imaging. **None of this works while the
display is asleep** — window capture and the accessibility API both go dark.
See MACOS-EXECUTION §4a.

Sending keystrokes *does* need focus. Guard every one:

```bash
front=$(osascript -e 'tell application "System Events" to return name of first process whose frontmost is true')
[[ "$front" != "eDraft (macOS)" ]] && { echo "ABORT: $front"; exit 0; }
```

Without that guard the keystrokes go into whatever the owner is using. It has
happened.

---

## 1. The document opens scrolled past its first lines

**Evidence.** Open a screenplay whose first element is an action line. The
first visible line is cut in half at the top of the viewport, and the element
above it is off-screen. The writer's first sight of their script is its middle.

**Where to look.** `ScriptSurface` scrolls in three places:

| line | what |
|---|---|
| `centreHorizontallyIfNeeded` | new; sets x only, preserves `origin.y` |
| `scroll(bringingToTop:)` | reveal; sets both |
| `restoreViewport` | after a render |

`takeInitialFocus()` calls `placeCaretForEditing()` before
`makeFirstResponder`, and that restores a selection, which AppKit may scroll to.
The opening scroll position is nobody's stated responsibility, which is
probably why it is wrong.

**What must be true.** A document opens showing its first line, at the top of
the page, with the page's top margin visible above it. Test it: a surface bound
to a multi-page script, in a window, must have `contentView.bounds.origin.y`
at 0 after the first layout.

**Suspect first** that this is a regression from the zoom work in `f432114`
(`applyZoomForCurrentSize` now runs from a `frameDidChangeNotification`, which
fires earlier than anything did before). Check by stubbing that method out. If
the fault predates it, say so — it is worth knowing either way.

---

## 2. The page is one continuous sheet, not a sequence of pages

**Evidence.** Twenty-five scenes render as an unbroken column. The Navigator's
page column counts 1, 2, 3, 4 correctly, so pagination *knows* where the breaks
are — the canvas simply does not draw them.

**Where.** `PageCanvasView.layoutPage` builds exactly one card:

```swift
let pageHeight = max(pageSize.height, format.textTop + textHeight + format.textTop)
pageView.frame = CGRect(x: …, y: canvasPadding, width: pageSize.width, height: pageHeight)
```

and `draw(_:)` strokes a hairline every `pageRect.height` down it. So a
120-page script is one card 95,000 points tall with rules across it.

**What it should be.** Discrete sheets with desk between them, the way Pages
and Word show a document — because the page edge is the ruler a screenwriter
reads length by (`MACOS-DESIGN` §3.2), and a rule across a continuous strip is
not an edge.

**This is the hard one, and it is mostly arithmetic, not drawing.** The text
view is a single `NSTextView` spanning the whole script; making the page card
discrete means the text must skip the gap between sheets. Options, in the order
worth considering:

1. **Draw sheets, keep one text run.** The canvas draws N cards with gaps and
   the text view sits above them, but then a line lands in a gap.
2. **Exclusion paths.** `NSTextContainer.exclusionPaths` for each gap, so the
   layout manager flows around them. One text view, real page breaks, and the
   caret arithmetic in `PageScroll` keeps working. Most promising.
3. **A text view per page.** Correct-looking and a great deal of machinery —
   find, undo, and the incremental edit path all assume one view.

Whatever is chosen, `ScreenplayPageLayout` in the core already knows where the
breaks fall and the PDF already prints them; **do not compute page breaks a
second time in the surface.** Ask the core.

---

## 3. A tall glyph is clipped

**Evidence.** `ACT ONE 🔑` — the emoji's top is sliced off.

**Why.** A screenplay is six lines to the inch, so the paragraph style pins
`minimumLineHeight` and `maximumLineHeight` to 12. An emoji's ascent exceeds
that and `maximumLineHeight` clips rather than overflows.

**The tension is real and the answer is a decision, not a fix.** Letting the
line grow breaks the six-lines-per-inch rhythm the whole format rests on and
would make the on-screen page disagree with the printed one. The likely right
answer is that an emoji is drawn at the line's height rather than its own —
scaled down to fit, not clipped. Confirm what the PDF does with the same
character before changing the screen: **the two must agree**, and if the PDF
already scales it, the screen has a bug rather than a question.

---

## Standard

Read the tree, not this page. A green suite is not a finished box — all three
of these shipped past one. Every claim in your report should name how you saw
it: a test that failed first, or a screenshot.

Do not touch `EDraftCore.PageZoom` or the zoom control's behaviour; that landed
in `f432114` and the owner has settled its defaults (opens at 150%, ⌘0 actual
size, ⌘9 fit, the percentage button toggles). If fixing 1 or 2 requires
changing it, say why before you do.

Floor: measure it. Boundaries green, both apps build, iOS untouched. Prose
commit messages in the voice of `git log`.

## Report

1. Whether fault 1 predates the zoom work, and how you know.
2. Which of the three approaches to fault 2 you took, and what the other two
   would have cost.
3. What the PDF does with the emoji, before and after.
4. What a human should look at, in order, and what would count as wrong.
5. What in this brief the tree contradicts.
