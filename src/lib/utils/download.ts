/**
 * Trigger a browser file download from an in-memory string.
 * Object URLs are revoked after a short delay so memory does not leak.
 */

export function download(text: string, filename: string, type: string): void {
	const blob = new Blob([text], { type: `${type};charset=utf-8` });
	const url = URL.createObjectURL(blob);
	const anchor = document.createElement('a');
	anchor.href = url;
	anchor.download = filename;
	document.body.appendChild(anchor);
	anchor.click();
	anchor.remove();
	setTimeout(() => URL.revokeObjectURL(url), 1000);
}

/** Binary variant for generated files (PDF etc.) — bytes pass through untouched. */
export function downloadBytes(bytes: Uint8Array, filename: string, type: string): void {
	const blob = new Blob([bytes as BlobPart], { type });
	const url = URL.createObjectURL(blob);
	const anchor = document.createElement('a');
	anchor.href = url;
	anchor.download = filename;
	document.body.appendChild(anchor);
	anchor.click();
	anchor.remove();
	setTimeout(() => URL.revokeObjectURL(url), 1000);
}
