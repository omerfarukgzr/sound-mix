import AppKit
import Combine
import CoreAudio
import Foundation
import ServiceManagement

@MainActor
final class Model: ObservableObject {
    static let chromeID = "com.google.Chrome"
    /// Duraklatılan video ve sessizleşen uygulamaların listede kalma süresi (Ayarlar'dan).
    var recentWindow: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "recentMinutes") as? Int ?? 10
        return TimeInterval(minutes * 60)
    }

    var showOtherApps: Bool { UserDefaults.standard.object(forKey: "showOtherApps") as? Bool ?? true }

    @Published var systemVolume: Double = 0
    @Published var systemVolumeAvailable = false
    @Published var outputName = ""
    @Published var tabs: [ChromeTab] = []
    @Published var chromeConnected = false
    @Published var apps: [AudioApp] = []
    @Published var appGains: [String: Double] = [:]
    @Published var tapError = false
    @Published var audioPermission = AudioPermission.status

    private var taps: [String: AppVolumeTap] = [:]
    private var lastHeard: [String: Date] = [:]
    private var localVideoVolume: [Int: (value: Double, at: Date)] = [:]
    private var timer: Timer?
    private var slowTick = 0

    init() {
        appGains = UserDefaults.standard.dictionary(forKey: "appGains") as? [String: Double] ?? [:]
        refresh(full: true)
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        var addr = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    private func tick() {
        slowTick += 1
        refresh(full: slowTick % 2 == 0)
    }

    func refresh(full: Bool) {
        let now = Date()
        let newTabs = ChromeBridge.tabs().filter { $0.playing || now.timeIntervalSince($0.lastActiveDate) < recentWindow }
        if newTabs != tabs { tabs = newTabs }
        chromeConnected = ChromeBridge.isConnected

        if let volume = SystemVolume.volume {
            systemVolumeAvailable = SystemVolume.isSettable
            if abs(volume - systemVolume) > 0.005 { systemVolume = volume }
        } else {
            systemVolumeAvailable = false
        }
        outputName = SystemVolume.deviceName
        let permission = AudioPermission.status
        if permission != audioPermission { audioPermission = permission }

        if full { refreshApps() }
    }

    // MARK: Menü çubuğu ikonu

    var isActive: Bool {
        tabs.contains(where: \.playing) || apps.contains(where: \.isPlaying)
    }

    // MARK: Sistem sesi

    func setSystemVolume(_ value: Double) {
        systemVolume = value
        SystemVolume.set(value)
    }

    // MARK: Chrome videoları

    var playingTabs: [ChromeTab] { tabs.filter(\.playing) }
    var pausedTabs: [ChromeTab] { tabs.filter { !$0.playing }.sorted { $0.lastActive > $1.lastActive } }

    func videoVolume(_ tab: ChromeTab) -> Double {
        if let local = localVideoVolume[tab.tabId], Date().timeIntervalSince(local.at) < 2 { return local.value }
        return tab.volume ?? 1
    }

    func setVideoVolume(_ tab: ChromeTab, _ value: Double) {
        localVideoVolume[tab.tabId] = (value, Date())
        objectWillChange.send()
        ChromeBridge.setVolume(tab, value)
    }

    // MARK: Uygulama sesleri

    /// Gösterilecek uygulamalar: Chrome her zaman en üstte, diğerleri çalıyorsa,
    /// son 10 dakikada ses çıkardıysa ya da sesi kısılmışsa.
    var visibleApps: [AudioApp] {
        guard showOtherApps else { return [] }
        let now = Date()
        let others = apps.filter { app in
            app.bundleID != Self.chromeID && (
                app.isPlaying
                    || now.timeIntervalSince(lastHeard[app.bundleID] ?? .distantPast) < recentWindow
                    || gain(app.bundleID) < 1
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return others
    }

    var chromeApp: AudioApp? { apps.first { $0.bundleID == Self.chromeID } }

    var chromeIcon: NSImage {
        if let app = chromeApp { return app.icon }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Self.chromeID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    }

    func gain(_ bundleID: String) -> Double { appGains[bundleID] ?? 1 }

    func setGain(_ bundleID: String, _ value: Double) {
        appGains[bundleID] = value
        UserDefaults.standard.set(appGains, forKey: "appGains")
        applyTap(for: bundleID)
    }

    private func refreshApps() {
        let now = Date()
        let fresh = AudioProcesses.apps()
        for app in fresh where app.isPlaying { lastHeard[app.bundleID] = now }
        if fresh.sorted(by: { $0.bundleID < $1.bundleID }) != apps.sorted(by: { $0.bundleID < $1.bundleID }) {
            apps = fresh
        }
        for app in fresh { applyTap(for: app.bundleID) }
        for id in taps.keys where !fresh.contains(where: { $0.bundleID == id }) { taps[id] = nil }
    }

    /// Kazanç %100'se tap'i kaldır (ek gecikme olmasın), değilse oluştur/güncelle.
    private func applyTap(for bundleID: String) {
        let value = gain(bundleID)
        guard value < 0.999, let app = apps.first(where: { $0.bundleID == bundleID }), !app.processObjects.isEmpty else {
            taps[bundleID] = nil
            return
        }
        let linear = Float(value * value) // kulağa doğal gelen eğri
        if let tap = taps[bundleID], tap.processObjects == app.processObjects {
            tap.setGain(linear)
            return
        }
        taps[bundleID] = nil
        taps[bundleID] = AppVolumeTap(name: app.name, processObjects: app.processObjects, gain: linear)
        tapError = taps[bundleID] == nil
    }

    private func outputChanged() {
        let ids = Array(taps.keys)
        taps.removeAll()
        for id in ids { applyTap(for: id) }
        refresh(full: false)
    }

    func requestAudioPermission() {
        AudioPermission.request { [weak self] _ in
            // İzin penceresi kapanınca odak başka uygulamaya geçiyor; Ayarlar'ı tekrar öne getir
            NSApp.activate(ignoringOtherApps: true)
            NSApp.windows.first { $0.title == "Tab Mixer Ayarları" }?.makeKeyAndOrderFront(nil)
            guard let self else { return }
            self.audioPermission = AudioPermission.status
            self.tapError = false
            for id in self.appGains.keys { self.applyTap(for: id) }
        }
    }

    func resetGains() {
        appGains = [:]
        UserDefaults.standard.removeObject(forKey: "appGains")
        taps.removeAll()
        tapError = false
    }

    // MARK: Girişte başlat

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            objectWillChange.send()
            if newValue { try? SMAppService.mainApp.register() } else { try? SMAppService.mainApp.unregister() }
        }
    }
}
