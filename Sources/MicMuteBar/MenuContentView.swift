import AppKit
import SwiftUI

struct MenuContentView: View {
    @Environment(\.openSettings) private var openSettings

    let controller: MicMuteController
    let launchAtLogin: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(controller.toggleButtonTitle) {
                controller.toggleMute()
            }
            .disabled(!controller.canToggle)

            Button("Refresh Status") {
                controller.refreshState()
            }

            Divider()

            Text(controller.statusLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Selection: \(controller.selectedDeviceLabel)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("Shortcut: Cmd+Shift+M")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Divider()

            Toggle("Mute all mute-capable mics", isOn: muteAllDevicesBinding)
                .toggleStyle(.checkbox)

            Toggle("Lock mic volume to 100 (when unmuted)", isOn: lockVolumeBinding)
                .toggleStyle(.checkbox)

            Toggle("Launch At Login", isOn: launchAtLoginBinding)
                .toggleStyle(.checkbox)

            Text(launchAtLogin.statusDescription)
                .font(.caption2)
                .foregroundStyle(.secondary)

            if let launchError = launchAtLogin.lastError {
                Text(launchError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let errorMessage = controller.lastErrorMessage {
                Divider()
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Settings...") {
                openSettings()
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(10)
        .frame(minWidth: 290, alignment: .leading)
        .onAppear {
            launchAtLogin.refreshStatus()
            controller.refreshDevices()
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLogin.isEnabled },
            set: { launchAtLogin.setEnabled($0) }
        )
    }

    private var muteAllDevicesBinding: Binding<Bool> {
        Binding(
            get: { controller.muteAllCapableInputDevices },
            set: { controller.setMuteAllCapableInputDevices($0) }
        )
    }

    private var lockVolumeBinding: Binding<Bool> {
        Binding(
            get: { controller.lockInputVolumeTo100WhenUnmuted },
            set: { controller.setLockInputVolumeTo100WhenUnmuted($0) }
        )
    }
}
