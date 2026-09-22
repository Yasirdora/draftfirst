<script lang="ts">
	/**
	 * The designed 404. Prerendered to build/404.html, which static hosts
	 * (including Cloudflare Pages) serve for unmatched paths.
	 */
	import SiteLayout from '$lib/site/SiteLayout.svelte';
</script>

<svelte:head>
	<title>Page not found — eDraft</title>
	<meta name="robots" content="noindex" />
</svelte:head>

<SiteLayout
	links={[
		{ href: '/help', label: 'Help Center' },
		{ href: '/privacy', label: 'Privacy' }
	]}
>
	<main id="main">
		<section class="lost">
			<p class="label">404</p>
			<h1>This page isn’t in the script.</h1>
			<p class="copy">The page you’re looking for doesn’t exist or has moved — but your screenplay is waiting.</p>
			<div class="actions">
				<a class="button" href="/">eDraft home</a>
				<a class="text-link" href="/help">Help Center <span aria-hidden="true">›</span></a>
			</div>
		</section>
	</main>
</SiteLayout>

<style>
	.lost { max-width: 640px; margin: auto; padding: 140px 24px 160px; text-align: center; }
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	h1 { font-size: clamp(34px, 5vw, 56px); font-weight: 650; letter-spacing: -.045em; line-height: 1.08; margin-top: 20px; }
	.copy { font-size: 17px; line-height: 1.6; color: #6e6e73; margin-top: 18px; }
	.actions { display: flex; align-items: center; justify-content: center; gap: 26px; margin-top: 34px; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: white; padding: 13px 26px; font-size: 15px; transition: background .18s; }
	.button:hover { background: #0062c4; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #0066cc; font-size: 15px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 22px; line-height: 1; }
	@media (max-width: 600px) {
		.lost { padding: 96px 18px 112px; }
		.actions { flex-direction: column; gap: 18px; }
	}
</style>
