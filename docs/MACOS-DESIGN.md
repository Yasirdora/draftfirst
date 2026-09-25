# eDraft on macOS — Design

*Status: design, pre-code · A one-page summary of this document is published at
<https://claude.ai/code/artifact/8165da3d-ddcc-4c8a-8dd1-5778ec970307> and kept in
`docs/artifacts/macos-design-direction.html`. Companion to [MACOS-PLAN.md](MACOS-PLAN.md) (why and when) and [SHARED-ARCHITECTURE.md](SHARED-ARCHITECTURE.md) (how the two apps stay one app).*

---

## 1. Reading the references

Three Apple apps were given as the reference layout: **Finder**, **Messages**,
**Find My**. They are not three designs. They are one grammar, and it is worth
naming precisely, because most of what makes them feel native is invisible
until you try to violate it.

### 1.1 The sidebar answers "which one", the content answers "what is it"

In all three, the split is not visual — it is a division of *questions*.
Finder's sidebar names places; Messages' names conversations; Find My's names
tracked things. None of them contains a control that acts on the content.
There is no formatting button, no zoom, no share in a sidebar. The moment a
sidebar starts doing work on the thing to its right, it stops being navigation
and becomes a second toolbar, and the window loses its centre.

**The rule we inherit:** the sidebar contains *destinations*, never *verbs*.

### 1.2 Scope lives at the top of the list it scopes

Find My is the clearest case: **People · Devices · Items** is a segmented
control directly above the list, and switching it re-populates the list without
touching the map. Messages puts search and a filter in the same position.
Finder does it structurally, with headed sections (Favorites, Locations, Tags).

Three apps, three mechanisms, one placement — the scope selector is the first
thing in the sidebar, above the rows it governs, and never in the content's
toolbar.

**The rule we inherit:** if a list can show two kinds of thing, the switch sits
on top of that list.

### 1.3 A row is a triplet

Find My's row is the whole lesson in one line:

```
(icon)  Ysr's Backpack  [battery]        0 mi
        Home · Now
```

- a **leading glyph**, same size, same x, down the entire list;
- a **title**, with any status that *qualifies the name* set inline with it
  (the battery pill);
- a **subtitle** in secondary colour, carrying context ("Home · Now");
- a **trailing metric**, right-aligned, carrying the number you compare rows by
  ("0 mi").

It scans because the columns are alignment spines: the eye reads *down* one
column, not across each row. Messages and Finder use reduced forms of the same
triplet.

**The rule we inherit:** every row we design must decide which of its facts is
the identity, which is the context, and which is the comparable number — and
put them in those three places.

### 1.4 Selection is a filled, inset rounded rectangle

Messages' selected conversation is a full-width accent-filled capsule inset
from the sidebar's edges. Not a tinted row, not a bar in the margin. It reads
as "this row is the subject of the right-hand pane", which is exactly the
relationship it encodes.

### 1.5 The toolbar is grouped pills, right-aligned, with the title on the left

Finder: `[view switcher] [share · tags · more] [search]`. Relatedness is
encoded by grouping; the gaps between groups do the work that separators and
labels do in lesser designs. Search is always furthest right. The title is
left, bold, and is the *location*, not the app's name.

### 1.6 Content owns its space; controls float or dock

Find My floats map controls in the corners — the map is never interrupted.
Messages docks the composer to the bottom edge, because typing is the recurring
act in a chat. Finder leaves the content pane entirely to the files.

**The rule we inherit:** controls may float over a *canvas*, never over the
thing being read.

### 1.7 Only three typographic levels

Title (semibold), subtitle (secondary), metric (tertiary), plus a deliberately
quiet section header. That is the whole hierarchy. Depth comes from colour and
weight, not from size — the size range across an entire Finder sidebar is about
two points.

---

## 2. What not to copy

Being faithful to the references means knowing which parts are answers to *their*
problems.

- **Messages' bottom composer is wrong for a document.** A chat has a "send"; a
  screenplay does not. A docked input bar under a page would compete with the
  page for the eye and steal vertical space from the only thing that matters.
  What the composer *represents* — the recurring act, always in reach — belongs
  in eDraft as the element control in the toolbar and on the keyboard.
- **Finder's Tags section is a long, low-value tail.** It fills the sidebar
  because the sidebar has room. We will not add a section to eDraft's sidebar
  unless a writer navigates by it.
- **Find My's floating controls sit over a map, which has no reading order.**
  Floating anything over the page would occlude the sentence being read. On our
  canvas, floating controls are allowed only in the margins beside the page.

---

## 3. The direction

> **The window is the script's desk: the structure on the left, the page in the
> middle — and nothing else, until there is something to read alongside the page.**

