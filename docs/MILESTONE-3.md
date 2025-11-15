# Milestone 3 — Local library

**Status:** implemented  
**Goal:** From one desk to your papers — still zero network for content.

## Delivered

| Feature | Implementation |
|---------|----------------|
| **Multi-document store** | `library/library.ts` · `writing-desk:library:v2` in localStorage |
| **Legacy migration** | Automatic from `writing-desk:v1` single-doc state |
| **Sidebar** | `LibrarySidebar.svelte` — list, search, new, rename, delete |
| **Search** | Title + body, client-side, recent-first |
| **Soft delete + undo** | ~60s trash bin with Undo strip |
| **Auto titles** | From first heading / line unless renamed (locked) |
| **Import** | Open / drop `.md` creates a **new** library document |
| **Layout** | ☰ toggle · narrow screens start with library closed |

## Privacy

- All documents stay in `localStorage` on this device  
- Footer reminder: “Stored only in this browser”  
- No accounts, no sync, no analytics  

## How to try

1. **☰** or open Library → **New document**  
2. Type a `# Heading` — title updates automatically  
3. **✎** rename (locks title) · **⌫** delete · **Undo**  
4. Search across titles and body  
5. Drop a `.md` file — imports as a new note  

## Exit criteria

- [x] 50 notes remain calm (sidebar + search)  
- [x] Still zero network for content  
- [x] Switch notes without losing unsaved typing (flush before switch)  
- [x] Unit tests for library pure logic  

## Next

**Milestone 4 — Fidelity & power:** Truth mode, optional dialect packs, large-doc performance.
