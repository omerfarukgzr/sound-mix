import AppKit
import Combine
import CoreAudio
import Foundation
import ServiceManagement

@MainActor
final class Model: ObservableObject {
    /// Duraklatılan video ve sessizleşen uygulamaların listede kalma süresi (Ayarlar'dan).
    var recentWindow: TimeInterval {
        let minutes = UserDefaults.standard.object(forKey: "recentMinutes") as? Int ?? 10
        return TimeInterval(minutes * 60)
    }

    /// Ayarlanan süre okunur biçimde: "10 dakikada", "1 saatte".
    var recentWindowText: String {
        let minutes = Int(recentWindow / 60)
        return minutes % 60 == 0 ? "\(minutes / 60) saatte" : "\(minutes) dakikada"
    }

    var showOtherApps: Bool { UserDefaults.standard.object(forKey: "showOtherApps") as? Bool ?? true }

    @Published var systemVolume: Double = 0
    @Published var systemVolumeAvailable = false
    @Published var outputName = ""
    /// Bütün tarayıcılardaki videolar; her biri hangi köprüden geldiğini bilir.
    @Published var tabs: [ChromeTab] = []
    /// Yaşayan köprüler ve onları başlatan tarayıcılar. Eklenti yeniden yüklenince köprü yeni bir pid'le gelir;
    /// kurulum yardımcısı yüklemeyi tarayıcının geç yazılan tercihlerini beklemeden buradan anlar.
    @Published var bridgeBrowsers: [pid_t: Browser] = [:]
    /// Kurulum ve ayar metinlerinde adı geçen tarayıcı: bağlı ilk tarayıcı, yoksa son bağlanan ya da kurulu ilk tarayıcı.
    @Published var browser = Browser.preferred
    /// Uygulamanın içindekinden farklı sürümde çalışan eklentinin sürümü (varsa).
    @Published var staleExtensionVersion: String?
    @Published var apps: [AudioApp] = []
    @Published var appGains: [String: Double] = [:]
    @Published var tapError = false
    @Published var audioPermission = AudioPermission.status
    @Published var update: AvailableUpdate? = UpdateChecker.stored
    @Published var updateStatus = UpdateStatus.idle
    @Published var checkingUpdate = false
    /// GitHub'a son başarılı soru; Ayarlar'da "Son denetim" olarak görünür.
    @Published var lastUpdateCheck = UpdateChecker.lastCheck
    /// Elle başlatılan son denetim GitHub'a ulaşamadı.
    @Published var updateCheckFailed = false
    /// Tarayıcı eklentiyi kalıcı klasör yerine geçici bir kopyadan yüklüyor; Ayarlar onarım önerir.
    @Published var extensionNeedsRepair = false
    /// Tarayıcıdaki eklenti uygulamanın içindekiyle aynı sürümde değil (güncelleme yüklenememiş).
    @Published var extensionOutdated = false
    private var versionMismatchSince: Date?

    /// Eklentinin yeniden yüklenmesi gerekiyor: geçici kopyadan yükleniyor ya da güncel değil.
    var extensionNeedsAttention: Bool { extensionNeedsRepair || extensionOutdated }

    private var taps: [String: AppVolumeTap] = [:]
    private var lastHeard: [String: Date] = [:]
    private var localVideoVolume: [String: (value: Double, at: Date)] = [:]
    private var timer: Timer?
    private var updateTimer: Timer?
    private var slowTick = 0
    /// Menü paneli açıkken uygulama listesi daha sık yenilenir.
    var panelOpen = false

