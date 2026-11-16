import AVFoundation
import CoreAudio

/// Which camera or microphone to use: the one the person picked while it's connected, otherwise the
/// system default. Pure, so it can be tested without hardware.
enum DeviceChoice {
    struct Device: Equatable, Identifiable {
        let id: String
        let name: String
    }

    /// The saved device's id if it's still connected; nil means "use the system default".
    static func resolve(saved: String?, available: [Device]) -> String? {
        guard let saved, available.contains(where: { $0.id == saved }) else { return nil }
        return saved
    }

    /// The name to show for the current choice.
    static func label(saved: String?, available: [Device], defaultName: String?) -> String {
        if let id = resolve(saved: saved, available: available), let d = available.first(where: { $0.id == id }) { return d.name }
        return defaultName ?? "System default"
    }
}

/// The cameras and microphones macOS can see right now. Listing them doesn't open them.
enum CaptureDevices {
    static func cameras() -> [DeviceChoice.Device] {
        AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera],
            mediaType: .video, position: .unspecified
        ).devices.map { DeviceChoice.Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static func microphones() -> [DeviceChoice.Device] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified)
            .devices.map { DeviceChoice.Device(id: $0.uniqueID, name: $0.localizedName) }
    }

    static var defaultCameraName: String? { AVCaptureDevice.default(for: .video)?.localizedName }
    static var defaultMicrophoneName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    /// Core Audio's id for a microphone's unique id (AVFoundation's uniqueID is Core Audio's device UID).
    static func audioDeviceID(uid: String) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var cfUID = uid as CFString
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = withUnsafeMutablePointer(to: &cfUID) { uidPtr in
            AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address,
                                       UInt32(MemoryLayout<CFString>.size), uidPtr, &size, &device)
        }
        return status == noErr && device != kAudioObjectUnknown ? device : nil
    }
}
