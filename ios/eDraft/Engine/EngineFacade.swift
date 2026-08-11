import Foundation
import JavaScriptCore

/// The one-way door between Swift and the Draft First screenwriting engine.
///
/// The engine ships as `edraft-engine.js` — the exact `@draftfirst/core` build
/// that powers the web app, bundled by `scripts/ios-engine-sync.mjs` — and runs
/// unchanged inside JavaScriptCore. Every engine interaction in the app goes
/// through this facade; nothing else may touch `JSContext` or `JSValue`.
///
/// Threading: JavaScriptCore contexts must not be used concurrently. Every
/// call is serialized onto a dedicated queue, so the facade is safe to call
/// from any thread (UI for predictions, background for pagination/benchmarks).
final class EngineFacade {

	enum Failure: Error, LocalizedError {
		case bundleMissing
		case loadFailed(String)
		case callFailed(fn: String, message: String)
		case invalidResponse(fn: String)

		var errorDescription: String? {
			switch self {
			case .bundleMissing:
				return "edraft-engine.js is missing from the app bundle."
			case .loadFailed(let message):
				return "The screenwriting engine failed to load: \(message)"
			case .callFailed(let fn, let message):
				return "Engine call '\(fn)' failed: \(message)"
			case .invalidResponse(let fn):
				return "Engine call '\(fn)' returned an unreadable response."
			}
		}
	}

	struct Prediction: Decodable {
		let text: String
		let why: String
		let becomes: String?
		let hint: Bool?
	}

	struct BenchResult: Decodable {
		let elements: Int
		let pages: Int
		let runtime: String
		let printedLines: Int
		let parseMs: Int
		let paginateMs: Int
		let predict500Ms: Int
		let predictHits: Int
	}

	/// Engine semver baked into the bundle at build time.
	private(set) var version = "unknown"

	private let queue = DispatchQueue(label: "xyz.draftfirst.engine", qos: .userInitiated)
	private var context: JSContext!

	init(bundle: Bundle = .main) throws {
		guard let url = bundle.url(forResource: "edraft-engine", withExtension: "js") else {
			throw Failure.bundleMissing
		}
		let source = try String(contentsOf: url, encoding: .utf8)

		// Set up on the engine queue so the context is born and dies on one thread.
		try queue.sync {
			let context = JSContext()!
			var loadError: String?
			context.exceptionHandler = { _, exception in
				loadError = exception?.toString()
			}
			context.evaluateScript(source)
			if let loadError {
				throw Failure.loadFailed(loadError)
			}
			self.context = context
			self.version = context.evaluateScript("__edraftVersion")?.toString() ?? "unknown"
		}
	}

	// MARK: - Typed engine calls

	/// Parse Fountain source into the engine's screenplay model, returned as raw
	/// JSON so it can round-trip into later calls without losing fields Swift
	/// doesn't model yet.
	func parse(fountain: String) throws -> String {
		try callRaw("parseFountain", args: [fountain])
	}

	/// The element list of a parsed screenplay (convenience for UI code).
	func elements(ofScreenplayJSON screenplayJSON: String) throws -> [[String: Any]] {
		let object = try JSONSerialization.jsonObject(with: Data(screenplayJSON.utf8))
		guard
			let screenplay = object as? [String: Any],
			let elements = screenplay["elements"] as? [[String: Any]]
		else { throw Failure.invalidResponse(fn: "elements") }
		return elements
	}

	/// Predict completions for the block being edited.
	func predict(screenplayJSON: String, type: String, text: String, index: Int) throws -> [Prediction] {
		let screenplay = try jsonObject(from: screenplayJSON)
		let json = try callRaw("predict", args: [
			screenplay,
			["type": type, "text": text, "index": index]
		])
		return try decode([Prediction].self, from: json, fn: "predict")
	}

	/// The displayable remainder of a prediction against the current block text.
	func ghostSuffix(candidate: String, blockText: String, hint: Bool = false) throws -> String {
		let json = try callRaw("ghostSuffix", args: [candidate, blockText, hint])
		return try decodeString(json, fn: "ghostSuffix")
	}

	/// Engine-accurate page count for a parsed screenplay.
	func pageCount(screenplayJSON: String) throws -> Int {
		let screenplay = try jsonObject(from: screenplayJSON)
		let json = try callRaw("paginate", args: [screenplay])
		let object = try JSONSerialization.jsonObject(with: Data(json.utf8))
		guard let pages = object as? [Any] else { throw Failure.invalidResponse(fn: "paginate") }
		return pages.count
	}

	/// In-engine benchmark. Timings are measured inside JavaScriptCore, so they
	/// exclude bridge overhead and reflect interpreter-only execution on device.
	func benchmark(sceneCount: Int) throws -> BenchResult {
		let json = try queue.sync { () throws -> String in
			var thrown: String?
			context.exceptionHandler = { _, exception in thrown = exception?.toString() }
			guard
				let bench = context.objectForKeyedSubscript("__edraftBench"),
				let value = bench.call(withArguments: [sceneCount]),
				let json = value.toString()
			else { throw Failure.invalidResponse(fn: "__edraftBench") }
			if let thrown { throw Failure.callFailed(fn: "__edraftBench", message: thrown) }
			return json
		}
		return try decode(BenchResult.self, from: json, fn: "__edraftBench")
	}

	// MARK: - Plumbing

	/// Call `__edraftCall(fn, args)` and return the raw JSON string result.
	/// Arguments cross via JSValue bridging; results cross back as JSON text.
	private func callRaw(_ fn: String, args: [Any]) throws -> String {
		try queue.sync { () throws -> String in
			var thrown: String?
			context.exceptionHandler = { _, exception in thrown = exception?.toString() }
			guard let callable = context.objectForKeyedSubscript("__edraftCall") else {
				throw Failure.loadFailed("__edraftCall missing — engine bundle is corrupt")
			}
			let result = callable.call(withArguments: [fn, args])
			if let thrown { throw Failure.callFailed(fn: fn, message: thrown) }
			guard let json = result?.toString() else { throw Failure.invalidResponse(fn: fn) }
			return json
		}
	}

	private func jsonObject(from json: String) throws -> Any {
		try JSONSerialization.jsonObject(with: Data(json.utf8))
	}

	private func decode<T: Decodable>(_ type: T.Type, from json: String, fn: String) throws -> T {
		do {
			return try JSONDecoder().decode(type, from: Data(json.utf8))
		} catch {
			throw Failure.invalidResponse(fn: fn)
		}
	}

	private func decodeString(_ json: String, fn: String) throws -> String {
		let object = try JSONSerialization.jsonObject(with: Data(json.utf8), options: [.allowFragments])
		guard let string = object as? String else { throw Failure.invalidResponse(fn: fn) }
		return string
	}
}
