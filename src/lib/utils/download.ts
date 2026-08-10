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