Two panes is the reference grammar, and it is the grammar we use. A third pane
was drawn here because Pages, Keynote, Xcode and Sketch all keep a properties
inspector on the right. Those inspectors earn permanent width because in those
apps you are formatting continuously. This product's charter is the opposite:
the writer never formats. A title is set once, a scene's length checked
occasionally, a character renamed rarely. Transient things are a sheet or a
destination in the sidebar, not a column that clips the page.

The right column is **reserved**, not cancelled. It returns when there is
something to read *alongside* the page: comments and notes anchored to
`ScriptElement.id`. That is a real workflow. Properties of the selection are not.

One column has already earned its way in on those terms, and it is not on the
right. Selecting a character in the Cast tab opens that character's thread — every
scene they appear in, every line they speak — in a narrow column *between* the
Navigator and the page, the way Notes shows a note beside its folder list. It is
something to read alongside the page rather than something to state about it, it
appears only while a character is selected, and it takes width from nothing when
no one is. Deselect, or leave the Cast tab, and the window is two panes again.

```
┌──────────────┬──────────────────────────────────────────┐
│  NAVIGATOR   │                 PAGE                     │
│              │                                          │
│ ⌜Scenes│Cast⌝│         ┌───────────────────┐            │
│              │         │                   │            │
│ 1  INT. …  1 │         │   the page, on a  │            │
│ 2  EXT. …  3 │         │   neutral canvas  │            │
│ 3  INT. …  4 │         │                   │            │
│              │         │                   │            │
│ ──────────── │         └───────────────────┘            │
│ 3 scenes ·   │                                          │
│ 2 locations  │                                          │
└──────────────┴──────────────────────────────────────────┘

and with a character selected in Cast — the thread takes its width from
the canvas, never from the page:

┌──────────────┬───────────────┬──────────────────────────┐
│  NAVIGATOR   │  MARA      ⋯  │           PAGE           │
│              │               │                          │
│ ⌜Scenes│Cast⌝│ 12 speeches   │      ┌──────────────┐    │
│              │ ───────────── │      │              │    │
│ ◯ MARA    12 │ INT. CAFE     │      │  the page    │    │
│ ◯ ELENA    8 │ "We are late" │      │              │    │
│ ◯ DAVID    3 │ "I know"      │      │              │    │
│              │ EXT. STREET   │      └──────────────┘    │
│ ──────────── │ "Not here"    │                          │
│ 3 scenes ·   │               │                          │
│ 2 locations  │               │                          │
└──────────────┴───────────────┴──────────────────────────┘
```

### 3.1 Left — the Navigator

The same information architecture as the iOS Navigator, deliberately: **Scenes ·
Cast**, a segmented control at the top of the list (§1.2), the same row grammar,
the same footnote of document statistics at the bottom. A writer who learns the
phone knows the Mac, and neither had to be taught twice.

Rows use the triplet (§1.3), and the app already computes every field:

| List | Leading | Title | Subtitle | Trailing |
|---|---|---|---|---|
| Scenes | scene number (monospaced) | the heading | — | page number |
| Cast | character glyph | the name | — | cue count |

Clicking a row does on macOS exactly what tapping it does on iOS: it reveals the
element **and marks it**, because scrolling alone cannot say "here" when the
page has nowhere left to scroll. That behaviour is already built and tested on
iOS; the Mac inherits the logic, not a re-implementation.

Visible by default — this reverses the earlier plan's "hidden by default", and
the references are why: on a Mac the sidebar *is* the organisation panel, and a
window that opens without one looks like an iPad app. Distraction-free writing
is a mode (⌥⌘S, or full-screen Focus), not a default.

### 3.2 Centre — the page

A real page on a neutral canvas, centred, at the same metrics the PDF prints —
so what a writer sees is what production receives. Not edge-to-edge text: the
page edge is the ruler a screenwriter reads length by, and taking it away breaks
the one measurement the craft depends on.

Three view modes, in the toolbar's view group: **Page** (default), **Typewriter**
(current line held at a fixed height), **Focus** (sidebar collapses, canvas
widens). Margin-floating controls only (§2).

### 3.3 Where the properties live, without a pane

- **Title page** — File → Title Page…. The same `TitlePageSheet` the phone
  presents. Set once, not consulted while typing.
- **Scene** — number and page on the Navigator row, where you compare scenes.
  Numbering is Format → Scene Numbers. Length is the page itself.
- **Character** — the Cast tab. A name is not a place, so the row opens the
  character's thread (scenes and every speech); a speech reveals that line
  on the page. Rename lives on that thread, with the blast-radius warning
  both surfaces already share.
- **Comments and notes** (later) — the thing that would earn the right column
  back: something to read alongside the page, keyed to `ScriptElement.id`.

### 3.4 The toolbar, and the menu bar behind it

