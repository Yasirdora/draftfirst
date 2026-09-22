<script lang="ts">
	/**
	 * The eDraft privacy policy as a first-class page — same chrome and
	 * type scale as the rest of the site. Content mirrors
	 * docs/privacy-policy.html; the support email stays the launch token.
	 */
	import SiteLayout from '$lib/site/SiteLayout.svelte';
</script>

<svelte:head>
	<title>Privacy — eDraft</title>
	<meta name="description" content="The eDraft privacy policy. No accounts, no analytics, no data collection. Your screenplays are files you own." />
</svelte:head>

<SiteLayout
	eyebrow="Privacy"
	links={[
		{ href: '/', label: 'eDraft home' },
		{ href: '/help', label: 'Help Center' }
	]}
>
	<main id="main">
		<article class="policy">
			<p class="label">Privacy</p>
			<h1>Privacy Policy</h1>
			<p class="updated">Last updated: September 19, 2026</p>

			<h2>Our approach</h2>
			<p>eDraft is a screenwriting app for Mac, iPhone, and iPad. It is designed to keep your work yours. We do not collect personal data through eDraft. There are no accounts, logins, registrations, or email collection. We do not use analytics, crash-reporting services, third-party SDKs, advertising, ad identifiers, or tracking across apps or websites.</p>

			<h2>Data not collected</h2>
			<p>eDraft’s App Store privacy disclosure is <strong>Data Not Collected</strong>. eDraft does not collect, retain, or transmit information about you, your use of the app, or the content you create in it.</p>

			<h2>What eDraft stores</h2>
			<p>Your screenplays are plain-text files that you own. They are stored on your device or in your personal iCloud Drive. eDraft does not operate a server or backend, and the developer never receives, stores, or can read your scripts, notes, or files. We do not share or sell your data—ever.</p>

			<h2>iCloud</h2>
			<p>When you use iCloud, eDraft reads and writes only inside its own iCloud Documents container, named <code>iCloud.xyz.edraft</code>. Sync between your devices happens entirely through your own iCloud account, operated by Apple. Your access to iCloud and the handling of information by Apple are governed by your Apple ID and Apple’s iCloud terms. eDraft does not receive a copy of your iCloud files.</p>

			<h2>Camera scanning</h2>
			<p>On iPhone and iPad, eDraft offers an optional feature that photographs paper pages for scanning. Scans are processed entirely on your device and are never uploaded anywhere. You choose whether to use this feature and whether to grant camera access.</p>

			<h2>Children’s privacy</h2>
			<p>eDraft does not knowingly collect personal information from children or from anyone else. Because eDraft has no accounts, analytics, advertising, or data-collection systems, it has no child-specific personal information to retain or share.</p>

			<h2>Changes to this policy</h2>
			<p>If our privacy practices change, we will update this policy and its “Last updated” date. The current version will describe the practices that apply to eDraft.</p>

			<h2>Contact</h2>
			<p>If you have a privacy question about eDraft, contact us at <a href="mailto:[SUPPORT EMAIL]">[SUPPORT EMAIL]</a>.</p>
		</article>
	</main>
</SiteLayout>

<style>
	.label { font-size: 12px; font-weight: 600; letter-spacing: .09em; text-transform: uppercase; color: #86868b; }
	.policy { max-width: 720px; margin: auto; padding: 88px 24px 112px; }
	h1 { font-size: clamp(36px, 5vw, 60px); font-weight: 650; letter-spacing: -.045em; line-height: 1.08; margin-top: 20px; }
	.updated { font-size: 14px; color: #6e6e73; margin-top: 16px; padding-bottom: 36px; border-bottom: 1px solid #e3e3e8; }
	h2 { font-size: 24px; font-weight: 650; letter-spacing: -.03em; line-height: 1.2; margin-top: 44px; }
	p { font-size: 16px; line-height: 1.75; color: #3a3a3f; margin-top: 14px; max-width: 680px; }
	code { font-family: ui-monospace, 'SF Mono', Menlo, monospace; font-size: 13.5px; background: #f5f5f7; border: 1px solid #e6e6eb; border-radius: 6px; padding: 2px 7px; }
	a { color: #0066cc; }
	a:hover { text-decoration: underline; }
	@media (max-width: 600px) {
		.policy { padding: 56px 18px 80px; }
		h2 { font-size: 21px; }
	}
</style>
