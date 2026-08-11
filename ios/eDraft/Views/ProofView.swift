import SwiftUI

/// Phase 0 proof screen.
///
/// Runs the full engine loop — parse → predict → ghost → paginate — inside
/// JavaScriptCore on every keystroke, renders the ghost whisper inline in a
/// UITextView (Spike A), and hosts the in-app benchmark (Spike B). This screen
/// exists to prove the architecture; it is not the product UI.
struct ProofView: View {
	@State private var engine: EngineFacade?
	@State private var engineError: String?

	@State private var text = "FADE IN:\n\nINT. SCHOOL HALLWAY - DAY\n\nStudents RUSH past, late slips flying.\n\n"
	@State private var ghost = ""
	@State private var whisperWhy = ""
	@State private var stats = "—"
	@State private var bench: EngineFacade.BenchResult?
	@State private var benchRunning = false

	var body: some View {
		NavigationStack {
			VStack(spacing: 0) {
				statusBar
				Divider()
				ScriptTextView(text: $text, ghost: ghost) { newText in
					text = newText
					refreshEngine()
				}
				.frame(maxWidth: .infinity, maxHeight: .infinity)
				.background(Color(uiColor: .systemBackground))
				Divider()
				controlBar
			}
			.navigationTitle("eDraft · Engine Proof")
			.navigationBarTitleDisplayMode(.inline)
			.onAppear(perform: boot)
		}
	}

	// MARK: - Sections

	private var statusBar: some View {
		HStack(spacing: 8) {
			Circle()
				.fill(engine != nil ? Color.green : (engineError != nil ? Color.red : Color.orange))
				.frame(width: 8, height: 8)
			if let engineError {
				Text(engineError).font(.caption).foregroundStyle(.red)
			} else if let engine {
				Text("Engine \(engine.version) · JavaScriptCore")
					.font(.caption)
					.foregroundStyle(.secondary)
			} else {
				Text("Loading engine…").font(.caption).foregroundStyle(.secondary)
			}
			Spacer()
			Text(stats)
				.font(.caption.monospacedDigit())
				.foregroundStyle(.secondary)
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 10)
	}

	private var controlBar: some View {
		VStack(spacing: 12) {
			// The whisper, mirrored where thumbs live — the touch answer to Tab.
			HStack(spacing: 12) {
				if ghost.isEmpty {
					Text("No prediction")
						.font(.callout)
						.foregroundStyle(.tertiary)
				} else {
					Text(ghost)
						.font(.system(.callout, design: .monospaced))
						.padding(.horizontal, 12)
						.padding(.vertical, 7)
						.background(Color.accentColor.opacity(0.12), in: Capsule())
						.overlay(Capsule().strokeBorder(Color.accentColor.opacity(0.35)))
					if !whisperWhy.isEmpty {
						Text(whisperWhy)
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}
				}
				Spacer()
				Button(action: acceptGhost) {
					Label("Accept", systemImage: "return")
						.font(.callout.weight(.medium))
				}
				.buttonStyle(.borderedProminent)
				.disabled(ghost.isEmpty)
			}

			Divider()

			// Spike B — interpreter-mode numbers from inside the real runtime.
			HStack {
				Button(action: runBenchmark) {
					Label(
						benchRunning ? "Benchmarking…" : "Benchmark · 650 scenes",
						systemImage: "speedometer"
					)
					.font(.callout)
				}
				.buttonStyle(.bordered)
				.disabled(engine == nil || benchRunning)

				Spacer()

				if let bench {
					Text(
						"\(bench.elements) el · \(bench.pages) pg · parse \(bench.parseMs)ms · " +
						"paginate \(bench.paginateMs)ms · predict×500 \(bench.predict500Ms)ms · \(bench.predictHits) hits"
					)
					.font(.caption2.monospacedDigit())
					.foregroundStyle(.secondary)
					.multilineTextAlignment(.trailing)
				}
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 12)
		.background(.bar)
	}

	// MARK: - Engine loop

	private func boot() {
		guard engine == nil, engineError == nil else { return }
		do {
			engine = try EngineFacade()
			refreshEngine()
		} catch {
			engineError = error.localizedDescription
		}
	}

	/// parse → predict → ghost → paginate, on every keystroke.
	private func refreshEngine() {
		guard let engine else { return }
		do {
			let screenplayJSON = try engine.parse(fountain: text)
			let elements = try engine.elements(ofScreenplayJSON: screenplayJSON)
			let pages = try engine.pageCount(screenplayJSON: screenplayJSON)
			stats = "\(elements.count) elements · \(pages) page\(pages == 1 ? "" : "s")"

			guard let last = elements.last else {
				ghost = ""
				whisperWhy = ""
				return
			}
			let lastType = last["type"] as? String ?? "action"
			let lastText = last["text"] as? String ?? ""
			let predictions = try engine.predict(
				screenplayJSON: screenplayJSON,
				type: lastType,
				text: lastText,
				index: max(elements.count - 1, 0)
			)
			if let first = predictions.first(where: { !($0.hint ?? false) }) {
				ghost = try engine.ghostSuffix(candidate: first.text, blockText: lastText)
				whisperWhy = first.why
			} else {
				ghost = ""
				whisperWhy = ""
			}
		} catch {
			ghost = ""
			whisperWhy = ""
			stats = "engine: \(error.localizedDescription)"
		}
	}

	private func acceptGhost() {
		guard !ghost.isEmpty else { return }
		text += ghost
		refreshEngine()
	}

	private func runBenchmark() {
		guard let engine, !benchRunning else { return }
		benchRunning = true
		DispatchQueue.global(qos: .userInitiated).async {
			let result = try? engine.benchmark(sceneCount: 650)
			DispatchQueue.main.async {
				bench = result
				benchRunning = false
			}
		}
	}
}

#Preview {
	ProofView()
}