Toolbar, following §1.5 exactly: title left; on the right,
`[element control] [view: page · typewriter · focus] [share]` and
search furthest right. Nothing else. Everything a professional reaches for lives
in the menu bar, where Mac users look for it:

| Menu | Contents | Today |
|---|---|---|
| File | New, Open, Save, Revert, Title Page, Export (PDF · FDX · Fountain · Text), Print | all present |
| Edit | Undo/Redo, Find (⌘F), Find Scene (⌘L), Accept Suggestion | all present; Undo also takes back a Move to Trash in the launch window |
| Format | Element ⌘1–⌘9 (the same nine on iPad), Scene Numbers, Revision | elements and numbers present; Revision is M4 |
| View | Sidebar, Page/Typewriter/Focus, Zoom | Zoom present (⌘+ ⌘− ⌘0 actual size, ⌥⌘0 fit); sidebar and view modes still missing |
| Window, Help | Standard | standard |

The third column is not decoration. Read against the running app on
2026-09-06, the View menu held only what macOS puts there itself. It now also
holds Zoom In, Zoom Out, Actual Size and Zoom to Fit, for a reason worth
recording: a screenplay's measurements are absolute — 612 points is 8½ inches —
but a screen point is not. On a 13.6-inch laptop one measures 0.0067 inches, so
a page drawn at its own metrics comes out 4.1 inches wide, 48% of life size,
with 12-point Courier reading as under six. §3.2's claim that the page prints
what it shows is about metrics, and holds; the *scale* is a display question,
and the page now fits the window by default rather than pretending otherwise.

**One shortcut, one command** (amended 2026-09-25, IL-0108). This table used
to give ⌘9 to both Element and Zoom to Fit. The running app never showed it:
AppKit silently drops the second of two identical key equivalents when the
menu bar is installed, so Zoom to Fit had no key at all and ⌘9 was only ever
Lyrics. The element row keeps ⌘1–⌘9 — ⌘1–⌘7 are Final Draft's own, and a
writer's fingers are worth more than a symmetric View menu — and Zoom to Fit
moves to ⌥⌘0, beside Actual Size: a choice, not a platform convention. The
nine element keys are one table (`ScreenplayKind.shortcutKinds`), read by this
menu and by the iPad's hardware keyboard, so ⌘9 is Lyrics on both. The launch
window's Undo is Edit ▸ Undo's, as in Finder, not a ⌘Z of the banner's own.
`MenuKeyEquivalentTests` walks the bar as declared and fails on any key bound
to two commands.

The view modes are M3 and not yet built, which is expected; the sidebar command
is neither built nor scheduled, and §3.1 leans on it: *"Distraction-free writing is a mode (⌥⌘S, or full-screen
Focus), not a default"* is the argument for the sidebar being visible by
default, and half of it does not exist.

The capability does — `NavigationSplitView` puts its own toggle in the toolbar,
and that is what the app shows. What is missing is the menu command and the
keystroke, which is where a Mac user looks first.

Two things to settle before building it. The shortcut here was written ⌥⌘S;
macOS's own is **⌃⌘S**, and this project's rule is to follow the platform
rather than invent beside it. And a command that toggles the sidebar belongs
in the same View menu as the view modes, so it may be worth doing with M3
rather than twice.

### 3.5 What must not appear

No onboarding, no account, no upsell, no first-run tour, no badges, no
"AI assistant" surface, no floating palettes. The engine's intelligence shows up
as *the page behaving correctly*, never as chrome announcing itself.

---

## 4. Metrics and tokens

Shared with iOS wherever the platform allows, so the two apps are one product.

| Token | Value | Note |
|---|---|---|
| Sidebar width | 240 min · 260 default · 360 max | Finder-class |
| Row height | 28 (compact list) · 44 (two-line) | |
| Row inset | 8 leading, 10 trailing | selection capsule inset |
| Selection | accent fill, 6pt continuous corner | §1.4 |
| Title | 13pt semibold | §1.7 |
| Subtitle / metric | 11pt secondary / tertiary | |
| Section header | 11pt semibold, secondary | |
| Canvas | `NSColor.screenplayDesk` — Apple's `underPageBackgroundColor`, tinted by the system | see below |
| Page | `NSColor.screenplayPaper` — #FAF8F4, both looks by default; #3A3A3C when the writer picks Dark Page | 1pt shadow |
| Page ink | `NSColor.screenplayInk` — paired with the paper, not the appearance | caret and ghost too |
| Script face | Courier Prime 12pt, engine metrics | identical to iOS and to print |

Materials: sidebar `.sidebar`, toolbar unified (`.windowToolbarStyle(.unified)`
— a `DocumentGroup` otherwise gets the two-row expanded style, and the first
row is empty here because the title is removed from it).

