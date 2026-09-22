/**
 * Quiet scroll-reveal for marketing pages.
 * The initial hidden state only exists once the `.js` class is present,
 * so prerendered HTML is fully visible without JavaScript.
 */
export function setupReveal(): () => void {
	const root = document.querySelector('.website');
	root?.classList.add('js');

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
}
