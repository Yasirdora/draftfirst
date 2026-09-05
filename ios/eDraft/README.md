# eDraft for iOS

eDraft is a native iOS 26 screenplay editor built with SwiftUI, UIKit text editing, Liquid Glass controls, and the native `EDraftEngine` Swift package — no JavaScript runtime, no bridge.

## Run

1. Open `ios/eDraft.xcodeproj` in Xcode 26.6 or newer.
2. Select the **eDraft** scheme and an iOS 26 simulator or device.
3. Build and run.

The project uses the system document browser and opens `.draft`, `.fountain`, and plain-text screenplay files in place.

## Engine

All screenplay intelligence is native Swift in `ios/eDraftEngine` (linked as a local package): element choreography, text normalization, Fountain parsing and serialization, deterministic pagination, and the prediction engine. Behaviour is pinned to the TypeScript reference engine by a conformance corpus — regenerate the fixtures from the repository root after changing the TypeScript engine, then run the package tests:

```sh
npm run engine:conformance
cd ios/eDraftEngine && swift test
```

## Mobile element choreography

- **Return** moves to the most likely next screenplay element.
- **Tap the element pill** to choose from contextual elements first or any supported element.
- **Swipe left / right** in the editor cycles the element forward / backward, mirroring Tab / Shift-Tab.
- **Hardware Tab / Shift-Tab** keep the desktop screenplay workflow on iPad keyboards.

## Prediction

Inline suggestions come from the native prediction engine for character, location, continuation, and format completions. The completion is laid out by TextKit on the editor's real glyph line, including screenplay indentation, Dynamic Type, wrapping, and scroll position.

- **Space** accepts an actionable inline completion and adds one trailing space.
- **Keep typing** rejects the completion without interrupting native input.
- Apple autocorrection, spell checking, dictation, selection, and Writing Tools remain native.
- The overlapping system inline predictor is disabled because eDraft supplies screenplay-aware completions.

Editor preview builds must use a separate bundle identifier so they never replace the regular app or its document-browser launch state:

```sh
PRODUCT_BUNDLE_IDENTIFIER=xyz.edraft.ios.qa \
SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG EDITOR_PREVIEW'
```