Semantic colours only — accent colour is the user's, never ours — with **one
stated exception, the canvas**. It was `underPageBackgroundColor`, which is
AppKit's own behind-the-page grey and resolves to a neutral #282828 in dark.
In a real window it does not: a semantic colour is resolved against the
window, whose ground answers to the writer's desktop picture, and on a blue
desktop it came out #181925 — blue, and *darker* than the page at #1E1E1E. The
sheet sank into the desk. The page never moved with it, because a layer's
`cgColor` is a snapshot and is not re-resolved, so the two surfaces drifted
apart until they crossed.

The desk and the paper are therefore the fixed values in the app, stated in
`ScreenplayDesk.swift` and pinned by `ScreenplayDeskTests`. Note that the
relationship tests there pass with the old colour and only the exact-value
test fails — outside a window the semantic colour looks correct, which is why
this survived as long as it did.

**One rule orders them: the desk is darker than the paper, in both looks.**
That is how a sheet has always read, and it is what Pages shows — a white page
on grey. Dark mode had it inverted (desk #2A2A2B over paper #1E1E1E), which
cost two things. The page read as a hole rather than a sheet. And the desk met
the toolbar — whose own ground is `windowBackgroundColor`, #1E1E1E — at a
twelve-level step, drawing a line across the top of the window exactly where
the system was trying to draw a gradient. The desk is Apple's `underPageBackgroundColor`. It was a stated grey for a
while and the reason was real then: with the old near-black page the tinted
value resolved *darker* than the sheet and the page became a hole. The page is
paper now — two hundred levels above anything the tint can produce — so the
reason is gone, and a fixed grey only made this the one window on the desktop
that does not answer to the writer's Appearance settings. The window does not
override its `containerBackground` either, so the sidebar sits on the system's
ground the way Finder's does. Measured against Finder, same wallpaper:

| | eDraft | Finder |
| --- | --- | --- |
| window edge | #1F202C | #1F1E2C |
| sidebar | #1E1F27 | #1D1C26 |
| desk | #1B1C27 | #21202C |

That is also what closes the seam at the sidebar's top corner. It was never a
missing line: the corner is the system's inset sidebar shape and Finder has
the same one, but with the desk stated as a fixed grey there was no tonal
difference along the panel's top edge for the outline to show against, so the
curve appeared to stop in mid-air.

**One rule orders the two surfaces: the desk is darker than the paper, in
every combination** — both papers, both looks, checked by
`ScreenplayDeskTests`. It earns its place: putting the desk back on the system
colour left the *dark* page four levels above its own desk, and that test is
what said so.

**The page is paper by default, even in the dark** — `PagePaper`, View → Page.
Pages, Preview and Word all darken the chrome and leave the document alone,
and the reason it matters here is the header: the system fades the page into
the chrome at the top of the window, and a fade is only as visible as the
distance it travels. Measured down the page through the toolbar's edge:

| | chrome → page | what the fade has to work with |
| --- | --- | --- |
| Dark page (#3A3A3C) | desk → #3A3A3C | ~18 levels — present, barely visible |
| Paper (#FAF8F4) | desk → #FAF8F4 | ~200 levels — the gradient Pages draws |

The near-black page remains as a choice, because some writers want it. It is
a real fork rather than a theme tweak: the ink, the caret and the ghost are
all paired with the *paper* rather than the appearance, since `labelColor` is
white in a dark app and a light page in a dark app is exactly the case it
cannot know about.

---

## 5. Accessibility, from the first commit

VoiceOver labels on every row already exist on iOS (`SceneListRow`,
`CastListRow` carry them) and move with the shared code. Full keyboard access:
every pane reachable with ⌃F6, every row with arrows, every action with a menu
equivalent. Reduce-motion respected by the reveal mark (it becomes an instant
mark, not a fade). Dynamic text honoured in the chrome; the page itself is fixed
at screenplay metrics by definition, and zooms instead.

---

## 6. The continuity contract

The two apps must teach the same thing. This is the checklist any macOS feature
must pass before it ships:

1. **Same names.** "Navigator", "Scenes", "Cast", "Element", "Reveal" mean the
   same thing on both platforms.
2. **Same verbs.** A Navigator row reveals and marks. An element control converts.
   Tab cycles by the engine's choreography, not by a per-platform table.
3. **Same rules.** Anything that decides screenplay behaviour lives in
   `EDraftEngine` and is pinned by the conformance corpus — never re-decided in
   a view.
4. **Same document.** One `.draft` on iCloud Drive; no macOS-only fields.
5. **Different surfaces, honestly.** The Mac gets menus, windows and a
   pointer; iOS gets touch, scanning and a keyboard bar. Neither pretends
   to be the other. A right-hand pane returns when there is something to
   read alongside the page, not something to state about it.
