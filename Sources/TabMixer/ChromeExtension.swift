import Foundation

/// Tarayıcıların Sound Mix eklentisini hangi klasörden yüklediğini profil tercihlerinden okur.
/// Paketlenmemiş eklentilerde Chromium klasörün tam yolunu `extensions.settings.<kimlik>.path` altında saklar.
/// Sadece okur; açılışta ve Ayarlar ya da kurulum penceresi açıkken çağrılır, her saniye değil.
enum ChromeExtension {
    /// Eklentinin yüklendiği klasörler (bütün tarayıcı ve profillerde, tekrarsız). Dosya yoksa ya da bozuksa o profil atlanır.
    static func loadedFolders() -> [URL] {
        var paths: [String] = []
        for profile in Browser.all.flatMap(\.profileURLs) {
            for file in ["Secure Preferences", "Preferences"] {
                let url = profile.appendingPathComponent(file)
                guard let data = try? Data(contentsOf: url),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let extensions = json["extensions"] as? [String: Any],
                      let settings = extensions["settings"] as? [String: Any],
                      let entry = settings[Installer.extensionID] as? [String: Any],
                      // Mağazadan kurulanlarda yol göreli olur; bizimki her zaman tam yol
                      let path = entry["path"] as? String, path.hasPrefix("/") else { continue }
                let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
                if !paths.contains(resolved) { paths.append(resolved) }
            }
        }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Kalıcı klasör dışında olup hâlâ diskte duran yükleme klasörleri (ör. eski bir sürüklemenin geçici kopyası).
    static func strayFolders() -> [URL] {
        let permanent = Paths.extensionFolder.resolvingSymlinksInPath().path
        return loadedFolders().filter { $0.path != permanent && FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Tarayıcı eklentiyi kalıcı klasör yerine geçici bir kopyadan yüklüyorsa true; Ayarlar "Onar…" gösterir.
    static var loadedFromTemporaryCopy: Bool { !strayFolders().isEmpty }
}
