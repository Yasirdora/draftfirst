<script lang="ts">
	import { onMount } from 'svelte';
	import SiteLayout from '$lib/site/SiteLayout.svelte';
	import PageHero from '$lib/site/PageHero.svelte';
	import Split from '$lib/site/Split.svelte';
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

	const scenes = [
		{ n: '1', title: 'INT. THE REX CINEMA, PROJECTION BOOTH - NIGHT', active: false },
		{ n: '2', title: 'INT. THE REX CINEMA, AUDITORIUM - CONTINUOUS', active: true },
		{ n: '3', title: 'EXT. THE REX CINEMA, STREET - NIGHT', active: false },
		{ n: '4', title: 'INT. THE REX CINEMA, PROJECTION BOOTH - LATER', active: false }
	];

	const cast = ['ELIAS', 'MARA', 'THE PROJECTIONIST', 'YOUNG MARA'];

	onMount(() => setupReveal());
</script>

<svelte:head>
	<title>Story — eDraft Features</title>
	<meta name="description" content="Scenes, cast, notes, and reversible omissions in eDraft: the structure of your screenplay stays beside the page, never in the way." />
</svelte:head>

<SiteLayout eyebrow="Features · Story" links={navLinks}>
	<main id="main">
		<PageHero
			eyebrow="Story"
			title="The whole story,"
			accent="beside the page."
			intro="A screenplay is a structure before it is a document. eDraft keeps the structure — scenes, cast, notes — one glance away from the line you are writing."
			back={{ href: '/features', label: 'Features' }}
		/>

		<Split
			eyebrow="Scenes"
			title="Jump the length of a"
			accent="hundred pages."
			intro="The scene panel lists every scene by number and opening line. Pick one and the page turns for you — no scrolling marathon, no lost place."
			points={[
				{ title: 'Numbered, in order.', text: 'Each scene carries its number and slug line, so a note like "fix scene 14" is an address, not a search.' },
				{ title: 'The page follows you.', text: 'Moving between scenes keeps your cursor and your context. Return lands exactly where you left.' }
			]}
		>
			<div class="panel" aria-label="Scene panel example">
				<div class="panel-head">Scenes</div>
				{#each scenes as scene}
					<div class="scene-row" class:active={scene.active}>
						<span class="num">{scene.n}</span>
						<span class="slug">{scene.title}</span>
					</div>
				{/each}
			</div>
		</Split>

		<Split
			theme="alt"
			flip
			eyebrow="Cast"
			title="Characters, gathered"
			accent="as you write."
			intro="Every cue you type joins the cast panel automatically. The people of your story collect themselves — no index cards to maintain, no list to retype."
			points={[
				{ title: 'Born from the page.', text: 'The cast is built from your own cues, in the order they appear. A character exists because you wrote them.' },
				{ title: 'Find anyone, fast.', text: 'Scan the panel to see who is in the story and jump to their first moment on the page.' }
			]}
		>
			<div class="chips" aria-label="Cast panel example">
				<div class="panel-head">Cast</div>
				<div class="chip-grid">
					{#each cast as name}
						<span class="chip">{name}</span>
					{/each}
				</div>
				<p class="chip-note">4 characters · collected from cues</p>
			</div>
		</Split>

		<Split
			theme="dark"
			eyebrow="Omissions"
			title="Omit, don't"
			accent="delete."
			intro="Cutting a scene should not mean losing it. Omitting folds the scene away and leaves a card marked OMITTED in its place — the numbering holds, and the cut is reversible."
			points={[
				{ title: 'The schedule keeps its shape.', text: 'Scene numbers are preserved, so the scenes around the cut are never renumbered. Schedules and references stay intact.' },
				{ title: 'Prints clean, restores whole.', text: 'An omitted scene does not print or export. Restore it and the scene returns exactly as written — same words, same number.' },
				{ title: 'Deletion stays deliberate.', text: 'Omitting is the reversible cut. Deletion remains the one gesture with no undo across saves.' }
			]}
		>
			<div class="panel dark-panel" aria-label="Omitted scene example">
				<div class="panel-head">Scenes</div>
				<div class="scene-row"><span class="num">3</span><span class="slug">EXT. THE REX CINEMA, STREET - NIGHT</span></div>
				<div class="omitted-card">
					<span class="omitted-tag">OMITTED</span>
					<span class="omitted-num">4</span>
					<span class="omitted-hint">Restore anytime — nothing was deleted.</span>
				</div>
				<div class="scene-row"><span class="num">5</span><span class="slug">INT. THE REX CINEMA, AUDITORIUM - DAWN</span></div>
			</div>
		</Split>

		<Split
			eyebrow="Notes"
			title="Notes that live"
			accent="in the file."
			intro="Margin notes attach to the line they belong to and thread into conversations with yourself. They live in your document — not in a separate app, not on someone else's server."
			points={[
				{ title: 'Attached, not appended.', text: 'A note stays anchored to its line as the script moves and grows around it.' },
				{ title: 'Threads, not stickies.', text: 'Replies stack into threads, so a passing thought can become a short conversation — and resolve when it is done.' }
			]}
		>
			<div class="panel note-panel" aria-label="Margin note example">
				<div class="note-line">MARA <span class="note-cue">(O.S.)</span></div>
				<div class="note-body">You kept it.</div>
				<div class="note-thread">
					<span class="note-tag">NOTE</span>
					<p>Her first line back — land it quiet, no music.</p>
					<p class="note-reply">And she should see the reel before he sees her.</p>
				</div>
			</div>
		</Split>

		<CtaBand />
		<Pager href="/features/formats" title="Formats" />
	</main>
</SiteLayout>

<style>
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }

	/* Reconstructed panels — the app's side panel, typeset to match */
	.panel { background: #fff; border: 1px solid #e6e6ea; border-radius: 14px; padding: 22px 20px; width: 100%; max-width: 440px; margin: auto; box-shadow: 0 24px 60px #18263712; }
	.panel-head { font-size: 11px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; padding-bottom: 14px; border-bottom: 1px solid #ececf0; margin-bottom: 8px; }
	.scene-row { display: flex; gap: 14px; padding: 13px 10px; border-radius: 9px; align-items: baseline; }
	.scene-row.active { background: #f0f7ff; }
	.num { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 12px; color: #86868b; flex-shrink: 0; }
	.scene-row.active .num { color: #0879cf; }
	.slug { font-size: 12.5px; line-height: 1.45; color: #48484d; }
	.scene-row.active .slug { color: #1d1d1f; font-weight: 500; }

	.chips { background: #fff; border: 1px solid #e6e6ea; border-radius: 14px; padding: 22px 20px; width: 100%; max-width: 440px; margin: auto; box-shadow: 0 24px 60px #18263712; }
	.chip-grid { display: flex; flex-wrap: wrap; gap: 10px; padding: 8px 0 4px; }
	.chip { font-size: 13px; font-weight: 500; letter-spacing: .02em; color: #1d1d1f; background: #f5f5f7; border: 1px solid #e3e3e8; border-radius: 8px; padding: 8px 14px; }
	.chip-note { font-size: 12px; color: #86868b; padding-top: 12px; border-top: 1px solid #ececf0; margin-top: 10px; }

	.dark-panel { background: #161617; border-color: #2c2c2e; box-shadow: none; }
	.dark-panel .panel-head { color: #86868b; border-bottom-color: #2c2c2e; }
	.dark-panel .slug { color: #a1a1a6; }
	.dark-panel .num { color: #6e6e73; }
	.omitted-card { margin: 10px 0; padding: 18px; border: 1px dashed #4a4a4f; border-radius: 9px; display: flex; flex-direction: column; gap: 6px; }
	.omitted-tag { font-size: 10px; font-weight: 700; letter-spacing: .12em; color: #f5f5f7; background: #3a3a3f; border-radius: 4px; padding: 3px 8px; align-self: flex-start; }
	.omitted-num { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 12px; color: #6e6e73; }
	.omitted-hint { font-size: 12px; color: #86868b; }

	.note-panel { font-family: 'Courier New', ui-monospace, Menlo, monospace; font-size: 12.5px; line-height: 1.6; padding: 28px 26px; }
	.note-line { font-weight: 700; padding-left: 34ch; }
	.note-cue { font-weight: 400; }
	.note-body { padding-left: 25ch; margin-bottom: 20px; }
	.note-thread { border-left: 3px solid #0071e3; background: #f5f9ff; border-radius: 0 10px 10px 0; padding: 16px 18px; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; }
	.note-tag { font-size: 10px; font-weight: 700; letter-spacing: .12em; color: #0879cf; }
	.note-thread p { font-size: 13px; line-height: 1.55; color: #48484d; margin-top: 8px; }
	.note-reply { padding-left: 14px; border-left: 2px solid #d2d2d7; color: #6e6e73 !important; }

	@media (max-width: 600px) {
		.note-line { padding-left: 20ch; }
		.note-body { padding-left: 14ch; }
	}
</style>
