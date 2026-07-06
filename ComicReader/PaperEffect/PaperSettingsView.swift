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
