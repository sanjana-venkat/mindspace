import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

public struct AudioInputDevice: Identifiable, Hashable, Sendable {
    public let uid: String
    public let name: String
    public let isSystemDefault: Bool
    public var id: String { uid }
}

public enum AudioInputDevices {
    public static func available() -> [AudioInputDevice] {
        let defaultID = defaultInputDeviceID()
        return allDeviceIDs()
            .filter(hasInputStreams)
            .compactMap { deviceID -> AudioInputDevice? in
                guard let uid = stringProperty(kAudioDevicePropertyDeviceUID, deviceID: deviceID) else { return nil }
                let name = stringProperty(kAudioObjectPropertyName, deviceID: deviceID) ?? "Microphone \(deviceID)"
                return AudioInputDevice(uid: uid, name: name, isSystemDefault: deviceID == defaultID)
            }
            .sorted {
                if $0.isSystemDefault != $1.isSystemDefault { return $0.isSystemDefault }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
    }

    static func deviceID(forUID uid: String?) -> AudioObjectID? {
        guard let uid else { return nil }
        return allDeviceIDs().first {
            hasInputStreams($0) && stringProperty(kAudioDevicePropertyDeviceUID, deviceID: $0) == uid
        }
    }

    static func apply(uid: String?, to engine: AVAudioEngine) throws {
        guard let uid else { return }
        guard var deviceID = deviceID(forUID: uid) else {
            throw NSError(domain: "Notefy.AudioInput", code: 2, userInfo: [NSLocalizedDescriptionKey: "The selected microphone is no longer connected. Choose another input in Settings."])
        }
        guard let audioUnit = engine.inputNode.audioUnit else {
            throw NSError(domain: "Notefy.AudioInput", code: 1, userInfo: [NSLocalizedDescriptionKey: "The selected microphone has no audio unit."])
        }
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
        guard status == noErr else {
            throw NSError(domain: "Notefy.AudioInput", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "The selected microphone could not be activated (\(status))."])
        }
    }

    private static func defaultInputDeviceID() -> AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        return AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID) == noErr
            ? deviceID : nil
    }

    private static func allDeviceIDs() -> [AudioObjectID] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }
        var devices = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &devices) == noErr else { return [] }
        return devices
    }

    private static func hasInputStreams(_ deviceID: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &size) == noErr, size > 0 else { return false }
        let pointer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { pointer.deallocate() }
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer) == noErr else { return false }
        let list = UnsafeMutableAudioBufferListPointer(pointer.assumingMemoryBound(to: AudioBufferList.self))
        return list.reduce(0) { $0 + Int($1.mNumberChannels) } > 0
    }

    private static func stringProperty(_ selector: AudioObjectPropertySelector, deviceID: AudioObjectID) -> String? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let pointer = UnsafeMutablePointer<CFString?>.allocate(capacity: 1)
        pointer.initialize(to: nil)
        defer { pointer.deinitialize(count: 1); pointer.deallocate() }
        var size = UInt32(MemoryLayout<CFString?>.size)
        guard AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, pointer) == noErr,
              let value = pointer.pointee else { return nil }
        return value as String
    }
}
