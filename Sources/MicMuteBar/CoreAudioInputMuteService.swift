import CoreAudio
import Foundation

enum CoreAudioMuteError: LocalizedError {
    case noDefaultInputDevice
    case inputMuteNotSupported(String)
    case muteWriteHadNoEffect(String)
    case osStatus(OSStatus, String)

    var errorDescription: String? {
        switch self {
        case .noDefaultInputDevice:
            return "No default input device is available."
        case .inputMuteNotSupported(let deviceName):
            return "Input device '\(deviceName)' does not expose a mutable CoreAudio mute control."
        case .muteWriteHadNoEffect(let deviceName):
            return "Tried multiple CoreAudio mute controls for '\(deviceName)', but none changed the mute state."
        case .osStatus(let status, let operation):
            return "\(operation) failed (\(status))."
        }
    }
}

struct InputMuteState {
    let isMuted: Bool
    let canToggle: Bool
    let statusLine: String
    let deviceUID: String?
    let deviceName: String
    let isUsingDefaultDevice: Bool
}

struct AllInputsMuteState {
    let isMuted: Bool
    let canToggle: Bool
    let statusLine: String
    let totalCapableDevices: Int
    let mutedDevices: Int
    let failedDevices: Int
}

struct MicInputDevice: Identifiable, Hashable {
    let uid: String
    let name: String
    let isDefault: Bool
    let canToggle: Bool
    let isMuted: Bool?

    var id: String { uid }

    var displayName: String {
        isDefault ? "\(name) (Default)" : name
    }
}

