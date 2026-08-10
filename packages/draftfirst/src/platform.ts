/**
 * Platform primitives the engine needs but TypeScript's ES2022 lib does not
 * declare. The package builds against lib ES2022 ONLY — no DOM, no Node
 * types — so it stays environment-agnostic; these globals exist in every
 * supported runtime (browsers, Node ≥ 17, workers). Declared once here,
 * structurally, so no file ever reaches for `any`.
 */

/** Minimal shape of the platform UTF-8 decoder. */
interface PlatformTextDecoder {
	decode(bytes: Uint8Array): string;
}

declare const TextDecoder: (new () => PlatformTextDecoder) | undefined;

/** Minimal shape of the platform UTF-8 encoder. */
interface PlatformTextEncoder {
	encode(text: string): Uint8Array;
}

declare const TextEncoder: (new () => PlatformTextEncoder) | undefined;

/** Minimal shape of the platform inflate stream (raw DEFLATE). */
interface InflateSession {
	writable: {
		getWriter(): {
			write(chunk: Uint8Array): Promise<void>;
			close(): Promise<void>;
		};
	};
	readable: {
		getReader(): {
			read(): Promise<{ done: boolean; value?: Uint8Array }>;
		};
	};
}

declare const DecompressionStream: (new (format: 'deflate-raw') => InflateSession) | undefined;

/** Decode UTF-8 bytes; throws a plain Error when the runtime cannot. */
export function decodeUtf8(bytes: Uint8Array): string {
	if (typeof TextDecoder === 'undefined') {
		throw new Error('this runtime cannot decode text (TextDecoder missing)');
	}
	return new TextDecoder().decode(bytes);
}

/** Encode text as UTF-8; throws a plain Error when the runtime cannot. */
export function encodeUtf8(text: string): Uint8Array {
	if (typeof TextEncoder === 'undefined') {
		throw new Error('this runtime cannot encode text (TextEncoder missing)');
	}
	return new TextEncoder().encode(text);
}

/**
 * Inflate a raw DEFLATE stream through the platform's native decompressor.
 * Verifies the inflated length against the archive's own record — a mismatch
 * means the container lied, and we say so rather than trust the bytes.
 */
export async function inflateRaw(data: Uint8Array, expectedSize: number): Promise<Uint8Array> {
	if (typeof DecompressionStream === 'undefined') {
		throw new Error('this runtime cannot inflate data (DecompressionStream missing)');
	}
	const session = new DecompressionStream('deflate-raw');
	const writer = session.writable.getWriter();
	const reader = session.readable.getReader();
	const written = writer.write(data).then(() => writer.close());
	const chunks: Uint8Array[] = [];
	let length = 0;
	for (;;) {
		const { done, value } = await reader.read();
		if (done) break;
		if (value) {
			chunks.push(value);
			length += value.length;
		}
	}
	await written;
	const out = new Uint8Array(length);
	let at = 0;
	for (const chunk of chunks) {
		out.set(chunk, at);
		at += chunk.length;
	}
	if (out.length !== expectedSize) {
		throw new Error(`corrupt archive entry: expected ${expectedSize} bytes, inflated ${out.length}`);
	}
	return out;
}
