import { defineConfig } from 'vitest/config';

export default defineConfig({
	test: {
		environment: 'node',
		include: ['src/**/*.test.ts'],
		coverage: {
			provider: 'v8',
			reporter: ['text', 'json-summary'],
			include: ['src/**/*.ts'],
			exclude: ['src/**/*.test.ts', 'src/sample.ts'],
			thresholds: {
				lines: 85,
				functions: 85,
				statements: 85,
				branches: 75
			}
		}
	}
});
