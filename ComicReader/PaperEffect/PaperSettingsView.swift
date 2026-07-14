//
//  PaperSettingsView.swift
//  Comic Reader
//
//  SwiftUI controls for the paper effect: on/off, presets, and live sliders.
//

import SwiftUI

struct PaperSettingsView: View {
	@ObservedObject var settings: PaperSettings

	var body: some View {
		Form {
			Section {
				PaperPreview(params: settings.params, enabled: settings.isEnabled)
					.frame(maxWidth: .infinity)
					.listRowInsets(EdgeInsets())
					.listRowBackground(Color.clear)
			}

			Section {
				Toggle("Paper effect", isOn: $settings.isEnabled)
			}

			Section("Preset") {
				Picker("Preset", selection: presetSelection) {
					ForEach(PaperParams.presets.indices, id: \.self) { i in
						Text(PaperParams.presets[i].name).tag(i)
					}
					Text("Custom").tag(PaperParams.presets.count)
				}
				.pickerStyle(.menu)
			}

			Section("Adjust") {
				slider("Paper show-through", value: $settings.params.showThrough, in: 0...0.8)
				slider("Grain", value: $settings.params.grain, in: 0...0.4)
				slider("Warmth", value: $settings.params.warmth, in: 0...1)
				slider("Black lift", value: $settings.params.blackLift, in: 0...1)
			}
			.disabled(!settings.isEnabled)
		}
		.navigationTitle("Paper Effect")
		// Reserve room so the last slider clears the floating tab bar (which sits over
		// the bottom safe area) instead of being hidden under it.
		.contentMargins(.bottom, 80, for: .scrollContent)
	}

	private var presetSelection: Binding<Int> {
		Binding(
			get: { settings.matchingPresetIndex ?? PaperParams.presets.count },
			set: { idx in
				if idx < PaperParams.presets.count {
					settings.applyPreset(PaperParams.presets[idx].params)
				}
			}
		)
	}

	@ViewBuilder
	private func slider(_ title: String, value: Binding<CGFloat>, in range: ClosedRange<Double>) -> some View {
		VStack(alignment: .leading, spacing: 2) {
			HStack {
				Text(title)
				Spacer()
				Text(String(format: "%.2f", value.wrappedValue))
					.monospacedDigit()
					.foregroundStyle(.secondary)
			}
			Slider(
				value: Binding(get: { Double(value.wrappedValue) },
							   set: { value.wrappedValue = CGFloat($0) }),
				in: range
			)
		}
	}
}

/// A live preview of the paper effect applied to a synthetic sample page. Re-renders
/// (off the main thread) whenever the params or the on/off state change.
private struct PaperPreview: View {
	let params: PaperParams
	let enabled: Bool

	@State private var rendered: UIImage?

	var body: some View {
		Image(uiImage: rendered ?? SamplePage.preview)
			.resizable()
			.scaledToFit()
			.frame(maxHeight: 320)
			.clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
			.overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(.white.opacity(0.08)))
			.shadow(color: .black.opacity(0.3), radius: 5, y: 3)
			.padding(.vertical, 6)
			.task(id: PreviewKey(params: params, enabled: enabled)) { await render() }
	}

	private func render() async {
		guard enabled else { rendered = nil; return }
		let base = SamplePage.preview
		let p = params
		rendered = await Task.detached(priority: .userInitiated) {
			PaperFilter.shared.apply(to: base, params: p)
		}.value
	}

	private struct PreviewKey: Equatable { let params: PaperParams; let enabled: Bool }
}
