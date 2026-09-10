#!/usr/bin/env node
/*
 * Conformance corpus freshness.
 *
 * The golden masters in apple/eDraftEngine/Fixtures pin the Swift engine to
 * the TypeScript one — but only if they were generated from the CURRENT
 * engine. Until now nothing checked that, so an engine change could land
 * without its corpus update and the pin would silently describe yesterday's
 * behaviour. Regenerate from a freshly built dist (a stale dist would fake
 * freshness with old code) and compare against the checkout: any drift fails
 * the build, with the regenerated files left in the tree to review.
 *
 * Run: npm run check:conformance
 */
import { execFileSync } from 'node:child_process';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const fixtures = 'apple/eDraftEngine/Fixtures';

function run(command, args) {
	return execFileSync(command, args, { cwd: root, encoding: 'utf8' });
}

run('npm', ['run', '--silent', 'package:build']);
run(process.execPath, [join(root, 'scripts/engine-conformance-export.mjs')]);

/* Porcelain over plain diff: modified, added, and deleted masters all count
   as drift, and only status sees the whole set. */
const drift = run('git', ['status', '--porcelain', '--', fixtures]).trim();
if (drift) {
	console.error('✗ the conformance corpus is stale — the engine no longer produces what is committed:');
	console.error(drift.split('\n').map((line) => `    ${line}`).join('\n'));
	console.error('  the regenerated masters are in the working tree; the diff IS the behaviour change —');
	console.error('  review it like code, then commit it.');
	process.exit(1);
}
console.log('✓ conformance corpus is fresh');
