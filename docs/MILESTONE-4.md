# Milestone 4 — Fidelity & power tools

**Status:** in progress (section 1 shipped)  
**Goal:** Trust and expert depth without cluttering the novice path.

## Section 1 — Versions / Truth foundation ✅

| Feature | Implementation |
|---------|----------------|
| **Fidelity core** | `markdown/fidelity.ts` — pure diff, cosmetic normalise, lossy heuristics |
| **Round-trip inventory** | `fidelity.test.ts` + linkedom render→serialise fixtures (incl. SAMPLE) |
| **Versions prefs** | Off by default; **enabled + per-doc baselines** survive reload |
| **Review sheet** | Apple-style bottom sheet — prose list, not git diffs |
| **Banner** | Quiet “N changes · Review” when the sheet is closed |
| **Restore** | Per row (one region) · **Restore everything** (full baseline) |
| **Keep current version** | Accept current source as new trusted baseline |
| **Show on page** | Jumps to the change on the typeset page |
| **Status** | **Versions** / **Review · N** pill |

### How to try

1. Status bar → **Versions** (on).  
2. Edit on the **Page**.  
3. **Review Changes** sheet — scannable prose (“X became Y”).  
4. **Restore** one row · expand for Previous / Now · **Show on page**.  
5. **Restore everything** / **Keep current version**.  
6. **Done** → quiet banner until you Review again.  

### Exit criteria (section 1)

- [x] Golden fidelity tests for identical / normalised / changed / lossy  
- [x] Round-trip inventory never classifies no-edit SAMPLE as lossy  
- [x] Versions off by default (progressive disclosure)  
- [x] Selective restore without resetting the whole baseline  
- [x] Review UI is list-first (not one-by-one carousel, not raw git hunks)  

## Remaining (M4)

| Section | Focus |
|---------|--------|
| **2** | Dialect pack registry (on/off, badge, lazy load) |
| **3** | Smart paste (HTML/plain → clean MD) |
| **4** | Footnotes pack (first non-GFM pack) |
| **5** | Math (KaTeX) opt-in pack |
| **6** | Mermaid opt-in pack |
| **7** | Large-doc performance |
| **8** | Hardening + ship note |

## Privacy

- Fidelity comparison runs entirely on-device.  
- No network for Versions / Truth.  
- Preference + baselines stored only in this browser.
