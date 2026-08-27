import AVFoundation
import CoreAudio
import Foundation

/// The microphones offered in Settings (PRD §11.1).
public struct AudioInputDevice: Sendable, Hashable, Identifiable {
    public var id: AudioDeviceID
    public var uniqueID: String
    public var name: String
}

public enum AudioDeviceLister {
    /// All input-capable devices, System Default excluded — that is the `nil`
    /// selection in preferences.
    public static func inputDevices() -> [AudioInputDevice] {
        let session = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )
        return session.devices.compactMap { device in
            guard let id = coreAudioDeviceID(forUniqueID: device.uniqueID) else { return nil }
            return AudioInputDevice(id: id, uniqueID: device.uniqueID, name: device.localizedName)
        }
    }

    /// True when the previously chosen microphone is currently attached.
    public static func isAvailable(uniqueID: String) -> Bool {
        inputDevices().contains { $0.uniqueID == uniqueID }
    }

    /// The device the system is currently using for input.
    public static func defaultInputDeviceID() -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }

    private static func coreAudioDeviceID(forUniqueID uniqueID: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var uid = uniqueID as CFString
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &uid) { uidPointer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                UInt32(MemoryLayout<CFString>.size),
                uidPointer,
                &size,
                &deviceID
            )
        }
        guard status == noErr, deviceID != kAudioObjectUnknown else { return nil }
        return deviceID
    }
}
