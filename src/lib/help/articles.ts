/**
 * eDraft Help Center content — one structured module.
 *
 * Every article is data, not markup: title, slug, category, a one-line
 * summary, related slugs, and body blocks. The same data will later
 * generate the Apple Help Book, so keep everything here plain and
 * serializable. Renderers live in the routes; they never invent content.
 */

export type HelpBlock =
	| { type: 'p'; text: string }
	| { type: 'h'; text: string }
	| { type: 'list'; items: string[] }
	| { type: 'steps'; items: string[] }
	| { type: 'table'; head: string[]; rows: string[][] }
	| { type: 'tip'; text: string };

export interface HelpArticle {
	slug: string;
	title: string;
	category: string;
	summary: string;
	related: string[];
	blocks: HelpBlock[];
}

export interface HelpCategory {
	id: string;
	name: string;
	description: string;
}

export const helpCategories: HelpCategory[] = [
	{ id: 'getting-started', name: 'Get started', description: 'New scripts, opening files, and bringing in work from other apps.' },
	{ id: 'writing', name: 'Writing', description: 'Elements, the Tab and Return flow, and writing suggestions.' },
	{ id: 'notes', name: 'Notes', description: 'Margin notes, threads, and where notes live in your file.' },
	{ id: 'scenes', name: 'Scenes', description: 'Numbering, omitting, and moving between scenes.' },
	{ id: 'pages', name: 'Pages & title page', description: 'Layouts, zoom, paper, and the title page.' },
	{ id: 'files', name: 'Files & privacy', description: 'Where scripts live, iCloud, and file formats.' },
	{ id: 'export', name: 'Export & print', description: 'PDF, Final Draft, Fountain, plain text, and printing.' },
	{ id: 'support', name: 'Shortcuts & support', description: 'Every shortcut, first fixes, and how to reach us.' }
];

export const popularArticles = [
	'import-final-draft',
	'tab-and-return',
	'writing-suggestions',
	'export-pdf',
	'omit-a-scene'
];

