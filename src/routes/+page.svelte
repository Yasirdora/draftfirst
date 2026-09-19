<script lang="ts">
	const logo = '/edraft-logo.png';

	let appearance = $state<'light' | 'dark'>('light');
	let menuOpen = $state(false);
	const faqs = [
		{ question: 'Do I need an account?', answer: 'No. Open the browser editor and start writing. eDraft does not require registration or a subscription to use the web editor.' },
		{ question: 'Where is my screenplay saved?', answer: 'The browser editor keeps a working copy in local browser storage. Save or export your screenplay to keep a separate file on your device. Clearing browser data can remove the local working copy, so save files regularly.' },
		{ question: 'Can I open a script from another application?', answer: 'Yes. You can import Fountain text and supported Final Draft (.fdx) files. FDX support covers a defined subset of the format; review import warnings and keep your original file when moving a production script.' },
		{ question: 'How do I share my screenplay?', answer: 'Export a PDF for reading, a Fountain file for plain-text exchange, or a supported FDX file for another screenwriting application. You choose where to save and share it.' }
	];
</script>

<svelte:head>
	<title>eDraft — Screenwriting, beautifully simple.</title>
	<meta name="description" content="Write screenplays with automatic formatting, scene navigation, and private local storage. Open eDraft in your browser. No account required." />
	<meta property="og:title" content="eDraft — Screenwriting, beautifully simple." />
	<meta property="og:description" content="A focused screenplay editor. Automatic formatting, portable files, and your work kept on your device." />
</svelte:head>

