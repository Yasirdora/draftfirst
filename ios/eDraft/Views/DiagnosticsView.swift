import SwiftUI

/// Engineering diagnostics, deliberately out of the writer's way.
/// Reached only via ⋮ → Diagnostics.
struct DiagnosticsView: View {

	let engine: EngineFacade?

	@State private var bench: EngineFacade.BenchResult?
	@State private var running = false
	@Environment(\.dismiss) private var dismiss

	var body: some View {
		NavigationStack {
			List {
				Section("Engine") {
					LabeledContent("Version", value: engine?.version ?? "not loaded")
					LabeledContent("Runtime", value: "JavaScriptCore (no JIT)")
					LabeledContent("Bundle", value: "edraft-engine.js · sha256-pinned")
				}
				Section("Benchmark") {
					Button {
						runBenchmark()
					} label: {
						Label(running ? "Benchmarking…" : "650-scene script", systemImage: "speedometer")
					}
					.disabled(engine == nil || running)

					if let bench {
						LabeledContent("Elements", value: "\(bench.elements)")
						LabeledContent("Pages", value: "\(bench.pages) (\(bench.printedLines) lines)")
						LabeledContent("Parse", value: "\(bench.parseMs) ms")
						LabeledContent("Paginate", value: "\(bench.paginateMs) ms")
						LabeledContent("Predict ×500", value: "\(bench.predict500Ms) ms (\(bench.predictHits) hits)")
					}
				}
			}
			.navigationTitle("Diagnostics")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .topBarTrailing) {
					Button("Done") { dismiss() }
				}
			}
		}
	}

	private func runBenchmark() {
		guard let engine, !running else { return }
		running = true
		DispatchQueue.global(qos: .userInitiated).async {
			let result = try? engine.benchmark(sceneCount: 650)
			DispatchQueue.main.async {
				bench = result
				running = false
			}
		}
	}
}
