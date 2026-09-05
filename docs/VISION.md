# eDraft

> The writer never formats. The form is the app's job; the story is the writer's.

That sentence is already true of the code. This page names it so a change can
be caught for breaking it.

The writer *does* say what a line is — Tab, Return on an empty line, ⌘1–9.
That is taxonomy, not typesetting. What they never do is set an indent, shout
a cue, or space a scene-heading dash. If a change asks them to, it is wrong.

---

## The evidence

Seven behaviours. One idea. All shipped.

| The writer… | The app… | Where a break shows up |
|---|---|---|
| types `int. kitchen` on an action line | the line becomes a heading, shouted | `ScenePromotion`; `testTypingASlugTurnsAnActionLineIntoASceneHeading` |
| presses Return on an empty line | the kind changes, a paragraph is not inserted | `Choreography.emptyLineEscape`; `testReturnOnAnEmptyCueEscapesToAction` |
| presses Tab | the next kind is a function of the line above | `Choreography.tabSetFor(previous:)`; `testTabCyclesTheElementTheCaretIsInNotTheOneLastJumpedTo` |
| converts a cue to action and back | it says "Mara", not "MARA" | `ElementCaseMemory`; `testConvertingBackRestoresOriginalCasing` |
| types `-` in a heading | the page writes `" - "`; one delete takes it back | `SceneHeadingSeparator`; `testADashInAHeadingWritesTheSpacedSeparator` |
| pauses on a cue they have used | the rest of the name is offered, and is not in the file until accepted | `PredictionEngine`; `testTheDocumentDoesNotContainTheGhost` |
| types a cue in lowercase | the page shouts it, the keyboard does not | `ScreenplayKind.uppercasesInput`; `testACueOnThePageMatchesTheCueInTheDocument` |

A scene heading is deliberately not in the Return ring. Fountain already
defines a line beginning INT./EXT./EST./I/E. as a slug, and
`ScenePromotion` promotes it as it is typed — so Return stays a two-stop
ring between the two kinds a writer cannot type their way into. That
trade is written in `Choreography.swift`, not here.

A screenplay rule that lands in a view will be a second editor. The two
apps will disagree. `Choreography.emptyLineEscape` is the template: the
rule moved out of `ScriptTextView` into the engine, and the TypeScript
engine got the same change in the same commit.

---

## What we are not

**Not a production office.** `RevisionDiff` and `SceneNumbering` already
exist in `EDraftEngine`. Coloured pages, locked numbers, OMITTED — that
work has a plan (`REVISIONS-PLAN.md`) and a milestone (M4), and M4 is
forbidden before M3 ships. This product competes on the page a writer
is in, not on the packet a crew is issued. Shipping the writing surface
as if it were a demo until the colours arrive would be the other way
round.

**Not a Markdown editor.** A charter for that product sat at this path
and has been deleted. Fountain is the file; the engine's job is a
screenplay, not a dialect of markup.

**Not a service.** The engine has no network, no telemetry, no
file-system access (`packages/edraft/README.md`). A file leaves the
device when the writer exports it.

---

## The desk — a proposal, not a decision

*What does the Mac app do that the phone cannot — because it is a desk?*

Today: nothing. Every M2 box is the phone's behaviour on a larger
surface. That was the right call. Two apps that disagree about Return
are two products; the port is how they stay one.

A desk is not a bigger phone. It is simultaneous surfaces — a page you
are in *and* a list you can see, later an inspector, later a second
window. A hand sequences those (a sheet, a modal). A desk shows them.
`MACOS-DESIGN.md` already drew that window. Two of the three panes are
built; Find, export and print closed M2; the inspector is M3. None of
that is a new screenplay rule. It is the same script, visible at once.

What would have to be true before "the desk" is a behaviour rather than
a layout: something a writer cannot do in one hand, not merely something
prettier at arm's length. Two documents side by side is a candidate.
An inspector that stays while they type is a candidate. Inventing either
before Find and the third pane exist would be decorating a port.

Until then the Mac's job is the same as the phone's: the writer never
formats.
