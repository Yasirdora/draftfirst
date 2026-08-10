import type { Screenplay } from './types.js';

export type DiagnosticSeverity = 'warning' | 'error';

export interface DraftFirstDiagnostic {
	readonly code: string;
	readonly severity: DiagnosticSeverity;
	readonly message: string;
	/** JSON-style path into the supplied value, for example `elements[3].text`. */
	readonly path?: string;
}

export interface ScreenplayLimits {
	readonly maxElements: number;
	readonly maxElementTextLength: number;
	readonly maxTitleEntries: number;
	readonly maxTitleValuesPerEntry: number;
	readonly maxTitleValueLength: number;
	readonly maxSectionDepth: number;
}

export const DEFAULT_SCREENPLAY_LIMITS: Readonly<ScreenplayLimits> = Object.freeze({
	maxElements: 100_000,
	maxElementTextLength: 1_000_000,
	maxTitleEntries: 100,
	maxTitleValuesPerEntry: 100,
	maxTitleValueLength: 100_000,
	maxSectionDepth: 10
});

export type ScreenplayValidationResult =
	| {
			readonly ok: true;
			readonly value: Screenplay;
			readonly diagnostics: readonly DraftFirstDiagnostic[];
	  }
	| {
			readonly ok: false;
			readonly diagnostics: readonly DraftFirstDiagnostic[];
	  };

const ELEMENT_TYPES = new Set([
	'scene',
	'action',
	'character',
	'dialogue',
	'parenthetical',
	'transition',
	'shot',
	'general',
	'centered',
	'lyrics',
	'note',
	'section',
	'synopsis',
	'pagebreak'
]);

function isRecord(value: unknown): value is Record<string, unknown> {
	return typeof value === 'object' && value !== null && !Array.isArray(value);
}

function positiveInteger(value: number | undefined, fallback: number, name: string): number {
	if (value === undefined) return fallback;
	if (!Number.isSafeInteger(value) || value <= 0) {
		throw new RangeError(`${name} must be a positive safe integer`);
	}
	return value;
}

function resolveLimits(overrides: Partial<ScreenplayLimits>): ScreenplayLimits {
	return {
		maxElements: positiveInteger(
			overrides.maxElements,
			DEFAULT_SCREENPLAY_LIMITS.maxElements,
			'maxElements'
		),
		maxElementTextLength: positiveInteger(
			overrides.maxElementTextLength,
			DEFAULT_SCREENPLAY_LIMITS.maxElementTextLength,
			'maxElementTextLength'
		),
		maxTitleEntries: positiveInteger(
			overrides.maxTitleEntries,
			DEFAULT_SCREENPLAY_LIMITS.maxTitleEntries,
			'maxTitleEntries'
		),
		maxTitleValuesPerEntry: positiveInteger(
			overrides.maxTitleValuesPerEntry,
			DEFAULT_SCREENPLAY_LIMITS.maxTitleValuesPerEntry,
			'maxTitleValuesPerEntry'
		),
		maxTitleValueLength: positiveInteger(
			overrides.maxTitleValueLength,
			DEFAULT_SCREENPLAY_LIMITS.maxTitleValueLength,
			'maxTitleValueLength'
		),
		maxSectionDepth: positiveInteger(
			overrides.maxSectionDepth,
			DEFAULT_SCREENPLAY_LIMITS.maxSectionDepth,
			'maxSectionDepth'
		)
	};
}

