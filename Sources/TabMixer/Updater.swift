import AppKit
import CryptoKit
import Foundation

/// Yeni sürümü indirir, eski uygulamanın yerine koyar ve uygulamayı yeniden başlatır.
/// Ayarlar UserDefaults'ta olduğu için korunur; Chrome eklentisine yeni sürüm açılınca Installer bakar.
enum Updater {
    enum Failure: Error { case download, checksum, unpack, invalidBundle, replace }

    /// Uygulama bulunduğu yerde güncellenebilir mi? Downloads'tan geçici bir yoldan (App Translocation)
    /// çalışıyorsa ya da klasörüne yazılamıyorsa hayır; o zaman Releases sayfası açılır.
    static var canInstall: Bool {
        let app = Bundle.main.bundleURL
        return app.pathExtension == "app" && !Installer.isTranslocated
            && FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
    }

    static func install(_ update: AvailableUpdate) async throws {
        guard let download = update.download else { throw Failure.download }
        let fm = FileManager.default
        let current = Bundle.main.bundleURL
        // Uygulamayla aynı diskte geçici klasör; yer değiştirme kopyalamadan tek adımda olur
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: current, create: true)
        defer { try? fm.removeItem(at: staging) }

        guard let (file, response) = try? await URLSession.shared.download(for: URLRequest(url: download, timeoutInterval: 60)),
              (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure.download }
        let zip = staging.appendingPathComponent("SoundMix.zip")
        guard (try? fm.moveItem(at: file, to: zip)) != nil else { throw Failure.download }

        if let expected = update.sha256 {
            guard let data = try? Data(contentsOf: zip, options: .mappedIfSafe) else { throw Failure.download }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            guard digest == expected.lowercased() else { throw Failure.checksum }
        }

        let unpacked = staging.appendingPathComponent("unpacked")
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else { throw Failure.unpack }

        // Zip'ten çıkan gerçekten Sound Mix'in daha yeni bir sürümü mü?
        guard let app = try? fm.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }),
              let bundle = Bundle(url: app), bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
              let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
              UpdateChecker.isNewer(version, than: UpdateChecker.currentVersion),
              let executable = bundle.executableURL, fm.isExecutableFile(atPath: executable.path)
        else { throw Failure.invalidBundle }

        // Eski uygulama silinir, yenisi aynı yola geçer (kullanıcı adını değiştirdiyse o adla)
        guard (try? fm.replaceItemAt(current, withItemAt: app)) != nil else { throw Failure.replace }
    }

    /// Bu süreç kapanınca uygulamayı aynı yoldan yeniden açar.
    @MainActor
    static func relaunch() {
        let wait = "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", wait, Bundle.main.bundlePath]
        try? process.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }
}
