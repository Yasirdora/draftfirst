/**
 * eDraft Help Center content — one structured module.
 *
 * Every article is data, not markup: title, slug, category, a one-line
 * summary, related slugs, and body blocks. The same data will later
 * generate the Apple Help Book, so keep everything here plain and
 * serializable. Renderers live in the routes; they never invent content.
 *
 * Written to Apple's help standard for the Mac app: imperative titles for
 * tasks, "Intro to …" for concepts, "If …" for problems; second person;
 * menu paths as "File > Export > PDF"; the app's own names for things. A
 * Tip only when it saves the reader time; a caveat is a Note. Every claim
 * is true of the app as it ships — a behaviour that is not built yet does
 * not get an article.
 */

export type HelpBlock =
	| { type: 'p'; text: string }
	| { type: 'h'; text: string }
	| { type: 'list'; items: string[] }
	| { type: 'steps'; items: string[] }
	| { type: 'table'; head: string[]; rows: string[][] }
	| { type: 'tip'; text: string }
	| { type: 'note'; text: string };

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
	{ id: 'getting-started', name: 'Get started', description: 'The library, new scripts, and Final Draft files.' },
	{ id: 'writing', name: 'Write', description: 'Elements, Tab and Return, suggestions, and emphasis.' },
	{ id: 'notes', name: 'Notes', description: 'Add notes to lines and review them in the Navigator.' },
	{ id: 'scenes', name: 'Scenes & structure', description: 'The Navigator, scene numbers, omitted scenes, and characters.' },
	{ id: 'pages', name: 'Pages & view', description: 'Page layouts, zoom, Focus, Dark Mode, and the title page.' },
	{ id: 'files', name: 'Final Draft & files', description: 'Saving, versions, Final Draft and Fountain files, and privacy.' },
	{ id: 'export', name: 'Export & print', description: 'PDF, Final Draft, Fountain, plain text, and printing.' },
	{ id: 'support', name: 'Shortcuts & support', description: 'Keyboard shortcuts, fixes for common problems, and contact.' }
];

export const popularArticles = [
	'import-final-draft',
	'tab-and-return',
	'omit-a-scene',
	'export-pdf',
	'keyboard-shortcuts'
];

