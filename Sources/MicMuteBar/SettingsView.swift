import SwiftUI

struct SettingsView: View {
    let controller: MicMuteController
    let preferences: MicMutePreferences
    let launchAtLogin: LaunchAtLoginManager

    var body: some View {
        Form {
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Mute all mute-capable input devices", isOn: muteAllDevicesBinding)
                Text("When enabled, the hotkey and menu toggle mute/unmute every connected input device that exposes a real CoreAudio mute control.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Lock input volume to 100 when unmuted", isOn: lockVolumeBinding)
                Text("Built-in replacement for your cron job. The app re-applies input volume 100% in the background, but skips volume writes while muted so mute state stays intact.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Microphone")
                Picker("Microphone", selection: selectedDeviceUIDBinding) {
                    Text("System Default").tag(nil as String?)
                    ForEach(controller.availableDevices) { device in
                        Text(devicePickerLabel(device))
                            .tag(Optional(device.uid))
                    }
                }
                .labelsHidden()
                .disabled(preferences.muteAllCapableInputDevices)

                if preferences.selectedDeviceUID != nil && controller.selectedDeviceMissing {
                    Text("Your previously selected microphone is unavailable. Using the current system default until it returns.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if controller.availableDevices.isEmpty {
                    Text("No input devices detected yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if preferences.muteAllCapableInputDevices {
                    Text("Specific microphone selection is ignored while all-mics mode is enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Refresh Device List") {
                    controller.refreshState()
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Toggle("Launch At Login", isOn: launchAtLoginBinding)
                Text(launchAtLogin.statusDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if let launchError = launchAtLogin.lastError {
                    Text(launchError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("On-screen feedback")
                Text("A small toast appears when you mute/unmute or if a toggle fails.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Test Mute Toast") {
                    ToastPresenter.shared.showMuteChanged(isMuted: true, deviceName: controller.activeDeviceName.isEmpty ? "Microphone" : controller.activeDeviceName)
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Status")
                Text(controller.statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Shortcut: Cmd+Shift+M")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            launchAtLogin.refreshStatus()
            controller.refreshState()
        }
    }

    private var selectedDeviceUIDBinding: Binding<String?> {
        Binding(
            get: { preferences.selectedDeviceUID },
            set: { controller.setSelectedDeviceUID($0) }
        )
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var muteAllDevicesBinding: Binding<Bool> {
        Binding(
            get: { preferences.muteAllCapableInputDevices },
            set: { controller.setMuteAllCapableInputDevices($0) }
        )
    }

    private var lockVolumeBinding: Binding<Bool> {
        Binding(
            get: { preferences.lockInputVolumeTo100WhenUnmuted },
            set: { controller.setLockInputVolumeTo100WhenUnmuted($0) }
        )
    }

    private func devicePickerLabel(_ device: MicInputDevice) -> String {
        var parts = [device.name]
        if device.isDefault {
            parts.append("Default")
        }
        if !device.canToggle {
            parts.append("No CoreAudio mute")
        } else if let isMuted = device.isMuted {
            parts.append(isMuted ? "Muted" : "Live")
        }
        return parts.joined(separator: " • ")
    }
}
