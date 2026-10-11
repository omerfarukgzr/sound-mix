import AppKit
import Foundation

/// Tarayıcı eklentisinin bildirdiği bir video sekmesi.
struct ChromeTab: Identifiable, Decodable, Equatable {
    let tabId: Int
    let playing: Bool
    let lastActive: Double
    let title: String?
    let icon: String?
    let volume: Double?
    /// Sekmeyi bildiren köprü; komutlar onun soketine gider. Sekme numaraları tarayıcılar arasında çakışabilir.
    var bridge: pid_t = 0

    private enum CodingKeys: String, CodingKey { case tabId, playing, lastActive, title, icon, volume }

    var id: String { "\(bridge):\(tabId)" }
    var lastActiveDate: Date { Date(timeIntervalSince1970: lastActive / 1000) }
}

/// Çalışan bir köprü: bir tarayıcı profilindeki eklentinin bağlantısı.
struct BridgeSession: Equatable {
    let pid: pid_t
    let tabs: [ChromeTab]
    let version: String?
}

/// Köprülerin (NativeHost) yazdığı durum dosyalarını okur, komutları her köprünün unix soketiyle gönderir.
enum ChromeBridge {
    private static var iconCache: [String: NSImage] = [:]
    private static var cache: [pid_t: (stamp: FileStamp, session: BridgeSession)] = [:]

    /// Dosya değişti mi diye bakmak için inode + boyut + değişme zamanı (atomik yazım inode'u da değiştirir).
    private struct FileStamp: Equatable {
        let ino: ino_t, size: off_t, sec: Int, nsec: Int
    }

    /// Pid'deki süreç bizim ikilimiz mi? Pid başka bir sürece verilmiş olabilir; yola bakmıyoruz çünkü
    /// güncellemeden sonra eski köprünün ikilisi silinmiş olur ve yolu okunamaz.
    static func isBridge(_ pid: pid_t) -> Bool {
        guard pid > 0, pid != getpid() else { return false }
        var name = [CChar](repeating: 0, count: 2 * Int(MAXCOMLEN) + 1)
        guard proc_name(pid, &name, UInt32(name.count)) > 0 else { return false }
        return String(cString: name) == (Bundle.main.executableURL?.lastPathComponent ?? "SoundMix")
    }

    /// Yaşayan köprüler, pid sırasıyla. Çökmüş köprülerden kalan dosyalar silinir. Her saniye çağrılıyor, ucuz tutuldu.
    static func sessions() -> [BridgeSession] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: Paths.bridges.path)) ?? []
        var alive: [BridgeSession] = []
        for name in names where name.hasSuffix(".json") {
            guard let pid = pid_t(name.dropLast(5)) else { continue }
            guard isBridge(pid) else {
                unlink(Paths.bridgeState(pid).path)
                unlink(Paths.bridgeSocket(pid))
                continue
            }
            if let session = load(pid) { alive.append(session) }
        }
        let pids = Set(alive.map(\.pid))
        cache = cache.filter { pids.contains($0.key) }
        return alive.sorted { $0.pid < $1.pid }
    }

    private static func load(_ pid: pid_t) -> BridgeSession? {
        struct State: Decodable { let tabs: [ChromeTab]; let version: String? }
        let url = Paths.bridgeState(pid)
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        let stamp = FileStamp(ino: info.st_ino, size: info.st_size,
                              sec: info.st_mtimespec.tv_sec, nsec: info.st_mtimespec.tv_nsec)
        if let cached = cache[pid], cached.stamp == stamp { return cached.session }
        let state = (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(State.self, from: $0) }
        let tabs = (state?.tabs ?? []).map { tab in
            var tab = tab
            tab.bridge = pid
            return tab
        }
        let session = BridgeSession(pid: pid, tabs: tabs, version: state?.version)
        cache[pid] = (stamp, session)
        return session
    }

    /// 1.2.x'ten kalan, tek soketli eski köprünün pid'i; güncellemeden sonra kapatılır.
    static var legacyBridgePID: pid_t? {
        guard let text = try? String(contentsOfFile: Paths.legacyBridgePID, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), isBridge(pid) else { return nil }
        return pid
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

    static func send(_ command: [String: Any], to pid: pid_t) {
        send(command, socketPath: Paths.bridgeSocket(pid))
    }

    /// Bütün köprülere (eski tek soketli köprü dahil) gönderir; reload ve uninstall için.
    static func sendAll(_ command: [String: Any]) {
        for session in sessions() { send(command, to: session.pid) }
        if legacyBridgePID != nil { send(command, socketPath: Paths.legacySocket) }
    }

    private static func send(_ command: [String: Any], socketPath: String) {
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

    static func toggle(_ tab: ChromeTab) { send(["cmd": "toggle", "tabId": tab.tabId], to: tab.bridge) }
    static func focus(_ tab: ChromeTab) { send(["cmd": "focus", "tabId": tab.tabId], to: tab.bridge) }
    static func setVolume(_ tab: ChromeTab, _ value: Double) { send(["cmd": "volume", "tabId": tab.tabId, "value": value], to: tab.bridge) }
    /// Eklenti kendini her tarayıcıdan kaldırır; tarayıcı önce kendi onay penceresini gösterir.
    static func uninstallExtension() { sendAll(["cmd": "uninstall"]) }
}
