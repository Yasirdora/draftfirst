#!/usr/bin/env node
/*
 * Builds the iOS engine bundle.
 *
 *   tsc (packages/draftfirst/dist) → esbuild IIFE (scripts/ios-bridge-entry.js)
 *   → ios/eDraft/Resources/edraft-engine.js + ENGINE-CHECKSUM.txt
 *
 * The artifact is then verified inside the REAL JavaScriptCore runtime
 * (macOS ships the jsc CLI) so a broken bundle can never reach the app
 * unnoticed. Run: npm run ios:engine
 */
import { execFileSync, execSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const pkgPath = join(root, 'packages/draftfirst/package.json');
const version = JSON.parse(readFileSync(pkgPath, 'utf8')).version;
const outDir = join(root, 'ios/eDraft/Resources');
const outFile = join(outDir, 'edraft-engine.js');
const esbuild = join(root, 'node_modules/.bin/esbuild');

console.log(`▸ building @draftfirst/core ${version} (tsc)`);
execSync('npm run build --workspace=@draftfirst/core', { cwd: root, stdio: 'inherit' });

if (!existsSync(esbuild)) {
	console.error('✗ esbuild not found — run `npm install` first');
	process.exit(1);
}

console.log('▸ bundling engine for JavaScriptCore (esbuild IIFE, es2022, minified)');
mkdirSync(outDir, { recursive: true });
execFileSync(esbuild, [
	join(root, 'scripts/ios-bridge-entry.js'),
	'--bundle',
	'--format=iife',
	'--target=es2022',
	'--minify',
	`--define:__ENGINE_VERSION__="${version}"`,
	`--outfile=${outFile}`
], { stdio: 'inherit' });

const bytes = readFileSync(outFile);
const sha = createHash('sha256').update(bytes).digest('hex');
writeFileSync(join(outDir, 'ENGINE-CHECKSUM.txt'), [
	`engine: @draftfirst/core ${version}`,
	'file: edraft-engine.js',
	`bytes: ${bytes.length}`,
	`sha256: ${sha}`,
	`built: ${new Date().toISOString()}`,
	''
].join('\n'));
console.log(`▸ wrote ios/eDraft/Resources/edraft-engine.js (${bytes.length} bytes, sha256 ${sha.slice(0, 12)}…)`);

const jsc = '/System/Library/Frameworks/JavaScriptCore.framework/Versions/Current/Helpers/jsc';
if (existsSync(jsc)) {
	console.log('▸ verifying the bundle inside real JavaScriptCore (jsc CLI)');
	execFileSync(jsc, [outFile, join(root, 'scripts/ios-jsc-smoke.js')], { stdio: 'inherit' });
	console.log('✓ iOS engine bundle verified — safe to embed');
} else {
	console.warn('! jsc CLI not found on this machine — skipped on-engine verification');
}
