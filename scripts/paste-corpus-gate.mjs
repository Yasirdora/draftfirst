#!/usr/bin/env node
/*
 * Paste-route corpus gate (RFC-ACT-BREAK phase 3; routing pack, step 1).
 *
 * Runs the engine's plain-text import — the same classifier the paste
 * route feeds — over the local scripts corpus and holds it to the facts
 * the corpus carries:
 *
 *   breaking-bad.txt  TEASER, then ACT ONE…ACT FOUR, as actbreaks; its
 *                     four closing cards dropped; none of the nine card
 *                     lines adopted as a speaker.
 *   every other file  zero actbreaks, zero end-of-act drops — measured
 *                     true of the corpus before this gate existed, so a
 *                     change here is a false positive introduced, named.
 *   every file        zero pagination artifacts stored — page numbers,
 *                     (MORE), CONTINUED are the printed page's furniture;
 *                     and the numbered scene headings and OMITTED cards
 *                     the corpus witnesses (gone-girl's 244 flanked
 *                     headings, corpus-6's 40 numbered and 13 omitted)
 *                     land as scenes with their numbers homed.
 *
 * The corpus is not committed (the scripts are not ours to ship), so the
 * golden facts are: scripts/fixtures/paste-corpus-golden.json. Without the
 * corpus directory the gate skips cleanly; with it, a disagreement is a
 * failure with the diff spelled out.
 *
 * Run: node scripts/paste-corpus-gate.mjs [--corpus=<dir>] [--engine=<dist/index.js>] [--write-golden]
 */
import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..');
const args = Object.fromEntries(
	process.argv.slice(2).map((a) => {
		const m = /^--([^=]+)(?:=(.*))?$/.exec(a);
		return m ? [m[1], m[2] ?? true] : [a, true];
	})
);

const corpusDir =
	args.corpus ??
	process.env.EDRAFT_SCRIPT_CORPUS ??
	'/Users/x/Documents/kimi/tasks/2026-09-09/17-57-54-2b2c55e4/scripts-corpus';
const enginePath = args.engine ?? join(repo, 'packages/edraft/dist/plaintext.js');
const goldenPath = join(repo, 'scripts/fixtures/paste-corpus-golden.json');

if (!existsSync(corpusDir)) {
	console.log(`paste-corpus gate: no corpus at ${corpusDir} — skipped (scripts are not committed)`);
	process.exit(0);
}
const { importPlainText, isPaginationArtifact } = await import(pathToFileURL(enginePath).href);

/* A card line adopted as a speaker: the exact failure this phase removes. */
const CARD_CUE = /^(ACT\s|TEASER$|COLD OPEN$|END\s)/;

function panelOf(file) {
	const source = readFileSync(join(corpusDir, file), 'utf8');
	const { script, report } = importPlainText(source, { format: 'paste' });
	const dropped = report.warnings.reduce((n, w) => {
		const m = /^dropped (\d+) end-of-act card/.exec(w);
		return m ? n + Number(m[1]) : n;
	}, 0);
	const stripped = report.warnings.reduce((n, w) => {
		const m = /^stripped (\d+) pagination artifact/.exec(w);
		return m ? n + Number(m[1]) : n;
	}, 0);
	return {
		actbreaks: script.elements.filter((e) => e.type === 'actbreak').map((e) => e.text),
		endCardsDropped: dropped,
		cardCues: report.characters.filter((name) => CARD_CUE.test(name)),
		artifactsStripped: stripped,
		artifactElements: script.elements.filter((e) => isPaginationArtifact(e.text)).length,
		numberedScenes: script.elements.filter((e) => e.sceneNumber !== undefined).length,
		omittedScenes: script.elements.filter((e) => e.type === 'scene' && e.text === 'OMITTED').length,
		/* the route's shape rule, pinned against the breaking-bad regression:
		   a speech never splits at its wrap into an action line */
		dialogueActionSplits: script.elements.filter(
			(e, i, all) => e.type === 'action' && i > 0 && all[i - 1].type === 'dialogue'
		).length,
		scenes: report.scenes /* informational — never gated */
	};
}

const files = readdirSync(corpusDir).filter((f) => f.endsWith('.txt')).sort();
if (files.length === 0) {
	console.log(`paste-corpus gate: no .txt scripts in ${corpusDir} — skipped`);
	process.exit(0);
}

const panels = Object.fromEntries(files.map((f) => [f, panelOf(f)]));

if (args['write-golden']) {
	mkdirSync(dirname(goldenPath), { recursive: true });
	writeFileSync(goldenPath, `${JSON.stringify(panels, null, 2)}\n`);
	console.log(`✓ golden recorded: ${goldenPath} (${files.length} scripts)`);
	process.exit(0);
}

const golden = existsSync(goldenPath)
	? JSON.parse(readFileSync(goldenPath, 'utf8'))
	: null;

let failures = 0;
function check(label, actual, expected) {
	const a = JSON.stringify(actual);
	const e = JSON.stringify(expected);
	if (a === e) {
		console.log(`  ✓ ${label}`);
	} else {
		failures++;
		console.log(`  ✗ ${label}\n      expected ${e}\n      actual   ${a}`);
	}
}

for (const [file, panel] of Object.entries(panels)) {
	console.log(file);
	if (file === 'breaking-bad.txt') {
		check('acts are TEASER, ACT ONE…ACT FOUR', panel.actbreaks, [
			'TEASER', 'ACT ONE', 'ACT TWO', 'ACT THREE', 'ACT FOUR'
		]);
		check('four closing cards dropped', panel.endCardsDropped, 4);
		check('no card line is a speaker', panel.cardCues, []);
	} else {
		check('no actbreaks', panel.actbreaks, []);
		check('no end-of-act drops', panel.endCardsDropped, 0);
	}
	if (golden?.[file]) {
		check(
			'matches the recorded golden (card cues)',
			panel.cardCues,
			golden[file].cardCues
		);
		check(
			'matches the recorded golden (artifacts stripped)',
			panel.artifactsStripped,
			golden[file].artifactsStripped
		);
		check(
			'matches the recorded golden (numbered scenes)',
			panel.numberedScenes,
			golden[file].numberedScenes
		);
		check(
			'matches the recorded golden (omitted scenes)',
			panel.omittedScenes,
			golden[file].omittedScenes
		);
	}
	check('no pagination artifact is stored', panel.artifactElements, 0);
	check('no speech splits at its wrap', panel.dialogueActionSplits, 0);
}

if (failures > 0) {
	console.error(`\npaste-corpus gate: ${failures} check(s) failed`);
	process.exit(1);
}
console.log(`\n✓ paste-corpus gate: ${files.length} scripts hold`);