export const helpArticles: HelpArticle[] = [
	// Get started

	{
		slug: 'intro-to-edraft',
		title: 'Intro to eDraft',
		category: 'getting-started',
		summary: 'The library, the script window, and where the commands are.',
		related: ['use-the-library', 'use-the-navigator', 'screenplay-elements'],
		blocks: [
			{ type: 'p', text: 'eDraft is a screenwriting app. As you type, it formats each line as part of a screenplay — a scene heading, action, a character’s name, dialogue — on pages laid out the way they print.' },
			{ type: 'h', text: 'The library' },
			{ type: 'p', text: 'When you open eDraft, the library shows the scripts you opened most recently. Click a script to open it, or click New Screenplay to start one.' },
			{ type: 'h', text: 'The script window' },
			{ type: 'list', items: [
				'The Navigator, on the left, lists the script’s scenes, its cast, and its notes. Click an item to go to it.',
				'The page, in the middle, is where you write.',
				'The toolbar has Back, which returns to the library; the Element button, which shows the current line’s element; Focus; Layout; Page; Title Page; Export; and More.',
				'Below the script’s name, the window shows its page count and an estimate of its running time.',
				'The zoom control is in the lower-right corner of the window.'
			] },
			{ type: 'p', text: 'Commands for elements, scene numbers, and omitted scenes are in the Format menu. Commands for how the page looks are in the View menu.' }
		]
	},
	{
		slug: 'start-a-screenplay',
		title: 'Create a screenplay',
		category: 'getting-started',
		summary: 'Start a new script and choose where it’s saved.',
		related: ['use-the-library', 'where-files-live', 'title-page'],
		blocks: [
			{ type: 'steps', items: [
				'In the library, click New Screenplay, or choose File > New (⌘N).',
				'Start typing on the page. To begin a scene heading, type INT. or EXT.',
				'Choose File > Save (⌘S), enter a name, then click Save.'
			] },
			{ type: 'p', text: 'The first time you save a new script, eDraft suggests the eDraft folder in iCloud Drive. You can choose another folder instead.' },
			{ type: 'p', text: 'After the first save, eDraft saves your changes as you work.' },
			{ type: 'p', text: 'A new script starts with a title page titled Untitled Screenplay. To change it, see Create a title page.' }
		]
	},
	{
		slug: 'use-the-library',
		title: 'Find and manage scripts in the library',
		category: 'getting-started',
		summary: 'Open recent scripts, search, mark favorites, and move scripts to the Trash.',
		related: ['start-a-screenplay', 'open-and-manage', 'where-files-live'],
		blocks: [
			{ type: 'p', text: 'The library opens when you start eDraft. It shows your most recent scripts, newest first, with the date each one last changed.' },
			{ type: 'p', text: 'To return to the library from a script, click Back in the toolbar. The script’s window closes.' },
			{ type: 'h', text: 'Find a script' },
			{ type: 'list', items: [
				'To switch between cards and a list, click Grid or List in the toolbar.',
				'To find a script by name, type in the search field in the toolbar.',
				'Favorites always appear first.'
			] },
			{ type: 'h', text: 'Manage a script' },
			{ type: 'p', text: 'Click the More button (…) next to a script’s name, then choose any of the following:' },
			{ type: 'list', items: [
				'Open in New Window: Opens the script in a new window.',
				'Rename: Changes the script’s name. The file stays in the same folder.',
				'Duplicate: Makes a copy of the script.',
				'Favorite or Unfavorite: Keeps the script at the top of the library, or stops keeping it there.',
				'Move to Trash: Moves the file to the Trash. To put it back, click Undo in the bar at the bottom of the window.'
			] }
		]
	},
	{
		slug: 'import-final-draft',
		title: 'Open a Final Draft file',
		category: 'getting-started',
		summary: 'Open a .fdx script and keep working in it.',
		related: ['final-draft-files', 'final-draft-page-locks', 'share-with-final-draft-users'],
		blocks: [
			{ type: 'p', text: 'eDraft opens Final Draft files (.fdx) and saves your changes back to the same file, so the script stays a Final Draft file.' },
			{ type: 'steps', items: [
				'Choose File > Open (⌘O).',
				'Select the .fdx file, then click Open.'
			] },
			{ type: 'p', text: 'You can also Control-click the file in the Finder, then choose Open With > eDraft.' },
			{ type: 'note', text: 'eDraft saves your changes to the .fdx file as you work. To keep an unchanged copy, duplicate the file in the Finder before you open it: select the file, then choose File > Duplicate.' },
			{ type: 'h', text: 'What you see' },
			{ type: 'p', text: 'The script’s text, scene numbers, title page, and notes open in eDraft. Notes written in Final Draft can be read but not changed. Scenes omitted in Final Draft appear as OMITTED cards.' },
			{ type: 'h', text: 'What eDraft keeps' },
			{ type: 'p', text: 'A Final Draft file can hold things eDraft doesn’t show, such as revisions, locked pages, and tags. eDraft keeps them in the file, and when it saves, it rewrites only the parts of the script you changed.' },
			{ type: 'p', text: 'If the script has locked pages, eDraft tells you the first time you edit it. See Edit a Final Draft script with locked pages.' }
		]
	},

	// Write

	{
		slug: 'screenplay-elements',
		title: 'Intro to screenplay elements',
		category: 'writing',
		summary: 'The kinds of lines a screenplay is made of.',
		related: ['change-an-element', 'tab-and-return', 'writing-suggestions'],
		blocks: [
			{ type: 'p', text: 'Every line in a screenplay is an element. eDraft sets the margins and capitals for each element, so you only choose which element a line is.' },
			{ type: 'table', head: ['Element', 'Use it for'], rows: [
				['Scene Heading', 'Where and when a scene takes place: INT. KITCHEN - NIGHT'],
				['Action', 'What the audience sees and hears'],
				['Character', 'The name of the person who speaks'],
				['Parenthetical', 'A short direction for how a line is spoken'],
				['Dialogue', 'What the character says'],
				['Transition', 'A move between scenes, such as CUT TO:'],
				['Shot', 'A particular camera shot, such as CLOSE ON'],
				['General', 'Text that isn’t one of the other elements'],
				['Centered', 'A line centered on the page, such as THE END'],
				['Lyrics', 'The words of a song']
			] },
			{ type: 'p', text: 'The Element button in the toolbar shows the element of the line you’re typing in.' },
			{ type: 'tip', text: 'Start a line with INT. or EXT. and eDraft makes it a scene heading as you type.' }
		]
	},
	{
		slug: 'change-an-element',
		title: 'Change a line’s element',
		category: 'writing',
		summary: 'Use the Format menu, the toolbar, or the keyboard.',
		related: ['screenplay-elements', 'tab-and-return', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'Click in the line, then do any of the following:' },
			{ type: 'list', items: [
				'Choose Format > Element, then choose an element.',
				'Press one of the shortcuts in the table below.',
				'Click the Element button in the toolbar, then choose an element. The elements that fit best where you’re typing are listed first, under Suggested.',
				'Press Tab to step through the elements that can follow the line above. See Move between elements with Tab and Return.'
			] },
			{ type: 'table', head: ['Element', 'Shortcut'], rows: [
				['Scene Heading', '⌘1'],
				['Action', '⌘2'],
				['Character', '⌘3'],
				['Parenthetical', '⌘4'],
				['Dialogue', '⌘5'],
				['Transition', '⌘6'],
				['Shot', '⌘7'],
				['General', '⌘8'],
				['Lyrics', '⌘9']
			] },
			{ type: 'p', text: 'Centered is in the toolbar’s Element menu, and Lyrics is in Format > Element.' }
		]
	},
	{
		slug: 'tab-and-return',
		title: 'Move between elements with Tab and Return',
		category: 'writing',
		summary: 'Change the current line with Tab; start the next one with Return.',
		related: ['change-an-element', 'writing-suggestions', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'Tab changes the element of the line you’re typing in. Return starts a new line and chooses its element for you.' },
			{ type: 'h', text: 'Tab' },
			{ type: 'p', text: 'Press Tab to change the current line to the next element that can follow the line above it. Press Shift-Tab to go back.' },
			{ type: 'table', head: ['After this line', 'Tab steps through'], rows: [
				['Scene Heading or Action', 'Action, Character, Transition'],
				['Character', 'Dialogue, Parenthetical'],
				['Parenthetical', 'Dialogue'],
				['Dialogue', 'Dialogue, Transition, Scene Heading, Action, Character'],
				['Any other line, or the top of the script', 'Scene Heading, Action, Character, Transition']
			] },
			{ type: 'h', text: 'Return' },
			{ type: 'p', text: 'Press Return at the end of a line to start a new one. The new line’s element depends on the line you finished:' },
			{ type: 'table', head: ['After', 'Return starts'], rows: [
				['Scene Heading', 'Action'],
				['Action', 'Action'],
				['Character', 'Dialogue'],
				['Parenthetical', 'Dialogue'],
				['Dialogue', 'Character'],
				['Transition', 'Scene Heading'],
				['Shot, General, or Centered', 'Action'],
				['Lyrics', 'Lyrics']
			] },
			{ type: 'p', text: 'If the line is empty, Return changes it instead of adding a line: an empty Action line becomes Character, and any other empty line becomes Action.' },
			{ type: 'tip', text: 'To write a speech, press Return after the character’s name and type the dialogue. Press Return twice after the dialogue to go back to action.' }
		]
	},
	{
		slug: 'writing-suggestions',
		title: 'Accept writing suggestions',
		category: 'writing',
		summary: 'Finish names, places, and extensions with one key.',
		related: ['tab-and-return', 'screenplay-elements', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'As you type, eDraft may suggest how to finish the line — a character’s name, a location already in your script, or an extension such as (V.O.). The suggestion appears as dimmed text after the insertion point.' },
			{ type: 'p', text: 'To accept a suggestion, do any of the following:' },
			{ type: 'list', items: [
				'Press ⌘→, or choose Edit > Accept Suggestion.',
				'At the end of the line, press Space.',
				'Click the suggestion.'
			] },
			{ type: 'p', text: 'Accepting fills in the rest of the suggestion. To ignore a suggestion, keep typing.' },
			{ type: 'p', text: 'Suggestions come from your own script and are made on your Mac.' }
		]
	},
	{
		slug: 'add-emphasis',
		title: 'Add bold, italic, underline, or a highlight',
		category: 'writing',
		summary: 'Format selected words from the bar above the selection.',
		related: ['add-a-note', 'screenplay-elements', 'export-pdf'],
		blocks: [
			{ type: 'steps', items: [
				'Select the words you want to format.',
				'In the bar that appears above the selection, click Bold, Italic, Underline, Strikethrough, or Highlight.'
			] },
			{ type: 'p', text: 'To remove the formatting, select the same words and click the button again.' },
			{ type: 'p', text: 'Highlights are yellow, and they print. The bar also has Add Note; see Add a note to a line.' },
			{ type: 'note', text: 'Highlights are kept only in Final Draft (.fdx) files. eDraft scripts (.draft) and Fountain files don’t keep them after you close the script, and Final Draft removes them when it saves a file.' }
		]
	},

	// Notes

	{
		slug: 'add-a-note',
		title: 'Add a note to a line',
		category: 'notes',
		summary: 'Leave a note beside a line. Notes never print.',
		related: ['edit-notes', 'review-notes', 'where-notes-live'],
		blocks: [
			{ type: 'steps', items: [
				'Click in the line.',
				'Choose Edit > Add Note (⇧⌘K).',
				'Type your note, then click Done.'
			] },
			{ type: 'p', text: 'The first time you add a note, eDraft asks for your name and, if you like, your role. Your notes carry this name, in eDraft and in Final Draft. The name is kept on this Mac.' },
			{ type: 'p', text: 'A note appears as a mark in the right margin, beside its line. Notes don’t print.' },
			{ type: 'p', text: 'You can also add a note in these ways:' },
			{ type: 'list', items: [
				'Control-click a line, then choose Add Note.',
				'Select some text, then click Add Note in the bar above the selection. The note goes on the line.',
				'Click More in the toolbar, then choose Add Note.'
			] }
		]
	},
	{
		slug: 'edit-notes',
		title: 'Read, edit, or delete a note',
		category: 'notes',
		summary: 'Open a line’s notes from its mark in the margin.',
		related: ['add-a-note', 'review-notes', 'where-notes-live'],
		blocks: [
			{ type: 'p', text: 'Click a note’s mark in the margin to open the card for that line. The card shows every note on the line.' },
			{ type: 'p', text: 'In the card, do any of the following:' },
			{ type: 'list', items: [
				'Edit a note: Click in its text, make your changes, then click Done.',
				'Add another note to the same line: Click Add.',
				'Delete a note: Click its Delete button (trash).'
			] },
			{ type: 'p', text: 'Notes written in Final Draft show who wrote them. You can read them in eDraft; to change them, use Final Draft.' },
			{ type: 'p', text: 'Each person’s notes have their own color, in the margin and in the Navigator.' }
		]
	},
	{
		slug: 'review-notes',
		title: 'Review notes in the Navigator',
		category: 'notes',
		summary: 'See every note in the script in one list.',
		related: ['add-a-note', 'edit-notes', 'use-the-navigator'],
		blocks: [
			{ type: 'steps', items: [
				'If the Navigator is hidden, choose View > Show Sidebar (⌃⌘S).',
				'Click Notes at the top of the Navigator.',
				'Click a note to go to its line.'
			] },
			{ type: 'p', text: 'To narrow the list, type in the search field. eDraft matches the note’s words, its author, and the scene it’s in.' },
			{ type: 'p', text: 'To see one person’s notes, click the filter button next to the search field, then choose a name. To see everyone’s notes again, choose All Notes.' },
			{ type: 'p', text: 'The bottom of the Navigator shows how many notes there are and how many scenes have them.' }
		]
	},
	{
		slug: 'where-notes-live',
		title: 'How eDraft saves notes',
		category: 'notes',
		summary: 'Notes are saved in the script file, in a form other apps can read.',
		related: ['add-a-note', 'final-draft-files', 'fountain-files'],
		blocks: [
			{ type: 'p', text: 'Notes are saved in the script file itself, so they go wherever the file goes.' },
			{ type: 'list', items: [
				'In an eDraft script (.draft) or a Fountain file, a note is saved as text in double brackets, [[like this]], just before its line.',
				'In a Final Draft file, a note is saved as a Final Draft note titled [eDraft], with your name as its author.',
				'Notes that came from Final Draft stay exactly as they were.'
			] },
			{ type: 'p', text: 'Notes never print and aren’t part of the script’s pages.' }
		]
	},

	// Scenes & structure

	{
		slug: 'use-the-navigator',
		title: 'Move around your script with the Navigator',
		category: 'scenes',
		summary: 'Go to any scene, character, or note.',
		related: ['find-a-scene', 'character-scenes', 'review-notes'],
		blocks: [
			{ type: 'p', text: 'The Navigator is the list on the left side of the script window. To show or hide it, choose View > Show Sidebar (⌃⌘S), or click the sidebar button in the toolbar.' },
			{ type: 'p', text: 'Click Scenes, Cast, or Notes at the top of the Navigator to choose what it lists:' },
			{ type: 'list', items: [
				'Scenes: Every scene, with its number, its heading, and the page it starts on. Click a scene to go to it; eDraft marks the heading so you can find it on the page.',
				'Cast: Every character who speaks, with the number of times each one is cued. Click a name to see every scene they’re in.',
				'Notes: Every note in the script. Click a note to go to its line.'
			] },
			{ type: 'h', text: 'Narrow the scene list' },
			{ type: 'list', items: [
				'To find a scene, type part of its heading or its number in the search field.',
				'To show only interiors or exteriors, click the filter button next to the search field, then choose Interior, Exterior, or Int. / Ext. To see every scene again, choose All Scenes.'
			] },
			{ type: 'p', text: 'The bottom of the Navigator shows the script’s length in pages, its estimated running time, and its word count, with counts of its scenes and locations.' },
			{ type: 'p', text: 'Omitted scenes stay in the list, dimmed, with how much of a page each one cut.' }
		]
	},
	{
		slug: 'find-a-scene',
		title: 'Find a scene or text',
		category: 'scenes',
		summary: 'Go to a scene by heading or number, or search the script’s words.',
		related: ['use-the-navigator', 'scene-numbering', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'h', text: 'Go to a scene' },
			{ type: 'steps', items: [
				'Choose Edit > Find Scene (⌘L). The Navigator shows the scene list, ready for you to type.',
				'Type part of the scene’s heading or its number.',
				'Press Return to go to the first scene in the list.'
			] },
			{ type: 'h', text: 'Find words' },
			{ type: 'list', items: [
				'Choose Edit > Find > Find (⌘F), then type in the find bar.',
				'To go to the next match, press ⌘G. To go to the previous match, press ⇧⌘G.'
			] }
		]
	},
	{
		slug: 'scene-numbering',
		title: 'Number scenes',
		category: 'scenes',
		summary: 'Add, renumber, or remove scene numbers.',
		related: ['omit-a-scene', 'use-the-navigator', 'find-a-scene'],
		blocks: [
			{ type: 'p', text: 'Scene numbers print in both margins beside each scene heading, and appear next to each scene in the Navigator.' },
			{ type: 'p', text: 'Choose Format > Scene Numbers, then choose one of the following:' },
			{ type: 'list', items: [
				'Number New Scenes: Numbers only the scenes that don’t have a number yet, and keeps every existing number. A scene added after 12 becomes 12A. If no scene has a number, every scene is numbered from 1.',
				'Number All Scenes: Numbers every scene again, starting from 1. Numbers already in use can change, so eDraft asks you to confirm.',
				'Remove Scene Numbers: Removes every scene number. eDraft asks you to confirm. This command is dimmed when the script has no scene numbers.'
			] },
			{ type: 'tip', text: 'Once a script has gone to a production, use Number New Scenes. It never changes a number that a schedule or call sheet may already cite.' }
		]
	},
	{
		slug: 'omit-a-scene',
		title: 'Omit or restore a scene',
		category: 'scenes',
		summary: 'Cut a scene but keep its number and its text.',
		related: ['scene-numbering', 'if-omit-scene-is-dimmed', 'final-draft-files'],
		blocks: [
			{ type: 'p', text: 'When you omit a scene, eDraft replaces it on the page with an OMITTED card that keeps the scene’s number. The scene’s text stays in the file, so you can restore it later exactly as it was.' },
			{ type: 'note', text: 'You can omit scenes only in Final Draft (.fdx) scripts. In other scripts, Omit Scene is dimmed. See If Omit Scene is dimmed.' },
			{ type: 'h', text: 'Omit a scene' },
			{ type: 'p', text: 'Do any of the following:' },
			{ type: 'list', items: [
				'In the Navigator, hold the pointer over the scene, then click the Omit Scene button (scissors).',
				'Control-click the scene’s heading on the page, then choose Omit Scene.',
				'Click anywhere in the scene, then choose Format > Omit Scene.'
			] },
			{ type: 'h', text: 'Restore a scene' },
			{ type: 'p', text: 'Do any of the following:' },
			{ type: 'list', items: [
				'In the Navigator, hold the pointer over the omitted scene, then click the Restore Scene button.',
				'Control-click the OMITTED card, then choose Restore Scene.',
				'Click the OMITTED card, then choose Format > Restore Scene.'
			] },
			{ type: 'p', text: 'The scene comes back with its words and its number. To reverse either change right away, choose Edit > Undo (⌘Z).' },
			{ type: 'h', text: 'Work around an omitted scene' },
			{ type: 'list', items: [
				'To read the cut text, hold the pointer over the OMITTED card, then click the arrow at the end of the line. Click it again to hide the text.',
				'You can’t type in an omitted scene. To change its text, restore it first.',
				'The insertion point skips over an omitted scene. You can still select across one and copy it.',
				'A line you add at the OMITTED card goes after the omitted scene, not inside it.'
			] },
			{ type: 'p', text: 'In the Navigator, an omitted scene is dimmed and shows how many pages were cut.' }
		]
	},
	{
		slug: 'character-scenes',
		title: 'See every scene a character is in',
		category: 'scenes',
		summary: 'Open a character’s scenes and speeches beside the page.',
		related: ['rename-a-character', 'use-the-navigator', 'focus'],
		blocks: [
			{ type: 'steps', items: [
				'In the Navigator, click Cast.',
				'Click a character’s name.'
			] },
			{ type: 'p', text: 'A column opens beside the page, listing every scene the character is in and every line they speak. Click a scene heading or a line to go to it on the page.' },
			{ type: 'p', text: 'To close the column, click the character’s name again, or click Scenes or Notes.' },
			{ type: 'p', text: 'To change the order of the cast list, click the sort button next to the search field, then choose Lead, to list the characters who speak most first, or Alphabetical.' }
		]
	},
	{
		slug: 'rename-a-character',
		title: 'Rename a character',
		category: 'scenes',
		summary: 'Change a character’s name in every cue, and in action and dialogue if you choose.',
		related: ['character-scenes', 'use-the-navigator', 'find-a-scene'],
		blocks: [
			{ type: 'steps', items: [
				'In the Navigator, click Cast, then click the character’s name.',
				'At the top of the column that opens, click the More button (…), then choose Rename Character.',
				'Type the new name.',
				'If the name appears only in cues, click Rename. If it also appears in action or dialogue, click Rename Everywhere to change it there too, or Cues Only to change only the cues.'
			] },
			{ type: 'p', text: 'Before you rename, eDraft shows how many cues will change and how many other times the name appears. If the new name belongs to a character who already speaks, the two characters are merged.' }
		]
	},

	// Pages & view

	{
		slug: 'pages-and-continuous',
		title: 'View your script as pages or as one column',
		category: 'pages',
		summary: 'Switch between printed pages and one continuous column.',
		related: ['arrange-pages', 'zoom', 'page-settings'],
		blocks: [
			{ type: 'p', text: 'Choose View > Pages to see the script as sheets of paper, with their margins, as they print. Choose View > Continuous to see it as one column, without the space between pages.' },
			{ type: 'p', text: 'You can also choose Pages or Continuous from the More menu in the toolbar.' },
			{ type: 'p', text: 'In Continuous, each page break is marked with the number of the page that begins there. Pages break in the same places in both views.' },
			{ type: 'p', text: 'Below the script’s name, the window shows its page count and an estimate of its running time.' }
		]
	},
	{
		slug: 'arrange-pages',
		title: 'Show one page, two pages, or a grid',
		category: 'pages',
		summary: 'Arrange the pages on screen with the Layout menu.',
		related: ['pages-and-continuous', 'zoom', 'focus'],
		blocks: [
			{ type: 'p', text: 'Click the Layout button in the toolbar, then choose an arrangement:' },
			{ type: 'list', items: [
				'Single: One page after another, down the window.',
				'Two-page: Pages side by side in pairs, like an open book. You can write on either page.',
				'Grid: Every page as a small card, so you can see the whole script at once. You can’t type in Grid. To open a page, double-click it.'
			] },
			{ type: 'p', text: 'In Grid, clicking a scene in the Navigator highlights the page it’s on.' },
			{ type: 'p', text: 'If you choose Two-page or Grid while the script is in Continuous, eDraft switches to Pages. Choosing View > Continuous returns to Single.' }
		]
	},
	{
		slug: 'zoom',
		title: 'Zoom in or out',
		category: 'pages',
		summary: 'Make the page larger or smaller on screen.',
		related: ['arrange-pages', 'focus', 'keyboard-shortcuts'],
		blocks: [
			{ type: 'p', text: 'Do any of the following:' },
			{ type: 'list', items: [
				'Choose View > Zoom In (⌘+) or View > Zoom Out (⌘−).',
				'Choose View > Actual Size (⌘0) to see the page at 100%.',
				'Choose View > Zoom to Fit to fit the page to the window.',
				'Pinch on a trackpad.',
				'In the zoom control in the lower-right corner of the window, click − or +.'
			] },
			{ type: 'p', text: 'Click the percentage in the zoom control to switch between 100% and the size you were using. Near 100%, the percentage opens a menu of sizes instead, including Fit to Screen.' },
			{ type: 'p', text: 'The page can be shown from 100% to 200%.' }
		]
	},
	{
		slug: 'focus',
		title: 'Write in Focus',
		category: 'pages',
		summary: 'Hide everything but the page.',
		related: ['arrange-pages', 'zoom', 'dark-page'],
		blocks: [
			{ type: 'p', text: 'Click Focus in the toolbar to hide the Navigator, the character column, and the zoom control, so only the page is in the window. Click Focus again to bring them back.' },
			{ type: 'tip', text: 'To fill the screen too, choose View > Enter Full Screen (⌃⌘F).' }
		]
	},
	{
		slug: 'dark-page',
		title: 'Keep the page light or dark in Dark Mode',
		category: 'pages',
		summary: 'Choose whether the page darkens with the rest of the app.',
		related: ['page-settings', 'focus', 'pages-and-continuous'],
		blocks: [
			{ type: 'p', text: 'When your Mac uses Dark Mode, eDraft keeps the page light, like paper. You can choose a dark page instead.' },
			{ type: 'p', text: 'Do any of the following:' },
			{ type: 'list', items: [
				'Choose View > Paper or View > Dark Page.',
				'Click the Page button in the toolbar to switch between the two.',
				'Choose eDraft > Settings, then choose Paper or Dark Page under Appearance.'
			] },
			{ type: 'p', text: 'The choice applies to every open script. It makes no difference in Light Mode.' }
		]
	},
	{
		slug: 'page-settings',
		title: 'Change paper size and page numbers',
		category: 'pages',
		summary: 'Choose US Letter or A4, and whether pages are numbered.',
		related: ['print', 'export-pdf', 'if-page-counts-differ'],
		blocks: [
			{ type: 'steps', items: [
				'Choose eDraft > Settings (⌘,).',
				'Under Page, choose US Letter or A4 from the Paper Size menu.',
				'To turn page numbers on or off, click Page Numbers.'
			] },
			{ type: 'p', text: 'Page numbers appear at the top right of every page after the first.' },
			{ type: 'p', text: 'These settings apply to every script, and to every PDF and printout. Changing the paper size changes where pages break and how many pages a script has.' }
		]
	},
	{
		slug: 'title-page',
		title: 'Create a title page',
		category: 'pages',
		summary: 'Add the title, writing credit, writers, and contact details.',
		related: ['export-pdf', 'print', 'page-settings'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File > Title Page, or click Title Page in the toolbar.',
				'Click Title, Credit, or Writers to fill them in. To add a credit such as Based On, click Add Credit.',
				'To add your name, email, phone, and address, click Contact Information.',
				'Click Done.'
			] },
			{ type: 'p', text: 'In the Writers list, & joins writers who worked as a team, and “and” joins writers of separate drafts.' },
			{ type: 'p', text: 'The title page prints before the first page of the script. To leave it out of PDFs and printouts, turn off Include in PDF Export.' }
		]
	},

	// Final Draft & files

	{
		slug: 'where-files-live',
		title: 'Save scripts in iCloud Drive or on your Mac',
		category: 'files',
		summary: 'Where eDraft keeps your scripts, and how they’re saved.',
		related: ['open-and-manage', 'versions', 'privacy'],
		blocks: [
			{ type: 'p', text: 'An eDraft script is a file with the .draft extension. You can keep it in any folder on your Mac or in iCloud Drive.' },
			{ type: 'p', text: 'When you save a new script, eDraft suggests the eDraft folder in iCloud Drive. Files in iCloud Drive are available on your other devices signed in to the same Apple Account.' },
			{ type: 'p', text: 'After you save a script the first time, eDraft saves your changes as you work.' },
			{ type: 'p', text: 'A .draft file is plain text in the Fountain screenplay format, so other apps that read Fountain can open it. See Work with Fountain files.' }
		]
	},
	{
		slug: 'open-and-manage',
		title: 'Rename, move, or duplicate a script',
		category: 'files',
		summary: 'File menu commands for the open script.',
		related: ['use-the-library', 'where-files-live', 'versions'],
		blocks: [
			{ type: 'p', text: 'With the script open, choose any of the following from the File menu:' },
			{ type: 'list', items: [
				'Rename: Changes the script’s name. The file stays in the same folder.',
				'Move To: Moves the file to another folder.',
				'Duplicate (⇧⌘S): Opens a copy of the script.',
				'Show in Finder: Shows the file in its folder. This command is dimmed until you save the script.',
				'Open Recent: Lists the scripts you opened most recently. To empty the list, choose Clear Menu.'
			] },
			{ type: 'p', text: 'You can also rename, duplicate, or move a script to the Trash from the library. See Find and manage scripts in the library.' }
		]
	},
	{
		slug: 'versions',
		title: 'Go back to an earlier version',
		category: 'files',
		summary: 'Return to the last save, or browse earlier versions.',
		related: ['open-and-manage', 'where-files-live', 'omit-a-scene'],
		blocks: [
			{ type: 'p', text: 'eDraft saves versions of a script as you work, so you can go back if a change goes wrong.' },
			{ type: 'list', items: [
				'To discard the changes made since you last saved, choose File > Revert To > Last Saved.',
				'To look through earlier versions, choose File > Revert To > Browse All Versions. Select a version, then click Restore. To leave without changing anything, click Done.'
			] }
		]
	},
	{
		slug: 'final-draft-files',
		title: 'Intro to Final Draft files in eDraft',
		category: 'files',
		summary: 'What eDraft shows, what it keeps, and how it saves a .fdx file.',
		related: ['import-final-draft', 'final-draft-page-locks', 'share-with-final-draft-users'],
		blocks: [
			{ type: 'p', text: 'When you open a Final Draft file (.fdx) in eDraft, you work in the file itself. Your changes are saved back to it as a Final Draft file.' },
			{ type: 'h', text: 'What you can work with' },
			{ type: 'list', items: [
				'The script’s text and elements, its scene numbers, and its title page.',
				'Notes. Notes you add are saved as Final Draft notes with your name. Notes written in Final Draft can be read but not changed.',
				'Omitted scenes. You can omit and restore scenes, and the file keeps them as Final Draft omissions.'
			] },
			{ type: 'h', text: 'What eDraft keeps without showing' },
			{ type: 'p', text: 'A Final Draft file can hold revisions, locked pages, and tags. eDraft doesn’t show these, but it keeps them in the file. When it saves, it rewrites only the parts of the script you changed.' },
			{ type: 'note', text: 'eDraft doesn’t yet move locked pages to follow your edits. See Edit a Final Draft script with locked pages.' },
			{ type: 'p', text: 'To give the script to someone who uses Final Draft, see Send a script to a Final Draft user.' }
		]
	},
	{
		slug: 'final-draft-page-locks',
		title: 'Edit a Final Draft script with locked pages',
		category: 'files',
		summary: 'What eDraft does with Final Draft’s locked pages, and what to check.',
		related: ['final-draft-files', 'import-final-draft', 'share-with-final-draft-users'],
		blocks: [
			{ type: 'p', text: 'In Final Draft, a production can lock a script’s pages, so that later changes don’t move the text on any locked page. As the script is edited, Final Draft moves each lock along with the text.' },
			{ type: 'p', text: 'eDraft keeps a file’s locked pages when it saves, but it doesn’t move them with your edits yet. After you add or remove text above a locked page, that page can start in the wrong place when the file is opened in Final Draft.' },
			{ type: 'h', text: 'The notice' },
			{ type: 'p', text: 'The first time you edit a Final Draft script that has locked pages, a notice appears below the toolbar: “This script has Final Draft page locks.” It appears once each time you open the script, and doesn’t change the file. To close it, click the Dismiss button (X).' },
			{ type: 'h', text: 'What to do' },
			{ type: 'list', items: [
				'If the pages are locked for production, make your changes in Final Draft, so the locks follow the text.',
				'If you edit the script in eDraft, open it in Final Draft before you send it, and check that each locked page starts where it should.',
				'To keep an untouched copy, duplicate the file in the Finder before you edit it.'
			] },
			{ type: 'p', text: 'Opening the script, reading it, and saving it without changes leave the locks exactly as they were.' }
		]
	},
	{
		slug: 'share-with-final-draft-users',
		title: 'Send a script to a Final Draft user',
		category: 'files',
		summary: 'Choose the right file to send, and what arrives with it.',
		related: ['final-draft-files', 'export-final-draft', 'final-draft-page-locks'],
		blocks: [
			{ type: 'p', text: 'Which file to send depends on the kind of script:' },
			{ type: 'list', items: [
				'If you opened the script from a Final Draft file (.fdx): Send that file. eDraft has already saved your changes to it. To find it, choose File > Show in Finder.',
				'If the script is an eDraft script (.draft): Choose File > Export > Final Draft, then send the .fdx file you save.'
			] },
			{ type: 'p', text: 'Notes you add to a .fdx file appear in Final Draft as notes titled [eDraft], with your name as their author.' },
			{ type: 'note', text: 'Final Draft removes eDraft highlights when it saves a file. If the script has locked pages, see Edit a Final Draft script with locked pages before you send it.' }
		]
	},
	{
		slug: 'fountain-files',
		title: 'Work with Fountain files',
		category: 'files',
		summary: 'Plain-text scripts, and the Fountain format at a glance.',
		related: ['where-files-live', 'export-fountain-text', 'if-omit-scene-is-dimmed'],
		blocks: [
			{ type: 'p', text: 'Fountain is a plain-text format for screenplays. eDraft scripts (.draft) are saved in Fountain, so other apps that read Fountain can open them. eDraft also opens plain-text files (.txt).' },
			{ type: 'h', text: 'Fountain at a glance' },
			{ type: 'table', head: ['For', 'Type'], rows: [
				['A scene heading', 'A line starting with INT. or EXT.'],
				['A character', 'A name in capitals, with dialogue on the next line'],
				['A parenthetical', '(quietly) on the line after the character'],
				['A transition', 'A line in capitals ending in TO:, such as CUT TO:'],
				['Centered text', '> THE END <'],
				['Lyrics', '~ at the start of the line'],
				['A note', '[[your note]]'],
				['Bold, italic, underline', '**bold**, *italic*, _underline_'],
				['A heading that doesn’t start with INT. or EXT.', 'A period first: .FLASHBACK'],
				['A page break', '=== on a line by itself']
			] },
			{ type: 'p', text: 'Fountain has no way to record an omitted scene or a highlight, so in .draft and Fountain scripts, Omit Scene is dimmed and highlights aren’t kept.' }
		]
	},
	{
		slug: 'privacy',
		title: 'Privacy and your scripts',
		category: 'files',
		summary: 'eDraft has no account and no server.',
		related: ['where-files-live', 'contact', 'writing-suggestions'],
		blocks: [
			{ type: 'list', items: [
				'eDraft has no account and no sign-in.',
				'Your scripts are files on your Mac or in your iCloud Drive. eDraft has no server, and nobody at eDraft receives your scripts or notes.',
				'iCloud Drive is synced by Apple, through your Apple Account.',
				'Writing suggestions are made on your Mac, from your own script.',
				'The name you give for notes is kept on this Mac and in the notes you write.',
				'eDraft doesn’t use analytics, crash reporting, or advertising. Its App Store privacy label is Data Not Collected.'
			] },
			{ type: 'p', text: 'The full privacy policy is on the eDraft website.' }
		]
	},

	// Export & print

	{
		slug: 'export-pdf',
		title: 'Export a PDF',
		category: 'export',
		summary: 'Save the script as a PDF for reading and sharing.',
		related: ['print', 'title-page', 'page-settings'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File > Export > PDF, or click Export in the toolbar and choose PDF.',
				'Enter a name, choose where to save the PDF, then click Save.'
			] },
			{ type: 'p', text: 'The PDF uses the paper size and page numbers set in eDraft > Settings, and prints scene numbers in both margins.' },
			{ type: 'list', items: [
				'The title page comes first, if it has content and Include in PDF Export is turned on. See Create a title page.',
				'Highlights print in yellow.',
				'Notes don’t print.'
			] }
		]
	},
	{
		slug: 'export-final-draft',
		title: 'Export a Final Draft file',
		category: 'export',
		summary: 'Save a copy of the script as a .fdx file.',
		related: ['share-with-final-draft-users', 'final-draft-files', 'export-pdf'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File > Export > Final Draft, or click Export in the toolbar and choose Final Draft.',
				'Enter a name, choose where to save the file, then click Save. The file has the .fdx extension.'
			] },
			{ type: 'note', text: 'Exporting creates a new file from the script. If you opened the script from a Final Draft file, the export doesn’t include the revisions, locked pages, or tags that the original file keeps. To give someone the complete file, send the original .fdx instead. See Send a script to a Final Draft user.' }
		]
	},
	{
		slug: 'export-fountain-text',
		title: 'Export Fountain or plain text',
		category: 'export',
		summary: 'Save the script as a Fountain file or as plain text.',
		related: ['fountain-files', 'export-pdf', 'export-final-draft'],
		blocks: [
			{ type: 'list', items: [
				'To save a Fountain file, choose File > Export > Fountain. Other apps that read Fountain can open it.',
				'To save plain text, choose File > Export > Plain Text. The text is laid out like the printed pages, with each element indented as it prints.'
			] },
			{ type: 'p', text: 'You can also click Export in the toolbar and choose Fountain or Plain Text.' }
		]
	},
	{
		slug: 'print',
		title: 'Print a script',
		category: 'export',
		summary: 'Print the same pages as the PDF.',
		related: ['export-pdf', 'page-settings', 'title-page'],
		blocks: [
			{ type: 'steps', items: [
				'Choose File > Print (⌘P).',
				'Choose a printer and any options, then click Print.'
			] },
			{ type: 'p', text: 'eDraft prints the same pages it exports as a PDF, including the title page if Include in PDF Export is turned on.' },
			{ type: 'p', text: 'Pages break according to the paper size in eDraft > Settings. If the printer’s paper is a different size, the pages are scaled to fit it.' }
		]
	},

	// Shortcuts & support

	{
		slug: 'keyboard-shortcuts',
		title: 'Keyboard shortcuts',
		category: 'support',
		summary: 'Every eDraft shortcut, while writing and by menu.',
		related: ['tab-and-return', 'change-an-element', 'find-a-scene'],
		blocks: [
			{ type: 'p', text: 'Standard Mac shortcuts, such as Copy (⌘C) and Paste (⌘V), work in eDraft as they do in other apps.' },
			{ type: 'h', text: 'While writing' },
			{ type: 'table', head: ['Action', 'Shortcut'], rows: [
				['Change the current line’s element', 'Tab'],
				['Step back through elements', '⇧Tab'],
				['Start the next line', 'Return'],
				['Accept a suggestion', '⌘→, or Space at the end of the line'],
				['Add a note', '⇧⌘K']
			] },
			{ type: 'h', text: 'Menu commands' },
			{ type: 'table', head: ['Command', 'Shortcut'], rows: [
				['File > New', '⌘N'],
				['File > Open', '⌘O'],
				['File > Close', '⌘W'],
				['File > Save', '⌘S'],
				['File > Duplicate', '⇧⌘S'],
				['File > Page Setup', '⇧⌘P'],
				['File > Print', '⌘P'],
				['Edit > Undo', '⌘Z'],
				['Edit > Redo', '⇧⌘Z'],
				['Edit > Accept Suggestion', '⌘→'],
				['Edit > Add Note', '⇧⌘K'],
				['Edit > Find > Find', '⌘F'],
				['Edit > Find > Find Next', '⌘G'],
				['Edit > Find > Find Previous', '⇧⌘G'],
				['Edit > Find Scene', '⌘L'],
				['Edit > Emoji & Symbols', '⌃⌘Space'],
				['Format > Element > Scene Heading', '⌘1'],
				['Format > Element > Action', '⌘2'],
				['Format > Element > Character', '⌘3'],
				['Format > Element > Parenthetical', '⌘4'],
				['Format > Element > Dialogue', '⌘5'],
				['Format > Element > Transition', '⌘6'],
				['Format > Element > Shot', '⌘7'],
				['Format > Element > General', '⌘8'],
				['Format > Element > Lyrics', '⌘9'],
				['View > Zoom In', '⌘+'],
				['View > Zoom Out', '⌘−'],
				['View > Actual Size', '⌘0'],
				['View > Show Sidebar', '⌃⌘S'],
				['View > Enter Full Screen', '⌃⌘F'],
				['eDraft > Settings', '⌘,']
			] }
		]
	},
	{
		slug: 'if-omit-scene-is-dimmed',
		title: 'If Omit Scene is dimmed',
		category: 'support',
		summary: 'Why a scene can’t be omitted, and what to check.',
		related: ['omit-a-scene', 'final-draft-files', 'fountain-files'],
		blocks: [
			{ type: 'p', text: 'Omit Scene is available only when eDraft can save the omission. Check the following:' },
			{ type: 'list', items: [
				'The script is a Final Draft file (.fdx). eDraft scripts (.draft) and Fountain files can’t store omitted scenes. To see the reason, hold the pointer over Format > Omit Scene.',
				'The insertion point is in a scene. Omit Scene is dimmed above the first scene heading.',
				'The scene heading has text. A scene with an empty heading can’t be omitted.',
				'The line isn’t already an OMITTED card. On a card, the command is Restore Scene.'
			] },
			{ type: 'p', text: 'If a Final Draft file’s omitted scenes can’t be matched to its text, eDraft turns omitting off for that file and gives the reason in the same place.' }
		]
	},
	{
		slug: 'if-final-draft-opens-instead',
		title: 'If a Final Draft file opens in Final Draft',
		category: 'support',
		summary: 'Open a .fdx file in eDraft when Final Draft is installed.',
		related: ['import-final-draft', 'final-draft-files', 'share-with-final-draft-users'],
		blocks: [
			{ type: 'p', text: 'If Final Draft is installed on your Mac, double-clicking a .fdx file can open it in Final Draft. To open it in eDraft, do one of the following:' },
			{ type: 'list', items: [
				'In eDraft, choose File > Open, select the file, then click Open.',
				'In the Finder, Control-click the file, then choose Open With > eDraft.'
			] },
			{ type: 'p', text: 'To always open .fdx files in eDraft, select one in the Finder and choose File > Get Info. Choose eDraft from the “Open with” menu, then click Change All.' }
		]
	},
	{
		slug: 'if-page-counts-differ',
		title: 'If page counts don’t match Final Draft',
		category: 'support',
		summary: 'Why the same script can have a different page count.',
		related: ['page-settings', 'final-draft-files', 'final-draft-page-locks'],
		blocks: [
			{ type: 'list', items: [
				'Check the paper size. Choose eDraft > Settings, then make sure Paper Size matches the paper size used in Final Draft.',
				'eDraft decides where pages break by its own rules, which can differ from Final Draft’s. The same script can come out a little longer or shorter in each app.'
			] },
			{ type: 'p', text: 'For a script with locked pages, see Edit a Final Draft script with locked pages.' }
		]
	},
	{
		slug: 'contact',
		title: 'Contact eDraft support',
		category: 'support',
		summary: 'Email support, send feedback, or report a problem.',
		related: ['keyboard-shortcuts', 'privacy', 'if-page-counts-differ'],
		blocks: [
			{ type: 'list', items: [
				'Email support@edraft.xyz with questions about eDraft, your files, or your privacy.',
				'To send feedback from eDraft, choose eDraft > Settings, then click Send Feedback. A new email message opens.',
				'To report a problem, open an issue at github.com/Yasirdora/eDraft/issues. Include what you did, what you expected, and your eDraft version, which is shown in eDraft > Settings.'
			] },
			{ type: 'note', text: 'Don’t post security problems publicly. Report them privately at github.com/Yasirdora/eDraft/security.' }
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
		} else if (block.type === 'p' || block.type === 'h' || block.type === 'tip' || block.type === 'note') {
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