struct CoreAudioInputMuteService {
    func inputDevices() throws -> [MicInputDevice] {
        let defaultID = try? defaultInputDeviceID()

        let devices = try allAudioDeviceIDs().compactMap { deviceID -> MicInputDevice? in
            guard (try? streamChannelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)) ?? 0 > 0 else {
                return nil
            }

            let name = (try? deviceName(deviceID)) ?? "Unknown Input"
            let uid = (try? deviceUID(deviceID)) ?? "device-\(deviceID)"
            let readableGroups = (try? readableMuteTargetGroups(for: deviceID)) ?? []
            let writableGroups = (try? writableMuteTargetGroups(for: deviceID)) ?? []
            let readGroup = preferredGroup(in: writableGroups) ?? preferredGroup(in: readableGroups)
            let muted = readGroup.flatMap { try? allTargetsMuted($0) }

            return MicInputDevice(
                uid: uid,
                name: name,
                isDefault: defaultID == deviceID,
                canToggle: !writableGroups.isEmpty,
                isMuted: muted
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    func inputState(selectedDeviceUID: String?) throws -> InputMuteState {
        let resolved = try resolveTargetDevice(selectedDeviceUID: selectedDeviceUID)
        let readableGroups = try readableMuteTargetGroups(for: resolved.deviceID)
        let writableGroups = try writableMuteTargetGroups(for: resolved.deviceID)

        guard let readGroup = (preferredGroup(in: writableGroups) ?? preferredGroup(in: readableGroups)) else {
            return InputMuteState(
                isMuted: false,
                canToggle: false,
                statusLine: unavailableMuteStatusLine(for: resolved),
                deviceUID: resolved.uid,
                deviceName: resolved.name,
                isUsingDefaultDevice: resolved.isDefault
            )
        }

        let muted = try allTargetsMuted(readGroup)
        let label = muted ? "muted" : "live"
        var status = "Input (\(resolved.name)) is \(label)"
        if resolved.selectedDeviceMissing {
            status += " • selected mic missing, using default"
        } else if !resolved.isDefault {
            status += " • custom mic selected"
        }

        return InputMuteState(
            isMuted: muted,
            canToggle: !writableGroups.isEmpty,
            statusLine: status,
            deviceUID: resolved.uid,
            deviceName: resolved.name,
            isUsingDefaultDevice: resolved.isDefault
        )
    }

    func toggleInputMute(selectedDeviceUID: String?) throws -> InputMuteState {
        let resolved = try resolveTargetDevice(selectedDeviceUID: selectedDeviceUID)
        try toggleMute(on: resolved.deviceID, deviceName: resolved.name)
        return try inputState(selectedDeviceUID: selectedDeviceUID)
    }

    func allMuteCapableInputsState() throws -> AllInputsMuteState {
        let devices = try muteCapableInputDevices()
        guard !devices.isEmpty else {
            return AllInputsMuteState(
                isMuted: false,
                canToggle: false,
                statusLine: "No mute-capable input devices found",
                totalCapableDevices: 0,
                mutedDevices: 0,
                failedDevices: 0
            )
        }

        var mutedCount = 0
        var failedCount = 0

        for device in devices {
            let readableGroups = try readableMuteTargetGroups(for: device.deviceID)
            let writableGroups = try writableMuteTargetGroups(for: device.deviceID)
            guard let readGroup = preferredGroup(in: writableGroups) ?? preferredGroup(in: readableGroups) else {
                failedCount += 1
                continue
            }

            if (try? allTargetsMuted(readGroup)) == true {
                mutedCount += 1
            }
        }

        let isAllMuted = mutedCount == devices.count
        var status = "All mute-capable inputs: \(mutedCount)/\(devices.count) muted"
        if failedCount > 0 {
            status += " • \(failedCount) unreadable"
        }

        return AllInputsMuteState(
            isMuted: isAllMuted,
            canToggle: true,
            statusLine: status,
            totalCapableDevices: devices.count,
            mutedDevices: mutedCount,
            failedDevices: failedCount
        )
    }

    func toggleAllMuteCapableInputs() throws -> AllInputsMuteState {
        let before = try allMuteCapableInputsState()
        guard before.canToggle else { return before }

        let nextMuted = !before.isMuted
        let devices = try muteCapableInputDevices()

        var successes = 0
        for device in devices {
            do {
                try setMute(on: device.deviceID, deviceName: device.name, muted: nextMuted)
                successes += 1
            } catch {
                continue
            }
        }

        if successes == 0 {
            throw CoreAudioMuteError.muteWriteHadNoEffect("all mute-capable input devices")
        }

        return try allMuteCapableInputsState()
    }

    func lockInputVolumeTo100IfUnmuted(selectedDeviceUID: String?) throws {
        let resolved = try resolveTargetDevice(selectedDeviceUID: selectedDeviceUID)
        try lockInputVolumeTo100IfUnmuted(on: resolved.deviceID)
    }

    func lockInputVolumeTo100IfUnmutedForAllMuteCapableInputs() throws {
        for device in try muteCapableInputDevices() {
            try? lockInputVolumeTo100IfUnmuted(on: device.deviceID)
        }
    }

    private func toggleMute(on deviceID: AudioDeviceID, deviceName: String) throws {
        let writableGroups = try writableMuteTargetGroups(for: deviceID)
        guard !writableGroups.isEmpty else {
            throw CoreAudioMuteError.inputMuteNotSupported(deviceName)
        }

        let readableGroups = try readableMuteTargetGroups(for: deviceID)
        let baselineGroup = preferredGroup(in: readableGroups) ?? preferredGroup(in: writableGroups)!
        let currentlyMuted = try allTargetsMuted(baselineGroup)
        let nextMuted = !currentlyMuted

        for group in orderedToggleCandidates(writableGroups, preferred: baselineGroup) {
            let before = try? allTargetsMuted(group)

            do {
                try setMuted(nextMuted, for: group)
            } catch {
                continue
            }

            if let after = try? allTargetsMuted(group), after == nextMuted {
                return
            }

            if let effective = try? allTargetsMuted(baselineGroup), effective == nextMuted {
                return
            }

            if let before {
                try? setMuted(before, for: group)
            }
        }

        throw CoreAudioMuteError.muteWriteHadNoEffect(deviceName)
    }

    private func setMute(on deviceID: AudioDeviceID, deviceName: String, muted: Bool) throws {
        let writableGroups = try writableMuteTargetGroups(for: deviceID)
        guard !writableGroups.isEmpty else {
            throw CoreAudioMuteError.inputMuteNotSupported(deviceName)
        }

        let readableGroups = try readableMuteTargetGroups(for: deviceID)
        let baselineGroup = preferredGroup(in: readableGroups) ?? preferredGroup(in: writableGroups)!

        for group in orderedToggleCandidates(writableGroups, preferred: baselineGroup) {
            let before = try? allTargetsMuted(group)

            do {
                try setMuted(muted, for: group)
            } catch {
                continue
            }

            if let after = try? allTargetsMuted(group), after == muted {
                return
            }

            if let effective = try? allTargetsMuted(baselineGroup), effective == muted {
                return
            }

            if let before {
                try? setMuted(before, for: group)
            }
        }

        throw CoreAudioMuteError.muteWriteHadNoEffect(deviceName)
    }

    private func lockInputVolumeTo100IfUnmuted(on deviceID: AudioDeviceID) throws {
        if try isDeviceMuted(deviceID) {
            return
        }

        let volumeGroups = try writableVolumeTargetGroups(for: deviceID)
        guard !volumeGroups.isEmpty else { return }

        var wroteAny = false
        for group in volumeGroups {
            do {
                try setVolumeScalar(1.0, for: group)
                wroteAny = true
            } catch {
                continue
            }
        }

        if !wroteAny {
            throw CoreAudioMuteError.osStatus(-1, "Setting input volume to 100")
        }
    }

    private func unavailableMuteStatusLine(for resolved: ResolvedDevice) -> String {
        var status = "Input (\(resolved.name)) cannot be muted by CoreAudio"
        if resolved.selectedDeviceMissing {
            status += " • selected mic missing, using default"
        }
        return status
    }

    private func resolveTargetDevice(selectedDeviceUID: String?) throws -> ResolvedDevice {
        let defaultID = try defaultInputDeviceID()
        let defaultName = (try? deviceName(defaultID)) ?? "Unknown Input"
        let defaultUID = (try? deviceUID(defaultID)) ?? "device-\(defaultID)"

        guard let selectedDeviceUID, !selectedDeviceUID.isEmpty else {
            return ResolvedDevice(
                deviceID: defaultID,
                name: defaultName,
                uid: defaultUID,
                isDefault: true,
                selectedDeviceMissing: false
            )
        }

        if let selectedID = try findInputDeviceID(uid: selectedDeviceUID) {
            let selectedName = (try? deviceName(selectedID)) ?? "Unknown Input"
            return ResolvedDevice(
                deviceID: selectedID,
                name: selectedName,
                uid: selectedDeviceUID,
                isDefault: selectedID == defaultID,
                selectedDeviceMissing: false
            )
        }

        return ResolvedDevice(
            deviceID: defaultID,
            name: defaultName,
            uid: defaultUID,
            isDefault: true,
            selectedDeviceMissing: true
        )
    }

    private func allAudioDeviceIDs() throws -> [AudioDeviceID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr else {
            throw CoreAudioMuteError.osStatus(sizeStatus, "Reading audio device list size")
        }

        let count = Int(size) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: count)

        let dataStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceIDs
        )
        guard dataStatus == noErr else {
            throw CoreAudioMuteError.osStatus(dataStatus, "Reading audio device list")
        }

        return deviceIDs
    }

