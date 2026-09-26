import Foundation

/// İlk açılışta (ve güncellemelerde) Chrome köprüsünü kaydeder, eklentiyi kullanıcı klasörüne kopyalar.
enum Installer {
    static let hostName = "io.github.omerfarukgzr.tabmixer"
    static let extensionID = "hjdkncghobmcamdopbkbjonaebigjdcp"

    static func run() {
        installNativeHost()
        if copyExtension() {
            // Eklenti zaten yüklüyse yeni sürümü hemen yüklesin
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { ChromeBridge.send(["cmd": "reload"]) }
        }
    }

    private static func installNativeHost() {
        guard let executable = Bundle.main.executablePath else { return }
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
        let sourceManifest = try? Data(contentsOf: source.appendingPathComponent("manifest.json"))
        let targetManifest = try? Data(contentsOf: target.appendingPathComponent("manifest.json"))
        if sourceManifest != nil, sourceManifest == targetManifest { return false }

        let existed = targetManifest != nil
        try? fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.removeItem(at: target)
        try? fm.copyItem(at: source, to: target)
        return existed
    }
}
