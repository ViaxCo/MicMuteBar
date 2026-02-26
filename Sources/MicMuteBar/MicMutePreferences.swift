import Foundation
import Observation

@MainActor
@Observable
final class MicMutePreferences {
    private let defaults = UserDefaults.standard
    private let selectedDeviceKey = "MicMuteBar.selectedDeviceUID"
    private let muteAllDevicesKey = "MicMuteBar.muteAllCapableInputDevices"
    private let lockVolumeKey = "MicMuteBar.lockInputVolumeTo100WhenUnmuted"

    var selectedDeviceUID: String? {
        didSet {
            if let selectedDeviceUID, !selectedDeviceUID.isEmpty {
                defaults.set(selectedDeviceUID, forKey: selectedDeviceKey)
            } else {
                defaults.removeObject(forKey: selectedDeviceKey)
            }
        }
    }

    var muteAllCapableInputDevices = false {
        didSet {
            defaults.set(muteAllCapableInputDevices, forKey: muteAllDevicesKey)
        }
    }

    var lockInputVolumeTo100WhenUnmuted = false {
        didSet {
            defaults.set(lockInputVolumeTo100WhenUnmuted, forKey: lockVolumeKey)
        }
    }

    init() {
        selectedDeviceUID = defaults.string(forKey: selectedDeviceKey)
        muteAllCapableInputDevices = defaults.bool(forKey: muteAllDevicesKey)
        lockInputVolumeTo100WhenUnmuted = defaults.bool(forKey: lockVolumeKey)
    }
}
