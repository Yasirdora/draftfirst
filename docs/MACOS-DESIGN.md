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
> middle, the details on the right when asked — and nothing else.**

Two panes is the reference grammar. We use **three**, because a screenplay has a
third question the references do not have to answer: *what are the properties of
the thing I am looking at?* Pages, Keynote, Xcode and Sketch all resolve it the
same way, and Mac users already know where to look — the inspector on the right,
hidden until summoned.

```
┌──────────────┬───────────────────────────────────┬──────────────┐
│  NAVIGATOR   │              PAGE                 │  INSPECTOR   │
│              │                                   │  (⌥⌘I,       │
│ ⌜Scenes│Cast⌝│      ┌───────────────────┐        │   hidden by  │
│              │      │                   │        │   default)   │
│ 1  INT. …  1 │      │   the page, on a  │        │              │
│ 2  EXT. …  3 │      │   neutral canvas  │        │  title page  │
│ 3  INT. …  4 │      │                   │        │  scene       │
│              │      │                   │        │  character   │
│ ──────────── │      └───────────────────┘        │  revision    │
│ 3 scenes ·   │                                   │              │
│ 2 locations  │                                   │              │
└──────────────┴───────────────────────────────────┴──────────────┘
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
(current line held at a fixed height), **Focus** (sidebar and inspector collapse,
canvas widens). Margin-floating controls only (§2).

### 3.3 Right — the Inspector

Contextual to the selection, and empty of anything the page can do better:

- **Title page** — the fields, edited in place instead of in a sheet.
- **Scene** — number, page, characters present, length; the place where scene
  numbering is applied and explained.
- **Character** — cue count, scenes, first/last appearance, rename with the same
  blast-radius warning the iOS character page shows.
- **Revision** (M4) — colour, marks, locked pages.

### 3.4 The toolbar, and the menu bar behind it

Toolbar, following §1.5 exactly: title left; on the right,
`[element control] [view: page · typewriter · focus] [share] [inspector]` and
search furthest right. Nothing else. Everything a professional reaches for lives
in the menu bar, where Mac users look for it:

| Menu | Contents |
|---|---|
| File | New, Open, Save, Revert, Export (PDF · FDX · Fountain · Text), Print |
| Edit | Undo/Redo, Find (⌘F), Find Scene (⌘L), Writing Assistance |
| Format | Element ⌘1–⌘9, Scene Numbers, Revision |
| View | Sidebar (⌥⌘S), Inspector (⌥⌘I), Page/Typewriter/Focus, Zoom |
| Window, Help | Standard |

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
| Inspector width | 260 fixed | Pages-class |
| Row height | 28 (compact list) · 44 (two-line) | |
| Row inset | 8 leading, 10 trailing | selection capsule inset |
| Selection | accent fill, 6pt continuous corner | §1.4 |
| Title | 13pt semibold | §1.7 |
| Subtitle / metric | 11pt secondary / tertiary | |
| Section header | 11pt semibold, secondary | |
| Canvas | `NSColor.underPageBackgroundColor` | system, adapts to dark |
| Page | `textBackgroundColor`, 1pt shadow | |
| Script face | Courier Prime 12pt, engine metrics | identical to iOS and to print |

Materials: sidebar `.sidebar`, inspector `.contentBackground`, toolbar unified.
Semantic colours only — accent colour is the user's, never ours.

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
5. **Different surfaces, honestly.** The Mac gets menus, an inspector, windows
   and a pointer; iOS gets touch, scanning and a keyboard bar. Neither pretends
   to be the other.