    private func findInputDeviceID(uid: String) throws -> AudioDeviceID? {
        for deviceID in try allAudioDeviceIDs() {
            let channelCount = (try? streamChannelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)) ?? 0
            guard channelCount > 0 else { continue }
            if (try? deviceUID(deviceID)) == uid {
                return deviceID
            }
        }
        return nil
    }

    private func muteCapableInputDevices() throws -> [ResolvedDevice] {
        let defaultID = try? defaultInputDeviceID()
        var devices: [ResolvedDevice] = []

        for deviceID in try allAudioDeviceIDs() {
            let channelCount = (try? streamChannelCount(for: deviceID, scope: kAudioDevicePropertyScopeInput)) ?? 0
            guard channelCount > 0 else { continue }
            let writableGroups = try writableMuteTargetGroups(for: deviceID)
            guard !writableGroups.isEmpty else { continue }

            let name = (try? deviceName(deviceID)) ?? "Unknown Input"
            let uid = (try? deviceUID(deviceID)) ?? "device-\(deviceID)"
            devices.append(
                ResolvedDevice(
                    deviceID: deviceID,
                    name: name,
                    uid: uid,
                    isDefault: defaultID == deviceID,
                    selectedDeviceMissing: false
                )
            )
        }

        return devices.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func isDeviceMuted(_ deviceID: AudioDeviceID) throws -> Bool {
        let readableGroups = try readableMuteTargetGroups(for: deviceID)
        let writableGroups = try writableMuteTargetGroups(for: deviceID)
        guard let readGroup = preferredGroup(in: writableGroups) ?? preferredGroup(in: readableGroups) else {
            return false
        }
        return try allTargetsMuted(readGroup)
    }

    private func defaultInputDeviceID() throws -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )

        guard status == noErr else {
            throw CoreAudioMuteError.osStatus(status, "Reading default input device")
        }
        guard deviceID != kAudioObjectUnknown else {
            throw CoreAudioMuteError.noDefaultInputDevice
        }
        return deviceID
    }

    private func deviceName(_ deviceID: AudioDeviceID) throws -> String {
        try stringProperty(deviceID: deviceID, selector: kAudioObjectPropertyName)
    }

    private func deviceUID(_ deviceID: AudioDeviceID) throws -> String {
        try stringProperty(deviceID: deviceID, selector: kAudioDevicePropertyDeviceUID)
    }

    private func stringProperty(deviceID: AudioDeviceID, selector: AudioObjectPropertySelector) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)

        guard status == noErr else {
            throw CoreAudioMuteError.osStatus(status, "Reading string property")
        }

        return value as String
    }

    private func readableMuteTargetGroups(for deviceID: AudioDeviceID) throws -> [MuteTargets] {
        try muteTargetGroups(for: deviceID, requireSettable: false)
    }

    private func writableMuteTargetGroups(for deviceID: AudioDeviceID) throws -> [MuteTargets] {
        try muteTargetGroups(for: deviceID, requireSettable: true)
    }

    private func muteTargetGroups(for deviceID: AudioDeviceID, requireSettable: Bool) throws -> [MuteTargets] {
        var groups: [MuteTargets] = []

        for scope in [kAudioDevicePropertyScopeInput, kAudioObjectPropertyScopeGlobal, kAudioDevicePropertyScopeOutput] {
            let channels = ((try? candidateChannelElements(for: deviceID, scope: scope)) ?? [])
                .filter {
                    requireSettable
                        ? canControlMute(deviceID: deviceID, scope: scope, element: $0)
                        : hasMuteControl(deviceID: deviceID, scope: scope, element: $0)
                }

            if !channels.isEmpty {
                groups.append(MuteTargets(deviceID: deviceID, scope: scope, elements: channels))
            }

            let main = kAudioObjectPropertyElementMain
            let mainEligible = requireSettable
                ? canControlMute(deviceID: deviceID, scope: scope, element: main)
                : hasMuteControl(deviceID: deviceID, scope: scope, element: main)

            if mainEligible {
                groups.append(MuteTargets(deviceID: deviceID, scope: scope, elements: [main]))
            }
        }

        return deduplicatedGroups(groups)
    }

    private func writableVolumeTargetGroups(for deviceID: AudioDeviceID) throws -> [VolumeTargets] {
        try volumeTargetGroups(for: deviceID, requireSettable: true)
    }

    private func volumeTargetGroups(for deviceID: AudioDeviceID, requireSettable: Bool) throws -> [VolumeTargets] {
        var groups: [VolumeTargets] = []

        for scope in [kAudioDevicePropertyScopeInput, kAudioObjectPropertyScopeGlobal] {
            let channels = ((try? candidateChannelElements(for: deviceID, scope: scope)) ?? [])
                .filter {
                    requireSettable
                        ? canControlVolume(deviceID: deviceID, scope: scope, element: $0)
                        : hasVolumeControl(deviceID: deviceID, scope: scope, element: $0)
                }

            if !channels.isEmpty {
                groups.append(VolumeTargets(deviceID: deviceID, scope: scope, elements: channels))
            }

            let main = kAudioObjectPropertyElementMain
            let mainEligible = requireSettable
                ? canControlVolume(deviceID: deviceID, scope: scope, element: main)
                : hasVolumeControl(deviceID: deviceID, scope: scope, element: main)

            if mainEligible {
                groups.append(VolumeTargets(deviceID: deviceID, scope: scope, elements: [main]))
            }
        }

        return deduplicatedVolumeGroups(groups)
    }

    private func candidateChannelElements(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> [AudioObjectPropertyElement] {
        let count = max(try streamChannelCount(for: deviceID, scope: scope), 2)
        let channels = (1...count).map(AudioObjectPropertyElement.init)
        return uniqueElements(channels)
    }

    private func streamChannelCount(for deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) throws -> Int {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0

        let sizeStatus = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size)
        guard sizeStatus == noErr else {
            throw CoreAudioMuteError.osStatus(sizeStatus, "Reading stream configuration size")
        }
        guard size > 0 else { return 0 }

        var bytes = [UInt8](repeating: 0, count: Int(size))
        let dataStatus = bytes.withUnsafeMutableBytes { rawBuffer in
            AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, rawBuffer.baseAddress!)
        }
        guard dataStatus == noErr else {
            throw CoreAudioMuteError.osStatus(dataStatus, "Reading stream configuration")
        }

        return bytes.withUnsafeMutableBytes { rawBuffer in
            let list = rawBuffer.baseAddress!.assumingMemoryBound(to: AudioBufferList.self)
            let buffers = UnsafeMutableAudioBufferListPointer(list)
            return buffers.reduce(0) { partial, buffer in
                partial + Int(buffer.mNumberChannels)
            }
        }
    }

    private func allTargetsMuted(_ targets: MuteTargets) throws -> Bool {
        let values = try targets.elements.map { try muteValue(deviceID: targets.deviceID, scope: targets.scope, element: $0) }
        guard !values.isEmpty else { return false }
        return values.allSatisfy { $0 }
    }

    private func setMuted(_ muted: Bool, for targets: MuteTargets) throws {
        for element in targets.elements {
            try setMuteValue(muted, deviceID: targets.deviceID, scope: targets.scope, element: element)
        }
    }

    private func setVolumeScalar(_ value: Float32, for targets: VolumeTargets) throws {
        for element in targets.elements {
            try setVolumeValue(value, deviceID: targets.deviceID, scope: targets.scope, element: element)
        }
    }

    private func canControlMute(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = muteAddress(scope: scope, element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private func hasMuteControl(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = muteAddress(scope: scope, element: element)
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func canControlVolume(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(scope: scope, element: element)
        guard AudioObjectHasProperty(deviceID, &address) else { return false }

        var settable: DarwinBoolean = false
        let status = AudioObjectIsPropertySettable(deviceID, &address, &settable)
        return status == noErr && settable.boolValue
    }

    private func hasVolumeControl(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> Bool {
        var address = volumeAddress(scope: scope, element: element)
        return AudioObjectHasProperty(deviceID, &address)
    }

    private func muteValue(deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) throws -> Bool {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress(scope: scope, element: element)

        let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw CoreAudioMuteError.osStatus(status, "Reading mute state")
        }

        return value != 0
    }

    private func setMuteValue(_ muted: Bool, deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) throws {
        var value: UInt32 = muted ? 1 : 0
        let size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress(scope: scope, element: element)

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
        guard status == noErr else {
            throw CoreAudioMuteError.osStatus(status, "Setting mute state")
        }
    }

    private func setVolumeValue(_ value: Float32, deviceID: AudioDeviceID, scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) throws {
        var scalar = max(0, min(value, 1))
        let size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress(scope: scope, element: element)

        let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &scalar)
        guard status == noErr else {
            throw CoreAudioMuteError.osStatus(status, "Setting input volume")
        }
    }

    private func muteAddress(scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: scope,
            mElement: element
        )
    }

    private func volumeAddress(scope: AudioObjectPropertyScope, element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: scope,
            mElement: element
        )
    }

    private func uniqueElements(_ elements: [AudioObjectPropertyElement]) -> [AudioObjectPropertyElement] {
        var seen = Set<AudioObjectPropertyElement>()
        var result: [AudioObjectPropertyElement] = []
        result.reserveCapacity(elements.count)

        for element in elements where seen.insert(element).inserted {
            result.append(element)
        }

        return result
    }

    private func preferredGroup(in groups: [MuteTargets]) -> MuteTargets? {
        groups.first
    }

    private func orderedToggleCandidates(_ groups: [MuteTargets], preferred: MuteTargets) -> [MuteTargets] {
        var ordered: [MuteTargets] = []
        ordered.reserveCapacity(groups.count)

        if let preferredIndex = groups.firstIndex(of: preferred) {
            ordered.append(groups[preferredIndex])
        }

        for group in groups where group != preferred {
            ordered.append(group)
        }

        return ordered
    }

    private func deduplicatedGroups(_ groups: [MuteTargets]) -> [MuteTargets] {
        var seen = Set<MuteTargets>()
        var result: [MuteTargets] = []

        for group in groups where seen.insert(group).inserted {
            result.append(group)
        }

        return result
    }

    private func deduplicatedVolumeGroups(_ groups: [VolumeTargets]) -> [VolumeTargets] {
        var seen = Set<VolumeTargets>()
        var result: [VolumeTargets] = []

        for group in groups where seen.insert(group).inserted {
            result.append(group)
        }

        return result
    }
}

private struct ResolvedDevice {
    let deviceID: AudioDeviceID
    let name: String
    let uid: String
    let isDefault: Bool
    let selectedDeviceMissing: Bool
}

private struct MuteTargets: Hashable {
    let deviceID: AudioDeviceID
    let scope: AudioObjectPropertyScope
    let elements: [AudioObjectPropertyElement]
}

private struct VolumeTargets: Hashable {
    let deviceID: AudioDeviceID
    let scope: AudioObjectPropertyScope
    let elements: [AudioObjectPropertyElement]
}
