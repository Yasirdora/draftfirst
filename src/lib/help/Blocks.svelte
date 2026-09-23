<script lang="ts">
	/**
	 * Renders help article body blocks as plain elements — no {@html},
	 * so article data stays inert text end to end.
	 */
	import type { HelpBlock } from './articles';

	let { blocks }: { blocks: HelpBlock[] } = $props();
</script>

{#each blocks as block}
	{#if block.type === 'h'}
		<h2>{block.text}</h2>
	{:else if block.type === 'p'}
		<p>{block.text}</p>
	{:else if block.type === 'list'}
		<ul>
			{#each block.items as item}
				<li>{item}</li>
			{/each}
		</ul>
	{:else if block.type === 'steps'}
		<ol>
			{#each block.items as item}
				<li>{item}</li>
			{/each}
		</ol>
	{:else if block.type === 'table'}
		<div class="table-scroll" role="region" aria-label="Table">
			<table>
				<thead>
					<tr>{#each block.head as cell}<th scope="col">{cell}</th>{/each}</tr>
				</thead>
				<tbody>
					{#each block.rows as row}
						<tr>{#each row as cell}<td>{cell}</td>{/each}</tr>
					{/each}
				</tbody>
			</table>
		</div>
	{:else if block.type === 'tip'}
		<aside class="tip" aria-label="Tip">
			<p>{block.text}</p>
		</aside>
	{:else if block.type === 'note'}
		<aside class="note" aria-label="Note">
			<p>{block.text}</p>
		</aside>
	{/if}
{/each}

<style>
	h2 { font-size: 21px; font-weight: 600; letter-spacing: -.02em; line-height: 1.3; margin-top: 34px; }
	p { font-size: 16px; line-height: 1.7; color: #3a3a3f; margin-top: 16px; max-width: 680px; }
	ul, ol { margin: 16px 0 0; padding-left: 24px; max-width: 680px; }
	li { font-size: 16px; line-height: 1.65; color: #3a3a3f; margin-top: 8px; }
	ol li::marker { font-weight: 600; color: #1477c9; }
	.table-scroll { margin-top: 20px; overflow-x: auto; border: 1px solid #e3e3e8; border-radius: 12px; }
	table { width: 100%; border-collapse: collapse; font-size: 15px; min-width: 460px; }
	th, td { text-align: left; padding: 11px 16px; border-bottom: 1px solid #ececf0; vertical-align: top; }
	th { font-size: 12px; font-weight: 600; text-transform: uppercase; letter-spacing: .05em; color: #6e6e73; background: #fbfbfd; }
	tr:last-child td { border-bottom: 0; }
	tbody tr:nth-child(even) { background: #fafafc; }
	td:first-child { white-space: nowrap; font-weight: 500; color: #1d1d1f; }
	td:last-child { color: #3a3a3f; }
	.tip { margin-top: 26px; padding: 16px 20px; background: #f0f7ff; border: 1px solid #d3e5f8; border-radius: 12px; max-width: 680px; }
	.tip p { margin: 0; font-size: 14px; line-height: 1.6; color: #1f4e79; }
	.tip::before { content: 'Tip'; display: block; font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; color: #1477c9; margin-bottom: 6px; }
	.note { margin-top: 26px; padding: 16px 20px; background: #f5f5f7; border: 1px solid #e3e3e8; border-radius: 12px; max-width: 680px; }
	.note p { margin: 0; font-size: 14px; line-height: 1.6; color: #3a3a3f; }
	.note::before { content: 'Note'; display: block; font-size: 11px; font-weight: 700; letter-spacing: .08em; text-transform: uppercase; color: #6e6e73; margin-bottom: 6px; }
</style>
