import AppKit
import Foundation

/// Sound Mix eklentisini çalıştırabilen Chromium tabanlı bir tarayıcı.
/// Hepsi aynı eklentiyi ve aynı köprüyü kullanır; farkları veri klasörleri ve bundle ID'leri.
struct Browser: Equatable, Identifiable {
    let name: String
    let bundleID: String
    /// Profillerin durduğu klasör (Application Support'a göre).
    let dataFolder: String
    /// Köprü kaydının (native messaging host) arandığı klasörler (Application Support'a göre).
    let hostFolders: [String]
    let extensionsPage: String

    var id: String { bundleID }

    init(_ name: String, _ bundleID: String, data: String, hosts: [String]? = nil, extensionsPage: String = "chrome://extensions") {
        self.name = name
        self.bundleID = bundleID
        self.dataFolder = data
        self.hostFolders = hosts ?? [data + "/NativeMessagingHosts"]
        self.extensionsPage = extensionsPage
    }

    static let chrome = Browser("Chrome", "com.google.Chrome", data: "Google/Chrome")

    static let all: [Browser] = [
        chrome,
        Browser("Chrome Beta", "com.google.Chrome.beta", data: "Google/Chrome Beta"),
        Browser("Chrome Canary", "com.google.Chrome.canary", data: "Google/Chrome Canary"),
        Browser("Chromium", "org.chromium.Chromium", data: "Chromium"),
        Browser("Brave", "com.brave.Browser", data: "BraveSoftware/Brave-Browser"),
        Browser("Edge", "com.microsoft.edgemac", data: "Microsoft Edge", extensionsPage: "edge://extensions"),
        Browser("Arc", "company.thebrowser.Browser", data: "Arc/User Data"),
        // Dia'nın kayıt klasörü belgelenmemiş; iki olası yere de yazılır
        Browser("Dia", "company.thebrowser.dia", data: "Dia/User Data",
                hosts: ["Dia/User Data/NativeMessagingHosts", "Dia/NativeMessagingHosts"]),
        Browser("Vivaldi", "com.vivaldi.Vivaldi", data: "Vivaldi"),
        Browser("Opera", "com.operasoftware.Opera", data: "com.operasoftware.Opera"),
    ]

    private static let support = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support")

    var dataURL: URL { Self.support.appendingPathComponent(dataFolder) }
    var hostURLs: [URL] { hostFolders.map { Self.support.appendingPathComponent($0) } }
    var appURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) }
    /// Uygulama kurulu ya da daha önce kullanılmış (veri klasörü duruyor).
    var isPresent: Bool { appURL != nil || FileManager.default.fileExists(atPath: dataURL.path) }

    var icon: NSImage {
        if let url = appURL { return NSWorkspace.shared.icon(forFile: url.path) }
        return NSImage(systemSymbolName: "globe", accessibilityDescription: nil)!
    }

    /// Profil klasörleri: Default, Profile N; Opera gibi tek profilliler için klasörün kendisi.
    var profileURLs: [URL] {
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dataURL.path)) ?? [])
            .filter { $0 == "Default" || $0.hasPrefix("Profile ") }
        return [dataURL] + names.map { dataURL.appendingPathComponent($0) }
    }

    /// Bundle ID'si ya da yardımcı süreç kimliği (örn. com.google.Chrome.helper) verilen tarayıcı.
    /// Önce tam eşleşmeye bakılır ki Chrome Beta Chrome sanılmasın.
    static func with(bundleID id: String) -> Browser? {
        all.first { $0.bundleID == id }
            ?? all.filter { id.hasPrefix($0.bundleID + ".") }.max { $0.bundleID.count < $1.bundleID.count }
    }

    /// Bağlı tarayıcı bilinmiyorsa gösterilecek olan: son bağlanan, yoksa kurulu ilk tarayıcı.
    static var preferred: Browser {
        if let id = UserDefaults.standard.string(forKey: "lastBrowser"), let browser = with(bundleID: id) { return browser }
        return all.first { $0.appURL != nil } ?? chrome
    }

    /// Köprü sürecini başlatan tarayıcı; süreç ağacında birkaç adım yukarı çıkarak bulunur.
    static func owning(pid: pid_t) -> Browser? {
        var current = pid
        for _ in 0..<4 {
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(current, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            current = pid_t(info.pbi_ppid)
            guard current > 1 else { return nil }
            if let id = NSRunningApplication(processIdentifier: current)?.bundleIdentifier,
               let browser = with(bundleID: id) { return browser }
        }
        return nil
    }
}
