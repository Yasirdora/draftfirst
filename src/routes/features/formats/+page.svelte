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

	const formats = [
		{ name: 'eDraft', ext: 'draft', text: 'Save your screenplay in eDraft’s own document format.' },
		{ name: 'Final Draft', ext: 'fdx', text: 'Import and export supported FDX screenplay content.' },
		{ name: 'Fountain', ext: 'fountain', text: 'Move your screenplay between tools as readable plain text.' },
		{ name: 'PDF', ext: 'pdf', text: 'Export formatted pages for reading and sharing.' }
	];

	const printedPage = [
		{ kind: 'scene', text: 'INT. THE REX CINEMA, AUDITORIUM - DAWN' },
		{ kind: 'action', text: 'First light through the curtained doors. MARA sleeps in row four, the old reel held against her chest like a pillow.' },
		{ kind: 'character', text: 'ELIAS' },
		{ kind: 'dialogue', text: 'It always ends with the audience. Even when there isn’t one.' },
		{ kind: 'transition', text: 'FADE OUT.' }
	];

	onMount(() => setupReveal());
</script>

<svelte:head>
	<title>Formats — eDraft Features</title>
	<meta name="description" content="eDraft reads and writes the screenplay formats that matter: .draft, Final Draft (.fdx), Fountain, and PDF — with no lock-in and no watermark." />
</svelte:head>

<SiteLayout
	eyebrow="Features · Formats"
	links={navLinks}
	footnote="1. FDX compatibility covers a defined subset of the format. Review import and export warnings, and retain original production files."
>
	<main id="main">
		<PageHero
			eyebrow="Formats"
			title="Bring your work"
			accent="with you."
			intro="Your screenplay is yours. eDraft reads the formats the industry runs on and writes files you can open anywhere — today, and in twenty years."
			back={{ href: '/features', label: 'Features' }}
		/>

		<Split
			eyebrow="The formats"
			title="Four doors,"
			accent="one story."
			intro="Start something new or continue an existing draft. Exchange scripts with people on other tools. Share pages when you are ready. The document is always the same story."
			points={[
				{ title: 'Nothing proprietary to escape.', text: 'The native .draft format is built to be readable, and Fountain is plain text. Your archive does not depend on anyone’s business model.' },
				{ title: 'No watermark, ever.', text: 'The PDF you export is the PDF you send. eDraft does not hold your pages hostage behind a paid tier.' }
			]}
		>
			<div class="format-grid">
				{#each formats as format}
					<div class="format-tile">
						<h3>{format.name}</h3>
						<p class="ext">.{format.ext}</p>
						<p>{format.text}</p>
					</div>
				{/each}
			</div>
		</Split>

		<Split
			theme="alt"
			flip
			eyebrow="Import"
			title="Open the rest of the"
			accent="industry's files."
			intro="Bring in a Final Draft (.fdx) file or paste Fountain text and eDraft sets the pages for you. What the format carries, your screenplay keeps."
			points={[
				{ title: 'Fountain is plain text.', text: 'If you can read it, you can rescue it. Fountain files open anywhere text lives — including eDraft.' },
				{ title: 'Honest about FDX.', text: 'FDX support covers a defined subset of the format, and eDraft says so on import. Review the warnings, keep your original, and nothing is silently lost. (1)' }
			]}
		/>

		<Split
			theme="dark"
			eyebrow="Export"
			title="Pages that read"
			accent="like print."
			intro="The PDF export is set from the same engine that paginates your draft — margins, indents, and breaks to spec. Send it to a reader, a table, or a contest."
			points={[
				{ title: 'PDF for people.', text: 'Formatted pages for anyone who reads — no app required on their side.' },
				{ title: 'FDX for tools.', text: 'Send supported FDX back out to teammates on other screenwriting software.' },
				{ title: 'Fountain for the future.', text: 'Plain text is the most durable format ever made. Archive in it.' }
			]}
		>
			<Sheet lines={printedPage} page="112." />
		</Split>

		<CtaBand />
		<Pager href="/features/privacy" title="Privacy" />
	</main>
</SiteLayout>

<style>
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }

	/* Formats — wordmark grid */
	.format-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 44px; }
	.format-tile { padding: 26px 0 28px; border-top: 1px solid #d2d2d7; }
	.format-grid .format-tile:nth-child(-n + 2) { border-top: 0; padding-top: 4px; }
	.format-tile h3 { font-size: 22px; font-weight: 600; letter-spacing: -.03em; }
	.format-tile .ext { font-size: 12px; font-weight: 500; color: #86868b; font-family: ui-monospace, 'SF Mono', Menlo, monospace; margin-top: 4px; }
	.format-tile > p:last-child { font-size: 14px; line-height: 1.55; color: #6e6e73; margin-top: 10px; }

	@media (max-width: 600px) {
		.format-grid { grid-template-columns: 1fr; gap: 0; }
		.format-grid .format-tile:nth-child(-n + 2) { border-top: 1px solid #d2d2d7; padding-top: 26px; }
		.format-tile:first-child { border-top: 0; padding-top: 4px; }
	}
</style>
