import SwiftUI

struct SettingsView: View {
    @Bindable var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Settings")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    settings.save()
                    dismiss()
                } label: {
                    Text("Done")
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: 0x6B2FA0))
            }
            .padding()

            Divider()
                .overlay(Color.white.opacity(0.1))

            ScrollView {
                VStack(spacing: 20) {
                    // Audio Section
                    settingsSection("Audio") {
                        sliderRow(
                            title: "Buffer Length",
                            value: $settings.audioBufferLength,
                            range: Constants.Audio.minBufferLength...Constants.Audio.maxBufferLength,
                            step: 1,
                            unit: "s"
                        )

                        HStack {
                            Text("Sample Rate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Picker("", selection: $settings.sampleRate) {
                                Text("11,025 Hz").tag(Constants.Audio.defaultSampleRate)
                                Text("44,100 Hz").tag(Constants.Audio.highSampleRate)
                            }
                            .pickerStyle(.segmented)
                            .frame(width: 200)
                        }
                    }

                    // Detection Section
                    settingsSection("Detection") {
                        sliderRow(
                            title: "Interval",
                            value: $settings.detectionInterval,
                            range: Constants.Detection.minInterval...Constants.Detection.maxInterval,
                            step: 10,
                            unit: "s"
                        )

                        sliderRow(
                            title: "Confidence Threshold",
                            value: $settings.confidenceThreshold,
                            range: 0...1,
                            step: 0.05,
                            unit: "%",
                            isPercentage: true
                        )

                        HStack {
                            Text("Noise Gate")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Slider(
                                value: Binding(
                                    get: { Double(settings.noiseGateThreshold) },
                                    set: { settings.noiseGateThreshold = Float($0) }
                                ),
                                in: 0...0.1,
                                step: 0.005
                            )
                            .frame(width: 150)
                            Text(String(format: "%.3f", settings.noiseGateThreshold))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 45, alignment: .trailing)
                        }
                    }

                    // Cooldown Section
                    settingsSection("Cooldown") {
                        sliderRow(
                            title: "Global Cooldown",
                            value: $settings.cooldownDuration,
                            range: 0...120,
                            step: 5,
                            unit: "s"
                        )

                        sliderRow(
                            title: "Per-Track Cooldown",
                            value: $settings.perTrackCooldown,
                            range: 0...600,
                            step: 30,
                            unit: "s"
                        )

                        sliderRow(
                            title: "Similarity Threshold",
                            value: $settings.similarityThreshold,
                            range: 0...1,
                            step: 0.05,
                            unit: "%",
                            isPercentage: true
                        )
                    }

                    // Toggles Section
                    settingsSection("Features") {
                        toggleRow("Auto Detection", isOn: $settings.autoDetectionEnabled)
                        toggleRow("Gap Detection", isOn: $settings.gapDetectionEnabled)
                        toggleRow("Fallback Provider", isOn: $settings.fallbackProviderEnabled)
                        toggleRow("Debug Mode", isOn: $settings.debugModeEnabled)
                    }

                    // API Section
                    settingsSection("API") {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("AcoustID API Key")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            SecureField("Enter API key", text: $settings.acoustIDApiKey)
                                .textFieldStyle(.roundedBorder)
                                .font(.caption.monospaced())
                        }
                    }
                }
                .padding()
            }
        }
        .frame(width: 400, height: 520)
        .background(Color(hex: 0x1A1A2E))
    }

    // MARK: - Helper Views

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(Color(hex: 0x9B30FF))
                .tracking(1.2)

            VStack(spacing: 8) {
                content()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        unit: String,
        isPercentage: Bool = false
    ) -> some View {
        HStack {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Slider(value: value, in: range, step: step)
                .frame(width: 150)
            Text(displayText(value.wrappedValue, unit: unit, isPercentage: isPercentage))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .trailing)
        }
    }

    private func displayText(_ value: Double, unit: String, isPercentage: Bool) -> String {
        if isPercentage {
            return "\(Int(value * 100))%"
        } else {
            return "\(Int(value))\(unit)"
        }
    }

    private func toggleRow(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .font(.caption)
            .foregroundStyle(.secondary)
            .toggleStyle(.switch)
            .controlSize(.small)
    }
}

#Preview {
    SettingsView(settings: AppSettings())
}
