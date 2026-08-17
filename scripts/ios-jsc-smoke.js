/*
 * JSC smoke harness — evaluated by the real JavaScriptCore CLI immediately
 * after the iOS engine bundle:
 *
 *   jsc ios/DraftFirst/Resources/draftfirst-engine.js scripts/ios-jsc-smoke.js
 *
 * Exercises the exact global contract the Swift EngineFacade depends on.
 * Any failure throws, which fails `npm run ios:engine`.
 */
(function () {
	'use strict';
	var failures = 0;
	function check(name, cond, detail) {
		if (cond) {
			print('ok   ' + name + (detail ? ' — ' + detail : ''));
		} else {
			failures++;
			print('FAIL ' + name + (detail ? ' — ' + detail : ''));
		}
	}

	check('bundle exposes __draftfirstVersion', typeof __draftfirstVersion === 'string', __draftfirstVersion);
	check('bundle exposes __draftfirstCall', typeof __draftfirstCall === 'function');
	check('bundle exposes __draftfirstBench', typeof __draftfirstBench === 'function');

	var src = 'FADE IN:\n\nINT. SCHOOL HALLWAY - DAY\n\nStudents RUSH past, late slips flying.\n\nMARA\n(whispering)\nWe have to go.\n\nDAVID\nI know.';
	var script = JSON.parse(__draftfirstCall('parseFountain', [src]));
	check('parseFountain', script && script.elements && script.elements.length >= 7, script.elements.length + ' elements');

	/* character prediction: typing "MA" must surface MARA */
	var preds = JSON.parse(__draftfirstCall('predict', [script, { type: 'character', text: 'MA', index: script.elements.length }]));
	var names = preds.map(function (p) { return p.text; });
	check('predict character "MA" → MARA', names.indexOf('MARA') >= 0, names.join(', ') || '(no candidates)');

	/* DAVID was the last speaker (document ends after his dialogue):
	   "DAVID " with a trailing space must offer (CONT'D) */
	var contd = JSON.parse(__draftfirstCall('predict', [script, { type: 'character', text: 'DAVID ', index: script.elements.length }]));
	var contdText = contd.map(function (p) { return p.text; });
	check('predict "DAVID " → (CONT\'D)', contdText.indexOf("(CONT'D)") >= 0, contdText.join(', ') || '(no candidates)');

	/* same voice continuing across an action beat: MARA speaks, action
	   interrupts, "MARA " must offer (CONT'D) as well */
	var src2 = src + '\n\nThe bell RINGS overhead.';
	var script2 = JSON.parse(__draftfirstCall('parseFountain', [src2]));
	var contd2 = JSON.parse(__draftfirstCall('predict', [script2, { type: 'character', text: 'DAVID ', index: script2.elements.length }]));
	var contd2Text = contd2.map(function (p) { return p.text; });
	check('predict "DAVID " after action beat → (CONT\'D)', contd2Text.indexOf("(CONT'D)") >= 0, contd2Text.join(', ') || '(no candidates)');

	/* ghost suffix joins cleanly after the trailing space */
	var suffix = JSON.parse(__draftfirstCall('ghostSuffix', ["(CONT'D)", 'DAVID ']));
	check('ghostSuffix "(CONT\'D)" after "DAVID "', suffix === "(CONT'D)", JSON.stringify(suffix));

	/* pagination */
	var pages = JSON.parse(__draftfirstCall('paginate', [script]));
	check('paginate', Array.isArray(pages) && pages.length >= 1, pages.length + ' page(s)');

	var rt = JSON.parse(__draftfirstCall('estimateRuntime', [pages]));
	check('estimateRuntime', typeof rt === 'string' && rt.length > 0, rt);

	/* serialisation round-trip */
	var round = JSON.parse(__draftfirstCall('serialiseFountain', [script]));
	check('serialiseFountain round-trip', typeof round === 'string' && round.indexOf('INT. SCHOOL HALLWAY') >= 0);

	/* choreography contract: after a scene heading, Tab offers
	   action/character/transition — never parenthetical or dialogue */
	var set = JSON.parse(__draftfirstCall('tabSetFor', ['scene']));
	var okSet = Array.isArray(set) && set.indexOf('action') >= 0 && set.indexOf('character') >= 0 &&
		set.indexOf('transition') >= 0 && set.indexOf('parenthetical') < 0 && set.indexOf('dialogue') < 0;
	check('tabSetFor(scene) = {action, character, transition}', okSet, Array.isArray(set) ? set.join(', ') : String(set));

	if (failures > 0) {
		print('JSC SMOKE: ' + failures + ' FAILURE(S)');
		throw new Error('smoke failed');
	}
	print('JSC SMOKE: PASS');
})();
