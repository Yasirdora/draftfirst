<script lang="ts">
	import { onMount } from 'svelte';
	import SiteLayout from '$lib/site/SiteLayout.svelte';
	import PageHero from '$lib/site/PageHero.svelte';
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

	const features = [
		{
			href: '/features/writing',
			label: 'Writing',
			title: 'Formatting that disappears.',
			text: 'Scene headings, action, cues, and dialogue fall into place as you type. Tab and Return are the only lesson.',
			icon: 'M12 20h9M16.5 3.5a2.1 2.1 0 013 3L7 19l-4 1 1-4L16.5 3.5z'
		},
		{
			href: '/features/story',
			label: 'Story',
			title: 'The whole story, beside the page.',
			text: 'Scenes, cast, and notes live in a quiet side panel — close enough to check, far enough to ignore.',
			icon: 'M4 6h16M4 12h16M4 18h10'
		},
		{
			href: '/features/formats',
			label: 'Formats',
			title: 'Bring your work with you.',
			text: 'Open Final Draft and Fountain files, and export PDF, FDX, or plain text. Your work is never locked in.',
			icon: 'M4 7a2 2 0 012-2h4l2 2h6a2 2 0 012 2v8a2 2 0 01-2 2H6a2 2 0 01-2-2V7z'
		},
		{
			href: '/features/privacy',
			label: 'Privacy',
			title: 'Private by design.',
			text: 'No account, no server, no tracking. Your screenplay is processed on your device and saved where you choose.',
			icon: 'M7 11V8a5 5 0 0110 0v3M6 11h12v9H6v-9z'
		}
	];

	const compareRows: { label: string; edraft: string; fd: string; arc: string }[] = [
		{ label: 'Price', edraft: 'Free', fd: '$199.99, one-time', arc: 'Free tier, then $99/yr' },
		{ label: 'Account', edraft: 'None required', fd: 'Activation required', arc: 'Email sign-in' },
		{ label: 'Scripts', edraft: 'Unlimited', fd: 'Unlimited', arc: '2 on the free tier' },
		{ label: 'PDF export', edraft: 'No watermark', fd: 'Included', arc: 'Watermarked on free' },
		{ label: 'Where work lives', edraft: 'On your device', fd: 'Your computer', arc: 'Their cloud' },
		{ label: 'Your file', edraft: 'Plain text you own', fd: 'Proprietary .fdx', arc: 'Cloud documents' }
	];

	onMount(() => setupReveal());
</script>

<svelte:head>
	<title>Features — eDraft</title>
	<meta name="description" content="Automatic screenplay formatting, scene navigation, portable files, and privacy by design. Every eDraft feature, in detail." />
</svelte:head>

