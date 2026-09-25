/**
 * Builds the Apple Help Book from src/lib/help/articles.ts.
 *
 * The generator itself is TypeScript (it shares the Help Center's data and
 * is covered by vitest); this runner compiles the entry with the repo's own
 * esbuild — already a devDependency — into a temp file and runs it. No new
 * dependency, no build output in the repo (build/ is gitignored).
 *
 *   npm run build:help-book            # writes build/help-book/eDraft.help
 */
import { execFileSync } from 'node:child_process';
import { mkdtempSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const repo = join(dirname(fileURLToPath(import.meta.url)), '..');
const esbuild = join(repo, 'node_modules', '.bin', 'esbuild');
const bundle = join(mkdtempSync(join(tmpdir(), 'edraft-help-book-')), 'entry.mjs');

execFileSync(
	esbuild,
	[
		'scripts/help-book-entry.ts',
		'--bundle',
		'--platform=node',
		'--format=esm',
		'--packages=external',
		`--outfile=${bundle}`
	],
	{ cwd: repo, stdio: 'inherit' }
);

process.chdir(repo);
await import(pathToFileURL(bundle).href);
