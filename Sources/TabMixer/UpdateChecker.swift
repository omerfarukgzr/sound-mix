import Foundation

/// GitHub'daki en son sürüm.
struct AvailableUpdate: Equatable {
    let version: String
    /// Releases sayfası; otomatik kurulum olmazsa buraya yönlendirilir.
    let url: URL
    /// Yayındaki SoundMix.zip.
    let download: URL?
    /// GitHub'ın zip için hesapladığı SHA-256 (eski yayınlarda olmayabilir).
    let sha256: String?
}

/// Günde bir kez GitHub'daki son sürüme bakar. Hiçbir veri göndermez; ağ yoksa ya da
/// GitHub hata verirse sessizce geçer. Taslak ve ön sürümler /releases/latest'te zaten yer almaz.
enum UpdateChecker {
    private static let endpoint = URL(string: "https://api.github.com/repos/omerfarukgzr/sound-mix/releases/latest")!
    static let interval: TimeInterval = 24 * 60 * 60

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    static var isEnabled: Bool { UserDefaults.standard.object(forKey: "checkUpdates") as? Bool ?? true }

    /// Son kontrolde bulunan, şu anki sürümden yeni sürüm (yeniden açılışta da gösterilsin diye saklanır).
    static var stored: AvailableUpdate? {
        guard let version = UserDefaults.standard.string(forKey: "latestVersion"),
              let link = UserDefaults.standard.string(forKey: "latestURL"), let url = URL(string: link),
              isNewer(version, than: currentVersion) else { return nil }
        let download = UserDefaults.standard.string(forKey: "latestZipURL").flatMap(URL.init(string:))
        return AvailableUpdate(version: version, url: url, download: download,
                               sha256: UserDefaults.standard.string(forKey: "latestSHA256"))
    }

    /// Son kontrolün üzerinden gün geçtiyse (ya da force ile hemen) GitHub'a sorar.
    static func checkIfDue(force: Bool = false) async -> AvailableUpdate? {
        let last = UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast
        guard isEnabled, force || Date().timeIntervalSince(last) >= interval else { return stored }

        struct Asset: Decodable { let name: String; let browser_download_url: String; let digest: String? }
        struct Release: Decodable { let tag_name: String; let html_url: String; let assets: [Asset]? }
        var request = URLRequest(url: endpoint, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let release = try? JSONDecoder().decode(Release.self, from: data),
              let url = URL(string: release.html_url), url.host == "github.com" else { return stored }

        let version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        UserDefaults.standard.set(Date(), forKey: "lastUpdateCheck")
        UserDefaults.standard.set(version, forKey: "latestVersion")
        UserDefaults.standard.set(url.absoluteString, forKey: "latestURL")
        let zip = release.assets?.first { $0.name == "SoundMix.zip" }
        // Sadece GitHub'dan indir; GitHub oradan kendi depolama sunucusuna yönlendirir
        let download = zip.flatMap { URL(string: $0.browser_download_url) }
            .flatMap { $0.scheme == "https" && $0.host == "github.com" ? $0 : nil }
        UserDefaults.standard.set(download?.absoluteString, forKey: "latestZipURL")
        let digest = zip?.digest.flatMap { $0.hasPrefix("sha256:") ? String($0.dropFirst(7)) : nil }
        UserDefaults.standard.set(digest, forKey: "latestSHA256")
        return stored
    }

    /// "1.10.0" > "1.9.2" gibi sayısal karşılaştırma.
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }
}
