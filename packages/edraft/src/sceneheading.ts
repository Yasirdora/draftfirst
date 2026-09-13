/**
 * The numbered scene heading grammar (routing pack — corpus-witnessed).
 *
 * Production drafts print the scene number at the heading's left edge, and
 * some flank the heading with the same number at the right edge, a revision
 * asterisk on its tail: "2 EXT. NORTH CARTHAGE- MORNING 2", "3 EXT. NICK
 * DUNNE’S FRONT YARD- DAWN 3*" (gone-girl.txt, 244 witnesses), "15 INT.
 * HOLE." (corpus-6.txt, 40 witnesses). A scene added after distribution is
 * lettered against its neighbour and the letter is part of the number:
 * "128A EXT./INT. P~~BW MANSION - DUSK. 128A*" (corpus-6, 9 witnesses).
 * An omitted scene keeps its number and prints the OMITTED card, numbered
 * or bare: "113 OMITTED." (corpus-6), "OMITTED" (episode-101, whiplash) —
 * or short, in La La Land's hand: "OMIT" (lalaland ×45).
 *
 * The number is furniture with a home — the element's sceneNumber — and the
 * words are the writer's. One parser reads both shapes; the classifier's
 * scene arm consults it, and the screenplay builder applies it.
 */

/** A numbered heading, parsed: the number for the model, the words for the page. */
export interface NumberedSceneHeading {
	/** The leading number; absent on a bare OMITTED card. */
	number?: string;
	/** The heading without its furniture — and the OMITTED card without its period. */
	text: string;
}

const SCENE_INTRO = /^(INT\.?\/EXT\.?|INT\/EXT|EXT\.?\/INT\.?|EXT\/INT|I\/E|INT|EXT|EST)[.\s]/i;
const LEADING_NUMBER = /^(\d+[A-Z]?)\s+(.+)$/;
const FLANKING_NUMBER = /\s+(\d+[A-Z]?)\*?$/;
const OMITTED_CARD = /^(\d+\s+)?OMIT(?:TED)?\.?$/;

/**
 * Parse a numbered scene heading, or undefined when the line is not one.
 * The trailing number is stripped only when it equals the leading one —
 * that is the production convention every witness follows, and it is what
 * keeps "APARTMENT 4" a place rather than a coincidence. A bare OMITTED
 * card parses with no number; its trailing period is not meaning. The card
 * has one spelling in the model: La La Land's short "OMIT" and the
 * production's "OMITTED." are the same card, held in full.
 */
export function parseNumberedSceneHeading(text: string): NumberedSceneHeading | undefined {
	const omitted = OMITTED_CARD.exec(text);
	if (omitted) {
		const number = omitted[1]?.trim();
		return number ? { number, text: 'OMITTED' } : { text: 'OMITTED' };
	}

	const leading = LEADING_NUMBER.exec(text);
	if (!leading) return undefined;
	const number = leading[1] as string;
	let rest = leading[2] as string;
	if (!SCENE_INTRO.test(rest)) return undefined;

	/* the flanking number repeats the leading one, revisions marked — and
	   only then is it furniture */
	const flanking = FLANKING_NUMBER.exec(rest);
	if (flanking && flanking[1] === number) {
		rest = rest.slice(0, rest.length - flanking[0].length);
	}
	return { number, text: rest };
}