/** Validate an untrusted JavaScript value without mutating or cloning it. */
export function validateScreenplay(
	input: unknown,
	overrides: Partial<ScreenplayLimits> = {}
): ScreenplayValidationResult {
	const limits = resolveLimits(overrides);
	const diagnostics: DraftFirstDiagnostic[] = [];
	const error = (code: string, message: string, path?: string): void => {
		diagnostics.push(path === undefined
			? { code, severity: 'error', message }
			: { code, severity: 'error', message, path });
	};

	if (!isRecord(input)) {
		return {
			ok: false,
			diagnostics: [{ code: 'MODEL_NOT_OBJECT', severity: 'error', message: 'Screenplay must be an object.' }]
		};
	}

	if (!Array.isArray(input.titlePage)) {
		error('TITLE_PAGE_NOT_ARRAY', 'titlePage must be an array.', 'titlePage');
	} else if (input.titlePage.length > limits.maxTitleEntries) {
		error(
			'TITLE_PAGE_LIMIT_EXCEEDED',
			`titlePage exceeds the ${limits.maxTitleEntries} entry limit.`,
			'titlePage'
		);
	} else {
		for (let i = 0; i < input.titlePage.length; i++) {
			const entry = input.titlePage[i];
			const path = `titlePage[${i}]`;
			if (!isRecord(entry)) {
				error('TITLE_ENTRY_NOT_OBJECT', 'Title-page entry must be an object.', path);
				continue;
			}
			if (typeof entry.key !== 'string' || entry.key.trim() === '') {
				error('TITLE_KEY_INVALID', 'Title-page key must be a non-empty string.', `${path}.key`);
			} else if (entry.key.length > limits.maxTitleValueLength) {
				error('TITLE_KEY_TOO_LONG', 'Title-page key exceeds the configured limit.', `${path}.key`);
			}
			if (!Array.isArray(entry.values)) {
				error('TITLE_VALUES_NOT_ARRAY', 'Title-page values must be an array.', `${path}.values`);
				continue;
			}
			if (entry.values.length > limits.maxTitleValuesPerEntry) {
				error('TITLE_VALUES_LIMIT_EXCEEDED', 'Title-page entry has too many values.', `${path}.values`);
				continue;
			}
			for (let j = 0; j < entry.values.length; j++) {
				const value = entry.values[j];
				if (typeof value !== 'string') {
					error('TITLE_VALUE_INVALID', 'Title-page value must be a string.', `${path}.values[${j}]`);
				} else if (value.length > limits.maxTitleValueLength) {
					error('TITLE_VALUE_TOO_LONG', 'Title-page value exceeds the configured limit.', `${path}.values[${j}]`);
				}
			}
		}
	}

	if (!Array.isArray(input.elements)) {
		error('ELEMENTS_NOT_ARRAY', 'elements must be an array.', 'elements');
	} else if (input.elements.length > limits.maxElements) {
		error('ELEMENT_LIMIT_EXCEEDED', `elements exceeds the ${limits.maxElements} item limit.`, 'elements');
	} else {
		for (let i = 0; i < input.elements.length; i++) {
			const element = input.elements[i];
			const path = `elements[${i}]`;
			if (!isRecord(element)) {
				error('ELEMENT_NOT_OBJECT', 'Screenplay element must be an object.', path);
				continue;
			}
			if (typeof element.type !== 'string' || !ELEMENT_TYPES.has(element.type)) {
				error('ELEMENT_TYPE_INVALID', 'Screenplay element has an unsupported type.', `${path}.type`);
			}
			if (typeof element.text !== 'string') {
				error('ELEMENT_TEXT_INVALID', 'Screenplay element text must be a string.', `${path}.text`);
			} else if (element.text.length > limits.maxElementTextLength) {
				error('ELEMENT_TEXT_TOO_LONG', 'Screenplay element text exceeds the configured limit.', `${path}.text`);
			}
			if (element.dual !== undefined && typeof element.dual !== 'boolean') {
				error('ELEMENT_DUAL_INVALID', 'dual must be a boolean when present.', `${path}.dual`);
			}
			if (element.sceneNumber !== undefined && typeof element.sceneNumber !== 'string') {
				error('SCENE_NUMBER_INVALID', 'sceneNumber must be a string when present.', `${path}.sceneNumber`);
			}
			if (
				element.depth !== undefined &&
				(typeof element.depth !== 'number' ||
					!Number.isSafeInteger(element.depth) ||
					element.depth < 1 ||
					element.depth > limits.maxSectionDepth)
			) {
				error(
					'ELEMENT_DEPTH_INVALID',
					`depth must be an integer between 1 and ${limits.maxSectionDepth}.`,
					`${path}.depth`
				);
			}
		}
	}

	return diagnostics.length === 0
		? { ok: true, value: input as unknown as Screenplay, diagnostics }
		: { ok: false, diagnostics };
}

export class DraftFirstValidationError extends TypeError {
	readonly diagnostics: readonly DraftFirstDiagnostic[];

	constructor(diagnostics: readonly DraftFirstDiagnostic[]) {
		super(`Invalid screenplay document (${diagnostics.length} issue${diagnostics.length === 1 ? '' : 's'}).`);
		this.name = 'DraftFirstValidationError';
		this.diagnostics = diagnostics;
	}
}

/** Validate an untrusted value and return it with a narrowed Screenplay type. */
export function assertScreenplay(
	input: unknown,
	overrides: Partial<ScreenplayLimits> = {}
): Screenplay {
	const result = validateScreenplay(input, overrides);
	if (!result.ok) throw new DraftFirstValidationError(result.diagnostics);
	return result.value;
}
