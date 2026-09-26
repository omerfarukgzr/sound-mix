import AudioToolbox
import CoreAudio
import Foundation

/// Core Audio özelliklerini okumak/yazmak için küçük yardımcılar.
enum CA {
    static func address(_ selector: AudioObjectPropertySelector,
                        _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func get<T>(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                       scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, default value: T) -> T {
        var addr = address(selector, scope)
        var size = UInt32(MemoryLayout<T>.size)
        var result = value
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        return status == noErr ? result : value
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var addr = address(selector)
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var value: Unmanaged<CFString>?
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &addr, 0, nil, &size, $0)
        }
        guard status == noErr, let value else { return nil }
        return value.takeRetainedValue() as String
    }

    static func ids(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var list = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &addr, 0, nil, &size, &list) == noErr else { return [] }
        return list
    }

    static var defaultOutputDevice: AudioObjectID {
        CA.get(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice, default: AudioObjectID(kAudioObjectUnknown))
    }
}

/// Mac'in varsayılan çıkış cihazının ses seviyesi.
enum SystemVolume {
    private static var volumeAddress = CA.address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, kAudioDevicePropertyScopeOutput)

    static var deviceName: String {
        CA.string(CA.defaultOutputDevice, kAudioObjectPropertyName) ?? "Bilinmeyen çıkış"
    }

    static var isSettable: Bool {
        let device = CA.defaultOutputDevice
        guard AudioObjectHasProperty(device, &volumeAddress) else { return false }
        var settable: DarwinBoolean = false
        return AudioObjectIsPropertySettable(device, &volumeAddress, &settable) == noErr && settable.boolValue
    }

    static var volume: Double? {
        let device = CA.defaultOutputDevice
        guard AudioObjectHasProperty(device, &volumeAddress) else { return nil }
        var value: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        guard AudioHardwareServiceGetPropertyData(device, &volumeAddress, 0, nil, &size, &value) == noErr else { return nil }
        return Double(value)
    }

    static func set(_ volume: Double) {
        let device = CA.defaultOutputDevice
        var value = Float32(min(max(volume, 0), 1))
        AudioHardwareServiceSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }
}