<div class="website">
	<a class="skip-link" href="#main">Skip to content</a>
	<header>
		<nav class="navigation" aria-label="Main navigation">
			<a class="brand" href="/" aria-label="eDraft home"><img src={logo} alt="" width="36" height="36" /><span>eDraft</span></a>
			<div class="nav-links" class:expanded={menuOpen}>
				<a href="#features" onclick={() => menuOpen = false}>Features</a>
				<a href="#compatibility" onclick={() => menuOpen = false}>Compatibility</a>
				<a href="#privacy" onclick={() => menuOpen = false}>Privacy</a>
				<a href="#questions" onclick={() => menuOpen = false}>FAQs</a>
			</div>
			<div class="nav-actions">
				<a class="button small" href="/screenplay">Open eDraft</a>
				<button class="menu-toggle" aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} aria-expanded={menuOpen} onclick={() => menuOpen = !menuOpen}>
					<svg viewBox="0 0 24 24" aria-hidden="true"><path d={menuOpen ? 'M6 6l12 12M6 18L18 6' : 'M4 8h16M4 16h16'} /></svg>
				</button>
			</div>
		</nav>
	</header>

	<main id="main">
		<section class="hero" aria-labelledby="hero-title">
			<p class="eyebrow">eDraft Screenwriting</p>
			<h1 id="hero-title">Your story. <br /><span>Beautifully on the page.</span></h1>
			<p class="hero-description">A focused workspace for your screenplay.<br class="desktop-break" /> Automatic formatting. Thoughtful tools. Entirely your work.</p>
			<div class="hero-actions">
				<a class="button" href="/screenplay">Start writing</a>
				<a class="text-link" href="#features">Explore eDraft <span aria-hidden="true">›</span></a>
			</div>
			<p class="availability">Available in your browser. No account required.</p>
			<figure class="product">
				<div class="product-window">
					<div class="window-title"><span class="window-dots" aria-hidden="true"><i></i><i></i><i></i></span><span>The Empty Cinema</span><span class="window-label">eDraft for web</span></div>
					<img src={appearance === 'light' ? '/editor-preview.png' : '/editor-preview-dark.png'} width="1280" height="720" fetchpriority="high" alt={'The actual eDraft editor in ' + appearance + ' appearance, showing The Empty Cinema sample screenplay and scene navigator.'} />
				</div>
				<figcaption>
					<span>A clear view of your story.</span>
					<div class="appearance-switch" role="group" aria-label="Preview appearance">
						<button class:active={appearance === 'light'} aria-pressed={appearance === 'light'} onclick={() => appearance = 'light'}>Light</button>
						<button class:active={appearance === 'dark'} aria-pressed={appearance === 'dark'} onclick={() => appearance = 'dark'}>Dark</button>
					</div>
				</figcaption>
			</figure>
		</section>

		<section class="features section-width" id="features" aria-labelledby="features-title">
			<div class="section-heading">
				<p class="eyebrow">Made for screenwriting</p>
				<h2 id="features-title">Everything in its place.<br /><span>Including your focus.</span></h2>
				<p>From the first scene heading to the final line, eDraft takes care of the structure so you can keep writing.</p>
			</div>
			<div class="feature-columns">
				<article>
					<svg class="feature-icon" viewBox="0 0 32 32" aria-hidden="true"><path d="M7 5h18v22H7zM11 10h10M11 14h10M15 18h6M13 22h8" /></svg>
					<h3>Screenplay formatting</h3>
					<p>Scene headings, action, character cues, and dialogue are formatted as you write. Page breaks are handled for you.</p>
				</article>
				<article>
					<svg class="feature-icon" viewBox="0 0 32 32" aria-hidden="true"><rect x="4" y="6" width="24" height="20" rx="3" /><path d="M12 6v20M7 11h2M7 15h2M16 11h8M16 16h6M16 21h8" /></svg>
					<h3>Your story at a glance</h3>
					<p>Move between scenes and find your characters in the side panel. Keep the bigger picture close to the page.</p>
				</article>
				<article>
					<svg class="feature-icon" viewBox="0 0 32 32" aria-hidden="true"><rect x="3" y="8" width="26" height="17" rx="3" /><path d="M8 13h1m4 0h1m4 0h1m4 0h1M8 17h1m4 0h1m4 0h1m4 0h1M10 21h12" /></svg>
					<h3>Keep your hands on the keys</h3>
					<p>Use Tab and Return to move through screenplay elements, with character suggestions and shortcuts within reach.</p>
				</article>
			</div>
		</section>

		<section class="compatibility" id="compatibility" aria-labelledby="compatibility-title">
			<div class="section-width compatibility-layout">
				<div class="compatibility-copy">
					<p class="eyebrow">Bring your work with you</p>
					<h2 id="compatibility-title">Your screenplay.<br /><span>Your choice of format.</span></h2>
					<p>Start something new or continue an existing draft. Save a file you own, exchange scripts, and share pages when you’re ready.</p>
					<a class="text-link" href="/screenplay">Open a screenplay <span aria-hidden="true">›</span></a>
				</div>
				<div class="format-list">
					<div><span class="file-symbol">draft</span><div><h3>eDraft</h3><p>Save your screenplay in eDraft’s own document format.</p></div></div>
					<div><span class="file-symbol">fdx</span><div><h3>Final Draft</h3><p>Import and export supported FDX screenplay content.<sup>1</sup></p></div></div>
					<div><span class="file-symbol">txt</span><div><h3>Fountain</h3><p>Move your screenplay between tools as readable plain text.</p></div></div>
					<div><span class="file-symbol">pdf</span><div><h3>PDF</h3><p>Export formatted pages for reading and sharing.</p></div></div>
				</div>
			</div>
		</section>

		<section class="privacy section-width" id="privacy" aria-labelledby="privacy-title">
			<svg class="privacy-icon" viewBox="0 0 64 64" aria-hidden="true"><rect x="16" y="28" width="32" height="28" rx="6" /><path d="M22 28V18a10 10 0 0 1 20 0v10M32 39v7" /></svg>
			<p class="eyebrow">Private by design</p>
			<h2 id="privacy-title">Your work stays with you.</h2>
			<p class="privacy-intro">Your screenplay is personal. The browser editor works locally,<br class="desktop-break" /> without uploading your writing to an eDraft server.</p>
			<div class="privacy-points">
				<div><h3>No account to create.</h3><p>Open the editor and get straight to your screenplay.</p></div>
				<div><h3>No tracking in the editor.</h3><p>Your writing is processed on your device.</p></div>
				<div><h3>Files you control.</h3><p>Save a copy locally. Choose how and when to share it.</p></div>
			</div>
		</section>

		<section class="faq-section" id="questions" aria-labelledby="questions-title">
			<div class="faq-inner">
				<h2 id="questions-title">A few things to know.</h2>
				<div class="questions">
					{#each faqs as faq}
						<details><summary>{faq.question}<span aria-hidden="true">+</span></summary><p>{faq.answer}</p></details>
					{/each}
				</div>
			</div>
		</section>

		<section class="start-section">
			<img src={logo} alt="" width="76" height="76" loading="lazy" />
			<h2>Your next draft starts here.</h2>
			<p>Open eDraft and make yourself at home.</p>
			<a class="button" href="/screenplay">Start writing</a>
		</section>
	</main>

	<footer>
		<div class="footer-inner">
			<p class="footnote">1. FDX compatibility covers a defined subset of the format. Review import and export warnings, and retain original production files.</p>
			<div class="footer-row">
				<a class="brand" href="/"><img src={logo} alt="" width="28" height="28" /><span>eDraft</span></a>
				<p>© {new Date().getFullYear()} eDraft</p>
				<div class="footer-links"><a href="#privacy">Privacy</a><a href="https://github.com/Yasirdora/edraft" target="_blank" rel="noreferrer">Source code ↗</a><a href="https://github.com/Yasirdora/edraft/issues" target="_blank" rel="noreferrer">Support ↗</a></div>
			</div>
		</div>
	</footer>
</div>

<style>
	.website { color-scheme: light; background: #fff; color: #1d1d1f; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; -webkit-font-smoothing: antialiased; }
	.website :is(h1,h2,h3,p,figure) { margin: 0; }
	.website a { text-decoration: none; }
	.website button { font: inherit; cursor: pointer; }
	.website :is(a,button,summary):focus-visible { outline: 3px solid #0071e3; outline-offset: 5px; }
	.website section[id] { scroll-margin-top: 90px; }
	.skip-link { position: fixed; top: -80px; left: 20px; padding: 12px; background: #fff; z-index: 30; }
	.skip-link:focus { top: 10px; }
	header { position: sticky; top: 0; z-index: 20; background: rgb(255 255 255 / 94%); backdrop-filter: blur(20px); border-bottom: 1px solid #e8e8ed; }
	.navigation { max-width: 1120px; height: 72px; padding: 0 24px; margin: auto; display: flex; align-items: center; justify-content: space-between; gap: 30px; }
	.brand { display: inline-flex; align-items: center; gap: 7px; color: #1d1d1f; font-size: 23px; font-weight: 600; letter-spacing: -.8px; flex-shrink: 0; }
	.brand img { object-fit: contain; }
	.nav-links { display: flex; gap: 30px; margin-left: auto; margin-right: 20px; }
	.nav-links a { color: #515157; font-size: 13px; }
	.nav-links a:hover, .footer-links a:hover { color: #0066cc; }
	.nav-actions { display: flex; gap: 12px; align-items: center; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: white; padding: 13px 25px; font-size: 16px; line-height: 1.25; transition: background .18s; }
	.button:hover { background: #0062c4; }
	.button.small { font-size: 12px; padding: 9px 17px; }
	.menu-toggle { display: none; width: 34px; height: 34px; background: none; border: 0; padding: 5px; }
	.menu-toggle svg { fill: none; stroke: #1d1d1f; stroke-width: 1.5; }
	.hero { padding: 74px 24px 0; text-align: center; background: linear-gradient(#fff 65%, #f5f5f7); }
	.eyebrow { font-size: 17px; line-height: 1.4; font-weight: 600; }
	.hero h1 { font-size: clamp(42px, 5.7vw, 76px); font-weight: 650; letter-spacing: -.045em; line-height: 1.07; margin: 17px 0 23px; }
	.hero h1 span { color: #0879cf; }
	.hero-description { font-size: 21px; line-height: 1.5; letter-spacing: -.025em; color: #606066; }
	.hero-actions { display: flex; align-items: center; justify-content: center; gap: 29px; margin-top: 26px; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #0066cc; font-size: 17px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 25px; line-height: 1; }
	.hero .availability { font-size: 12px; color: #6e6e73; margin-top: 17px; }
	.hero .product { max-width: 1032px; margin: 57px auto 0; }
	.product-window { border: 1px solid #d6d8dc; border-radius: 15px; overflow: hidden; box-shadow: 0 18px 50px #18263715, 0 2px 8px #1826370a; background: white; }
	.window-title { height: 36px; background: #f7f7f9; border-bottom: 1px solid #e4e4e8; display: grid; grid-template-columns: 1fr 1fr 1fr; align-items: center; padding: 0 14px; font-size: 10px; font-weight: 500; color: #64646a; }
	.window-label { text-align: right; font-weight: 400; color: #85858b; }
	.window-dots { display: flex; gap: 6px; }
	.window-dots i { height: 8px; width: 8px; border-radius: 50%; background: #d5d5da; }
	.product-window > img { display: block; width: 100%; height: auto; }
	figcaption { display: flex; align-items: center; justify-content: center; gap: 24px; padding: 23px 0 30px; font-size: 12px; color: #6e6e73; }
	.appearance-switch { display: flex; padding: 3px; background: #e8e8ed; border-radius: 20px; }
	.appearance-switch button { background: transparent; border: 0; padding: 6px 15px; border-radius: 20px; color: #626269; font-size: 11px; }
	.appearance-switch button.active { background: white; color: #1d1d1f; box-shadow: 0 1px 4px #00000012; }
	.section-width { max-width: 1080px; margin: auto; padding-left: 24px; padding-right: 24px; }
	.features { padding-top: 110px; padding-bottom: 108px; }
	h2 { font-size: clamp(32px, 3.6vw, 48px); font-weight: 650; line-height: 1.13; letter-spacing: -.035em; }
	h2 span { color: #86868b; }
	.section-heading { max-width: 660px; }
	.section-heading .eyebrow, .compatibility-copy .eyebrow { color: #6e6e73; font-size: 14px; margin-bottom: 18px; }
	.section-heading > p:last-child { max-width: 545px; font-size: 18px; line-height: 1.6; color: #6e6e73; margin-top: 23px; }
	.feature-columns { display: grid; grid-template-columns: repeat(3, 1fr); gap: 52px; margin-top: 57px; }
	.feature-icon { width: 34px; height: 34px; fill: none; stroke: #1679cd; stroke-width: 1.5; stroke-linecap: round; stroke-linejoin: round; margin-bottom: 19px; }
	h3 { font-size: 18px; font-weight: 600; letter-spacing: -.025em; line-height: 1.35; }
	.feature-columns p { font-size: 15px; line-height: 1.65; color: #6e6e73; margin-top: 12px; }
	.compatibility { background: #f5f5f7; padding: 94px 0; }
	.compatibility-layout { display: grid; grid-template-columns: 1.1fr 1fr; gap: 92px; align-items: center; }
	.compatibility h2 { font-size: clamp(30px, 3.2vw, 42px); }
	.compatibility-copy > p:not(.eyebrow) { margin: 24px 0; color: #6e6e73; font-size: 17px; line-height: 1.6; }
	.format-list > div { display: flex; gap: 22px; align-items: center; padding: 24px 0; border-bottom: 1px solid #dedee3; }
	.format-list > div:first-child { padding-top: 0; }
	.format-list > div:last-child { border: 0; padding-bottom: 0; }
	.file-symbol { width: 46px; height: 58px; border: 1px solid #c8d4e0; background: #fff; color: #1477c9; display: grid; place-content: center; border-radius: 5px 12px 5px 5px; font-size: 11px; font-weight: 600; flex: 0 0 auto; }
	.format-list h3 { font-size: 17px; }
	.format-list p { color: #6e6e73; font-size: 14px; line-height: 1.5; margin-top: 5px; }
	.privacy { padding-top: 105px; padding-bottom: 105px; text-align: center; }
	.privacy-icon { width: 57px; height: 57px; fill: none; stroke: #1477c9; stroke-width: 2.5; stroke-linecap: round; margin-bottom: 21px; }
	.privacy .eyebrow { font-size: 14px; color: #6e6e73; margin-bottom: 16px; }
	.privacy-intro { color: #6e6e73; font-size: 19px; line-height: 1.55; margin-top: 24px !important; }
	.privacy-points { display: grid; grid-template-columns: repeat(3, 1fr); gap: 42px; text-align: left; margin-top: 60px; padding-top: 30px; border-top: 1px solid #e3e3e8; }
	.privacy-points h3 { font-size: 16px; }
	.privacy-points p { font-size: 14px; color: #6e6e73; line-height: 1.6; margin-top: 9px; }
	.faq-section { background: #f5f5f7; padding: 85px 24px; }
	.faq-inner { max-width: 790px; margin: auto; }
	.faq-inner h2 { text-align: center; font-size: 38px; margin-bottom: 38px; }
	details { border-bottom: 1px solid #dcdce2; }
	summary { list-style: none; display: flex; align-items: center; justify-content: space-between; gap: 20px; cursor: pointer; padding: 23px 0; font-size: 17px; font-weight: 500; }
	summary::-webkit-details-marker { display: none; }
	summary span { font-size: 24px; font-weight: 300; color: #6e6e73; transition: transform .2s; }
	details[open] summary span { transform: rotate(45deg); }
	details p { max-width: 700px; color: #626269; font-size: 15px; line-height: 1.7; padding: 0 30px 24px 0; }
	.start-section { text-align: center; padding: 88px 24px 98px; }
	.start-section img { object-fit: contain; margin-bottom: 22px; }
	.start-section h2 { font-size: 40px; }
	.start-section p { font-size: 18px; color: #6e6e73; margin: 19px 0 28px; }
	footer { background: #f5f5f7; padding: 27px 24px; }
	.footer-inner { max-width: 1032px; margin: auto; }
	.footnote { color: #75757b; font-size: 11px; line-height: 1.6; padding-bottom: 24px; border-bottom: 1px solid #dcdce2; }
	.footer-row { display: flex; align-items: center; gap: 28px; padding-top: 20px; }
	.footer-row .brand { font-size: 17px; }
	.footer-row p { font-size: 11px; color: #6e6e73; }
	.footer-links { margin-left: auto; display: flex; gap: 23px; font-size: 11px; }
	.footer-links a { color: #515157; }
	@media (max-width: 800px) {
		.nav-links { gap: 18px; margin-right: 0; }
		.feature-columns { gap: 25px; }
		.compatibility-layout { gap: 40px; }
		.hero { padding-top: 60px; }
		.hero-description { font-size: 18px; }
	}
	@media (max-width: 600px) {
		.navigation { height: 64px; padding: 0 18px; }
		.brand { font-size: 21px; }
		.nav-links { display: none; position: absolute; top: 64px; left: 0; right: 0; padding: 18px 24px 24px; background: white; border-bottom: 1px solid #e5e5eb; }
		.nav-links.expanded { display: flex; flex-direction: column; gap: 0; }
		.nav-links a { padding: 12px 0; font-size: 16px; }
		.menu-toggle { display: block; }
		.hero { padding: 47px 18px 0; }
		.eyebrow { font-size: 15px; }
		.hero h1 { font-size: clamp(30px, 7.9vw, 50px); margin: 18px 0; letter-spacing: -.04em; }
		.hero h1 br { display: none; }
		.hero-description { font-size: 17px; max-width: 340px; margin: auto; }
		.desktop-break { display: none; }
		.hero-actions { gap: 22px; }
		.button { font-size: 14px; padding: 12px 22px; }
		.text-link { font-size: 14px; }
		.hero .availability { font-size: 11px; }
		.hero .product { margin-top: 38px; }
		.product-window { border-radius: 8px; }
		.window-title { height: 27px; font-size: 8px; padding: 0 8px; }
		.window-label { display: none; }
		.window-dots { gap: 4px; }
		.window-dots i { width: 5px; height: 5px; }
		figcaption { gap: 15px; font-size: 10px; padding: 16px 0 23px; }
		.appearance-switch button { font-size: 10px; padding: 5px 11px; }
		.features { padding-top: 68px; padding-bottom: 68px; }
		.section-heading > p:last-child { font-size: 16px; }
		.feature-columns { grid-template-columns: 1fr; gap: 32px; margin-top: 35px; }
		.feature-icon { margin-bottom: 12px; }
		.feature-columns p { margin-top: 8px; }
		.compatibility { padding: 65px 0; }
		.compatibility-layout { grid-template-columns: 1fr; gap: 37px; }
		.compatibility-copy > p:not(.eyebrow) { font-size: 16px; }
		.privacy { padding-top: 65px; padding-bottom: 65px; }
		.privacy-intro { font-size: 16px; }
		.privacy-points { grid-template-columns: 1fr; gap: 26px; margin-top: 35px; }
		.faq-section { padding: 62px 24px; }
		.faq-inner h2 { font-size: 30px; text-align: left; margin-bottom: 20px; }
		summary { font-size: 15px; line-height: 1.4; }
		details p { font-size: 14px; }
		.start-section { padding: 64px 24px 72px; }
		.start-section h2 { font-size: 32px; }
		.start-section p { font-size: 16px; }
		.footer-row { flex-wrap: wrap; gap: 15px 22px; }
		.footer-links { width: 100%; margin: 0; padding-top: 5px; }
	}
	@media (prefers-reduced-motion: reduce) { .website * { transition: none !important; } }
</style>
