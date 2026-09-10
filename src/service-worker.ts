/// <reference no-default-lib="true"/>
/// <reference lib="esnext" />
/// <reference lib="webworker" />
/// <reference types="@sveltejs/kit" />

/** Precaches application assets for offline editing after the first visit.
 *
 *  The update policy, decided — not defaulted: a writing tool's tabs live
 *  for weeks, and a worker that waits for every tab to close never ships.
 *  So a new worker activates as soon as its precache lands. An open tab
 *  keeps running the code it loaded and still asks for ITS build's hashed
 *  assets, which only that build's cache can answer — so activation keeps
 *  one predecessor cache and lets the rest go. */

import { build, files, version } from '$service-worker';

const sw = self as unknown as ServiceWorkerGlobalScope;
const CACHE = `edraft-${version}`;
const ASSETS = [...build, ...files];

sw.addEventListener('install', (event) => {
	async function addFilesToCache() {
		const cache = await caches.open(CACHE);
		await cache.addAll(ASSETS);
	}
	/* Waiting until the precache has landed, then past the old worker — the
	   order matters: activating first would serve requests the cache cannot
	   answer yet. */
	event.waitUntil(addFilesToCache().then(() => sw.skipWaiting()));
});

sw.addEventListener('activate', (event) => {
	async function activate() {
		/* caches.keys() is creation order: the newest key that is not this
		   build is the one predecessor worth keeping. */
		const keys = await caches.keys();
		const predecessor = keys.filter((key) => key !== CACHE).at(-1);
		for (const key of keys) {
			if (key !== CACHE && key !== predecessor) await caches.delete(key);
		}
		await sw.clients.claim();
	}
	event.waitUntil(activate());
});

sw.addEventListener('fetch', (event) => {
	if (event.request.method !== 'GET') return;

	async function respond() {
		const url = new URL(event.request.url);
		const cache = await caches.open(CACHE);

		// Built assets and static files: always from cache when present.
		if (ASSETS.includes(url.pathname)) {
			const response = await cache.match(url.pathname);
			if (response) return response;
		}

		try {
			const response = await fetch(event.request);
			if (!(response instanceof Response)) {
				throw new Error('invalid response from fetch');
			}
			if (
				response.status === 200 &&
				!response.headers.get('cache-control')?.includes('no-store')
			) {
				cache.put(event.request, response.clone());
			}
			return response;
		} catch (err) {
			const response = await cache.match(event.request);
			if (response) return response;
			throw err;
		}
	}

	event.respondWith(respond());
});
