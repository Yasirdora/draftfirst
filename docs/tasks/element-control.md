# The element control, in the Mac toolbar

> **Superseded in part, 2026-09-06.** The toolbar quoted below still carries
> `[inspector]`. The inspector was retired the same day it was built; see
> MACOS-DESIGN §3.3 and §3.4 for what the toolbar and the menus actually hold.
> The rest of this brief stands as written.

Repo `/Users/x/Documents/edraft`, branch `rename/edraft`, HEAD `b8e70ac`.
Working directory for every command: that path.

Read `docs/HANDOFF.md`, then `docs/VISION.md`, then `docs/MACOS-DESIGN.md` §1
and §3, then this. In that order.

---

## The task

`MACOS-DESIGN.md` §3.4 specifies the window's toolbar:

> title left; on the right, `[element control] [view: page · typewriter ·
> focus] [share] [inspector]` and search furthest right. Nothing else.

Build **the element control**, and only that. `ScriptWindow` has no toolbar at
all yet, so you are adding one; the other three items are later boxes and must
not appear.

The control names the kind of line the caret is in, and lets a writer change it.
The phone has had one for a long time — `apple/eDraft/Views/ElementModeControl.swift`
— and **the Mac's must offer a writer the same thing the phone offers.** Read
that file properly before you design anything. What it does is not obvious from
its size, and copying its *shape* is not the same as offering the same thing.

Everything the control needs already exists in `EDraftCore`. If you find
yourself computing a screenplay fact inside a view, you have missed something
that is already written down — stop and go and find it.

---

## The standard this project holds

Stated once, plainly, because it is how the work is judged and not a style
preference:

**Read the tree, not the brief.** This document was written by someone who read
the code today and has still been wrong in every brief they have written. Where
the code disagrees with this page, the code wins, and saying so is part of the
job.

**A green suite is not a finished box.** This project has shipped a page card
with no script on it, and 56 tests passed. Launch the app and look at the thing
you built.

**Do not test your own bookkeeping.** Asserting that a flag you set is set
proves nothing. A test must fail before your change and pass after it, and you
must have watched it do both.

**Use the platform's components.** Before you write a view, find out whether
AppKit or SwiftUI already ships it. A hand-rolled lookalike loses keyboard
navigation, accessibility and hover, and looks identical in a screenshot — which
is exactly how it gets shipped.

**One channel per behaviour.** Changing an element's kind already has a path
through the model, used by ⌘1–9 and by Tab. A second path is a second editor,
and the two will disagree eventually.

---

## Verification

Baseline — if every package dies with `missing required module 'SwiftShims'`,
`rm -rf apple/*/.build`; that is a stale path, not a broken floor.

```
npm test                                              # 414
swift test --package-path apple/eDraftEngine            #  95
swift test --package-path apple/EDraftCore              #  84
swift test --package-path apple/EDraftUI                #  18
swift test --package-path apple/EDraftMacSurface        #  68
npm run check:boundaries
xcodebuild test -project apple/eDraft.xcodeproj -scheme eDraft \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'   # 96
xcodebuild build -project apple/eDraft.xcodeproj -scheme 'eDraft (macOS)' \
  -configuration Debug CODE_SIGN_IDENTITY="-" CODE_SIGN_STYLE=Manual \
  DEVELOPMENT_TEAM=""
```

Driving the running app: `open` the built `.app`. If you use AppleScript,
assert the frontmost process is `eDraft (macOS)` before every batch — System
Events types wherever focus is, and a previous session typed into someone's
terminal that way. The keyboard here is ABC-QWERTZ and `keystroke` swaps Y and
Z; do not type `DAY`. `screencapture -x -o -l<windowID>` captures one window,
with the id from `CGWindowListCopyWindowInfo`.

If you cannot see the window at all, the correct report is **"I cannot confirm
this renders"** — not "I could not check the colours."

---

## Out of scope

- The other three toolbar items, and search. Later boxes.
- The inspector (M3), anything in M4, the `.draft` format work.
- The three recorded issues in `MACOS-EXECUTION.md` §6.
- Any change to iOS. If you believe you need one, stop and say why first.

---

## Your report

Answer these six. They are the evaluation, and a thin answer to any of them is
a thin box.

1. **What did you build it from?** Name the SwiftUI or AppKit component you
   used, and the alternatives you rejected, with the reason — from the SDK, not
   from memory.
2. **What did the phone's control turn out to do** that a first guess would
   have missed, and where does that behaviour actually live?
3. **Which existing channel did you route the change through**, and what
   specifically would have broken had you added a second one?
4. **Show a test that failed before your change.** Paste the failure. If you did
   not see one fail, say so.
5. **What did you verify by looking**, and what could you not verify? Be exact
   about where a human should look.
6. **What in this brief was wrong**, or contradicted by the tree? If nothing
   was, say that — but the last four briefs each contained at least one error,
   so look properly before you answer.

Prose commit messages in the voice of `git log`; say what changed and why it
mattered. Trailer `Co-Authored-By: Claude Opus 5 <noreply@anthropic.com>`.

Commit at each green point. If the box cannot be closed honestly, do not close
it — an accurate account of why is worth more here than a ticked line.
