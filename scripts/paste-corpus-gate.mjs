#!/usr/bin/env node
/*
 * Paste-route corpus gate (RFC-ACT-BREAK phase 3).
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
const { importPlainText } = await import(pathToFileURL(enginePath).href);

/* A card line adopted as a speaker: the exact failure this phase removes. */
const CARD_CUE = /^(ACT\s|TEASER$|COLD OPEN$|END\s)/;

function panelOf(file) {
	const source = readFileSync(join(corpusDir, file), 'utf8');
	const { script, report } = importPlainText(source, { format: 'paste' });
	const dropped = report.warnings.reduce((n, w) => {
		const m = /^dropped (\d+) end-of-act card/.exec(w);
		return m ? n + Number(m[1]) : n;
	}, 0);
	return {
		actbreaks: script.elements.filter((e) => e.type === 'actbreak').map((e) => e.text),
		endCardsDropped: dropped,
		cardCues: report.characters.filter((name) => CARD_CUE.test(name)),
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
	}
}

if (failures > 0) {
	console.error(`\npaste-corpus gate: ${failures} check(s) failed`);
	process.exit(1);
}
console.log(`\n✓ paste-corpus gate: ${files.length} scripts hold`);
