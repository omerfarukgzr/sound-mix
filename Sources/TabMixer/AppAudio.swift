import AppKit
import AudioToolbox
import CoreAudio
import Foundation

/// Ses çıkaran bir uygulama (yardımcı süreçleriyle birlikte, örn. Chrome Helper).
struct AudioApp: Identifiable, Equatable {
    let bundleID: String
    let name: String
    let icon: NSImage
    var processObjects: [AudioObjectID]
    var isPlaying: Bool

    var id: String { bundleID }

    static func == (lhs: AudioApp, rhs: AudioApp) -> Bool {
        lhs.bundleID == rhs.bundleID && lhs.processObjects == rhs.processObjects && lhs.isPlaying == rhs.isPlaying
    }
}

enum AudioProcesses {
    /// Core Audio'nun bildiği süreçleri sahibi olan uygulamaya göre gruplar.
    static func apps() -> [AudioApp] {
        let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.bundleIdentifier != nil }
        var result: [String: AudioApp] = [:]

        for object in CA.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = CA.get(object, kAudioProcessPropertyPID, default: -1)
            let bundle = CA.string(object, kAudioProcessPropertyBundleID) ?? ""
            let owner = running.first { app in
                guard let id = app.bundleIdentifier else { return false }
                return app.processIdentifier == pid || bundle == id || bundle.hasPrefix(id + ".")
            }
            guard let owner, let ownerID = owner.bundleIdentifier, ownerID != Bundle.main.bundleIdentifier else { continue }

            let playing: UInt32 = CA.get(object, kAudioProcessPropertyIsRunningOutput, default: 0)
            var app = result[ownerID] ?? AudioApp(
                bundleID: ownerID,
                name: owner.localizedName ?? ownerID,
                icon: owner.icon ?? NSImage(systemSymbolName: "app", accessibilityDescription: nil)!,
                processObjects: [],
                isPlaying: false
            )
            app.processObjects.append(object)
            app.isPlaying = app.isPlaying || playing != 0
            result[ownerID] = app
        }
        return Array(result.values)
    }
}

/// Ses iş parçacığından okunan kazanç değeri.
final class GainBox: @unchecked Sendable {
    var value: Float = 1
}

/// Bir uygulamanın sesini yakalayıp (orijinalini susturarak) kazançla tekrar çalar.
final class AppVolumeTap {
    let processObjects: [AudioObjectID]
    private let gain = GainBox()
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var procID: AudioDeviceIOProcID?

    init?(name: String, processObjects: [AudioObjectID], gain value: Float) {
        self.processObjects = processObjects
        gain.value = value

        let description = CATapDescription(stereoMixdownOfProcesses: processObjects)
        description.uuid = UUID()
        description.muteBehavior = .mutedWhenTapped
        description.isPrivate = true
        guard AudioHardwareCreateProcessTap(description, &tapID) == noErr else { return nil }

        guard let outputUID = CA.string(CA.defaultOutputDevice, kAudioDevicePropertyDeviceUID) else {
            teardown()
            return nil
        }
        let config: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Tab Mixer – \(name)",
            kAudioAggregateDeviceUIDKey: "io.github.omerfarukgzr.tabmixer.\(UUID().uuidString)",
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapDriftCompensationKey: true,
                kAudioSubTapUIDKey: description.uuid.uuidString,
            ]],
        ]
        guard AudioHardwareCreateAggregateDevice(config as CFDictionary, &aggregateID) == noErr else {
            teardown()
            return nil
        }

        let box = gain
        let status = AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, nil) { _, input, _, output, _ in
            AppVolumeTap.render(input: input, output: output, gain: box.value)
        }
        guard status == noErr, AudioDeviceStart(aggregateID, procID) == noErr else {
            teardown()
            return nil
        }
    }

    func setGain(_ value: Float) {
        gain.value = value
    }

    /// Yakalanan sesi (son giriş akışı = tap) çıkışa kazançla kopyalar.
    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for out in outputs {
            if let data = out.mData { memset(data, 0, Int(out.mDataByteSize)) }
        }
        guard let source = inputs.last, let src = source.mData?.assumingMemoryBound(to: Float.self),
              let destination = outputs.first, let dst = destination.mData?.assumingMemoryBound(to: Float.self) else { return }

        let inChannels = max(Int(source.mNumberChannels), 1)
        let outChannels = max(Int(destination.mNumberChannels), 1)
        let frames = min(Int(source.mDataByteSize) / (4 * inChannels), Int(destination.mDataByteSize) / (4 * outChannels))
        for frame in 0..<frames {
            for channel in 0..<outChannels {
                dst[frame * outChannels + channel] = src[frame * inChannels + min(channel, inChannels - 1)] * gain
            }
        }
    }

    private func teardown() {
        if aggregateID != kAudioObjectUnknown {
            if let procID {
                AudioDeviceStop(aggregateID, procID)
                AudioDeviceDestroyIOProcID(aggregateID, procID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        procID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
    }

    deinit {
        teardown()
    }
}
