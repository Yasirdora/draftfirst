<script lang="ts">
	import { onMount } from 'svelte';
	import SiteLayout from '$lib/site/SiteLayout.svelte';
	import PageHero from '$lib/site/PageHero.svelte';
	import Split from '$lib/site/Split.svelte';
	import Sheet from '$lib/site/Sheet.svelte';
	import CtaBand from '$lib/site/CtaBand.svelte';
	import Pager from '$lib/site/Pager.svelte';
	import { setupReveal } from '$lib/site/reveal';

	const navLinks = [
		{ href: '/features', label: 'Overview' },
		{ href: '/features/writing', label: 'Writing' },
		{ href: '/features/story', label: 'Story' },
		{ href: '/features/formats', label: 'Formats' },
		{ href: '/help', label: 'Help' }
	];

	const flowLines = [
		{ kind: 'scene', text: 'INT. THE REX CINEMA, PROJECTION BOOTH - NIGHT' },
		{ kind: 'action', text: "Dust hangs in the beam of a 35mm projector. ELIAS VANCE, 60s, threads the final reel with surgeon's hands. The auditorium below is empty." },
		{ kind: 'character', text: 'ELIAS' },
		{ kind: 'paren', text: '(quietly, to the machine)' },
		{ kind: 'dialogue', text: 'One more time. Like we promised.' },
		{ kind: 'action', text: 'He flips the shutter. Light floods the booth.' },
		{ kind: 'transition', text: 'CUT TO:' }
	];

	const secondPage = [
		{ kind: 'scene', text: 'INT. THE REX CINEMA, AUDITORIUM - CONTINUOUS' },
		{ kind: 'action', text: 'Rows of vacant seats. On screen, a HOME MOVIE flickers: a birthday party, decades old. A young girl blows out candles.' },
		{ kind: 'character', text: 'MARA (O.S.)' },
		{ kind: 'dialogue', text: "You kept it." },
		{ kind: 'action', text: "Elias doesn't turn. MARA, 30s, stands in the aisle, out of breath." }
	];

	onMount(() => setupReveal());
</script>

<svelte:head>
	<title>Writing — eDraft Features</title>
	<meta name="description" content="Automatic screenplay formatting in eDraft: Tab and Return move through elements, suggestions complete character names, and the engine paginates to spec." />
</svelte:head>

<SiteLayout eyebrow="Features · Writing" links={navLinks}>
	<main id="main">
		<PageHero
			eyebrow="Writing"
			title="Formatting that"
			accent="disappears."
			intro="You think in scenes and dialogue. eDraft thinks in margins, indents, and page breaks — and never asks you to."
			back={{ href: '/features', label: 'Features' }}
		/>

		<section class="sticky-flow reveal" aria-labelledby="flow-title">
			<div class="sticky-inner">
				<div class="sticky-copy">
					<div class="flow-block">
						<p class="slabel">The flow</p>
						<h2 id="flow-title">Tab is the<br /><span>only lesson.</span></h2>
						<p class="sintro">Every screenplay element is one keystroke away. Return carries you down the page; Tab moves you across the elements — heading, action, character, dialogue, transition.</p>
					</div>
					<div class="flow-block">
						<h3>Elements follow the cursor.</h3>
						<p>Start a scene heading and the next Return is action. Name a character and dialogue is waiting. The page reads your intention, not your menu choices.</p>
					</div>
					<div class="flow-block">
						<h3>Scene headings remember.</h3>
						<p>Locations and INT./EXT. prefixes are carried forward. A new slug line takes a few letters, not a retype — so the mechanics stay beneath the story.</p>
					</div>
				</div>
				<div class="sticky-visual">
					<Sheet lines={flowLines} page="1." />
				</div>
			</div>
		</section>

		<Split
			theme="alt"
			flip
			eyebrow="Suggestions"
			title="Help that never"
			accent="interrupts."
			intro="As you type a character cue, eDraft offers the names already in your script. Accept it and keep moving — or keep typing and it steps aside."
			points={[
				{ title: 'Names, completed.', text: 'The cast you have written is the dictionary. No cloud service, no generic autocomplete — just your own story, handed back to you.' },
				{ title: 'Shortcuts within reach.', text: 'Every common command has a keyboard shortcut, so revision stays physical: select, cut, restore, move on.' }
			]}
		>
			<div class="editor-moment" aria-label="Character suggestion example">
				<div class="editor-card">
					<div class="editor-row">
						<span class="typed">EL</span><span class="ghost">IAS</span><span class="caret" aria-hidden="true"></span>
						<span class="suggest">Tab to accept</span>
					</div>
					<div class="editor-row next">
						<span class="dim">dialogue follows the cue —</span>
					</div>
					<div class="editor-row next">
						<span class="dim">never the other way around.</span>
					</div>
				</div>
			</div>
		</Split>

		<Split
			theme="dark"
			eyebrow="The page"
			title="A page count"
			accent="you can trust."
			intro="A screenplay page is a minute of screen time. eDraft paginates with the engine — margins, indents, and breaks to spec — so the number at the bottom of the file means something."
			points={[
				{ title: 'Courier, to spec.', text: 'Scene headings, cues, and dialogue are set in the classic one-minute page. Nothing to configure, nothing to nudge.' },
				{ title: 'Breaks chosen by the engine.', text: 'Page breaks land where a reader expects them — never orphaned mid-scene by the size of your window.' },
				{ title: 'A title page without fuss.', text: 'The title page is part of the document, set in the same pass. It prints and exports with the script.' }
			]}
		>
			<Sheet lines={secondPage} page="2." />
		</Split>

		<CtaBand />
		<Pager href="/features/story" title="Story" />
	</main>
