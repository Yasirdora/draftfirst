import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { promisify } from 'node:util';

const exec = promisify(execFile);
const repository = dirname(dirname(fileURLToPath(import.meta.url)));
const packageDirectory = join(repository, 'packages', 'draftfirst');
const temporaryDirectory = await mkdtemp(join(tmpdir(), 'draftfirst-package-smoke-'));
const consumerDirectory = join(temporaryDirectory, 'consumer');
const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
const npmEnvironment = {
	...process.env,
	npm_config_cache: join(temporaryDirectory, 'npm-cache')
};

try {
	await exec(npm, ['run', 'build'], { cwd: packageDirectory, env: npmEnvironment });
	const { stdout } = await exec(
		npm,
		['pack', '--json', '--ignore-scripts', '--pack-destination', temporaryDirectory],
		{ cwd: packageDirectory, env: npmEnvironment, maxBuffer: 10 * 1024 * 1024 }
	);
	const packResult = JSON.parse(stdout);
	assert.equal(packResult.length, 1, 'npm pack must create exactly one tarball');
	assert.equal(
		packResult[0].files.some((file) => /ScriptEditor|\.svelte$/i.test(file.path)),
		false,
		'the public package must not contain the Svelte editor'
	);

	await mkdir(consumerDirectory, { recursive: true });
	await writeFile(
		join(consumerDirectory, 'package.json'),
		JSON.stringify({ name: 'draftfirst-smoke-consumer', private: true, type: 'module' })
	);

	const tarball = join(temporaryDirectory, packResult[0].filename);
	await exec(
		npm,
		['install', '--ignore-scripts', '--no-audit', '--no-fund', '--save-exact', tarball],
		{ cwd: consumerDirectory, env: npmEnvironment, maxBuffer: 10 * 1024 * 1024 }
	);

	const smokeFile = join(consumerDirectory, 'smoke.mjs');
	await writeFile(
		smokeFile,
		`import assert from 'node:assert/strict';
import { parseFountain, serializeFountain, validateScreenplay } from '@draftfirst/core';
import { parseFdx } from '@draftfirst/core/fdx';
import { paginate } from '@draftfirst/core/layout';
import { collectSmartType } from '@draftfirst/core/analysis';
import { nextElement } from '@draftfirst/core/editor';

const script = parseFountain('INT. LAB - DAY\\n\\nMARA\\nWe begin.');
assert.equal(validateScreenplay(script).ok, true);
assert.match(serializeFountain(script), /INT\\. LAB - DAY/);
assert.equal(paginate(script).length, 1);
assert.deepEqual(collectSmartType(script).characters, ['MARA']);
assert.equal(nextElement('character', 'enter'), 'dialogue');
assert.equal(parseFdx('<FinalDraft><Content></Content></FinalDraft>').script.elements.length, 0);
`
	);
	await exec(process.execPath, [smokeFile], { cwd: consumerDirectory });

	const installedManifest = JSON.parse(
		await readFile(join(consumerDirectory, 'node_modules', '@draftfirst', 'core', 'package.json'), 'utf8')
	);
	assert.deepEqual(installedManifest.dependencies, undefined, 'Draft First must have zero runtime dependencies');
	process.stdout.write(`Package smoke test passed: ${packResult[0].filename}\n`);
} finally {
	await rm(temporaryDirectory, { recursive: true, force: true });
}