    init() {
        appGains = UserDefaults.standard.dictionary(forKey: "appGains") as? [String: Double] ?? [:]
        refresh(full: true)
        refreshExtensionLocation()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        // Açılıştan biraz sonra, sonra saatte bir "4 saat doldu mu" diye bak
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.checkForUpdate() }
        updateTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkForUpdate() }
        }
        var addr = CA.address(kAudioHardwarePropertyDefaultOutputDevice)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated { self?.outputChanged() }
        }
    }

    /// Her saniye hafif yenileme; süreç listesini taramak pahalı olduğu için tam yenileme
    /// panel açıkken 2, kapalıyken 4 saniyede bir (yeni yardımcı süreçler tap'e yine eklenir).
    private func tick() {
        slowTick += 1
        refresh(full: slowTick % (panelOpen ? 2 : 4) == 0)
    }

    func refresh(full: Bool) {
        let now = Date()
        let sessions = ChromeBridge.sessions()
        let newTabs = sessions.flatMap(\.tabs).filter { $0.playing || now.timeIntervalSince($0.lastActiveDate) < recentWindow }
        // @Published değerleri yalnızca değişince ata; yoksa her saniye arayüz yeniden çizilir
        if newTabs != tabs { tabs = newTabs }
        updateBridges(sessions)
        checkExtensionVersion(sessions, now: now)

        let available: Bool
        if let volume = SystemVolume.volume {
            available = SystemVolume.isSettable
            if abs(volume - systemVolume) > 0.005 { systemVolume = volume }
        } else {
            available = false
        }
        if available != systemVolumeAvailable { systemVolumeAvailable = available }
        let name = SystemVolume.deviceName
        if name != outputName { outputName = name }
        let permission = AudioPermission.status
        if permission != audioPermission { audioPermission = permission }

        if full { refreshApps() }
    }

    // MARK: Güncelleme

    func checkForUpdate(force: Bool = false, after: TimeInterval = UpdateChecker.interval) {
        guard UpdateChecker.isEnabled else {
            if update != nil { update = nil }
            return
        }
        // Menü açılışı ile saatlik tur aynı anda gelirse GitHub'a iki kez sorma
        guard !checkingUpdate else { return }
        checkingUpdate = true
        let before = UpdateChecker.lastCheck
        Task {
            let found = await UpdateChecker.checkIfDue(force: force, after: after)
            if found != update { update = found }
            let after = UpdateChecker.lastCheck
            if after != lastUpdateCheck { lastUpdateCheck = after }
            // Sadece elle denetimde hata göster; zamanı gelmemiş otomatik denetim de tarih değiştirmez
            if force { updateCheckFailed = after == before } else if after != before { updateCheckFailed = false }
            checkingUpdate = false
        }
    }

    enum UpdateStatus { case idle, installing, failed }

    /// Yeni sürümü indirip kurar ve uygulamayı yeniden başlatır. Yerinde kurulamıyorsa Releases sayfasını açar.
    func installUpdate() {
        guard let update, updateStatus != .installing else { return }
        guard update.download != nil, Updater.canInstall else {
            NSWorkspace.shared.open(update.url)
            return
        }
        updateStatus = .installing
        Task {
            do {
                try await Task.detached { try await Updater.install(update) }.value
                Updater.relaunch()
            } catch {
                updateStatus = .failed
            }
        }
    }

    // MARK: Tarayıcı eklentisi

    var browserConnected: Bool { !bridgeBrowsers.isEmpty }
    var bridgePIDs: Set<pid_t> { Set(bridgeBrowsers.keys) }

    /// Yeni köprülerin tarayıcısını bir kez bulur (süreç ağacına bakmak her saniye yapılmasın).
    private func updateBridges(_ sessions: [BridgeSession]) {
        var fresh: [pid_t: Browser] = [:]
        for session in sessions {
            fresh[session.pid] = bridgeBrowsers[session.pid] ?? Browser.owning(pid: session.pid) ?? browser
        }
        guard fresh != bridgeBrowsers else { return }
        let added = Set(fresh.values).subtracting(bridgeBrowsers.values)
        bridgeBrowsers = fresh
        // Yeni bağlanan tarayıcı (az önce kurulan) öne geçer; seçili tarayıcı hâlâ bağlıysa değişmez
        let connected = connectedBrowsers
        if let next = connected.first(where: added.contains) ?? (connected.contains(browser) ? nil : connected.first) {
            if next != browser { browser = next }
            UserDefaults.standard.set(next.bundleID, forKey: "lastBrowser")
        }
    }

    /// Kurulu ama eklentisi bağlı olmayan tarayıcılar; varsayılan ve açık olanlar önce.
    var unconnectedBrowsers: [Browser] {
        let connected = Set(connectedBrowsers)
        let running = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        let systemDefault = Browser.systemDefault
        func rank(_ browser: Browser) -> Int { browser == systemDefault ? 0 : running.contains(browser.bundleID) ? 1 : 2 }
        return Browser.installed.filter { !connected.contains($0) }
            .enumerated().sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }.map(\.element)
    }

    /// Kurulum yardımcısını bağlı olmayan bir tarayıcı için hazırlar.
    func selectBrowserToAdd() {
        if let next = unconnectedBrowsers.first, next != browser { browser = next }
    }

    /// Güncellemeden sonra eklentinin yeniden yüklenmesi birkaç saniye sürer; uyuşmazlık
    /// 10 saniyeden uzun sürerse eklentinin güncellenemediğini varsay.
    private func checkExtensionVersion(_ sessions: [BridgeSession], now: Date) {
        let bundled = Installer.bundledExtensionVersion
        let stale = bundled == nil ? nil : sessions.first { $0.version != bundled }
        let mismatch = stale != nil
        let version = stale?.version
        if version != staleExtensionVersion { staleExtensionVersion = version }
        // Güncelleme metni eski eklentinin durduğu tarayıcının adını söylesin
        if let stale, let owner = bridgeBrowsers[stale.pid], owner != browser { browser = owner }
        if mismatch {
            if versionMismatchSince == nil { versionMismatchSince = now }
        } else {
            versionMismatchSince = nil
        }
        let outdated = versionMismatchSince.map { now.timeIntervalSince($0) > 10 } ?? false
        if outdated != extensionOutdated { extensionOutdated = outdated }
    }

    func refreshExtensionLocation() {
        Installer.registerNativeHost()
        let repair = ChromeExtension.loadedFromTemporaryCopy
        if repair != extensionNeedsRepair { extensionNeedsRepair = repair }
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

    // MARK: Tarayıcı videoları

    /// Eklentisi bağlı tarayıcılar, listedeki sırayla. İki Chrome profili tek tarayıcı sayılır.
    var connectedBrowsers: [Browser] {
        let present = Set(bridgeBrowsers.values.map(\.bundleID))
        return Browser.all.filter { present.contains($0.bundleID) }
    }

    /// Menüde satırı olan tarayıcılar; hiçbiri bağlı değilse kurulum notuyla birlikte varsayılan tarayıcı.
    var shownBrowsers: [Browser] {
        let connected = connectedBrowsers
        return connected.isEmpty ? [browser] : connected
    }

    func tabs(of browser: Browser) -> [ChromeTab] { tabs.filter { bridgeBrowsers[$0.bridge] == browser } }
    func playingTabs(of browser: Browser) -> [ChromeTab] { tabs(of: browser).filter(\.playing) }
    func pausedTabs(of browser: Browser) -> [ChromeTab] {
        tabs(of: browser).filter { !$0.playing }.sorted { $0.lastActive > $1.lastActive }
    }

    func videoVolume(_ tab: ChromeTab) -> Double {
        if let local = localVideoVolume[tab.id], Date().timeIntervalSince(local.at) < 2 { return local.value }
        return tab.volume ?? 1
    }

    func setVideoVolume(_ tab: ChromeTab, _ value: Double) {
        localVideoVolume[tab.id] = (value, Date())
        objectWillChange.send()
        ChromeBridge.setVolume(tab, value)
    }

    // MARK: Uygulama sesleri

    /// Gösterilecek uygulamalar: tarayıcılar her zaman en üstte, diğerleri çalıyorsa,
    /// Ayarlar'daki süre içinde ses çıkardıysa ya da sesi kısılmışsa.
    var visibleApps: [AudioApp] {
        guard showOtherApps else { return [] }
        let now = Date()
        let browsers = Set(shownBrowsers.map(\.bundleID))
        let others = apps.filter { app in
            !browsers.contains(app.bundleID) && (
                app.isPlaying
                    || now.timeIntervalSince(lastHeard[app.bundleID] ?? .distantPast) < recentWindow
                    || gain(app.bundleID) < 1
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        return others
    }

    func icon(of browser: Browser) -> NSImage {
        apps.first { $0.bundleID == browser.bundleID }?.icon ?? browser.icon
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
        let sorted = fresh.sorted { $0.bundleID < $1.bundleID }
        if sorted != apps { apps = sorted }
        for app in fresh { applyTap(for: app.bundleID) }
        let ids = Set(fresh.map(\.bundleID))
        for id in taps.keys where !ids.contains(id) { taps[id] = nil }
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
            NSApp.windows.first { $0.title == "Sound Mix Ayarları" }?.makeKeyAndOrderFront(nil)
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

    // MARK: Kaldırma

    /// Sound Mix'i bu Mac'ten kaldırır: tarayıcı eklentisi, köprü kaydı, girişte başlatma, ayarlar ve uygulamanın kendisi.
    func uninstall() {
        // Komut köprü hâlâ ayaktayken gitsin; tarayıcı ayrıca kendi onayını sorar
        ChromeBridge.uninstallExtension()
        try? SMAppService.mainApp.unregister()
        resetGains() // kısılmış uygulamaların sesi geri gelsin
        timer?.invalidate()
        updateTimer?.invalidate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            Installer.removeFiles()
            if let id = Bundle.main.bundleIdentifier { UserDefaults.standard.removePersistentDomain(forName: id) }
            // Paketsiz çalışırken (swift run) bundleURL derleme klasörüdür; onu çöpe atma
            let app = Bundle.main.bundleURL
            guard app.pathExtension == "app" else { NSApp.terminate(nil); return }
            // Çöpe atılamasa da (ör. salt okunur bir yerden çalışıyorsa) uygulama kapansın
            NSWorkspace.shared.recycle([app]) { _, _ in
                DispatchQueue.main.async { NSApp.terminate(nil) }
            }
        }
    }
}
