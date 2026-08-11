/*
 * iOS bridge entry — bundled together with the engine dist into a single IIFE
 * that JavaScriptCore can evaluate (scripts/ios-engine-sync.mjs).
 *
 * Swift talks to exactly one global: __edraftCall(fn, argsArray) -> JSON string.
 * Arguments cross Swift→JS via JSValue bridging (NSString/NSArray/NSDictionary
 * become real JS strings/arrays/objects). Results cross JS→Swift as JSON text
 * so nothing depends on bridging quirks (undefined, prototypes, Maps).
 *
 * Only PUBLIC engine subpaths are imported — the same API the web app uses.
 */
import { parseFountain, serialiseFountain } from '../packages/draftfirst/dist/index.js';
import { paginate, estimateRuntime, printedLineCount } from '../packages/draftfirst/dist/layout.js';
import { predict, ghostSuffix } from '../packages/draftfirst/dist/editor.js';
import { tabCycle, tabSetFor, nextElement } from '../packages/draftfirst/dist/editor.js';

/* replaced by esbuild --define at bundle time */
const ENGINE_VERSION = __ENGINE_VERSION__; // eslint-disable-line no-undef

const api = {
	parseFountain,
	serialiseFountain,
	paginate,
	estimateRuntime,
	printedLineCount,
	predict,
	ghostSuffix,
	tabCycle,
	tabSetFor,
	nextElement
};

globalThis.__edraftVersion = ENGINE_VERSION;

globalThis.__edraftCall = function __edraftCall(fn, args) {
	const f = api[fn];
	if (typeof f !== 'function') {
		throw new Error('edraft: unknown engine function "' + fn + '"');
	}
	const list = Array.isArray(args) ? args : [];
	const result = f.apply(null, list);
	return JSON.stringify(result === undefined ? null : result);
};

/*
 * In-engine benchmark — identical code path in the jsc CLI and inside the app,
 * so Phase 0 Spike B measures the real thing on both. Timings exclude bridge
 * overhead by construction.
 */
globalThis.__edraftBench = function __edraftBench(sceneCount) {
	const scenes = Math.max(1, Math.floor(sceneCount) || 1);
	const parts = ['FADE IN:'];
	for (let i = 1; i <= scenes; i++) {
		/* Proper Fountain: blank lines separate blocks; a speech
		   (cue + parenthetical + dialogue) stays unbroken. */
		parts.push('');
		parts.push('INT. LOCATION ' + i + ' - ' + (i % 2 === 0 ? 'NIGHT' : 'DAY'));
		parts.push('');
		parts.push('Action line for scene ' + i + '. Something happens that matters to the story and pushes it forward.');
		parts.push('');
		parts.push('MARA');
		parts.push('(whispering)');
		parts.push('Dialogue for scene ' + i + ', beat one. We have to keep moving before they notice.');
		parts.push('');
		parts.push('DAVID');
		parts.push('Reply in scene ' + i + '. I hear you, and I agree completely.');
		if (i % 4 === 0) {
			parts.push('');
			parts.push('CUT TO:');
		}
	}
	const source = parts.join('\n');

	const t0 = Date.now();
	const script = parseFountain(source);
	const t1 = Date.now();
	const pages = paginate(script);
	const t2 = Date.now();

	/* 500 keystroke-scale predictions at the end of the document */
	const ctx = { type: 'character', text: 'MA', index: script.elements.length };
	let hits = 0;
	for (let k = 0; k < 500; k++) {
		ctx.text = 'MA' + 'R'.repeat(k % 3);
		hits += predict(script, ctx).length;
	}
	const t3 = Date.now();

	return JSON.stringify({
		elements: script.elements.length,
		pages: pages.length,
		runtime: estimateRuntime(pages),
		printedLines: printedLineCount(pages),
		parseMs: t1 - t0,
		paginateMs: t2 - t1,
		predict500Ms: t3 - t2,
		predictHits: hits
	});
};
