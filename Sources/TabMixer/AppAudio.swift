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
        // Her süreç nesnesi için listeyi baştan taramamak adına PID ve bundle ID tabloları
        var byPID: [pid_t: NSRunningApplication] = [:]
        var byBundle: [String: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            guard let id = app.bundleIdentifier else { continue }
            byPID[app.processIdentifier] = app
            if byBundle[id] == nil { byBundle[id] = app }
        }
        var result: [String: AudioApp] = [:]

        for object in CA.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyProcessObjectList) {
            let pid: pid_t = CA.get(object, kAudioProcessPropertyPID, default: -1)
            let bundle = CA.string(object, kAudioProcessPropertyBundleID) ?? ""
            guard let owner = byPID[pid] ?? owner(of: bundle, in: byBundle),
                  let ownerID = owner.bundleIdentifier, ownerID != Bundle.main.bundleIdentifier else { continue }

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

    /// Bundle ID'nin kendisi ya da üst kimliklerinden biri (örn. com.google.Chrome.helper → com.google.Chrome).
    private static func owner(of bundle: String, in byBundle: [String: NSRunningApplication]) -> NSRunningApplication? {
        var id = Substring(bundle)
        while !id.isEmpty {
            if let app = byBundle[String(id)] { return app }
            guard let dot = id.lastIndex(of: ".") else { break }
            id = id[..<dot]
        }
        return nil
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
    /// Tap stereo: tek interleaved tampon ya da (interleaved değilse) son iki mono tampon.
    /// Çıkış tamponları sırayla kanal kanal doldurulur; böylece interleaved, kanal başına ayrı
    /// tampon ve çok akışlı cihazlar aynı döngüyle çalışır. Ses iş parçacığı: bellek ayırma yok.
    private static func render(input: UnsafePointer<AudioBufferList>, output: UnsafeMutablePointer<AudioBufferList>, gain: Float) {
        let inputs = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input))
        let outputs = UnsafeMutableAudioBufferListPointer(output)
        for out in outputs {
            if let data = out.mData { memset(data, 0, Int(out.mDataByteSize)) }
        }
        guard let last = inputs.last, let lastData = last.mData?.assumingMemoryBound(to: Float.self) else { return }

        // Sol/sağ kanal başlangıcı, örnekler arası adım ve kare sayısı
        var left = lastData, right = lastData, stride = max(Int(last.mNumberChannels), 1)
        var inFrames = Int(last.mDataByteSize) / (4 * stride)
        if stride >= 2 {
            right = lastData + 1
        } else if inputs.count >= 2, inputs[inputs.count - 2].mNumberChannels == 1,
                  let leftData = inputs[inputs.count - 2].mData?.assumingMemoryBound(to: Float.self) {
            left = leftData
            inFrames = min(inFrames, Int(inputs[inputs.count - 2].mDataByteSize) / 4)
        }

        var channel = 0 // çıkış cihazındaki toplam kanal sırası
        for out in outputs {
            let outChannels = max(Int(out.mNumberChannels), 1)
            defer { channel += outChannels }
            guard let dst = out.mData?.assumingMemoryBound(to: Float.self) else { continue }
            let frames = min(inFrames, Int(out.mDataByteSize) / (4 * outChannels))
            for c in 0..<outChannels {
                let src = channel + c == 0 ? left : right
                for frame in 0..<frames {
                    dst[frame * outChannels + c] = src[frame * stride] * gain
                }
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
