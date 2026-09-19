/** SHA-256 against the FIPS 180-4 examples and a digest node computes. */
import { createHash } from 'node:crypto';
import { describe, expect, it } from 'vitest';
import { sha256Hex } from './sha256.js';

const ascii = (text: string): Uint8Array => new TextEncoder().encode(text);

describe('sha256', () => {
	it('matches the FIPS 180-4 examples', () => {
		expect(sha256Hex(ascii(''))).toBe('e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
		expect(sha256Hex(ascii('abc'))).toBe('ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
		expect(sha256Hex(ascii('abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'))).toBe(
			'248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1'
		);
	});

	it('matches a million a', () => {
		expect(sha256Hex(new Uint8Array(1_000_000).fill(0x61))).toBe(
			'cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0'
		);
	});

	it('agrees with the platform at every length across the padding boundaries', () => {
		for (let length = 0; length <= 200; length++) {
			const bytes = new Uint8Array(length).map((_, i) => (i * 31 + length) & 0xff);
			expect(sha256Hex(bytes)).toBe(createHash('sha256').update(bytes).digest('hex'));
		}
	});
});
