/*
 * JSC benchmark harness (Phase 0, Spike B):
 *
 *   jsc [--useJIT=false] ios/eDraft/Resources/edraft-engine.js \
 *       scripts/ios-jsc-bench.js -- [sceneCount]
 *
 * --useJIT=false reproduces the interpreter-only JavaScriptCore that
 * third-party iOS apps actually get, so these numbers are the honest ones.
 */
(function () {
	'use strict';
	var scenes = 650; /* ≈110 printed pages */
	if (typeof arguments !== 'undefined' && arguments.length > 0) {
		scenes = parseInt(arguments[0], 10) || scenes;
	}
	print('benchmark: ' + scenes + ' scenes');
	var t0 = Date.now();
	var result = JSON.parse(__edraftBench(scenes));
	var t1 = Date.now();
	print('elements:      ' + result.elements);
	print('pages:         ' + result.pages + ' (' + result.printedLines + ' printed lines, ~' + result.runtime + ')');
	print('parse:         ' + result.parseMs + ' ms');
	print('paginate:      ' + result.paginateMs + ' ms');
	print('predict ×500:  ' + result.predict500Ms + ' ms (' + result.predictHits + ' candidate hits)');
	print('bench total:   ' + (t1 - t0) + ' ms (incl. script generation)');
})();