export const helpArticles: HelpArticle[] = [
	{
		slug: 'start-a-screenplay',
		title: 'Start a new screenplay',
		category: 'getting-started',
		summary: 'The launch window, recent scripts, favorites, and the grid.',
		related: ['open-and-manage', 'where-files-live', 'screenplay-elements'],
		blocks: [
			{ type: 'p', text: 'When you open eDraft, the launch window is where you begin. It shows the scripts you had open most recently, with the newest first.' },
			{ type: 'steps', items: [
				'Click New Screenplay for a blank script.',
				'Click Open… to pick an existing file from anywhere on your Mac or in iCloud Drive.',
				'Click any recent script to continue where you left off.'
			] },
			{ type: 'h', text: 'The library' },
			{ type: 'p', text: 'Each recent script shows its name and when you last touched it — Today, Yesterday, or a date. The toolbar switch flips between the grid of pages and a compact list, and the toolbar search narrows the library by name.' },
			{ type: 'p', text: 'The ⋯ menu on a script opens it in a new window, renames it, duplicates it, favorites it, or moves it to the Trash. Trash is undoable — a banner appears at the bottom of the window with an Undo button until you dismiss it.' },
			{ type: 'tip', text: 'Star a script with Favorite to pin it to the top of the library.' }
		]
	},
	{
		slug: 'open-and-manage',
		title: 'Open, rename, move, or duplicate a script',
		category: 'getting-started',
		summary: 'File menu basics, Open Recent, and Revert To.',
		related: ['start-a-screenplay', 'where-files-live', 'troubleshooting'],
		blocks: [
			{ type: 'p', text: 'Scripts are ordinary documents. Everything you expect from a Mac document app is in the File menu.' },
			{ type: 'list', items: [
				'File → Open Recent lists the scripts you touched last, and Clear Menu empties the list.',
				'File → Rename… changes only the name. The file keeps its place.',
				'File → Move To… and File → Show in Finder put the file where you want it.',
				'File → Duplicate (⇧⌘S) saves a copy under a new name and opens that copy.'
			] },
			{ type: 'h', text: 'Going back' },
			{ type: 'p', text: 'File → Revert To → Last Saved discards changes since the last save. Revert To → Browse All Versions… opens the version browser, so you can compare and pull from earlier saves.' },
			{ type: 'tip', text: 'Rename and Duplicate are also on the ⋯ menu of any recent script in the launch window.' }
		]
	},
	{
		slug: 'import-final-draft',
		title: 'Import a Final Draft file',
		category: 'getting-started',
		summary: 'Open a .fdx, read the import report, and keep your original.',
		related: ['export-final-draft', 'fountain-and-fdx', 'troubleshooting'],
		blocks: [
			{ type: 'p', text: 'eDraft opens Final Draft files directly. Choose File → Open… and pick the .fdx file, or double-click it in Finder. There is no separate import step.' },
			{ type: 'h', text: 'What gets imported' },
			{ type: 'p', text: 'eDraft reads a deliberately bounded subset of FDX — the screenplay content itself. Scene headings, action, characters, parentheticals, dialogue, transitions, shots, scene numbers, and notes all come across.' },
			{ type: 'h', text: 'Read the report' },
			{ type: 'p', text: 'When something in the file is outside that subset, eDraft says so instead of guessing. Review any import warnings, and check the pages before a production deadline.' },
			{ type: 'tip', text: 'Keep the original .fdx. eDraft never modifies it, and a production file should never have only one home.' }
		]
	},
	{
		slug: 'screenplay-elements',
		title: 'The screenplay elements',
		category: 'writing',
		summary: 'Nine elements, Act Break, and Format → Element.',
		related: ['tab-and-return', 'scene-numbering', 'writing-suggestions'],
		blocks: [
			{ type: 'p', text: 'A screenplay is a handful of building blocks. eDraft formats each one for you — you never set an indent or a margin.' },
			{ type: 'list', items: [
				'Scene Heading — INT. KITCHEN - DAY',
				'Action — what the camera sees',
				'Character — who speaks',
				'Parenthetical — how, in a low voice',
				'Dialogue — the words',
				'Transition — CUT TO:',
				'Shot — CLOSE ON',
				'General and Lyrics — for songs and special cases'
			] },
			{ type: 'h', text: 'Set an element directly' },
			{ type: 'p', text: 'Format → Element converts the current line, with shortcuts ⌘1 through ⌘9 in the order above. The element menu in the toolbar lists what the cursor position suggests first.' },
			{ type: 'p', text: 'An Act Break is not a conversion — it marks that a new act starts here. Choose it at the bottom of the element menu to insert one.' },
			{ type: 'tip', text: 'Typing INT. or EXT. promotes the line to a Scene Heading by itself.' }
		]
	},
	{
		slug: 'tab-and-return',
		title: 'Tab and Return while writing',
		category: 'writing',
		summary: 'The keyboard flow that keeps your hands on the keys.',
		related: ['screenplay-elements', 'writing-suggestions', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'You can write a whole script without touching the mouse. Tab and Return carry you from element to element.' },
			{ type: 'table', head: ['Key', 'What it does'], rows: [
				['Tab at the end of a line', 'Commit the line and move to the next element'],
				['Tab inside text, or on an empty line', 'Change the element'],
				['⇧ Tab', 'Cycle elements back'],
				['Return', 'Next logical element — Character after a heading, Dialogue after a character'],
				['⇧ Return', 'New line, same element']
			] },
			{ type: 'p', text: 'This choreography is part of the writing engine, so it behaves the same on Mac, iPhone, and iPad.' },
			{ type: 'tip', text: 'Press ? inside the app to see the full shortcut sheet.' }
		]
	},
	{
		slug: 'writing-suggestions',
		title: 'Writing suggestions',
		category: 'writing',
		summary: 'Character names and extensions, accepted with ⌘→.',
		related: ['tab-and-return', 'screenplay-elements', 'add-a-note'],
		blocks: [
			{ type: 'p', text: 'As you type, eDraft suggests what usually comes next — a character you have already used, a location from your script, an extension like (V.O.). The suggestion appears dimmed ahead of the cursor.' },
			{ type: 'p', text: 'Press ⌘→ to accept it, one word at a time. Keep typing and the suggestion steps aside — ignoring it costs nothing.' },
			{ type: 'h', text: 'Where suggestions come from' },
			{ type: 'p', text: 'Suggestions are derived from your own document. Nothing you write is sent anywhere to make them.' },
			{ type: 'tip', text: 'Accept Suggestion is also in the Edit menu, with the same ⌘→ shortcut.' }
		]
	},
	{
		slug: 'add-a-note',
		title: 'Add a note to a line',
		category: 'notes',
		summary: '⇧⌘K opens the card; typing [[ also works.',
		related: ['note-threads', 'where-notes-live', 'writing-suggestions'],
		blocks: [
			{ type: 'p', text: 'Notes live beside the line they belong to, not in a separate app.' },
			{ type: 'steps', items: [
				'Place the cursor on the line.',
				'Choose Edit → Add Note (⇧⌘K).',
				'Type the note and press Return. Press Escape to cancel.'
			] },
			{ type: 'p', text: 'Either way, the caret returns exactly where it was. The note card sits next to the line, and everyone who opens the file sees it.' },
			{ type: 'h', text: 'The [[ way' },
			{ type: 'p', text: 'If your hands never leave the keyboard, type [[ and the note text, then ]]. eDraft reads this Fountain convention and moves the note onto the line.' },
			{ type: 'tip', text: 'Selecting text first? The format bar offers Add Note too.' }
		]
	},
	{
		slug: 'note-threads',
		title: 'Threads, replies, and resolving',
		category: 'notes',
		summary: 'Conversations on a line. Resolved fades — it never deletes.',
		related: ['add-a-note', 'where-notes-live', 'notes-report'],
		blocks: [
			{ type: 'p', text: 'A note can grow into a conversation. Replies stack on the same card, each with its author and role, so a line can hold a full discussion without leaving the page.' },
			{ type: 'h', text: 'Resolving' },
			{ type: 'p', text: 'When a thread is done, resolve it. The card dims and its replies collapse, but the words stay — a resolved thread fades, it never deletes. Switch the notes list between Open and All to see everything.' },
			{ type: 'h', text: 'Seeing every thread' },
			{ type: 'p', text: 'The notes inspector collects all threads — the card answers what did we say about this line, the inspector answers what is still open.' },
			{ type: 'tip', text: 'Export the notes report when you want every open thread as a document of its own.' }
		]
	},
	{
		slug: 'notes-report',
		title: 'The notes report',
		category: 'notes',
		summary: 'Every open thread, collected into one document.',
		related: ['note-threads', 'add-a-note', 'export-pdf'],
		blocks: [
			{ type: 'p', text: 'The notes report gathers every note in the script into a single document — each thread with its line, its scene, and its author.' },
			{ type: 'p', text: 'Use it for a notes pass before a draft goes out: read every open thread top to bottom, resolve what is done, and hand the list to a collaborator.' },
			{ type: 'h', text: 'What it contains' },
			{ type: 'list', items: [
				'The quoted line each thread is anchored to.',
				'Every message, with author and role.',
				'Open and resolved threads, marked as such.'
			] },
			{ type: 'tip', text: 'Notes are anchored to words, not positions — the report stays correct even after heavy edits.' }
		]
	},
	{
		slug: 'where-notes-live',
		title: 'Where notes live in your file',
		category: 'notes',
		summary: 'Inside the .draft, in FDX, and in Fountain — never on a server.',
		related: ['add-a-note', 'note-threads', 'where-files-live'],
		blocks: [
			{ type: 'p', text: 'Notes are part of your document, so they travel with it.' },
			{ type: 'list', items: [
				'In an eDraft file, notes are stored with the lines they belong to.',
				'Exported to Final Draft, they become ScriptNotes that Final Draft can read.',
				'Exported to Fountain, they become [[ note text ]] — readable by any Fountain tool.'
			] },
			{ type: 'p', text: 'Notes are anchored to the words they sit on, not to a position in the text. Add a scene above and every note still points at the right line.' },
			{ type: 'tip', text: 'There is no eDraft server. Your notes are never uploaded anywhere.' }
		]
	},
	{
		slug: 'scene-numbering',
		title: 'Number your scenes',
		category: 'scenes',
		summary: 'Number New Scenes, Number All Scenes, Remove Scene Numbers.',
		related: ['omit-a-scene', 'find-a-scene', 'screenplay-elements'],
		blocks: [
			{ type: 'p', text: 'Scene numbers live on the scene headings themselves, so they print exactly where a production expects them.' },
			{ type: 'steps', items: [
				'Choose Format → Scene Numbers → Number New Scenes to number only the scenes that do not have a number yet.',
				'Choose Number All Scenes… to number everything; eDraft asks before it renumbers.',
				'Choose Remove Scene Numbers… to strip them; eDraft asks before it does.'
			] },
			{ type: 'p', text: 'Once scenes are numbered, the numbers stay put — a new scene inserted between 4 and 5 becomes 4A, and the rest of the script is untouched.' },
			{ type: 'tip', text: 'Scene numbers appear on the right of the page, as production drafts expect.' }
		]
	},
	{
		slug: 'omit-a-scene',
		title: 'Omit a scene, restore it later',
		category: 'scenes',
		summary: 'A reversible cut that keeps the scene’s number.',
		related: ['scene-numbering', 'find-a-scene', 'export-pdf'],
		blocks: [
			{ type: 'p', text: 'Cutting a scene does not have to mean deleting it. Omitting folds the scene away and leaves a card in its place marked OMITTED, with the scene’s number on it — so schedules never grow a hole.' },
			{ type: 'h', text: 'What happens' },
			{ type: 'list', items: [
				'The scene’s text stays in your file. Nothing is deleted.',
				'The scene does not print or export while it is omitted.',
				'Its number is kept, so the scenes around it are not renumbered.'
			] },
			{ type: 'p', text: 'Restore brings the scene back exactly as written — same words, same number. The whole thing is reversible.' },
			{ type: 'tip', text: 'Omit instead of deleting anything you might want back. Deletion is the one gesture there is no undo for across saves.' }
		]
	},
	{
		slug: 'find-a-scene',
		title: 'Find a scene or words',
		category: 'scenes',
		summary: 'Find Scene ⌘L, Find ⌘F, Find Next ⌘G.',
		related: ['scene-numbering', 'omit-a-scene', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'Two searches, two jobs. Find looks for text. Find Scene takes you to a scene.' },
			{ type: 'list', items: [
				'Edit → Find Scene (⌘L) jumps scene to scene — the go-to-scene command.',
				'Edit → Find… (⌘F) opens the system find bar.',
				'⌘G finds the next match, ⇧⌘G the previous one.'
			] },
			{ type: 'p', text: 'The find bar is the macOS one you already know — the same search every other app on your Mac uses.' }
		]
	},
	{
		slug: 'pages-and-continuous',
		title: 'Pages and Continuous',
		category: 'pages',
		summary: 'Sheets for proofing, one column for drafting. Same pagination.',
		related: ['arrangements-and-zoom', 'page-settings', 'print'],
		blocks: [
			{ type: 'p', text: 'View → Pages draws your script as sheets, with their margins, exactly as they print. View → Continuous collapses the page margins into one column for drafting.' },
			{ type: 'h', text: 'Why both' },
			{ type: 'p', text: 'Drafting is reading a column — page margins repeated every fifty-five lines are a lot of scrolling for nothing. Proofing is the opposite: you want to see page turns, and where a scene lands.' },
			{ type: 'p', text: 'One thing never changes: which line begins which page. Continuous marks the page boundary with the page number instead of the margin, so your clock — a page is a minute of screen time — stays honest in both views.' },
			{ type: 'tip', text: 'The page count in the window subtitle is your running time. It only deserves trust because what you see is what prints.' }
		]
	},
	{
		slug: 'arrangements-and-zoom',
		title: 'Arrange and zoom the pages',
		category: 'pages',
		summary: 'Single, Two-page, Grid — and Preview’s zoom keys.',
		related: ['pages-and-continuous', 'page-settings', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'When the script is sheets, View arranges them three ways: Single (one sheet under the next), Two-page (an open book, facing sheets with a hairline between), and Grid (a bird’s-eye of every sheet — a map, not a writing surface).' },
			{ type: 'h', text: 'Zoom' },
			{ type: 'table', head: ['Command', 'Shortcut'], rows: [
				['View → Zoom In', '⌘+'],
				['View → Zoom Out', '⌘−'],
				['View → Actual Size', '⌘0'],
				['View → Zoom to Fit', '⌘9']
			] },
			{ type: 'p', text: 'The zoom keys are the ones Preview uses, so they are already in your hands.' }
		]
	},
	{
		slug: 'page-settings',
		title: 'Paper size, page numbers, and dark page',
		category: 'pages',
		summary: 'eDraft → Settings… (⌘,) holds everything about the page.',
		related: ['pages-and-continuous', 'arrangements-and-zoom', 'title-page'],
		blocks: [
			{ type: 'p', text: 'Choose eDraft → Settings… (⌘,). What is true for every script lives here; what is true of one script lives in that script.' },
			{ type: 'h', text: 'Page' },
			{ type: 'list', items: [
				'Paper Size — US Letter (55 lines) or A4 (58 lines), with the same margins.',
				'Page Numbers — whether pages carry their number.'
			] },
			{ type: 'h', text: 'Appearance' },
			{ type: 'p', text: 'Page chooses how the sheet behaves in dark mode: Paper keeps the page light, as it prints. Dark Page darkens the sheet with the app.' },
			{ type: 'p', text: 'A change here restyles every open window and every export — nothing needs re-opening and nothing needs saving.' },
			{ type: 'tip', text: 'The Settings window also shows your version and a Send Feedback link, in case you ever need either.' }
		]
	},
	{
		slug: 'title-page',
		title: 'The title page',
		category: 'pages',
		summary: 'File → Title Page… — the same sheet on Mac and iPhone.',
		related: ['page-settings', 'export-pdf', 'print'],
		blocks: [
			{ type: 'p', text: 'Choose File → Title Page…. The title page is part of the document, and it prints with the script.' },
			{ type: 'p', text: 'The Mac presents the same sheet the iPhone does — one form, not two. What you fill in on one device is what you see on the other.' },
			{ type: 'tip', text: 'The title page travels with the file through FDX and Fountain exports, so other tools see it too.' }
		]
	},
	{
		slug: 'where-files-live',
		title: 'Where your scripts live',
		category: 'files',
		summary: '.draft documents anywhere you save them, iCloud Drive, files you own forever.',
		related: ['open-and-manage', 'fountain-and-fdx', 'page-settings'],
		blocks: [
			{ type: 'p', text: 'Your scripts are files — .draft documents that belong to you, saved wherever you choose: on your Mac, or in iCloud Drive.' },
			{ type: 'h', text: 'iCloud' },
			{ type: 'p', text: 'When you save into iCloud Drive, eDraft reads and writes only inside its own container, named iCloud.xyz.edraft. Sync between your devices runs through your own Apple account. eDraft has no server and receives no copy of your files.' },
			{ type: 'h', text: 'Files you own forever' },
			{ type: 'p', text: 'There is no lock-in and no library to export from. A script is a document in a folder, like any other file on your Mac. Move it, copy it, back it up — it is yours.' },
			{ type: 'tip', text: 'eDraft collects no data at all. The App Store disclosure is Data Not Collected — no analytics, no crash reporting, no accounts.' }
		]
	},
	{
		slug: 'fountain-and-fdx',
		title: 'Fountain and Final Draft files',
		category: 'files',
		summary: 'What moves cleanly between apps, and what to check.',
		related: ['import-final-draft', 'export-final-draft', 'export-fountain-text'],
		blocks: [
			{ type: 'p', text: 'eDraft speaks two interchange formats, and is honest about both.' },
			{ type: 'h', text: 'Fountain — plain text' },
			{ type: 'p', text: 'Fountain files are plain text with simple conventions: INT. and EXT. for headings, capitalized names for characters, [[ ]] for notes. Any text editor can open one, and the words are never trapped.' },
			{ type: 'h', text: 'Final Draft — a bounded subset' },
			{ type: 'p', text: 'FDX support covers a defined subset of the format — screenplay content, scene numbers, notes, and title page. eDraft imports and exports that subset with explicit warnings when something falls outside it, instead of guessing.' },
			{ type: 'p', text: 'Files exported under eDraft’s former name still open; a rename is our problem, never a writer’s.' },
			{ type: 'tip', text: 'For a production script, review the import or export report and keep the original file until the round trip is verified.' }
		]
	},
	{
		slug: 'export-pdf',
		title: 'Export a PDF',
		category: 'export',
		summary: 'Formatted pages for reading and sharing.',
		related: ['print', 'title-page', 'omit-a-scene'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File → Export → PDF….',
				'Pick a name and a folder.',
				'Done — the pages are exactly what you saw on screen.'
			] },
			{ type: 'p', text: 'Pagination is decided by the engine, not by screen pixels, so the exported pages match the page count in the window subtitle. Omitted scenes stay out of the PDF, marked by their OMITTED card.' },
			{ type: 'tip', text: 'The title page prints with the script.' }
		]
	},
	{
		slug: 'export-final-draft',
		title: 'Export to Final Draft',
		category: 'export',
		summary: 'A .fdx another app can open. Review the report.',
		related: ['import-final-draft', 'fountain-and-fdx', 'export-pdf'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File → Export → Final Draft….',
				'Pick a name and a folder — the file gets the .fdx extension.',
				'Open it in Final Draft and check the pages.'
			] },
			{ type: 'p', text: 'The export writes the screenplay content of the FDX subset — elements, scene numbers, notes, title page. Anything outside the subset is reported, not guessed.' },
			{ type: 'tip', text: 'Keep your .draft as the working file and treat the .fdx as what you hand over.' }
		]
	},
	{
		slug: 'export-fountain-text',
		title: 'Export Fountain or plain text',
		category: 'export',
		summary: 'Readable plain text any tool opens.',
		related: ['fountain-and-fdx', 'export-pdf', 'where-notes-live'],
		blocks: [
			{ type: 'p', text: 'Two exports for when the words matter more than the layout.' },
			{ type: 'list', items: [
				'File → Export → Fountain… writes the screenplay as plain text with Fountain conventions — notes as [[ ]], ready for any Fountain-aware tool.',
				'File → Export → Plain Text… writes the script as readable text with no conventions at all.'
			] },
			{ type: 'p', text: 'Both open in any text editor, on any platform, now and in twenty years.' }
		]
	},
	{
		slug: 'print',
		title: 'Print and Page Setup',
		category: 'export',
		summary: '⌘P prints. ⇧⌘P sets the paper.',
		related: ['export-pdf', 'page-settings', 'pages-and-continuous'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File → Page Setup… (⇧⌘P) to confirm the paper and orientation.',
				'Choose File → Print… (⌘P) and print as you would from any Mac app.'
			] },
			{ type: 'p', text: 'What prints is the Pages layout — the sheets, their margins, and the page numbers, exactly as on screen. Omitted scenes print as their OMITTED card.' }
		]
	},
	{
		slug: 'keyboard-shortcuts',
		title: 'Keyboard shortcuts',
		category: 'support',
		summary: 'Every eDraft shortcut in one table.',
		related: ['tab-and-return', 'writing-suggestions', 'find-a-scene'],
		blocks: [
			{ type: 'p', text: 'Every shortcut eDraft defines, by menu. Standard Mac shortcuts — copy, paste, quit — are not listed; they are the ones every app uses.' },
			{ type: 'table', head: ['Command', 'Shortcut'], rows: [
				['File → New', '⌘N'],
				['File → Open…', '⌘O'],
				['File → Close', '⌘W'],
				['File → Save', '⌘S'],
				['File → Duplicate', '⇧⌘S'],
				['File → Page Setup…', '⇧⌘P'],
				['File → Print…', '⌘P'],
				['Edit → Undo / Redo', '⌘Z / ⇧⌘Z'],
				['Edit → Accept Suggestion', '⌘→'],
				['Edit → Add Note', '⇧⌘K'],
				['Edit → Find…', '⌘F'],
				['Edit → Find Next / Previous', '⌘G / ⇧⌘G'],
				['Edit → Find Scene', '⌘L'],
				['Format → Scene Heading', '⌘1'],
				['Format → Action', '⌘2'],
				['Format → Character', '⌘3'],
				['Format → Parenthetical', '⌘4'],
				['Format → Dialogue', '⌘5'],
				['Format → Transition', '⌘6'],
				['Format → Shot', '⌘7'],
				['Format → General', '⌘8'],
				['Format → Lyrics', '⌘9'],
				['View → Zoom In / Out', '⌘+ / ⌘−'],
				['View → Actual Size', '⌘0'],
				['View → Zoom to Fit', '⌘9'],
				['View → Show Sidebar', '⌃⌘S'],
				['View → Enter Full Screen', '⌃⌘F'],
				['eDraft → Settings…', '⌘,'],
				['Help → eDraft Help', '⌘?']
			] },
			{ type: 'tip', text: 'Press ? inside the app for the same list, without leaving the page.' }
		]
	},
	{
		slug: 'troubleshooting',
		title: 'Troubleshooting',
		category: 'support',
		summary: 'The four things to try before anything else.',
		related: ['contact', 'import-final-draft', 'open-and-manage'],
		blocks: [
			{ type: 'h', text: 'A change went wrong' },
			{ type: 'p', text: 'File → Revert To → Last Saved returns to the last saved state, and Browse All Versions… lets you pull from earlier saves.' },
			{ type: 'h', text: 'An FDX file looks off' },
			{ type: 'p', text: 'Check the import report first — eDraft warns instead of guessing when a file is outside the supported subset. Keep the original and compare against it.' },
			{ type: 'h', text: 'Pages do not match another app' },
			{ type: 'p', text: 'Pagination follows the paper size and margins in eDraft → Settings…. Confirm Paper Size matches the other app’s setup before comparing page counts.' },
			{ type: 'h', text: 'Something feels broken' },
			{ type: 'p', text: 'Note your version — eDraft → Settings… shows it — and tell us what you expected. A screenshot and the steps are usually enough.' },
			{ type: 'tip', text: 'Still stuck? The contact article lists the ways to reach a person.' }
		]
	},
	{
		slug: 'contact',
		title: 'Contact support',
		category: 'support',
		summary: 'Email, GitHub issues, and Send Feedback.',
		related: ['troubleshooting', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'Two ways to reach us, and both go to a person.' },
			{ type: 'list', items: [
				'Email [SUPPORT EMAIL] — for anything about your work, your files, or your privacy.',
				'GitHub issues at github.com/Yasirdora/edraft/issues — for bugs, with a screenshot and your version from eDraft → Settings….'
			] },
			{ type: 'p', text: 'Prefer not to leave the app? eDraft → Settings… has a Send Feedback link that opens a addressed message.' },
			{ type: 'tip', text: 'Security issues should not be posted publicly — use GitHub private vulnerability reporting instead.' }
		]
	}
];

