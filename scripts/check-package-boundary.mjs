import assert from 'node:assert/strict';
import { readdir, readFile } from 'node:fs/promises';
import { dirname, extname, join, relative } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const packageDirectory = join(repository, 'packages', 'edraft');
const sourceDirectory = join(packageDirectory, 'src');

async function filesBelow(directory) {
	const entries = await readdir(directory, { withFileTypes: true });
	const files = await Promise.all(
		entries.map((entry) =>
			entry.isDirectory() ? filesBelow(join(directory, entry.name)) : [join(directory, entry.name)]
		)
	);
	return files.flat();
}

const sourceFiles = (await filesBelow(sourceDirectory)).filter(
	(file) => extname(file) === '.ts' && !file.endsWith('.test.ts')
);
const externalImports = [];
for (const file of sourceFiles) {
	const source = await readFile(file, 'utf8');
	for (const match of source.matchAll(/\bfrom\s+['"]([^'"]+)['"]|\bimport\s*\(\s*['"]([^'"]+)['"]\s*\)/g)) {
		const specifier = match[1] ?? match[2] ?? '';
		if (!specifier.startsWith('./') && !specifier.startsWith('../')) {
			externalImports.push(`${relative(repository, file)} imports ${specifier}`);
		}
	}
}
assert.deepEqual(externalImports, [], `runtime source must be dependency-free:\n${externalImports.join('\n')}`);

const manifest = JSON.parse(await readFile(join(packageDirectory, 'package.json'), 'utf8'));
for (const field of ['dependencies', 'optionalDependencies', 'peerDependencies']) {
	assert.equal(manifest[field], undefined, `@edraft/core must not declare ${field}`);
}

const packageFiles = await filesBelow(packageDirectory);
assert.equal(
	packageFiles.some((file) => file.endsWith('.svelte') || /ScriptEditor/i.test(file)),
	false,
	'@edraft/core must not contain the Svelte editor'
);

/* The app-only screenplay modules the editor may reach for. Everything else
   under $lib/screenplay would be engine work living on the wrong side of the
   boundary: pdf and pageline are render policy the package deliberately does
   not ship, and sample is app content. */
const APP_ONLY_SCREENPLAY_MODULES = ['pdf', 'pageline', 'sample'];

const editorSource = await readFile(join(repository, 'src', 'lib', 'components', 'ScriptEditor.svelte'), 'utf8');
const legacyCoreImport = new RegExp(
	`\\$lib/screenplay/(?!${APP_ONLY_SCREENPLAY_MODULES.map((name) => `${name}(?:['"]|$)`).join('|')})`
).exec(editorSource);
assert.equal(
	legacyCoreImport,
	null,
	'ScriptEditor must consume the public @edraft/core API rather than legacy deep imports'
);

process.stdout.write(`Package boundary passed for ${sourceFiles.length} runtime modules.\n`);
