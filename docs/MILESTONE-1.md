# Milestone 1 — Product shell & identity

**Status:** implemented  
**Goal:** Apple-grade first impression without feature bloat.

## Delivered

| Item | Implementation |
|------|----------------|
| Dialect badge | `DialectBadge.svelte` + `editor/dialect.ts` — visible **CommonMark + GFM** contract |
| Keyboard shortcuts | `ShortcutsOverlay.svelte` + `editor/shortcuts.ts` — open with **?** or app bar / status **?** |
| First-run calm | `WelcomeStrip.svelte` + `utils/onboarding.ts` — dismissible, never blocks writing |
| Status chrome | `StatusBar.svelte` — counts, cursor, dialect, help |
| Brand mark | `BrandMark.svelte` |
| PWA installability | `static/manifest.webmanifest`, maskable + Apple touch icons, layout meta |

## Exit criteria (from VISION)

- [x] New user understands Page vs Source in &lt;10s (welcome strip + brand tag)
- [x] Dialect honesty in the chrome (status badge)
- [x] Discoverable power (`?` shortcuts)
- [x] Installable shell (manifest + icons)
- [x] Privacy line reinforced in welcome + shortcuts footer

## Next

**Milestone 2 — Structure intelligence:** slash palette, first-class tables, outline reorder prototype, find.
