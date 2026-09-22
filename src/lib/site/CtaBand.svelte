<script lang="ts">
	/** The closing call-to-action shared by all feature pages. */
	let {
		title = 'Your next draft starts here.',
		text = 'Open eDraft and make yourself at home.'
	} = $props();
</script>

<section class="cta">
	<img src="/edraft-mark.svg" alt="" width="64" height="64" loading="lazy" />
	<h2>{title}</h2>
	<p>{text}</p>
	<a class="button" href="/screenplay">Start writing</a>
</section>

<style>
	.cta { text-align: center; padding: 104px 24px 112px; }
	img { object-fit: contain; margin-bottom: 22px; }
	h2 { font-size: clamp(28px, 3.2vw, 42px); font-weight: 650; letter-spacing: -.04em; line-height: 1.1; }
	p { font-size: 17px; color: #6e6e73; margin: 16px 0 28px; }
	.button { display: inline-flex; align-items: center; justify-content: center; border-radius: 28px; background: #0071e3; color: #fff; padding: 13px 25px; font-size: 16px; line-height: 1.25; white-space: nowrap; transition: background .18s; }
	.button:hover { background: #0062c4; }
	@media (max-width: 600px) {
		.cta { padding: 72px 24px 80px; }
		.button { font-size: 14px; padding: 12px 22px; }
	}
</style>
