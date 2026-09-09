# Building for macOS 26, iOS 26 and iPadOS 26 as if Apple's own team did

*Written 2026-09-08 for whoever builds the next window, screen or app in this
repository — human or model. It exists because the Mac port was slowed by
things nobody had written down, and because the difference between an app that
feels native and one that does not is almost entirely in details that are
invisible until violated. Everything marked **measured** was verified on macOS
26.5 with real input events and a screenshot; everything else is Apple's
documented behaviour, a Human Interface Guidelines principle, or a rule this
project already lives by. Read [HANDOFF.md](HANDOFF.md) first.*

---

## 0. The standard

An app by Apple's own team has four properties, and each is a habit, not a
feature:

1. **The platform does the work.** Windows, documents, menus, sidebars,
   toolbars, undo, find, print, Versions, tabs, state restoration, Dark Mode,
   accessibility — every one of these is a system behaviour you *receive* by
   using the system class for the job, and *lose* the moment you draw your own.
   Before writing a view, name the AppKit or UIKit object Apple would use, and
   use it. Custom drawing is for the one thing your app is about (here: the
   page).
2. **Nothing is assumed; it is measured.** If a claim is about pixels, timing,
   focus or geometry, a screenshot or a number backs it. "It should work" is
   not a state a file can be in. The harness in §6 exists so that measuring is
   cheaper than guessing.
3. **The grammar is Apple's, not the app's.** Sidebar = destinations, never
   verbs. Toolbar = what acts on the document, grouped, trailing. Menu bar =
   everything, with shortcuts. Scope switches sit on top of the list they
   scope. Controls float over a canvas, never over the thing being read. Three
   type levels. Selection is a filled inset rounded rectangle. (See
   MACOS-DESIGN §1 for where each of these was read off Finder, Messages and
   Find My.)
4. **One product, two surfaces.** The rules of the craft live in the engine,
   the app's mind in the core, and only what genuinely differs per platform
   — text system, chrome, input — lives in a surface. A rule that mentions a
   view in its reason is in the wrong layer. (SHARED-ARCHITECTURE §2.)

## 1. The window on macOS 26 — the one decision that shapes everything

**The toolbar's Liquid Glass adapts to the content beneath it only in a window
AppKit created, whose content view controller is an `NSSplitViewController`.**
(measured) That adaptation *is* the native look on this OS: Pages' chips turn
light as the white page passes under them, dark over the desk, and the script
softens into the chrome instead of hitting a line.

Measured one arrangement at a time, with real scroll events:

| Arrangement | Chips adapt? |
|---|---|
| SwiftUI `WindowGroup` + `NavigationSplitView`, any style, with or without the sidebar toggle | No |
| The same with an `NSToolbar` installed on the SwiftUI window | No |
| `NSSplitViewController` hosted *inside* a SwiftUI window | No native sidebar, no toggle |
| Plain SwiftUI window with no split view | Yes, but no sidebar chrome |
| **`NSWindow` + `NSSplitViewController` + `NSToolbar`, SwiftUI inside each column** | **Yes: sidebar, toggle, tracking separator, all of it** |

Therefore: **the window is AppKit; the panels are SwiftUI.** That is
`apple/SplitWindowKit`, and it is the piece to copy into the next app. It also
decides the document architecture: `NSDocument` + `NSWindowController`, which
brings Save, Duplicate, Rename, Move To, Revert, Versions, Open Recent, tabs
and the "Edited" subtitle without a line of code. `DocumentGroup` remains
right for an app that does not need the adaptive toolbar and has no sidebar.

### 1.1 How the effect works, so its behaviour can be predicted

Beneath the toolbar the system draws a *scroll pocket*: a blur, and a tint in
a colour captured from the content, masked by a gradient over the bar and
about 28 points below it. It measures the luminance of what scrolls under the
bar and switches the bar's floating items between light and dark. Hence:

- Content **must run under the toolbar**: `.fullSizeContentView` on the
  window, and an `NSScrollView` that fills the column — it insets its own
  content below the bar. A SwiftUI `ScrollView` inside an
  `NSHostingController` gets the same pocket.
- **Never hide the toolbar background or draw a gradient of your own.** Both
  remove the system's edge. The old Mac window did exactly that to work
  around a `NavigationSplitView` that could not show it.
- The luminance **updates on real scrolling only**; programmatic offsets do
  not feed it. Verify with synthetic scroll events (§6), never by reasoning.
