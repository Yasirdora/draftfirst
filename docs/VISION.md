# Writing Desk — Visionary Plan

### *The world’s best Markdown editor*

> **North star**  
> “Markdown’s original promise was that a document should look like *writing*, not markup.  
> Every editor since has either made the markup harder, the beauty uglier, or the trust thinner.  
> We will make the page feel inevitable — private by default, beautiful by default, powerful only when asked.”

This document is the product and design charter for evolving **Writing Desk** from a privacy-first single-surface editor into the definitive Markdown writing instrument — built on our existing SvelteKit foundation.

---

## 1. Research foundation

### 1.1 What Markdown actually is

John Gruber’s Markdown (2004) had one overriding design goal: **easy-to-read, easy-to-write plain text** that remains publishable as-is, inspired by plain-text email. It is both a *syntax* and a *conversion tool*.

That clarity did not survive scale:

| Layer | Role | Reality today |
|-------|------|----------------|
| **Gruber Markdown** | Original, ambiguous prose | Still the cultural north star |
| **CommonMark** ([commonmark.org](https://commonmark.org/)) | Unambiguous baseline + test suite | Industry standard for parsers; 1.0 never “finalized” but de facto baseline |
| **GFM** (GitHub Flavored Markdown) | CommonMark + tables, task lists, strikethrough, autolinks, tag filter | What most developers actually write |
| **Dialect soup** | MultiMarkdown, Pandoc MD, Obsidian MD, MDX… | Same file, different meaning across tools |

**Implication for us:** pick a **clear dialect contract** (CommonMark + GFM core), show it in the UI, never silently rewrite user source, and make extensions *opt-in and labeled*.

### 1.2 Competitive landscape (strengths / weaknesses)

| Product | Strengths | Weaknesses / gaps |
|---------|-----------|-------------------|
| **Typora** | Seamless WYSIWYM; live typesetting feel; clean | Proprietary; Electron weight; closed core; limited collaboration story |
| **iA Writer** | Focus discipline; typography; syntax highlight-as-style; focus modes | Minimal feature set can feel sparse; tables/advanced structure weaker; multi-platform friction historically |
| **Obsidian** | Graph, plugins, local vaults, community | Cognitive overload; “second brain” not “writing instrument”; plugin quality variance; not Apple-quiet |
| **Bear** | Beautiful Apple-native notes; tags | Ecosystem lock-in; Markdown purity tradeoffs; subscription |
| **Ulysses** | Long-form workflow; library; publish targets | Subscription; not pure files-first; Apple-centric |
| **VS Code + MD** | Free, extensible, familiar to engineers | Split-pane preview lag; not writer UX; chrome-heavy |
| **StackEdit / HackMD** | Web collab; live preview | Network-first; privacy weak; UI dated |
| **MarkText** | Open Typora-like | Maintenance/polish variance |
| **Milkdown / ProseMirror kits** | Extensible engines for builders | Components, not a finished product; integration tax |
| **Notion / Craft** | Blocks, collab, polish | Not Markdown-native; export is a compromise |
| **Writing Desk (today)** | Zero network for content; dual surface; safe render; offline; free; localStorage | Single doc; no library; limited dialect; no collab; no plugins; no mobile-native |

### 1.3 Key pain points (all skill levels)

1. **Source vs page schizophrenia** — Writers bounce between “raw markdown” and “pretty preview”; caret, selection, and formatting state fight each other.  
2. **Flavor roulette** — “Works in GitHub, breaks in X” destroys trust.  
3. **Preview is a lie** — Side-by-side preview scrolls out of sync; WYSIWYG corrupts source (`****`, empty tags, HTML soup).  
4. **Tables & tasks are second-class** — The syntax people need most often is the worst to edit by hand.  
5. **Focus is theater** — Many “focus modes” only dim chrome, not the *thinking* surface.  
6. **Privacy is marketing** — Cloud-default notes apps leak by design; open tools often ship trackers.  
7. **Power vs calm** — Obsidian-scale power *or* iA-scale calm — almost never both with progressive disclosure.  
8. **Mobile is abandoned** — Floating toolbars and keyboards are afterthoughts.  
9. **Collaboration bolts on late** — Real-time CRDTs without a pure local mode become surveillance.  
10. **Accessibility gaps** — Contenteditable + custom toolbars often fail keyboard and screen-reader paths.

### 1.4 Market white space (our opportunity)

No product simultaneously owns:

- **Apple-level calm and typography**  
- **True Markdown fidelity** (round-trip integrity)  
- **Local-first privacy** with optional collab later  
- **Progressive power** (beginner → power user without mode shock)  
- **Open, portable files** (your vault is just folders)  
- **Web + native quality** without Electron bloat (SvelteKit static + future native shells)

**Writing Desk owns privacy + dual-surface already.** We expand without betraying that soul.

---

## 2. Product thesis

### Name & promise

**Writing Desk** — *Markdown that stays human. Nothing leaves unless you send it.*

### Design principles (Apple-inspired, Jobs-grade)

1. **One primary surface** — The page is the product. Source is always one gesture away, never a second app.  
2. **Progressive disclosure** — Novices see typography and a few tools; experts reveal syntax, outline, dialect, plugins.  
3. **Honesty of source** — What you save is Markdown you can open in any editor. No proprietary prison.  
4. **Privacy is a feature you can feel** — Offline-first, explicit export, no silent network.  
5. **Restraint is taste** — Every control must earn its pixels. Prefer gestures and contextual tools.  
6. **Speed is respect** — Typing latency is a moral issue. 60fps chrome; parse off the critical path when needed.  
7. **Accessibility is not a checkbox** — Full keyboard map, live regions, contrast, reduced motion, semantic structure.  
8. **Delight in the details** — Selection restoration, scroll coupling, soft save status, print that looks published.

### Who we serve

| Persona | Need | Our answer |
|---------|------|------------|
| **Writer** | Flow, beauty, focus | Page-first, Focus+, typewriter scroll |
| **Student / knowledge worker** | Notes + structure | Outline, library, tags (later) |
| **Developer** | GFM fidelity, code | Dialect badge, fenced code UX, export |
| **Privacy-conscious** | Local-only | Default offline; collab opt-in |
| **Team lead** (later) | Shared drafts | CRDT rooms, not account-first SaaS |

---

## 3. Innovative features (beyond the market)

### 3.1 Core differentiators

| Feature | What it is | Why it’s better |
|---------|------------|-----------------|
| **Unified caret** | One conceptual caret across page + source; commands never miss | Fixes #1 industry failure |
| **Dialect contract** | Visible: `CommonMark + GFM` · optional packs | Ends flavor roulette |
| **Truth mode** | Diff source before/after page edit; warn on lossy transforms | Trust |
| **Contextual rail** | Floating tools only when selection/block needs them | Calm UI, power when needed |
| **Structure palette** | Insert table/task/code via spatial UI that *writes clean MD* | Tables stop being pain |
| **Focus+** | Dim non-active *thought units* (block + optional sentence) | Real focus, not chrome opacity |
| **Instant paper** | Print/PDF and HTML export match on-screen sheet | Publish without reformatting |
| **Local library** | File System Access / folder vault (optional) | Obsidian power, Apple calm |
| **Whisper collab** | Optional, E2E, offline-first CRDT (phase later) | Collab without selling your soul |
| **Extensions as skills** | Sandboxed plugins; default zero network | Power without malware aesthetics |

### 3.2 Syntax & intelligence (without gimmicks)

- **Smart paste** — HTML/plain/Markdown → clean MD (never silent HTML inject).  
- **Slash menu** — `/table` `/task` `/code` with keyboard-first design.  
- **Syntax teach-in** — First-run tips that fade; never permanent training wheels.  
- **Outline that writes back** — Drag headings to restructure source.  
- **Find & replace with structure awareness** — Scope to code fences / headings.

### 3.3 Explicit non-goals (for now)

- Becoming Notion (blocks as product).  
- Forced accounts.  
- AI rewriting your voice by default (optional assistant later, local-preferring).  
- Crypto, social feed, or marketplace noise.

---

## 4. UX / UI system

### 4.1 Visual language

- **Two token worlds** (already in Writing Desk):  
  - *Chrome* — system-aware light/dark UI.  
  - *Paper* — always legible document surface (print-safe).  
- **Typography** — UI: SF-like system stack; Document: Charter/Georgia class serif with careful measure (~66ch).  
- **Motion** — Prefer opacity/transform; honor `prefers-reduced-motion`.  
- **Density** — Desktop: airy; phone: thumb targets ≥44px; toolbar rides above keyboard.

### 4.2 Interaction model

```
[ App bar: identity · status · view · outline · file · export ]
[ Paper / Source / Split workspace ]
[ Contextual format rail ]
[ Status: counts · dialect · cursor · offline ]
```

- **Views:** Page | Split | Source (collapse split on narrow).  
- **Menus:** Portaled, Escape-dismiss, return focus to trigger.  
- **Commands:** Single command bus (toolbar = keyboard = slash).

### 4.3 Accessibility bar

- WCAG 2.2 AA contrast for chrome and paper links.  
- Full shortcut cheatsheet (discoverable).  
- `role="toolbar"`, pressed states, live “Saved”.  
- Screen reader: announce view changes and save errors.

### 4.4 Performance bar

- Typing path: no full reparse on every key when possible (incremental later).  
- Bundle: static deploy, code-split dialect packs.  
- Large docs: virtualize outline; defer non-visible preview work.  
- Lighthouse: near-perfect a11y/perf on shell.

### 4.5 Cross-platform

| Surface | Strategy |
|---------|----------|
| **Web** | SvelteKit + adapter-static (now) |
| **PWA** | Service worker (now) + installability |
| **Desktop** | Tauri or native wrapper later (not Electron-first) |
| **iOS/iPadOS** | Safari-quality first; native shell later |
| **Files** | Download/open now → File System Access → folder vault |

---

## 5. Technical architecture (evolution of current codebase)

```
src/
  lib/markdown/     # Pure cores (keep sacred): render · serialise · format
  lib/dialect/      # CommonMark+GFM packs, optional extensions
  lib/editor/       # Command bus, selection, surface controller
  lib/library/      # Multi-doc / vault (future)
  lib/collab/       # Optional Yjs/CRDT (future)
  lib/plugins/      # Sandbox API (future)
  lib/components/   # WritingDesk → split into primitives over milestones
```

**Invariants we will never break:**

1. Only renderer output enters `innerHTML` / `{@html}`.  
2. `escapeHtml` + `safeUrl` on all user content.  
3. Document bytes do not leave the device without explicit export/share.  
4. Round-trip: page edit → serialise → source remains valid MD.

---

## 6. Roadmap — milestones

We build **section-by-section**, each milestone shippable, each with prototype → polish → tests.

### Milestone 0 — Foundation (✓ done)

- SvelteKit app, dual surface, cores, export, offline SW, tests, privacy model.  
- **Commit:** initial SvelteKit port of Writing Desk.

### Milestone 1 — Product shell & identity (✓ done)

**Focus:** Apple-grade first impression without feature bloat.  
**Details:** see [`MILESTONE-1.md`](./MILESTONE-1.md).

- Dismissible first-run welcome strip (Page vs Source, privacy).  
- Dialect badge in status bar (`CommonMark + GFM`).  
- Keyboard shortcuts overlay (`?` · app bar · status help).  
- Installable PWA manifest + icons.  
- Component extraction: BrandMark, StatusBar, WelcomeStrip, ShortcutsOverlay, DialectBadge.  

**Exit criteria:** New user understands Page vs Source in &lt;10 seconds; dialect honesty; discoverable shortcuts.

### Milestone 2 — Structure intelligence (✓ done)

**Focus:** Make hard Markdown easy without hiding it.  
**Details:** see [`MILESTONE-2.md`](./MILESTONE-2.md).

- Slash command palette (`/`) on Markdown + empty page blocks.  
- Table / task / structure inserts via clean Markdown snippets.  
- Outline section reorder (↑↓ prototype).  
- Find in document (`⌘F`).  

**Exit criteria:** Create a multi-column table without typing pipes; source remains pretty.

### Milestone 3 — Library (local multi-document) (✓ done)

**Focus:** From “one desk” to “your papers.”  
**Details:** see [`MILESTONE-3.md`](./MILESTONE-3.md).

- Sidebar library in localStorage (`library:v2`) with legacy migration.  
- Search titles/body; rename; soft-delete with undo.  
- Import/drop creates a new document; ☰ toggle; narrow starts closed.  
- Folder vault / File System Access deferred to a later platform pass.  

**Exit criteria:** 50 notes feel as calm as one; still zero network for content.

### Milestone 4 — Fidelity & power tools *(next)*

**Focus:** Trust and expert depth.

- Truth mode (lossy edit warnings).  
- Footnotes / definition lists as **optional dialect pack**.  
- Math (KaTeX) and Mermaid as opt-in packs (sandboxed).  
- Import/export packs; clipboard smart paste.  
- Incremental parse for 100k+ word docs.  

**Exit criteria:** Round-trip tests for all enabled packs; no silent HTML.

### Milestone 5 — Collaboration (optional)

**Focus:** Together without surveillance.

- Local-first CRDT sync; invite link rooms.  
- Presence cursors; offline queue.  
- End-to-end encryption for shared rooms.  
- Always runnable fully offline solo.  

**Exit criteria:** Collab is off by default; solo path unchanged.

### Milestone 6 — Platform & polish

**Focus:** Everywhere, still one product.

- Tauri desktop shell; deeper iOS PWA/native.  
- System share sheets; print templates.  
- Plugin API v1 (syntax + command + panel).  
- Design system documentation; contribution guide.  

**Exit criteria:** Desktop app feels native-adjacent; plugin cannot phone home without permission.

---

## 7. Prototype delivery method (how we work step-by-step)

For **each milestone**:

1. **Brief** — Problem, user stories, non-goals (1 page).  
2. **UX sketch** — Layout, states, empty/error/loading.  
3. **Prototype** — Minimal code on main path in SvelteKit.  
4. **Hardening** — a11y, perf, tests, security review.  
5. **Ship note** — What users gained; what we refused to add.

We will not ship a kitchen-sink Obsidian clone. We will ship **layers of inevitability**.

---

## 8. Success metrics

| Metric | Target |
|--------|--------|
| Time-to-first-sentence (new user) | &lt; 5 s |
| Input latency (p95) | &lt; 16 ms event handling |
| Round-trip fidelity tests | 100% of core dialect |
| Privacy default | 0 content network calls |
| SUS / qualitative “calm” | “I forgot I was using an editor” |
| Export open rate | HTML/PDF open cleanly offline |

---

## 9. Immediate next step

**Milestone 1 — Product shell & identity** is the first build section after this plan:

1. Shortcut overlay + dialect badge.  
2. PWA manifest.  
3. Component extraction of chrome.  
4. Empty-state / sample refinement.  

Say the word and we prototype Milestone 1 section-by-section.

---

## 10. Closing (the Jobs filter)

Every feature must survive three questions:

1. **Does it make writing more human?**  
2. **Does it keep the file honest?**  
3. **Would we be proud to demo it with the Wi‑Fi off?**

If any answer is no, it does not ship.

---

*Document status: living charter · aligns with Writing Desk SvelteKit codebase · research informed by Gruber Markdown, CommonMark, GFM, and the 2024–2026 editor landscape (Typora, iA Writer, Obsidian, Bear, Ulysses, VS Code, Milkdown/ProseMirror, collab web editors).*
