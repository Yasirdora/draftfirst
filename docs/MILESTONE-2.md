# Milestone 2 — Structure intelligence

**Status:** implemented  
**Goal:** Make hard Markdown easy without hiding the source.

## Delivered

| Feature | Implementation |
|---------|----------------|
| **Slash palette** | `/` at line start in Markdown; `/` on empty page paragraph · `SlashPalette.svelte` + `slash-commands.ts` |
| **Structure inserts** | Headings, lists, tasks, quote, code, tables (2×2 & 3-col), divider, image, link — all via one command bus |
| **Find** | `⌘F` / **Find** button · `FindBar.svelte` + `find.ts` · jump + select in source |
| **Outline reorder** | ↑↓ on each outline item · pure `outline-reorder.ts` moves whole ATX sections |
| **Tables** | Improved starter snippets; existing page table Tab / insert column tools remain |

## Exit criteria

- [x] Create a table without typing pipes (slash → Table)
- [x] Source remains clean Markdown after inserts
- [x] Find navigates matches without network
- [x] Outline can reorder sections (prototype controls)
- [x] Unit tests for slash, find, outline reorder

## How to try

1. Markdown view → type `/table` → Enter  
2. Page view → empty paragraph → `/` → Task list  
3. **Find** or `⌘F` → search a word → Enter / ↑↓  
4. **Outline** → use ↑↓ to reorder sections  

## Next

**Milestone 3 — Local library:** multi-document sidebar, search titles, optional folder vault.