- `.scrollEdgeEffectStyle(.hard)` is an opaque bar with a crisp clip
  (Preview's look). `.soft` is the fade. Neither substitutes for §1.

### 1.2 The shape of a Mac document window here

```
[toggle | separator] [Back]  Title / subtitle   …   [Element ⌄] [Focus | Zoom] [Page | Title page | Export]  [⋯]
```

- `NSToolbarItem.isNavigational` puts Back before the title. The title and
  subtitle are the document's: `NSDocument` names the window, the controller
  writes the subtitle from the model.
- Grouped items (`NSToolbarItemGroup`) share one piece of glass;
  relatedness is shown by grouping, not by separators.
- Every item and every menu item is a **selector with no target**. AppKit
  walks the responder chain — text view, split view controller, window
  controller, document, document controller, app, delegate — enables what is
  answered and greys out the rest. `validateMenuItem` on the window
  controller sets radio states. There is then no state to keep in sync
  between toolbar, menu bar and shortcut, because there is only one action.
- The menu bar is built in code (`MainMenu`). `Open Recent` must be filled by
  a menu delegate from `NSDocumentController.shared.recentDocumentURLs`; the
  automatic version only works from a nib. Register `windowsMenu`,
  `servicesMenu` and `helpMenu` so the system fills them.

### 1.3 One window, by default

A library becomes the script: the document window takes the library window's
frame and the library closes; Back hands the frame back. To the writer one
window changed what it holds. "Open in New Window" is the one explicit
exception. Do this by moving frames, not by swapping content view
controllers — each document keeps its own `NSWindowController`, which is what
Versions, tabs and restoration expect.

## 2. Hosting SwiftUI inside AppKit

- `NSHostingController.sizingOptions = []` for a column. Otherwise a hosted
  `List` reports the width of its longest row as intrinsic and fights the
  split view.
- **Assigning `contentViewController` resizes the window to that
  controller's view** (measured: 1093×500 for a window created at 1280×860).
  Call `setContentSize` *after* assigning it.
- SwiftUI re-exports AppKit's types on macOS. A shared package must not
  `import AppKit`; the boundary check forbids it, and it is unnecessary.
- `.sheet`, `.alert` (including one with a `TextField`) and `Menu` work inside
  hosted views and present as real sheets and menus.
- `updateNSView` does **not** run when only the representable's frame
  changes. Fit-to-width, re-centring, anything that reacts to size needs its
  own trigger (`onGeometryChange`, or a state change you control).
- Bridge an `@Observable` model to AppKit with `withObservationTracking`,
  re-armed on each change (`SplitWindowKit.observeChanges`). It stops itself
  once the closure's `[weak self]` is gone.
- `NavigationStack` inside a hosted column draws no bar and is harmless; it
  is there for `navigationDestination` declarations shared with iOS.

## 3. Documents, files and Swift 6

- `NSDocument` overrides that AppKit declares `nonisolated`
  (`autosavesInPlace`, `read(from:ofType:)`) must be `nonisolated` in Swift 6
  language mode. Wrap the body in `MainActor.assumeIsolated`: they are called
  on the main thread unless the class opts into concurrent reading.
- `@objc(Name)` on the document class and `NSDocumentClass` on each document
  type in `Info.plist`; `NSPrincipalClass` = `NSApplication` for
  `NSApplicationMain`. Keep the same UTIs and extensions on every platform
  — one document format is a rule, not a preference.
- With `autosavesInPlace`, closing never asks and killing the process still
  writes what was typed. Your test files will change under you; expect it.
- Reading and writing bytes belongs to the core (`ScreenplayFile`); the
  document class is the conformance and nothing more.
- Files a writer has *not* opened (rename, duplicate, trash from a library)
  are the app's job, in the one place that can ask the document controller
  whether the file is open and hand the operation to that document so its
  window follows (`NSDocument.move(to:)`). Trash, never delete.

## 4. Text views and geometry

- `NSTextView.textContainerOrigin` already contains `textContainerInset`. A
  rect from the layout manager offset by that origin is in **view
  coordinates**; adding the inset again moves every mark one line (measured
  three times over: reveal mark, find bar, format bar).
- Edit through `insertText(_:replacementRange:)`. `replaceCharacters` skips
  `shouldChangeTextIn`, which is where the model learns of the edit and undo
  is registered.
- Geometry read from a text view is a *result* of layout. Ask for layout
  (`ensureLayout(for:)`) before measuring; a blank last line lives in
  `extraLineFragmentUsedRect` and only after that call.
- `CGRect.isEmpty` is true when either dimension is zero; a blank line has
  no width and still has a place. Test `height > 0`.
- A view placed on a flipped canvas must itself be flipped, or its content
  sits at the foot.
- Layer `cgColor`s are snapshots; take them inside
  `effectiveAppearance.performAsCurrentDrawingAppearance`, or the view is
  wrong in one of the two appearances.
- HANDOFF §5 has the rest: TextKit 1 by decision, `minSize`/`maxSize`, Tab
  handled once, predictions being async.

## 5. iOS 26 and iPadOS 26

- Same engine, same core, same `.draft`. The touch surface holds only the
  page; the phone's chrome stays in its app target, and **the iPad's chrome
  has not been designed** — do not invent one shared with the phone
  (decision of 2026-09-06). When it is designed, it starts from the same
  grammar as the Mac: sidebar of destinations, toolbar of document actions,
  scope on top of the list.
- `DocumentGroupLaunchScene` exists on iOS and is unavailable on macOS; the
  Mac draws its own launch window on the same `LaunchIdentity` ground so
  the two greetings do not drift.
- `UITextView` with TextKit 1 (`usingTextLayoutManager: false`) is
  deliberate; `PageScroll` and the reveal mark were written against its
  rectangles.
- The keyboard is the phone's chrome: `isEditing` means something visible
  there and nothing on a Mac. A control that follows it belongs to iOS only.
- Liquid Glass on iOS adapts on its own inside the system bars; the
  AppKit-window constraint in §1 is a Mac fact. Not measured here — treat
  iOS behaviour as Apple documents it, and measure before relying on it.

## 6. Measuring instead of assuming — the harness

Nothing in this file was found by reading documentation. Every entry marked
measured came from this loop, which costs minutes:

1. **Build** the bundle with `xcodebuild … CODE_SIGN_IDENTITY="-"
   CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=""` (headless signing hangs
   otherwise).
2. **Launch** it with `open -n -a <App.app> --args -ApplePersistenceIgnoreState YES [file]`.
   Without the flag the last document and window frame come back and you will
   measure restoration, not your code.
3. **Find the window** by owner pid with `CGWindowListCopyWindowInfo`
   (`pgrep -f` takes a regex — escape the parentheses in `eDraft (macOS)`).
   A locked or sleeping display reports no windows; that is the display.
4. **Drive it with real input**: post `CGEvent` scroll and mouse events from a
   process that `AXIsProcessTrusted()`. Programmatic scroll offsets do not
   exercise the scroll pocket. Never do this while the owner is using the
   Mac — the events land in their session, and their keystrokes land in your
   measurement.
5. **Capture** with `screencapture -x -o -l <windowID>`; crop with `sips -c H W
   --cropOffset 1 1` (an offset of `0 0` centre-crops).
6. **Read the numbers**, not the impression: sample pixel columns for
   gradients, read window frames from the list, read `NSAlert`s from the
   window list too (a sheet is a window).
7. **Pin what you found** with a test that would have failed before the fix
   (`RevealMarkPlacementTests` is the template: it measures a frame against a
   layout rect), and write the number into the doc comment where the code
   would otherwise look arbitrary.

New Swift files must be added to `project.pbxproj` by hand — a
`PBXBuildFile`, a `PBXFileReference`, the group child and the Sources entry.
The build-file line contains the file reference's id too; count for both.

## 7. Definition of done for any piece of UI

- The system object for the job is used, and nothing it provides was
  re-implemented.
- It works in Light and Dark, with the page paper and dark, at 100% and at
  fit, and with the sidebar collapsed.
- Every action has a menu item, a shortcut where Apple has one, and is
  enabled only when it can do something.
- It is reachable by keyboard; every control has an accessibility label; the
  reveal and other motion respect Reduce Motion.
- A screenshot proves the visible claim; a test pins the measurable one; the
  boundary check and every package's `swift test` are green; the decision
  and any number you had to measure are in MACOS-EXECUTION.

## 8. Anti-patterns this project has already paid for

- Re-deciding a screenplay rule in a view or a model (§0.4).
- Drawing the toolbar's edge by hand because the system's was not showing —
  the fix was the window, not the gradient.
- Hidden characters in a text view "to render markup": ranges are the
  storage's, and a character that exists but does not draw breaks every
  measurement that follows. WYSIWYG is inline runs in the model (M5), not a
  trick in the view.
- A refactor that only forwards a call (M0.5 was cancelled for it).
- Reporting a UI result you could not drive or see. Say what was measured and
  what was not.
