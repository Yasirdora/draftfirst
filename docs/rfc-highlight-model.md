# RFC: Highlighter Model & Execution Plan

## 1. Executive Summary & Decisions
This document defines the architecture for the **Text Highlight** feature in eDraft.
Based on our strategic alignment, we are prioritizing a **single-color (Yellow) attention mark** over a full semantic palette, deferring multi-color functionality entirely to the future Script Notes feature.

**Decisions:**
- **Color:** Single color only (Yellow).
- **Behavior:** Toggle-off on re-click.
- **Model:** Stored as a color value on the text run (extensible in the future, but locked to "yellow" in v1).
- **Print:** Prints on PDF exports.
- **Plain Text:** Dropped silently on Fountain export (as Fountain has no highlight syntax).
- **FDX:** Round-tripped losslessly via the eDraft XML extension namespace.

## 2. Model Shape

The eDraft engine represents text runs as `[(range, traits)]`. We will expand the `traits` definition (which currently anticipates `bold`, `italic`, `underline`) to include a `highlight` property.

```typescript
// Proposed addition to the core model types
export interface StyleTraits {
    bold?: boolean;
    italic?: boolean;
    underline?: boolean;
    strikethrough?: boolean;
    highlight?: 'yellow'; // Explicitly typed as a string literal, not a boolean, to future-proof for palettes.
}
```

## 3. Format Mapping & Boundaries

### 3.1 Fountain (The Baseline)
Fountain has no native syntax for text highlighting (unlike bold `**` or italic `*`).
- **Export:** Highlight runs are stripped. The plain text remains. This is documented, graceful degradation.
- **Import:** N/A.

### 3.2 FDX (The Round-Trip)
Final Draft natively supports colored text, but not background highlights in the way a modern editor does (it relies on ScriptNotes for color-coded attention).
To ensure we don't lose the writer's highlights, we will use our established `EDraft:` XML namespace.

- **Export:** 
  ```xml
  <Text EDraft:Highlight="Yellow">This is highlighted text</Text>
  ```
- **Import:** The FDX parser (`packages/edraft/src/fdx.ts`) will read the `EDraft:Highlight` attribute on text runs and map it back to `highlight: 'yellow'` in the engine.

> [!WARNING]
> **Identified Risk / Potential Bug:** Final Draft is known to preserve unknown XML *paragraphs* (which is why our preserving round-trip works), but it is aggressively destructive toward unknown *attributes* on inline `<Text>` nodes. If a writer exports a highlighted script to FDX, opens it in Final Draft, and hits save, Final Draft might silently delete our `EDraft:Highlight` attribute.
> 
> **Mitigation Plan:** We must write a strict unit test verifying if FDX strips inline namespaced attributes. If it does, we will need to pivot to storing highlight ranges in the `.draft` sidecar zip (the metadata JSON) instead of injecting them into the FDX `<Text>` tags.

### 3.3 PDF & Print
The paginator and PDF renderer (`pdf.ts` and `ScreenplayPageRenderer`) will read the `highlight` trait and draw a yellow background bounding box behind the glyphs before drawing the text.

## 4. Edit-Survival Rules (Atomicity & Behavior)

Typing inside or at the edges of a highlighted run requires strict rules enforced by the engine (not the view), matching Apple Pages exactly:

1. **Typing at the trailing edge:** If the caret is at the exact end of a highlighted word, new characters **inherit** the highlight.
2. **Typing at the leading edge:** If the caret is at the exact beginning of a highlighted word, new characters **do not inherit** the highlight.
3. **Backspacing:** Backspacing a highlighted character deletes the character. If the run becomes empty, the highlight trait is destroyed (no invisible highlighted zero-width spaces).
4. **Selection Toggle:** Selecting text and clicking the highlight button applies `highlight: 'yellow'`. If the exact same range is selected and clicked again, the trait is removed (toggle-off). If a partial range is selected, the run is split.

## 5. UI Integration

- **Format Bar:** A new "Highlighter" swatch button will be added to the Center slot of the `SelectionFormatBar`.
- **Active State:** The button reflects the state of the text at the current caret position.

## 6. Test Plan

Before integrating into the UI, the engine must pass the following strict conformance tests:

1. **Run Splitting:** Apply highlight to characters 5-10. Insert regular text at index 7. Verify the run splits into two highlighted blocks around the unhighlighted insertion.
2. **Format Degradation:** Convert a model with highlights to Fountain and back. Assert the text survives but the highlight trait is completely removed.
3. **FDX Injection:** Serialize to FDX and parse back. Assert the highlight trait survives.
4. **Edge Inheritance:** Simulate a typing event at the trailing edge of a highlighted run. Assert the run length expands by 1.

---
**Status:** Ready for execution. Pending approval of the FDX inline-attribute risk mitigation.
