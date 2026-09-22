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

	onMount(() => setupReveal());
</script>

<svelte:head>
	<title>Privacy — eDraft Features</title>
	<meta name="description" content="eDraft is private by design: no account, no analytics, no server. Your screenplay is processed on your device and stored where you choose." />
</svelte:head>

<SiteLayout eyebrow="Features · Privacy" links={navLinks}>
	<main id="main">
		<PageHero
			eyebrow="Privacy"
			title="Your work"
			accent="stays with you."
			intro="A screenplay is written before it is shared — sometimes instead of being shared. eDraft is built so that decision is always yours."
			back={{ href: '/features', label: 'Features' }}
		/>

		<Split
			eyebrow="Local first"
			title="No account."
			accent="No server. No tracking."
			intro="Open the editor and you are already writing. There is nothing to sign into, because there is nothing on our side to sign into — no eDraft server ever receives your screenplay."
			points={[
				{ title: '“Data Not Collected.”', text: 'That is eDraft’s entire privacy disclosure on the App Store. No analytics, no crash-reporting services, no third-party SDKs, no ad identifiers.' },
				{ title: 'The working copy is yours.', text: 'The browser editor keeps its working copy in local storage on your device. Save a file regularly and you hold the only copy that matters.' }
			]}
		>
			<div class="badge-card" aria-label="App Store privacy summary">
				<span class="badge-label">App Store privacy</span>
				<span class="badge-value">Data Not<br />Collected</span>
				<span class="badge-sub">The whole disclosure. There is no “see more.”</span>
			</div>
		</Split>

		<Split
			theme="alt"
			flip
			eyebrow="Sync"
			title="iCloud is the"
			accent="only cloud."
			intro="In the eDraft app for Mac, iPhone, and iPad, sync between your devices runs through your own iCloud account — operated by Apple, governed by your Apple ID."
			points={[
				{ title: 'Your container, your key.', text: 'eDraft reads and writes only inside its own iCloud Documents container — icloud.xyz.edraft. The sync is yours, end to end.' },
				{ title: 'We never see a copy.', text: 'eDraft does not receive, store, or read your iCloud files. There is no eDraft copy of your screenplay — anywhere.' }
			]}
		>
			<div class="sync-card" aria-label="iCloud sync diagram">
				<div class="device">
					<span class="device-name">Mac</span>
					<span class="device-file">the-empty-cinema.draft</span>
				</div>
				<div class="sync-path">
					<span class="sync-line"></span>
					<span class="sync-label">your iCloud · <code>icloud.xyz.edraft</code></span>
					<span class="sync-line"></span>
				</div>
				<div class="device">
					<span class="device-name">iPhone</span>
					<span class="device-file">the-empty-cinema.draft</span>
				</div>
			</div>
		</Split>

		<Split
			theme="dark"
			eyebrow="Camera scanning"
			title="Paper in, and it"
			accent="never leaves."
			intro="On iPhone and iPad, eDraft can photograph paper pages to bring them into your draft. The scans are processed entirely on the device — and are never uploaded anywhere."
			points={[
				{ title: 'On-device, by default.', text: 'Scanning runs locally on your iPhone or iPad. Nothing is sent for “processing” because there is no processing to send.' },
				{ title: 'Your call, both times.', text: 'You choose whether to use the feature and whether to grant camera access. Either way, the app works.' }
			]}
		>
			<div class="scan-card" aria-label="Camera scanning example">
				<div class="scan-frame">
					<span class="scan-corner tl"></span><span class="scan-corner tr"></span>
					<span class="scan-corner bl"></span><span class="scan-corner br"></span>
					<span class="scan-text">INT. THE REX CINEMA…</span>
				</div>
				<span class="scan-note">Processed on this device · never uploaded</span>
			</div>
		</Split>

		<section class="policy reveal">
			<p class="label">The fine print, in plain sight</p>
			<h2>Read the policy.<br /><span>It’s one honest page.</span></h2>
			<p class="policy-intro">No lawyerspeak, no dark patterns — a short statement of what eDraft does not do with your work.</p>
			<a class="text-link" href="/privacy">Read the privacy policy <span aria-hidden="true">›</span></a>
		</section>

		<CtaBand />
		<Pager href="/features" kicker="Back to" title="All features" />
	</main>
