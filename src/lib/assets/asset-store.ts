/**
 * Binary asset store — pasted and dropped images live in IndexedDB as Blobs.
 *
 * The document body stays plain Markdown with `asset:<id>` references, so the
 * library in localStorage never carries image bytes (that is the data-URL
 * trap: multi-megabyte base64 in a string quota). Object URLs are minted at
 * render time; export inlines blobs as data URLs so the file stands alone.
 *
 * Thin async wrapper, browser-only — exercised by the browser smoke test,
 * kept free of logic so Node tests cover everything above it.
 */

export interface AssetMeta {
	id: string;
	mime: string;
	size: number;
	created: number;
}

const DB_NAME = 'writing-desk-assets';
const STORE = 'assets';

let dbPromise: Promise<IDBDatabase> | null = null;

function openDb(): Promise<IDBDatabase> {
	if (!dbPromise) {
		dbPromise = new Promise((resolve, reject) => {
			const request = indexedDB.open(DB_NAME, 1);
			request.onupgradeneeded = () => {
				if (!request.result.objectStoreNames.contains(STORE)) {
					request.result.createObjectStore(STORE, { keyPath: 'id' });
				}
			};
			request.onsuccess = () => resolve(request.result);
			request.onerror = () => reject(request.error);
		});
	}
	return dbPromise;
}

function requestToPromise<T>(request: IDBRequest<T>): Promise<T> {
	return new Promise((resolve, reject) => {
		request.onsuccess = () => resolve(request.result);
		request.onerror = () => reject(request.error);
	});
}

/** Store a blob; returns its metadata. Id is a UUID — references stay opaque. */
export async function putAsset(blob: Blob): Promise<AssetMeta> {
	const db = await openDb();
	const meta: AssetMeta = {
		id: crypto.randomUUID(),
		mime: blob.type || 'application/octet-stream',
		size: blob.size,
		created: Date.now()
	};
	const tx = db.transaction(STORE, 'readwrite');
	await requestToPromise(tx.objectStore(STORE).put({ ...meta, blob }));
	return meta;
}

/** Fetch one blob by id; null when missing (export of another machine's doc). */
export async function getAsset(id: string): Promise<Blob | null> {
	const db = await openDb();
	const tx = db.transaction(STORE, 'readonly');
	const row = await requestToPromise(tx.objectStore(STORE).get(id));
	return row && row.blob instanceof Blob ? row.blob : null;
}

/** Blob → data URL, for standalone HTML export. */
export function blobToDataUrl(blob: Blob): Promise<string> {
	return new Promise((resolve, reject) => {
		const reader = new FileReader();
		reader.addEventListener('load', () => resolve(String(reader.result)));
		reader.addEventListener('error', () => reject(reader.error));
		reader.readAsDataURL(blob);
	});
}
