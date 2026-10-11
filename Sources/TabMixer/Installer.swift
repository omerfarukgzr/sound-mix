import Foundation

/// İlk açılışta (ve güncellemelerde) tarayıcı köprüsünü kaydeder, eklentiyi kullanıcı klasörüne kopyalar.
enum Installer {
    static let hostName = "io.github.omerfarukgzr.tabmixer"
    static let extensionID = "hjdkncghobmcamdopbkbjonaebigjdcp"
    /// İndirilen zip Downloads'tan açılınca macOS uygulamayı rastgele geçici bir yoldan çalıştırır (App Translocation).
    /// O yol kaybolacağı için köprü kaydı yazılmaz; arayüz bu durumda uygulamayı taşıması için uyarabilir.
    static let isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")

    /// Uygulamanın içindeki eklentinin sürümü; tarayıcıdaki eklenti bununla karşılaştırılır.
    static let bundledExtensionVersion: String? = {
        guard let url = Bundle.main.url(forResource: "Extension", withExtension: nil)?.appendingPathComponent("manifest.json"),
              let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["version"] as? String
    }()

    static func run() {
        registerNativeHost()
        var extensionChanged = false
        if let source = Bundle.main.url(forResource: "Extension", withExtension: nil) {
            extensionChanged = copyExtension(from: source)
            if syncStrayCopies(from: source) { extensionChanged = true }
            removeLegacyFolderIfUnused()
        }
        // Her açılışta çağrılmalı ki son sürüm kaydedilsin
        let appChanged = appVersionChanged()
        if extensionChanged {
            // Eklenti yeni sürümü hemen yüklesin; köprü de onunla birlikte yeni ikiliyle başlar
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ChromeBridge.sendAll(["cmd": "reload"]) }
        } else if appChanged {
            // Eklenti aynı, ona dokunma (yeniden yüklenirse açık sekmelerin yenilenmesi gerekir).
            // Tarayıcıların başlattığı köprüler ise hâlâ eski ikiliyle çalışıyor; sadece onları kapat.
            // Eklenti bağlantı kopunca kendisi yeniden bağlanır, tarayıcı da yeni ikiliyi başlatır.
            let pids = ChromeBridge.sessions().map(\.pid) + [ChromeBridge.legacyBridgePID].compactMap { $0 }
            for pid in pids { kill(pid, SIGTERM) }
        }
        removeLegacyBridgeFiles()
    }

    /// 1.2.x köprüsünün tek soketli dosyaları; o köprü artık çalışmıyorsa silinir.
    private static func removeLegacyBridgeFiles() {
        guard ChromeBridge.legacyBridgePID == nil else { return }
        for path in [Paths.legacySocket, Paths.legacyBridgePID, Paths.shared.appendingPathComponent("state.json").path] {
            unlink(path)
        }
    }

    /// Uygulama son açılıştan beri güncellendiyse true döner.
    private static func appVersionChanged() -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let last = UserDefaults.standard.string(forKey: "lastRunVersion")
        UserDefaults.standard.set(current, forKey: "lastRunVersion")
        return last != nil && last != current
    }

    private static var manifestName: String { "\(hostName).json" }

    /// Köprü kaydını kurulu ya da kullanılmış her Chromium tarayıcısının klasörüne yazar; Chrome'a her zaman.
    /// Kurulum penceresi açılınca da çağrılır ki sonradan kurulan tarayıcılar uygulamayı yeniden başlatmadan bağlanabilsin.
    static func registerNativeHost() {
        guard !isTranslocated, let executable = Bundle.main.executablePath else { return }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Sound Mix",
            "path": executable,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return }
        for browser in Browser.all where browser == .chrome || browser.isPresent {
            for folder in browser.hostURLs {
                let url = folder.appendingPathComponent(manifestName)
                if (try? Data(contentsOf: url)) == data { continue }
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    /// Paketteki eklentiyi kalıcı klasöre kopyalar. Sürüm değiştiyse true döner.
    private static func copyExtension(from source: URL) -> Bool {
        let existed = FileManager.default.fileExists(atPath: Paths.extensionFolder.appendingPathComponent("manifest.json").path)
        return replace(Paths.extensionFolder, with: source) && existed
    }

    /// Tarayıcı eklentiyi kalıcı klasör yerine başka bir yerden (eski bir sürüklemenin geçici kopyası gibi)
    /// yüklüyorsa o kopyayı da günceller; yoksa her "reload" eski sürümü yeniden yükler.
    /// Güvenlik için sadece ev klasöründeki ve aynı eklenti anahtarını taşıyan klasörlere yazılır.
    private static func syncStrayCopies(from source: URL) -> Bool {
        guard let key = manifestKey(in: source) else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().path + "/"
        let bundle = Bundle.main.bundleURL.resolvingSymlinksInPath().path + "/"
        var changed = false
        for folder in ChromeExtension.strayFolders() {
            guard folder.path.hasPrefix(home), !folder.path.hasPrefix(bundle), manifestKey(in: folder) == key else { continue }
            if replace(folder, with: source) { changed = true }
        }
        return changed
    }

    /// Eski adla kurulan eklenti klasörünü, Chrome artık oradan yüklemiyorsa siler.
    private static func removeLegacyFolderIfUnused() {
        let legacy = Paths.legacyExtensionFolder.resolvingSymlinksInPath().path
        guard FileManager.default.fileExists(atPath: legacy),
              !ChromeExtension.loadedFolders().contains(where: { $0.path == legacy }) else { return }
        try? FileManager.default.removeItem(at: Paths.legacyExtensionFolder.deletingLastPathComponent())
    }

    /// Hedef klasörü paketteki eklentiyle değiştirir. İçerik zaten aynıysa dokunmaz; yazdıysa true döner.
    private static func replace(_ target: URL, with source: URL) -> Bool {
        let sourceFiles = contents(of: source)
        guard !sourceFiles.isEmpty, sourceFiles != contents(of: target) else { return false }
        let fm = FileManager.default
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        return (try? fm.copyItem(at: source, to: target)) != nil
    }

    /// manifest.json'daki "key"; eklenti kimliği bundan türediği için klasörün bizim eklentimiz olduğunu gösterir.
    private static func manifestKey(in folder: URL) -> String? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["key"] as? String
    }

    /// Kaldırırken uygulamanın yazdığı dosyaları siler. Tarayıcının yüklediği geçici kopyalara dokunmaz.
    static func removeFiles() {
        let fm = FileManager.default
        for folder in Browser.all.flatMap(\.hostURLs) { try? fm.removeItem(at: folder.appendingPathComponent(manifestName)) }
        try? fm.removeItem(at: Paths.extensionFolder.deletingLastPathComponent())
        try? fm.removeItem(at: Paths.legacyExtensionFolder.deletingLastPathComponent())
        try? fm.removeItem(at: Paths.shared)
    }

    /// Klasördeki bütün dosyalar (göreli yol → içerik); karşılaştırma için.
    private static func contents(of folder: URL) -> [String: Data] {
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return [:] }
        var result: [String: Data] = [:]
        for case let url as URL in files {
            if let data = try? Data(contentsOf: url) {
                result[url.path.replacingOccurrences(of: folder.path, with: "")] = data
            }
        }
        return result
    }
}
