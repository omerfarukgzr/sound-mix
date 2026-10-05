import AppKit
import Foundation

/// Chrome eklentisinin bildirdiği bir video sekmesi.
struct ChromeTab: Identifiable, Decodable, Equatable {
    let tabId: Int
    let playing: Bool
    let lastActive: Double
    let title: String?
    let icon: String?
    let volume: Double?

    var id: Int { tabId }
    var lastActiveDate: Date { Date(timeIntervalSince1970: lastActive / 1000) }
}

/// Köprünün (NativeHost) yazdığı durum dosyasını okur, komutları unix soketiyle gönderir.
enum ChromeBridge {
    private static let stateURL = Paths.state
    private static let socketPath = Paths.socket
    private static var iconCache: [String: NSImage] = [:]
    private static var cachedStamp: FileStamp?
    private static var cachedTabs: [ChromeTab] = []
    private static var cachedVersion: String?

    /// Dosya değişti mi diye bakmak için inode + boyut + değişme zamanı (atomik yazım inode'u da değiştirir).
    private struct FileStamp: Equatable {
        let ino: ino_t, size: off_t, sec: Int, nsec: Int
    }

    /// Köprü süreci gerçekten yaşıyor mu? Çökmüş köprünün soket dosyası diskte kalabiliyor,
    /// o yüzden pid dosyasındaki süreç hâlâ bizim ikilimiz mi diye bakıyoruz. Her saniye çağrılıyor, ucuz tutuldu.
    static var isConnected: Bool { bridgePID != nil }

    /// Çalışan köprünün pid'i. Eklenti yeniden yüklenince köprü de yeni bir süreçle başlar.
    static var bridgePID: pid_t? {
        guard let text = try? String(contentsOfFile: Paths.bridgePID, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return nil }
        // Pid başka bir sürece verilmiş olabilir; sürecin adı bizim ikilimizle aynı mı diye bak.
        // Yola bakmıyoruz: güncellemeden sonra eski köprünün ikilisi silinmiş olur ve yolu okunamaz.
        var name = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return nil }
        return String(cString: name) == (Bundle.main.executableURL?.lastPathComponent ?? "SoundMix") ? pid : nil
    }

    static func tabs() -> [ChromeTab] {
        // Köprü yoksa dosyada kalan "çalıyor" sekmeleri sonsuza kadar listelenmesin
        guard isConnected else { return [] }
        loadState()
        return cachedTabs
    }

    /// Chrome'da çalışan eklentinin sürümü (eski eklentiler bildirmez, o zaman nil).
    static func extensionVersion() -> String? {
        guard isConnected else { return nil }
        loadState()
        return cachedVersion
    }

    private static func loadState() {
        struct State: Decodable { let tabs: [ChromeTab]; let version: String? }
        var info = stat()
        guard stat(stateURL.path, &info) == 0 else {
            (cachedTabs, cachedVersion, cachedStamp) = ([], nil, nil)
            return
        }
        let stamp = FileStamp(ino: info.st_ino, size: info.st_size,
                              sec: info.st_mtimespec.tv_sec, nsec: info.st_mtimespec.tv_nsec)
        if stamp == cachedStamp { return }
        let state = (try? Data(contentsOf: stateURL)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        cachedTabs = state?.tabs ?? []
        cachedVersion = state?.version
        cachedStamp = stamp
    }

    static func icon(for tab: ChromeTab) -> NSImage? {
        guard let base64 = tab.icon, base64.utf8.count < 256 * 1024 else { return nil }
        if let cached = iconCache[base64] { return cached }
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 14, height: 14)
        // Sınırsız büyümesin; dolunca boşalt, güncel sekmelerin ikonları hemen yeniden dolar
        if iconCache.count >= 64 { iconCache.removeAll() }
        iconCache[base64] = image
        return image
    }

    static func send(_ command: [String: Any]) {
        guard let payload = try? JSONSerialization.data(withJSONObject: command) else { return }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        defer { close(fd) }

        guard var addr = unixAddress(socketPath) else { return }
        let connected = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else { return }
        // Köprü soketi erken kapatırsa SIGPIPE uygulamayı öldürmesin
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
    }

    static func toggle(_ tab: ChromeTab) { send(["cmd": "toggle", "tabId": tab.tabId]) }
    static func focus(_ tab: ChromeTab) { send(["cmd": "focus", "tabId": tab.tabId]) }
    static func setVolume(_ tab: ChromeTab, _ value: Double) { send(["cmd": "volume", "tabId": tab.tabId, "value": value]) }
    /// Eklenti kendini Chrome'dan kaldırır; Chrome önce kendi onay penceresini gösterir.
    static func uninstallExtension() { send(["cmd": "uninstall"]) }
}
