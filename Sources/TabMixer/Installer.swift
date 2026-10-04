import Foundation

/// İlk açılışta (ve güncellemelerde) Chrome köprüsünü kaydeder, eklentiyi kullanıcı klasörüne kopyalar.
enum Installer {
    static let hostName = "io.github.omerfarukgzr.tabmixer"
    static let extensionID = "hjdkncghobmcamdopbkbjonaebigjdcp"
    /// İndirilen zip Downloads'tan açılınca macOS uygulamayı rastgele geçici bir yoldan çalıştırır (App Translocation).
    /// O yol kaybolacağı için köprü kaydı yazılmaz; arayüz bu durumda uygulamayı taşıması için uyarabilir.
    static let isTranslocated = Bundle.main.bundlePath.contains("/AppTranslocation/")

    static func run() {
        installNativeHost()
        let extensionChanged = copyExtension()
        if extensionChanged || appVersionChanged() {
            // Eklenti yeni sürümü hemen yüklesin. Sadece uygulama değişse bile gerekli: Chrome'un başlattığı
            // köprü eski ikiliyle çalışmaya devam ediyor, eklenti yeniden bağlanınca yenisi başlıyor.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ChromeBridge.send(["cmd": "reload"]) }
        }
    }

    /// Uygulama son açılıştan beri güncellendiyse true döner.
    private static func appVersionChanged() -> Bool {
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let last = UserDefaults.standard.string(forKey: "lastRunVersion")
        UserDefaults.standard.set(current, forKey: "lastRunVersion")
        return last != nil && last != current
    }

    private static func installNativeHost() {
        guard !isTranslocated, let executable = Bundle.main.executablePath else { return }
        let manifest: [String: Any] = [
            "name": hostName,
            "description": "Tab Mixer",
            "path": executable,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(extensionID)/"],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys]) else { return }
        let url = Paths.nativeHostsFolder.appendingPathComponent("\(hostName).json")
        if (try? Data(contentsOf: url)) == data { return }
        try? FileManager.default.createDirectory(at: Paths.nativeHostsFolder, withIntermediateDirectories: true)
        try? data.write(to: url, options: .atomic)
    }

    /// Paketteki eklentiyi kopyalar. Sürüm değiştiyse true döner.
    @discardableResult
    private static func copyExtension() -> Bool {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "Extension", withExtension: nil) else { return false }
        let target = Paths.extensionFolder
        let sourceFiles = contents(of: source)
        let targetFiles = contents(of: target)
        if !sourceFiles.isEmpty, sourceFiles == targetFiles { return false }

        let existed = !targetFiles.isEmpty
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try? fm.copyItem(at: source, to: target)
        return existed
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
