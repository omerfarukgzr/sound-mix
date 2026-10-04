import Foundation

/// Chrome'un Sound Mix eklentisini hangi klasörden yüklediğini profil tercihlerinden okur.
/// Paketlenmemiş eklentilerde Chrome klasörün tam yolunu `extensions.settings.<kimlik>.path` altında saklar.
/// Sadece okur; açılışta ve Ayarlar ya da kurulum penceresi açıkken çağrılır, her saniye değil.
enum ChromeExtension {
    private static let chromeFolder = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Google/Chrome")

    /// Eklentinin yüklendiği klasörler (bütün profillerde, tekrarsız). Dosya yoksa ya da bozuksa o profil atlanır.
    static func loadedFolders() -> [URL] {
        let profiles = ((try? FileManager.default.contentsOfDirectory(atPath: chromeFolder.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        var paths: [String] = []
        for profile in profiles {
            for file in ["Secure Preferences", "Preferences"] {
                let url = chromeFolder.appendingPathComponent(profile).appendingPathComponent(file)
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

    /// Chrome eklentiyi kalıcı klasör yerine geçici bir kopyadan yüklüyorsa true; Ayarlar "Onar…" gösterir.
    static var loadedFromTemporaryCopy: Bool { !strayFolders().isEmpty }
}
