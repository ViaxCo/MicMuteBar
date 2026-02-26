import Carbon
import Foundation
import Observation

@MainActor
@Observable
final class MicMuteController {
    private let muteService = CoreAudioInputMuteService()
    private let hotKey = GlobalHotKey()
    private let preferences: MicMutePreferences
    private let toastPresenter = ToastPresenter.shared

    var isMuted = false
    var canToggle = false
    var statusLine = "Checking microphone..."
    var lastErrorMessage: String?
    var availableDevices: [MicInputDevice] = []
    var activeDeviceName = ""
    var activeDeviceUID: String?
    var usingDefaultDevice = true
    var selectedDeviceMissing = false

    private var refreshTimer: Timer?
    private var hasStarted = false
    private var lastToggleTime: ContinuousClock.Instant?
    private let clock = ContinuousClock()

    init(preferences: MicMutePreferences) {
        self.preferences = preferences
    }

    var selectedDeviceUID: String? {
        preferences.selectedDeviceUID
    }

    var muteAllCapableInputDevices: Bool {
        preferences.muteAllCapableInputDevices
    }

    var lockInputVolumeTo100WhenUnmuted: Bool {
        preferences.lockInputVolumeTo100WhenUnmuted
    }

    var menuBarSymbolName: String {
        if !canToggle {
            return "mic.badge.xmark"
        }
        return isMuted ? "mic.slash.fill" : "mic.fill"
    }

    var toggleButtonTitle: String {
        if muteAllCapableInputDevices {
            return isMuted ? "Unmute All Microphones" : "Mute All Microphones"
        }
        return isMuted ? "Unmute Microphone" : "Mute Microphone"
    }

    var selectedDeviceLabel: String {
        if muteAllCapableInputDevices {
            return "All mute-capable microphones"
        }
        if let selectedDeviceUID,
           let device = availableDevices.first(where: { $0.uid == selectedDeviceUID }) {
            return device.name
        }
        if selectedDeviceMissing {
            return "Selected mic unavailable"
        }
        return "System Default"
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        refreshState()
        registerHotKey()
        startPolling()
        startVolumeLockLoop()
    }

    func setSelectedDeviceUID(_ uid: String?) {
        preferences.selectedDeviceUID = uid?.isEmpty == true ? nil : uid
        refreshState()
    }

    func setMuteAllCapableInputDevices(_ enabled: Bool) {
        preferences.muteAllCapableInputDevices = enabled
        refreshState()
    }

    func setLockInputVolumeTo100WhenUnmuted(_ enabled: Bool) {
        preferences.lockInputVolumeTo100WhenUnmuted = enabled
        if enabled {
            enforceVolumeLockIfNeeded()
        }
    }

    func refreshDevices() {
        do {
            availableDevices = try muteService.inputDevices()
            lastErrorMessage = nil
        } catch {
            lastErrorMessage = error.localizedDescription
        }
    }

    func refreshState() {
        refreshDevices()

        do {
            if preferences.muteAllCapableInputDevices {
                let state = try muteService.allMuteCapableInputsState()
                applyAll(state)
            } else {
                let state = try muteService.inputState(selectedDeviceUID: preferences.selectedDeviceUID)
                apply(state)
            }
            lastErrorMessage = nil
        } catch {
            canToggle = false
            isMuted = false
            statusLine = "Unable to read input device state"
            lastErrorMessage = error.localizedDescription
        }
    }

    func toggleMute() {
        guard canPerformToggleNow() else { return }

        do {
            if preferences.muteAllCapableInputDevices {
                let state = try muteService.toggleAllMuteCapableInputs()
                applyAll(state)
                toastPresenter.showMuteChanged(
                    isMuted: state.isMuted,
                    deviceName: "\(state.totalCapableDevices) microphones"
                )
                enforceVolumeLockIfNeeded()
            } else {
                let state = try muteService.toggleInputMute(selectedDeviceUID: preferences.selectedDeviceUID)
                apply(state)
                toastPresenter.showMuteChanged(isMuted: state.isMuted, deviceName: state.deviceName)
                enforceVolumeLockIfNeeded()
            }
            lastErrorMessage = nil
            refreshDevices()
        } catch {
            refreshState()
            lastErrorMessage = error.localizedDescription
            toastPresenter.showError(error.localizedDescription)
        }
    }

    private func apply(_ state: InputMuteState) {
        isMuted = state.isMuted
        canToggle = state.canToggle
        statusLine = state.statusLine
        activeDeviceName = state.deviceName
        activeDeviceUID = state.deviceUID
        usingDefaultDevice = state.isUsingDefaultDevice
        selectedDeviceMissing = preferences.selectedDeviceUID != nil && preferences.selectedDeviceUID != state.deviceUID
    }

    private func applyAll(_ state: AllInputsMuteState) {
        isMuted = state.isMuted
        canToggle = state.canToggle
        statusLine = state.statusLine
        activeDeviceName = state.totalCapableDevices == 1 ? "1 microphone" : "\(state.totalCapableDevices) microphones"
        activeDeviceUID = nil
        usingDefaultDevice = false
        selectedDeviceMissing = false
    }

    private func canPerformToggleNow() -> Bool {
        let now = clock.now
        if let lastToggleTime {
            let elapsed = lastToggleTime.duration(to: now)
            if elapsed < .milliseconds(300) {
                return false
            }
        }
        self.lastToggleTime = now
        return true
    }

    private func registerHotKey() {
        do {
            try hotKey.register(
                keyCode: UInt32(kVK_ANSI_M),
                modifiers: UInt32(cmdKey | shiftKey)
            ) { [weak self] in
                Task { @MainActor [weak self] in
                    self?.toggleMute()
                }
            }
        } catch {
            lastErrorMessage = "Hotkey registration failed: \(error.localizedDescription)"
        }
    }

    private func startPolling() {
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refreshState()
            }
        }
    }

    private func startVolumeLockLoop() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.enforceVolumeLockIfNeeded()
            }
        }
    }

    private func enforceVolumeLockIfNeeded() {
        guard preferences.lockInputVolumeTo100WhenUnmuted else { return }

        do {
            if preferences.muteAllCapableInputDevices {
                try muteService.lockInputVolumeTo100IfUnmutedForAllMuteCapableInputs()
            } else {
                try muteService.lockInputVolumeTo100IfUnmuted(selectedDeviceUID: preferences.selectedDeviceUID)
            }
        } catch {
            // Ignore background volume-lock errors to avoid noisy menu-state churn.
        }
    }
}