export function articlesInCategory(categoryId: string): HelpArticle[] {
	return helpArticles.filter((article) => article.category === categoryId);
}

export function getArticle(slug: string): HelpArticle | undefined {
	return helpArticles.find((article) => article.slug === slug);
}

export function getCategory(id: string): HelpCategory | undefined {
	return helpCategories.find((category) => category.id === id);
}

/** Flat, lowercase text of an article — the build-time search index. */
function indexText(article: HelpArticle): string {
	const parts = [article.title, article.summary];
	for (const block of article.blocks) {
		if (block.type === 'table') {
			parts.push(...block.head, ...block.rows.flat());
		} else if (block.type === 'p' || block.type === 'h' || block.type === 'tip') {
			parts.push(block.text);
		} else {
			parts.push(...block.items);
		}
	}
	return parts.join('\n').toLowerCase();
}

const searchIndex = new Map(helpArticles.map((article) => [article.slug, indexText(article)]));

/** Client-side search over the article index. Empty query returns nothing. */
export function searchArticles(query: string): HelpArticle[] {
	const needle = query.trim().toLowerCase();
	if (!needle) return [];
	const terms = needle.split(/\s+/);
	return helpArticles.filter((article) => {
		const haystack = searchIndex.get(article.slug) ?? '';
		return terms.every((term) => haystack.includes(term));
	});
}