</SiteLayout>

<style>
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }

	/* Sticky flow — the Apple pinned-visual pattern */
	.sticky-flow { padding: 132px 0; }
	.sticky-inner { max-width: 1120px; margin: auto; padding: 0 24px; display: grid; grid-template-columns: 1fr 1.1fr; gap: 96px; align-items: start; }
	.sticky-copy { display: flex; flex-direction: column; gap: 84px; padding: 40px 0 60px; }
	.flow-block h2 { font-size: clamp(34px, 4vw, 56px); font-weight: 650; line-height: 1.08; letter-spacing: -.04em; margin-top: 18px; }
	.flow-block h2 span { color: #86868b; }
	.slabel { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.sintro { font-size: 17px; line-height: 1.6; color: #6e6e73; margin-top: 20px; max-width: 440px; }
	.flow-block h3 { font-size: 21px; font-weight: 600; letter-spacing: -.025em; line-height: 1.3; }
	.flow-block p { font-size: 15px; line-height: 1.65; color: #6e6e73; margin-top: 10px; max-width: 440px; }
	.sticky-visual { position: sticky; top: 110px; }
	@media (max-width: 900px) {
		.sticky-flow { padding: 88px 0; }
		.sticky-inner { grid-template-columns: 1fr; gap: 48px; }
		.sticky-copy { gap: 44px; padding: 0; }
		.sticky-visual { position: static; }
	}

	/* A quiet reconstruction of the editor's suggestion moment */
	.editor-moment { display: flex; justify-content: center; }
	.editor-card { background: #fff; border: 1px solid #e6e6ea; border-radius: 14px; padding: 40px 36px; width: 100%; max-width: 460px; box-shadow: 0 24px 60px #18263712; font-family: 'Courier New', ui-monospace, Menlo, monospace; font-size: 13.5px; line-height: 2; }
	.editor-row { display: flex; align-items: baseline; padding-left: 34ch; position: relative; }
	.editor-row.next { padding-left: 25ch; }
	.typed { font-weight: 700; }
	.ghost { color: #9a9aa0; font-weight: 700; }
	.caret { display: inline-block; width: 7px; height: 16px; background: #0071e3; margin-left: 2px; transform: translateY(2px); animation: blink 1.1s steps(2, start) infinite; }
	.suggest { position: absolute; right: 14px; top: -24px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; font-size: 11px; color: #86868b; background: #f5f5f7; border: 1px solid #e3e3e8; border-radius: 6px; padding: 2px 8px; white-space: nowrap; }
	.dim { color: #8e8e93; }
	@keyframes blink { to { visibility: hidden; } }
	@media (max-width: 600px) {
		.editor-card { padding: 44px 20px 28px; font-size: 11.5px; }
		.editor-row { padding-left: 22ch; }
		.editor-row.next { padding-left: 16ch; }
		.suggest { top: -34px; right: 8px; }
	}
</style>
