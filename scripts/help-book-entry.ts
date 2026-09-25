/**
 * Writes the Apple Help Book to build/help-book/eDraft.help and builds its
 * search index with hiutil when available. Run via scripts/build-help-book.mjs
 * (which compiles this entry with the repo's esbuild).
 */
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { buildBookFiles } from '../src/lib/help/helpbook';

const root = process.argv[2] ?? 'build/help-book/eDraft.help';

rmSync(root, { recursive: true, force: true });
const files = buildBookFiles();
for (const file of files) {
	const target = join(root, file.path);
	mkdirSync(dirname(target), { recursive: true });
	writeFileSync(target, file.contents);
}

const lproj = join(root, 'Contents/Resources/en.lproj');
const hiutil = '/usr/bin/hiutil';
if (existsSync(hiutil)) {
	// -C create, -a index anchors too, -f index file, -m minimum term length
	execFileSync(hiutil, ['-Caf', 'search.helpindex', '-m', '3', '.'], { cwd: lproj, stdio: 'inherit' });
	console.log('help-book: search index built (search.helpindex)');
} else {
	console.log('help-book: hiutil not found — search.helpindex skipped (Help menu search will index on demand)');
}

console.log(`help-book: wrote ${files.length} files to ${root}`);