</SiteLayout>

<style>
	:global(.website.js .reveal) { opacity: 0; transform: translateY(20px); transition: opacity .7s ease, transform .7s ease; }
	:global(.website.js .reveal.in) { opacity: 1; transform: none; }

	/* App Store privacy badge */
	.badge-card { background: #fff; border: 1px solid #e6e6ea; border-radius: 18px; padding: 40px 36px; width: 100%; max-width: 400px; margin: auto; box-shadow: 0 24px 60px #18263712; display: flex; flex-direction: column; gap: 14px; }
	.badge-label { font-size: 11px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.badge-value { font-size: clamp(28px, 3vw, 36px); font-weight: 650; letter-spacing: -.04em; line-height: 1.1; color: #1d1d1f; }
	.badge-sub { font-size: 13px; line-height: 1.55; color: #6e6e73; }

	/* iCloud sync diagram */
	.sync-card { background: #fff; border: 1px solid #e6e6ea; border-radius: 18px; padding: 34px 30px; width: 100%; max-width: 400px; margin: auto; box-shadow: 0 24px 60px #18263712; display: flex; flex-direction: column; gap: 18px; }
	.device { display: flex; flex-direction: column; gap: 4px; background: #f5f5f7; border-radius: 12px; padding: 16px 18px; }
	.device-name { font-size: 15px; font-weight: 600; letter-spacing: -.02em; }
	.device-file { font-size: 12px; font-family: ui-monospace, 'SF Mono', Menlo, monospace; color: #6e6e73; }
	.sync-path { display: flex; align-items: center; gap: 12px; }
	.sync-line { flex: 1; height: 1px; background: #d2d2d7; }
	.sync-label { font-size: 11px; color: #86868b; white-space: nowrap; }
	code { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: .92em; background: #f0f0f3; border-radius: 4px; padding: 1px 5px; }
	.sync-label code { background: transparent; padding: 0; }

	/* Camera scanning card */
	.scan-card { display: flex; flex-direction: column; align-items: center; gap: 18px; }
	.scan-frame { position: relative; width: 100%; max-width: 380px; border: 1px solid #3a3a3f; border-radius: 14px; background: #161617; padding: 56px 30px; text-align: center; }
	.scan-corner { position: absolute; width: 18px; height: 18px; border: 2px solid #f5f5f7; }
	.scan-corner.tl { top: 12px; left: 12px; border-right: 0; border-bottom: 0; }
	.scan-corner.tr { top: 12px; right: 12px; border-left: 0; border-bottom: 0; }
	.scan-corner.bl { bottom: 12px; left: 12px; border-right: 0; border-top: 0; }
	.scan-corner.br { bottom: 12px; right: 12px; border-left: 0; border-top: 0; }
	.scan-text { font-family: 'Courier New', ui-monospace, Menlo, monospace; font-size: 13px; color: #d2d2d7; }
	.scan-note { font-size: 12px; color: #86868b; }

	/* Policy band */
	.policy { max-width: 720px; margin: auto; padding: 112px 24px 116px; text-align: center; }
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	h2 { font-size: clamp(30px, 3.4vw, 46px); font-weight: 650; line-height: 1.1; letter-spacing: -.04em; margin-top: 18px; }
	h2 span { color: #86868b; }
	.policy-intro { font-size: 17px; line-height: 1.6; color: #6e6e73; margin: 20px auto 28px; max-width: 520px; }
	.text-link { display: inline-flex; align-items: center; gap: 8px; color: #0066cc; font-size: 17px; }
	.text-link:hover { text-decoration: underline; }
	.text-link span { font-size: 25px; line-height: 1; }

	@media (max-width: 600px) {
		.policy { padding: 76px 24px 84px; }
	}
</style>
