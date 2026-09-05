#!/usr/bin/env node
/**
 * The layer boundaries, enforced.
 *
 * docs/SHARED-ARCHITECTURE.md draws three lines: the engine knows only
 * Foundation, the core knows no UI framework, and the shared panels know
 * SwiftUI but neither UIKit nor AppKit. Those lines are what let one
 * implementation serve an iPhone and a Mac — and a single stray import is
 * enough to quietly weld a layer to one platform, which nothing else in the
 * build would complain about until the day someone tries to compile it for
 * the other.
 *
 * Grep, not a compiler, because it has to run on any machine — including the
 * Linux box that runs CI, where no Swift toolchain exists.
 */
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join } from 'node:path';

const LAYERS = [
	{
		name: 'EDraftEngine',
		root: 'ios/eDraftEngine/Sources',
		banned: ['UIKit', 'AppKit', 'SwiftUI', 'EDraftCore', 'EDraftUI'],
		because: 'the rules of the craft are pure Foundation, and are pinned to the TypeScript engine'
	},
	{
		name: 'EDraftCore',
		root: 'ios/EDraftCore/Sources',
		banned: ['UIKit', 'AppKit', 'SwiftUI', 'EDraftUI'],
		because: 'the app’s mind must compile for any surface, and must not draw'
	},
	{
		name: 'EDraftUI',
		root: 'ios/EDraftUI/Sources',
		banned: ['UIKit', 'AppKit'],
		because: 'a shared panel that reaches for one platform’s views is no longer shared'
	},
	{
		name: 'EDraftMacSurface',
		root: 'ios/EDraftMacSurface/Sources',
		banned: ['UIKit'],
		because: 'the Mac surface is the one place AppKit belongs, and UIKit never does'
	}
];

/** Every .swift file under a directory. */
function swiftFiles(dir) {
	const out = [];
	for (const entry of readdirSync(dir)) {
		const path = join(dir, entry);
		if (statSync(path).isDirectory()) out.push(...swiftFiles(path));
		else if (entry.endsWith('.swift')) out.push(path);
	}
	return out;
}

const IMPORT = /^\s*(?:@\w+\s+)?import\s+([A-Za-z_][A-Za-z0-9_]*)/;

let failed = 0;
for (const layer of LAYERS) {
	let files;
	try {
		files = swiftFiles(layer.root);
	} catch {
		console.error(`✗ ${layer.name}: ${layer.root} is missing`);
		failed += 1;
		continue;
	}

	const breaches = [];
	for (const file of files) {
		const lines = readFileSync(file, 'utf8').split('\n');
		lines.forEach((line, index) => {
			const match = IMPORT.exec(line);
			if (match && layer.banned.includes(match[1])) {
				breaches.push(`${file}:${index + 1} imports ${match[1]}`);
			}
		});
	}

	if (breaches.length) {
		failed += breaches.length;
		console.error(`✗ ${layer.name} — ${layer.because}`);
		for (const breach of breaches) console.error(`    ${breach}`);
	} else {
		console.log(`✓ ${layer.name}: ${files.length} files, no forbidden imports`);
	}
}

if (failed) {
	console.error(`\n${failed} boundary violation(s). See docs/SHARED-ARCHITECTURE.md §2.`);
	process.exit(1);
}
console.log('\nLayer boundaries hold.');
