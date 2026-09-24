<script lang="ts">
	/**
	 * Renders help article body blocks as plain elements — no {@html},
	 * so article data stays inert text end to end.
	 *
	 * Apple's user-guide type: 17/26 text, quiet section headings, a Note
	 * or Tip as a paragraph that opens with the word in bold — no boxes, no
	 * tint, blue kept for links. Keyboard shortcuts are set as keycaps —
	 * glyph-led ones anywhere, bare Tab, Return and Space only in tables
	 * (see `keyRuns`); everything else stays text.
	 */
	import type { HelpBlock } from './articles';
	import { anchorFor, keyRuns } from './guide';

	let { blocks }: { blocks: HelpBlock[] } = $props();

	/* A table whose last column holds shortcuts gets a fixed shortcut column,
	   so every shortcut table on a page lines up with the next. */
	const keyed = (rows: string[][]) => rows.some((row) => keyRuns(row[row.length - 1] ?? '', { bareKeys: true }).some((run) => run.key));
</script>

{#snippet text(value: string, bareKeys = false)}
	{#each keyRuns(value, { bareKeys }) as run}{#if run.key}<kbd>{run.text}</kbd>{:else}{run.text}{/if}{/each}
{/snippet}

{#each blocks as block}
	{#if block.type === 'h'}
		<h2 id={anchorFor(block.text)}>{block.text}</h2>
	{:else if block.type === 'p'}
		<p>{@render text(block.text)}</p>
	{:else if block.type === 'list'}
		<ul>
			{#each block.items as item}
				<li>{@render text(item)}</li>
			{/each}
		</ul>
	{:else if block.type === 'steps'}
		<ol>
			{#each block.items as item}
				<li>{@render text(item)}</li>
			{/each}
		</ol>
	{:else if block.type === 'table'}
		<div class="table-scroll" role="region" aria-label="Table" tabindex="-1">
			<table class:keyed={keyed(block.rows)}>
				<thead>
					<tr>{#each block.head as cell}<th scope="col">{cell}</th>{/each}</tr>
				</thead>
				<tbody>
					{#each block.rows as row}
						<tr>
							{#each row as cell}
								<td>{@render text(cell, true)}</td>
							{/each}
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{:else if block.type === 'tip'}
		<p class="callout"><strong>Tip:</strong> {@render text(block.text)}</p>
	{:else if block.type === 'note'}
		<p class="callout"><strong>Note:</strong> {@render text(block.text)}</p>
	{/if}
{/each}

<style>
	h2 { font-size: 24px; font-weight: 500; letter-spacing: -.012em; line-height: 1.25; margin-top: 44px; color: #1d1d1f; text-wrap: balance; scroll-margin-top: 96px; }
	p, li { font-size: 17px; line-height: 26px; letter-spacing: -.022em; color: #1d1d1f; text-wrap: pretty; }
	p { margin-top: 17px; }
	ul, ol { margin: 17px 0 0; padding-left: 1.3em; }
	li { margin-top: 9px; padding-left: .2em; }
	ol li::marker { color: #1d1d1f; font-variant-numeric: tabular-nums; }
	ul li::marker { color: #86868b; }
	.callout strong { font-weight: 600; }

	.table-scroll { margin-top: 24px; overflow-x: auto; }
	.table-scroll:focus-visible { outline: 3px solid #0071e3; outline-offset: 4px; }
	table { width: 100%; border-collapse: collapse; min-width: 420px; }
	th, td { text-align: left; vertical-align: top; padding: 11px 24px 11px 0; font-size: 15px; line-height: 21px; letter-spacing: -.01em; }
	th { font-weight: 600; color: #1d1d1f; border-bottom: 1px solid #d2d2d7; }
	td { color: #1d1d1f; border-bottom: 1px solid #e8e8ed; }
	th:last-child, td:last-child { padding-right: 0; }
	tbody tr:last-child td { border-bottom: 0; }
	.keyed th:last-child, .keyed td:last-child { width: 36%; }

	/* A keycap: the glyphs as a menu shows them, on a key. */
	kbd { display: inline-block; min-width: 1.6em; padding: 0 6px; margin: 0 1px; border: 1px solid #d2d2d7; border-bottom-width: 2px; border-radius: 6px; background: #fbfbfd; font: 500 14px/20px -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif; letter-spacing: .06em; text-align: center; color: #1d1d1f; white-space: nowrap; }

	@media (max-width: 600px) {
		h2 { font-size: 21px; margin-top: 36px; }
		/* On a phone a two-column table wraps inside the column rather than
		   scrolling sideways; only a table wider than its words still scrolls. */
		table { min-width: 0; }
		th, td { padding-right: 14px; }
		.keyed th:last-child, .keyed td:last-child { width: 42%; }
	}
</style>
