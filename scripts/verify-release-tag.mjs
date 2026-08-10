import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const manifest = JSON.parse(
	await readFile(join(repository, 'packages', 'draftfirst', 'package.json'), 'utf8')
);
const tag = process.argv[2];

assert.equal(tag, `v${manifest.version}`, `release tag must be v${manifest.version}`);
process.stdout.write(`Release tag ${tag} matches @draftfirst/core@${manifest.version}.\n`);