<SiteLayout eyebrow="Features" links={navLinks}>
	<main id="main">
		<PageHero
			eyebrow="Features"
			title="Everything a screenplay asks for."
			accent="Nothing it doesn't."
			intro="eDraft keeps the craft and removes the apparatus — no account, no subscription, no locked-in files. Four ideas carry the whole app."
		>
			<div class="hero-actions">
				<a class="button" href="/screenplay">Start writing</a>
				<a class="text-link" href="/features/writing">Begin with Writing <span aria-hidden="true">›</span></a>
			</div>
		</PageHero>

		<section class="grid-band" aria-label="Feature pages">
			<div class="grid">
				{#each features as feature, i}
					<a class="card reveal" href={feature.href}>
						<span class="card-icon" aria-hidden="true"><svg viewBox="0 0 24 24"><path d={feature.icon} /></svg></span>
						<span class="card-label">{String(i + 1).padStart(2, '0')} — {feature.label}</span>
						<span class="card-title">{feature.title}</span>
						<span class="card-text">{feature.text}</span>
						<span class="card-link">Learn more <span class="card-arrow" aria-hidden="true">›</span></span>
					</a>
				{/each}
			</div>
		</section>

		<section class="compare" aria-labelledby="compare-title">
			<div class="compare-inner">
				<p class="label">The essentials, compared</p>
				<h2 id="compare-title">What a screenwriting tool owes you.</h2>
				<p class="compare-intro">The incumbents are powerful — and priced, gated, and cloud-bound to match. eDraft starts from the writer's side of the desk.</p>
				<div class="table-wrap reveal">
					<table>
						<thead>
							<tr><th scope="col"><span class="sr">Capability</span></th><th scope="col" class="us">eDraft</th><th scope="col">Final Draft 13</th><th scope="col">Arc Studio</th></tr>
						</thead>
						<tbody>
							{#each compareRows as row}
								<tr>
									<th scope="row">{row.label}</th>
									<td class="us">{row.edraft}</td>
									<td>{row.fd}</td>
									<td>{row.arc}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
				<p class="footnote">Competitor details from their public pricing and feature pages, September 2026. Verify current terms on their sites.</p>
			</div>
		</section>

		<CtaBand />
		<Pager href="/features/writing" title="Writing" />
	</main>
</SiteLayout>

<style>
	.hero-actions { display: flex; align-items: center; justify-content: center; gap: 29px; margin-top: 34px; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: #fff; padding: 13px 25px; font-size: 16px; line-height: 1.25; white-space: nowrap; transition: background .18s; }
	.button:hover { background: #0062c4; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #0066cc; font-size: 17px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 25px; line-height: 1; }

	/* Scroll reveal — hidden state exists only when JS does */
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }

	/* Feature grid */
	.grid-band { background: #f5f5f7; padding: 104px 0 112px; }
	.grid { max-width: 1120px; margin: auto; padding: 0 24px; display: grid; grid-template-columns: 1fr 1fr; gap: 20px; }
	.card { position: relative; display: flex; flex-direction: column; background: #fff; border-radius: 22px; padding: 44px 40px 40px; min-height: 320px; color: inherit; transition: transform .3s cubic-bezier(.2, .8, .2, 1), box-shadow .3s ease; }
	.card:hover { transform: translateY(-6px); box-shadow: 0 32px 80px #1826371a; }
	.card-icon { display: inline-flex; align-items: center; justify-content: center; width: 46px; height: 46px; border-radius: 13px; background: linear-gradient(135deg, #e8f1ff, #f0ecff); margin-bottom: 26px; }
	.card-icon svg { width: 22px; height: 22px; fill: none; stroke: #0879cf; stroke-width: 1.7; stroke-linecap: round; stroke-linejoin: round; }
	.card-label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.card-title { display: block; font-size: clamp(24px, 2.4vw, 32px); font-weight: 650; letter-spacing: -.035em; line-height: 1.15; margin-top: 14px; }
	.card-text { display: block; font-size: 15px; line-height: 1.6; color: #6e6e73; margin-top: 14px; }
	.card-link { margin-top: auto; padding-top: 24px; font-size: 15px; color: #0066cc; }
	.card:hover .card-link { text-decoration: underline; }
	.card-arrow { display: inline-block; transition: transform .2s ease; }
	.card:hover .card-arrow { transform: translateX(4px); }

	/* Comparison */
	.compare { padding: 112px 0 120px; }
	.compare-inner { max-width: 980px; margin: auto; padding: 0 24px; }
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	h2 { font-size: clamp(34px, 4vw, 56px); font-weight: 650; line-height: 1.08; letter-spacing: -.04em; margin-top: 18px; }
	.compare-intro { font-size: 17px; line-height: 1.6; color: #6e6e73; margin-top: 20px; max-width: 620px; }
	.table-wrap { margin-top: 48px; overflow-x: auto; }
	table { width: 100%; border-collapse: collapse; min-width: 640px; }
	th, td { text-align: left; font-size: 14px; padding: 16px 18px; border-bottom: 1px solid #e3e3e8; vertical-align: top; }
	thead th { font-size: 15px; font-weight: 650; letter-spacing: -.01em; border-bottom: 1px solid #d2d2d7; }
	tbody th { font-weight: 500; color: #1d1d1f; white-space: nowrap; }
	td { color: #6e6e73; }
	.us { color: #1d1d1f; font-weight: 500; background: #f5f5f7; }
	thead .us { background: transparent; color: #0879cf; }
	.sr { position: absolute; width: 1px; height: 1px; overflow: hidden; clip: rect(0 0 0 0); }
	.footnote { font-size: 12px; color: #86868b; margin-top: 20px; line-height: 1.6; }

	@media (max-width: 900px) {
		.grid { grid-template-columns: 1fr; }
		.card { min-height: 0; }
	}
	@media (max-width: 600px) {
		.hero-actions { gap: 20px; }
		.button { font-size: 14px; padding: 12px 22px; }
		.text-link { font-size: 14px; }
		.grid-band { padding: 64px 0 72px; }
		.card { padding: 32px 26px; }
		.compare { padding: 76px 0 84px; }
	}
</style>
