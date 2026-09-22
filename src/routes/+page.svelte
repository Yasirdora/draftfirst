<script lang="ts">
	import { onMount } from 'svelte';
	import SiteLayout from '$lib/site/SiteLayout.svelte';

	let appearance = $state<'light' | 'dark'>('light');

	const navLinks = [
		{ href: '/features', label: 'Features' },
		{ href: '/features/story', label: 'Story' },
		{ href: '/features/formats', label: 'Formats' },
		{ href: '/privacy', label: 'Privacy' },
		{ href: '/help', label: 'Help' }
	];

	const pillars = [
		{ href: '/features/writing', title: 'Screenplay formatting', text: 'Scene headings, action, character cues, and dialogue are formatted as you write. Page breaks are handled for you.' },
		{ href: '/features/story', title: 'Your story at a glance', text: 'Move between scenes and find your characters in the side panel. Keep the bigger picture close to the page.' },
		{ href: '/features/writing', title: 'Keep your hands on the keys', text: 'Use Tab and Return to move through screenplay elements, with character suggestions and shortcuts within reach.' }
	];

	const faqs = [
		{ question: 'Do I need an account?', answer: 'No. Open the editor and start writing. eDraft asks for no name, no email, and no sign-in.' },
		{ question: 'Where is my screenplay saved?', answer: 'The browser editor keeps a working copy in local browser storage. Save or export your screenplay to keep a separate file on your device. Clearing browser data can remove the working copy, so save a file regularly.' },
		{ question: 'Is my writing private?', answer: 'Yes. The editor works on your device. Your screenplay is never uploaded to an eDraft server, and the editor carries no analytics and no tracking.' },
		{ question: 'Can I open a script from another application?', answer: 'Yes. Import Fountain text and supported Final Draft (.fdx) files. FDX support covers a defined subset of the format — review the import warnings, and keep your original file when moving a production script.' },
		{ question: 'How do I share my screenplay?', answer: 'Export a PDF for reading, a Fountain file for plain-text exchange, or a supported FDX file for another screenwriting application. You choose where the file is saved and who receives it.' }
	];

	const formats = [
		{ name: 'eDraft', ext: 'draft', text: 'Save your screenplay in eDraft’s own document format.' },
		{ name: 'Final Draft', ext: 'fdx', text: 'Import and export supported FDX screenplay content.' },
		{ name: 'Fountain', ext: 'fountain', text: 'Move your screenplay between tools as readable plain text.' },
		{ name: 'PDF', ext: 'pdf', text: 'Export formatted pages for reading and sharing.' }
	];

	/* The opening of eDraft's own sample screenplay, typeset to spec. */
	const excerpt: { kind: string; text: string }[] = [
		{ kind: 'scene', text: 'INT. THE REX CINEMA, PROJECTION BOOTH - NIGHT' },
		{ kind: 'action', text: "Dust hangs in the beam of a 35mm projector. ELIAS VANCE, 60s, threads the final reel with surgeon's hands. The auditorium below is empty." },
		{ kind: 'character', text: 'ELIAS' },
		{ kind: 'paren', text: '(quietly, to the machine)' },
		{ kind: 'dialogue', text: 'One more time. Like we promised.' },
		{ kind: 'action', text: 'He flips the shutter. Light floods the booth.' },
		{ kind: 'transition', text: 'CUT TO:' }
	];

	onMount(() => {
		const root = document.querySelector('.website');
		root?.classList.add('js');

		/* Quiet reveal on scroll — initial hidden state exists only when JS does */
		const io = new IntersectionObserver(
			(entries) => {
				for (const entry of entries) {
					if (entry.isIntersecting) {
						entry.target.classList.add('in');
						io.unobserve(entry.target);
					}
				}
			},
			{ threshold: 0.1, rootMargin: '0px 0px -48px 0px' }
		);
		root?.querySelectorAll('.reveal').forEach((el) => io.observe(el));

		/* Safety: if observation never fires, nothing may stay hidden. */
		const safety = setTimeout(() => {
			root?.querySelectorAll('.reveal:not(.in)').forEach((el) => el.classList.add('in'));
		}, 2500);

		return () => {
			io.disconnect();
			clearTimeout(safety);
		};
	});
</script>

<svelte:head>
	<title>eDraft — Screenwriting, beautifully simple.</title>
	<meta name="description" content="Write screenplays with automatic formatting, scene navigation, and private local storage. Open eDraft in your browser. No account required." />
	<meta property="og:title" content="eDraft — Screenwriting, beautifully simple." />
	<meta property="og:description" content="A focused screenplay editor. Automatic formatting, portable files, and your work kept on your device." />
