<script lang="ts">
	/**
	 * The site's shared chrome: header, footer, and design tokens.
	 * Every page — home, Help Center, privacy, 404 — renders inside this
	 * layout, so the whole site speaks one language.
	 */
	import { onMount } from 'svelte';
	import { page } from '$app/state';

	const logo = '/edraft-mark.svg';

	let {
		eyebrow = '',
		links = [] as { href: string; label: string }[],
		footnote = '',
		children
	} = $props();

	let menuOpen = $state(false);
	let scrolled = $state(false);

	/* Exact match for top-level pages, prefix match for section hubs. */
	const isCurrent = (href: string) =>
		href === '/' ? page.url.pathname === '/' : page.url.pathname === href || page.url.pathname.startsWith(href + '/');

	onMount(() => {
		const onScroll = () => (scrolled = window.scrollY > 8);
		onScroll();
		window.addEventListener('scroll', onScroll, { passive: true });
		return () => window.removeEventListener('scroll', onScroll);
	});
</script>

<div class="website">
	<a class="skip-link" href="#main">Skip to content</a>
	<header class:scrolled>
		<nav class="navigation" aria-label="Main navigation">
			<a class="brand" href="/" aria-label="eDraft home"><img src={logo} alt="" width="30" height="30" /><span>eDraft</span></a>
			{#if eyebrow}<span class="mark">{eyebrow}</span>{/if}
			<div class="nav-links">
				{#each links as link}
					<a href={link.href} aria-current={isCurrent(link.href) ? 'page' : undefined}>{link.label}</a>
				{/each}
			</div>
			<div class="nav-actions">
				<a class="button small" href="/screenplay">Open eDraft</a>
				<button class="menu-toggle" aria-label={menuOpen ? 'Close navigation' : 'Open navigation'} aria-expanded={menuOpen} onclick={() => (menuOpen = !menuOpen)}>
					<svg viewBox="0 0 24 24" aria-hidden="true"><path d={menuOpen ? 'M6 6l12 12M6 18L18 6' : 'M4 8h16M4 16h16'} /></svg>
				</button>
			</div>
		</nav>
	</header>

	{#if links.length}
		<div class="menu-overlay" class:open={menuOpen} role="dialog" aria-modal="true" aria-label="Navigation">
			<nav class="menu-panel" aria-label="Mobile navigation">
				{#each links as link, i}
					<a
						href={link.href}
						class:current={isCurrent(link.href)}
						style:transition-delay={menuOpen ? `${60 + i * 45}ms` : '0ms'}
						onclick={() => (menuOpen = false)}
					>{link.label}</a
					>
				{/each}
			</nav>
			<p class="menu-foot">Screenwriting, beautifully simple.</p>
		</div>
	{/if}

	{@render children()}

	<footer>
		<div class="footer-inner">
			{#if footnote}
				<p class="footnote">{footnote}</p>
			{/if}
			<div class="footer-row">
				<div class="footer-brand">
					<a class="brand" href="/"><img src={logo} alt="" width="26" height="26" /><span>eDraft</span></a>
					<p>© {new Date().getFullYear()} eDraft</p>
				</div>
				<div class="footer-columns">
					<nav aria-label="Explore">
						<h3>Explore</h3>
						<a href="/features">Features</a>
						<a href="/features/writing">Writing</a>
						<a href="/features/story">Story</a>
						<a href="/features/formats">Formats</a>
					</nav>
					<nav aria-label="Support">
						<h3>Support</h3>
						<a href="/help">Help Center</a>
						<a href="/privacy">Privacy</a>
						<a href="https://github.com/Yasirdora/edraft" target="_blank" rel="noreferrer">Source code ↗</a>
						<a href="https://github.com/Yasirdora/edraft/issues" target="_blank" rel="noreferrer">Issues ↗</a>
					</nav>
				</div>
			</div>
		</div>
	</footer>
</div>

<style>
	.website { min-height: 100vh; display: flex; flex-direction: column; color-scheme: light; background: #fff; color: #1d1d1f; font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; -webkit-font-smoothing: antialiased; }
	.website :global(a) { text-decoration: none; }
	.website :global(button) { font: inherit; cursor: pointer; }
	.website :global(a:focus-visible), .website :global(button:focus-visible), .website :global(summary:focus-visible), .website :global(input:focus-visible) { outline: 3px solid #0071e3; outline-offset: 5px; }
	.website :global(section[id]) { scroll-margin-top: 80px; }
	.website :global(main) { flex: 1; }
	.skip-link { position: fixed; top: -80px; left: 20px; padding: 12px; background: #fff; z-index: 30; }
	.skip-link:focus { top: 10px; }
	header { position: sticky; top: 0; z-index: 20; background: rgb(255 255 255 / 86%); backdrop-filter: blur(20px) saturate(1.6); border-bottom: 1px solid #e8e8ed; transition: background .25s ease; }
	header.scrolled { background: rgb(255 255 255 / 94%); }
	.navigation { max-width: 1120px; height: 64px; padding: 0 24px; margin: auto; display: flex; align-items: center; gap: 18px; }
	.brand { display: inline-flex; align-items: center; gap: 8px; color: #1d1d1f; font-size: 21px; font-weight: 600; letter-spacing: -.8px; flex-shrink: 0; }
	.brand img { object-fit: contain; }
	.mark { font-size: 12px; font-weight: 600; letter-spacing: .08em; text-transform: uppercase; color: #86868b; border-left: 1px solid #d2d2d7; padding-left: 18px; }
	.nav-links { display: flex; gap: 30px; margin-left: auto; margin-right: 20px; }
	.nav-links a { position: relative; color: #515157; font-size: 13px; transition: color .18s; }
	.nav-links a:hover { color: #0066cc; }
	.nav-links a[aria-current='page'] { color: #1d1d1f; }
	.nav-links a[aria-current='page']::after { content: ''; position: absolute; left: 50%; bottom: -7px; width: 4px; height: 4px; border-radius: 50%; background: #0071e3; transform: translateX(-50%); }
	.nav-actions { display: flex; gap: 12px; align-items: center; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: white; padding: 13px 25px; font-size: 16px; line-height: 1.25; white-space: nowrap; transition: background .18s; }
	.button:hover { background: #0062c4; }
	.button.small { font-size: 12px; padding: 9px 17px; }
	.menu-toggle { display: none; width: 34px; height: 34px; background: none; border: 0; padding: 5px; }
	.menu-toggle svg { fill: none; stroke: #1d1d1f; stroke-width: 1.5; }

	/* Fullscreen mobile menu — staggered link rise, blur behind */
	.menu-overlay { position: fixed; inset: 0; z-index: 15; background: rgb(255 255 255 / 88%); backdrop-filter: blur(24px) saturate(1.6); display: flex; flex-direction: column; justify-content: center; padding: 0 34px; opacity: 0; visibility: hidden; transition: opacity .3s ease, visibility 0s linear .3s; }
	.menu-overlay.open { opacity: 1; visibility: visible; transition: opacity .3s ease; }
	.menu-panel { display: flex; flex-direction: column; }
	.menu-panel a { font-size: 30px; font-weight: 650; letter-spacing: -.03em; color: #1d1d1f; padding: 12px 0; opacity: 0; transform: translateY(18px); transition: opacity .35s ease, transform .35s ease, color .18s; }
	.menu-overlay.open .menu-panel a { opacity: 1; transform: none; }
	.menu-panel a:hover, .menu-panel a.current { color: #0066cc; }
	.menu-foot { margin-top: 44px; font-size: 13px; color: #86868b; opacity: 0; transition: opacity .4s ease .3s; }
	.menu-overlay.open .menu-foot { opacity: 1; }
	footer { background: #f5f5f7; padding: 48px 24px 40px; }
	.footer-inner { max-width: 1032px; margin: auto; }
	.footnote { color: #75757b; font-size: 11px; line-height: 1.6; padding-bottom: 28px; border-bottom: 1px solid #dcdce2; }
	.footer-row { display: flex; align-items: flex-start; gap: 28px; padding-top: 28px; }
	.footer-brand .brand { font-size: 17px; }
	.footer-brand p { font-size: 11px; color: #6e6e73; margin-top: 8px; }
	.footer-columns { margin-left: auto; display: flex; gap: 72px; }
	.footer-columns nav { display: flex; flex-direction: column; gap: 10px; }
	.footer-columns h3 { font-size: 11px; font-weight: 600; letter-spacing: .07em; text-transform: uppercase; color: #86868b; margin-bottom: 4px; }
	.footer-columns a { font-size: 13px; color: #515157; }
	.footer-columns a:hover { color: #0066cc; }
	@media (max-width: 600px) {
		.navigation { height: 60px; padding: 0 18px; gap: 12px; }
		.brand { font-size: 19px; }
		.mark { display: none; }
		.nav-links { display: none; }
		.menu-toggle { display: block; }
		.footer-row { flex-direction: column; gap: 28px; }
		.footer-columns { margin-left: 0; gap: 48px; }
	}
	@media (prefers-reduced-motion: reduce) { .website :global(*) { transition: none !important; } }
</style>