</svelte:head>

<SiteLayout links={navLinks} footnote="1. FDX compatibility covers a defined subset of the format. Review import and export warnings, and retain original production files.">
	<main id="main">
		<section class="hero" aria-labelledby="hero-title">
			<p class="label">eDraft Screenwriting</p>
			<h1 id="hero-title">The writer never formats. <br /><span>The story is yours.</span></h1>
			<p class="hero-description">A focused workspace for your screenplay. Automatic formatting, thoughtful tools — entirely your work.</p>
			<div class="hero-actions">
				<a class="button" href="/screenplay">Start writing</a>
				<a class="text-link" href="/features">Explore eDraft <span aria-hidden="true">›</span></a>
			</div>
			<p class="availability">Available in your browser. No account required.</p>
			<figure class="product">
				<img src={appearance === 'light' ? '/editor-preview.png' : '/editor-preview-dark.png'} width="1280" height="720" fetchpriority="high" alt={'The actual eDraft editor in ' + appearance + ' appearance, showing The Empty Cinema sample screenplay and scene navigator.'} />
				<div class="appearance-switch" role="group" aria-label="Preview appearance">
					<button class:active={appearance === 'light'} aria-pressed={appearance === 'light'} onclick={() => appearance = 'light'}>Light</button>
					<button class:active={appearance === 'dark'} aria-pressed={appearance === 'dark'} onclick={() => appearance = 'dark'}>Dark</button>
				</div>
				<figcaption>A clear view of your story.</figcaption>
			</figure>
		</section>

		<section class="promise reveal" id="features" aria-labelledby="features-title">
			<div class="section-width">
				<p class="label">Made for screenwriting</p>
				<h2 id="features-title">Everything in its place.<br /><span>Including your focus.</span></h2>
				<p class="section-intro">From the first scene heading to the final line, eDraft takes care of the structure so you can keep writing.</p>
				<div class="pillars stagger">
					{#each pillars as pillar}
						<a class="pillar" href={pillar.href}>
							<h3>{pillar.title}</h3>
							<p>{pillar.text}</p>
							<span class="pillar-link">Learn more <span aria-hidden="true">›</span></span>
						</a>
					{/each}
				</div>
			</div>
		</section>

		<section class="band alt reveal" id="formats" aria-labelledby="formats-title">
			<div class="section-width band-layout">
				<div class="band-copy">
					<p class="label">Formats</p>
					<h2 id="formats-title">Bring your work with you.</h2>
					<p>Start something new or continue an existing draft. Save a file you own, exchange scripts, and share pages when you’re ready.</p>
					<a class="text-link" href="/features/formats">Explore formats <span aria-hidden="true">›</span></a>
				</div>
				<div class="format-grid stagger">
					{#each formats as format}
						<div class="format-tile">
							<h3>{format.name}</h3>
							<p class="ext">.{format.ext}</p>
							<p>{format.text}</p>
						</div>
					{/each}
				</div>
			</div>
		</section>

		<section class="page-band reveal" id="page" aria-labelledby="page-title">
			<div class="section-width page-layout">
				<div class="page-copy">
					<p class="label">The page</p>
					<h2 id="page-title">It looks like a screenplay.<br /><span>Because it is one.</span></h2>
					<p class="section-intro">Scene headings, cues, and dialogue set in Courier to spec, paginated by the engine — never by the screen.</p>
					<div class="page-points">
						<div><h3>Margins and indents to spec.</h3><p>Nothing to set, nothing to nudge.</p></div>
						<div><h3>A page count you can trust.</h3><p>A page is a minute of screen time. The engine keeps your clock honest.</p></div>
					</div>
				</div>
				<div class="sheet-wrap">
					<div class="sheet" aria-label="Sample screenplay page">
						<p class="pg" aria-hidden="true">1.</p>
						{#each excerpt as line}
							<p class={line.kind}>{line.text}</p>
						{/each}
					</div>
				</div>
			</div>
		</section>

		<section class="interstitial reveal" aria-labelledby="interstitial-title">
			<div class="section-width">
				<p class="label light">The math of movies</p>
				<h2 id="interstitial-title">One page.<br /><span>One minute.</span></h2>
				<p class="interstitial-sub">The oldest contract in Hollywood — kept by the engine,<br class="desktop-break" /> not by your patience.</p>
			</div>
		</section>

		<section class="band dark reveal" id="privacy" aria-labelledby="privacy-title">
			<div class="section-width">
				<p class="label">Private by design</p>
				<h2 id="privacy-title">Your work stays with you.</h2>
				<p class="section-intro">Your screenplay is personal. The browser editor works locally,<br class="desktop-break" /> without uploading your writing to an eDraft server.</p>
				<div class="privacy-points stagger">
					<div><h3>No account to create.</h3><p>Open the editor and get straight to your screenplay.</p></div>
					<div><h3>No tracking in the editor.</h3><p>Your writing is processed on your device.</p></div>
					<div><h3>Files you control.</h3><p>Save a copy locally. Choose how and when to share it.</p></div>
				</div>
				<a class="text-link privacy-link" href="/features/privacy">See how privacy works <span aria-hidden="true">›</span></a>
			</div>
		</section>

		<section class="band alt reveal" id="questions" aria-labelledby="questions-title">
			<div class="faq-inner">
				<p class="label">Questions</p>
				<h2 id="questions-title">Questions, answered.</h2>
				<div class="questions">
					{#each faqs as faq}
						<details><summary>{faq.question}<span aria-hidden="true">+</span></summary><p>{faq.answer}</p></details>
					{/each}
				</div>
				<p class="faq-more">More answers live in the <a href="/help">Help Center</a>.</p>
			</div>
		</section>

		<section class="start-section reveal">
			<img src="/edraft-mark.svg" alt="" width="72" height="72" loading="lazy" />
			<h2>Your next draft starts here.</h2>
			<p>Open eDraft and make yourself at home.</p>
			<a class="button" href="/screenplay">Start writing</a>
		</section>
	</main>
</SiteLayout>

<style>
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.section-width { max-width: 1120px; margin: auto; padding-left: 24px; padding-right: 24px; }

	/* Scroll reveal — initial hidden state exists only when JS does */
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }
	:global(.website.js .reveal .stagger > *) { opacity: 0; transform: translateY(14px); transition: opacity .6s ease, transform .6s ease; }
	:global(.website.js .reveal.in .stagger > *) { opacity: 1; transform: none; }
	:global(.website.js .reveal.in .stagger > *:nth-child(2)) { transition-delay: .08s; }
	:global(.website.js .reveal.in .stagger > *:nth-child(3)) { transition-delay: .16s; }
	:global(.website.js .reveal.in .stagger > *:nth-child(4)) { transition-delay: .24s; }

	/* Hero — type first, product after */
	.hero { position: relative; padding: 118px 24px 0; text-align: center; background:
		radial-gradient(52% 44% at 18% 0%, #dcebff 0%, transparent 62%),
		radial-gradient(46% 40% at 86% 6%, #eae3ff 0%, transparent 66%),
		radial-gradient(38% 30% at 58% 0%, #d9f2f7 0%, transparent 72%); }
	.hero h1 { font-size: clamp(46px, 6.8vw, 88px); font-weight: 650; letter-spacing: -.045em; line-height: 1.04; margin: 20px 0 24px; }
	.hero h1 span { color: #0879cf; }
	.hero-description { font-size: 21px; line-height: 1.5; letter-spacing: -.02em; color: #55555c; max-width: 640px; margin: auto; }
	.hero-actions { display: flex; align-items: center; justify-content: center; gap: 29px; margin-top: 34px; }
	.hero-actions .button, .start-section .button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: #fff; padding: 14px 27px; font-size: 17px; line-height: 1.25; white-space: nowrap; transition: background .18s; }
	.hero-actions .button:hover, .start-section .button:hover { background: #0062c4; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #0066cc; font-size: 17px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 25px; line-height: 1; transition: transform .18s ease; }
	.text-link:hover span { transform: translateX(3px); }
	.hero .availability { font-size: 12px; color: #6e6e73; margin-top: 18px; }
	.product { position: relative; max-width: 1240px; margin: 80px auto 0; }
	.product img { display: block; width: 100%; height: auto; border-radius: 18px; border: 1px solid #e2e4e8; box-shadow: 0 60px 120px #1a2c441f, 0 8px 24px #1826370d; }
	.product figcaption { padding-top: 18px; font-size: 12px; color: #6e6e73; }
	.appearance-switch { position: absolute; right: 16px; top: 16px; display: flex; padding: 3px; background: rgb(255 255 255 / 86%); backdrop-filter: blur(14px); border-radius: 20px; box-shadow: 0 2px 10px #18263714; }
	.appearance-switch button { background: transparent; border: 0; padding: 6px 15px; border-radius: 20px; color: #626269; font-size: 11px; }
	.appearance-switch button.active { background: white; color: #1d1d1f; box-shadow: 0 1px 4px #0000001f; }

	/* Bands */
	h2 { font-size: clamp(32px, 3.8vw, 52px); font-weight: 650; line-height: 1.1; letter-spacing: -.04em; margin-top: 18px; }
	h2 span { color: #86868b; }
	.section-intro { font-size: 18px; line-height: 1.6; color: #6e6e73; margin-top: 22px; }
	h3 { font-size: 17px; font-weight: 600; letter-spacing: -.02em; line-height: 1.35; }
	.promise { padding: 130px 0 132px; }
	.pillars { display: grid; grid-template-columns: repeat(3, 1fr); gap: 56px; margin-top: 64px; padding-top: 40px; border-top: 1px solid #e3e3e8; }
	.pillar { display: block; color: inherit; border-radius: 14px; }
	.pillar h3 { transition: color .18s; }
	.pillar:hover h3 { color: #0066cc; }
	.pillars p { font-size: 15px; line-height: 1.65; color: #6e6e73; margin-top: 10px; }
	.pillar-link { display: inline-block; margin-top: 14px; font-size: 14px; color: #0066cc; }
	.pillar:hover .pillar-link { text-decoration: underline; }
	.band { padding: 118px 0; }
	.band.alt { background: #f5f5f7; }
	.band.dark { background: #000; color: #f5f5f7; }
	.band.dark .label { color: #86868b; }
	.band.dark h2 { color: #f5f5f7; }
	.band.dark .section-intro { color: #a1a1a6; }
	.band-layout { display: grid; grid-template-columns: 1fr 1.25fr; gap: 88px; align-items: start; }
	.band-copy > p:not(.label) { margin: 22px 0 26px; color: #6e6e73; font-size: 17px; line-height: 1.6; max-width: 420px; }

	/* Formats — wordmark grid */
	.format-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 0 48px; }
	.format-tile { padding: 28px 0 30px; border-top: 1px solid #d2d2d7; }
	.format-grid .format-tile:nth-child(-n + 2) { border-top: 0; padding-top: 4px; }
	.format-tile h3 { font-size: 22px; letter-spacing: -.03em; transition: color .18s; }
	.format-tile:hover h3 { color: #0066cc; }
	.format-tile .ext { font-size: 12px; font-weight: 500; color: #86868b; font-family: ui-monospace, 'SF Mono', Menlo, monospace; margin-top: 4px; }
	.format-tile > p:last-child { font-size: 14px; line-height: 1.55; color: #6e6e73; margin-top: 10px; }

	/* The page — a real screenplay sheet */
	.page-band { padding: 128px 0; overflow: hidden; }
	.page-layout { display: grid; grid-template-columns: 1fr 1.15fr; gap: 88px; align-items: center; }
	.page-points { display: grid; gap: 26px; margin-top: 44px; padding-top: 32px; border-top: 1px solid #e3e3e8; }
	.page-points p { font-size: 14px; line-height: 1.6; color: #6e6e73; margin-top: 6px; }
	.sheet-wrap { display: flex; justify-content: center; }
	.sheet { background: #fff; border: 1px solid #e6e6ea; width: 100%; max-width: 540px; padding: 56px 60px 60px; box-shadow: 0 32px 80px #18263718, 0 2px 10px #1826370c; font-family: 'Courier New', ui-monospace, Menlo, monospace; font-size: 12.5px; line-height: 1.5; color: #1a1a1c; }
	.sheet p { margin: 0 0 1em; max-width: 60ch; }
	.sheet .pg { text-align: right; color: #8e8e93; }
	.sheet .scene { font-weight: 700; }
	.sheet .character { padding-left: 34ch; }
	.sheet .paren { padding-left: 28ch; max-width: 58ch; }
	.sheet .dialogue { padding-left: 25ch; max-width: 64ch; }
	.sheet .transition { text-align: right; }

	/* Typographic interstitial — the Apple "big moment" */
	.interstitial { background: #000; color: #f5f5f7; padding: 150px 0 156px; text-align: center; }
	.label.light { color: #86868b; }
	.interstitial h2 { font-size: clamp(56px, 8.4vw, 112px); font-weight: 650; letter-spacing: -.05em; line-height: 1.02; margin-top: 22px; }
	.interstitial h2 span { background: linear-gradient(100deg, #4da3ff 10%, #8f7bff 55%, #d56bd0 90%); -webkit-background-clip: text; background-clip: text; color: transparent; }
	.interstitial-sub { font-size: 19px; line-height: 1.6; color: #a1a1a6; margin-top: 28px; }

	/* Privacy — the dark interlude */
	.privacy-points { display: grid; grid-template-columns: repeat(3, 1fr); gap: 48px; margin-top: 60px; padding-top: 36px; border-top: 1px solid #2c2c2e; }
	.privacy-points h3 { color: #f5f5f7; }
	.privacy-points p { font-size: 14px; color: #a1a1a6; line-height: 1.6; margin-top: 8px; }
	.privacy-link { margin-top: 44px; color: #2997ff; }

	/* FAQ */
	.faq-inner { max-width: 720px; margin: auto; padding-left: 24px; padding-right: 24px; }
	.faq-inner h2 { margin-top: 18px; }
	.questions { margin-top: 44px; border-top: 1px solid #d2d2d7; }
	details { border-bottom: 1px solid #d2d2d7; }
	summary { list-style: none; display: flex; align-items: center; justify-content: space-between; gap: 20px; cursor: pointer; padding: 22px 0; font-size: 17px; font-weight: 500; letter-spacing: -.01em; color: #1d1d1f; transition: color .2s; }
	summary::-webkit-details-marker { display: none; }
	summary:hover { color: #0066cc; }
	summary span { font-size: 22px; font-weight: 300; color: #86868b; transition: transform .25s ease; flex-shrink: 0; }
	details[open] summary { color: #1d1d1f; }
	details[open] summary span { transform: rotate(45deg); }
	details p { max-width: 640px; color: #48484d; font-size: 15px; line-height: 1.7; padding: 0 34px 26px 0; }
	.faq-more { text-align: center; margin-top: 36px; font-size: 14px; color: #6e6e73; }
	.faq-more a { color: #0066cc; }
	.faq-more a:hover { text-decoration: underline; }

	/* Final CTA */
	.start-section { text-align: center; padding: 116px 24px 124px; }
	.start-section img { object-fit: contain; margin-bottom: 24px; }
	.start-section h2 { font-size: clamp(30px, 3.4vw, 44px); }
	.start-section > p { font-size: 18px; color: #6e6e73; margin: 18px 0 30px; }

	@media (max-width: 900px) {
		.band-layout { grid-template-columns: 1fr; gap: 44px; }
		.page-layout { grid-template-columns: 1fr; gap: 56px; }
		.pillars { gap: 28px; }
		.privacy-points { gap: 28px; }
	}
		@media (max-width: 600px) {
		.hero { padding: 72px 18px 0; }
		.hero h1 { font-size: clamp(34px, 9.4vw, 54px); margin: 18px 0 20px; }
		.hero h1 br { display: none; }
		.hero-description { font-size: 17px; max-width: 340px; }
		.desktop-break { display: none; }
		.hero-actions { gap: 22px; }
		.button { font-size: 14px; padding: 12px 22px; }
		.text-link { font-size: 14px; }
		.hero .availability { font-size: 11px; }
		.product { margin-top: 48px; }
		.product img { border-radius: 10px; }
		.appearance-switch { right: 10px; top: 10px; }
		.promise { padding: 76px 0 80px; }
		.section-intro { font-size: 16px; }
		.pillars { grid-template-columns: 1fr; gap: 30px; margin-top: 40px; }
		.band { padding: 76px 0; }
		.band-copy > p:not(.label) { font-size: 16px; }
		.format-grid { grid-template-columns: 1fr; gap: 0; }
		.format-grid .format-tile:nth-child(-n + 2) { border-top: 1px solid #d2d2d7; padding-top: 28px; }
		.format-tile:first-child { border-top: 0; padding-top: 4px; }
		.page-band { padding: 80px 0; }
		.interstitial { padding: 92px 0 96px; }
		.interstitial-sub { font-size: 16px; margin-top: 20px; }
		.sheet { padding: 36px 26px 40px; font-size: 11px; }
		.privacy-points { grid-template-columns: 1fr; gap: 26px; margin-top: 36px; }
		.faq-inner h2 { font-size: 30px; text-align: left; }
		.questions { margin-top: 24px; }
		summary { font-size: 15px; line-height: 1.4; }
		details p { font-size: 14px; padding-right: 8px; }
		.start-section { padding: 80px 24px 88px; }
		.start-section > p { font-size: 16px; }
	}
</style>
