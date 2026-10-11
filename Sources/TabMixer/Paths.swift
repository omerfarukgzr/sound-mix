import Foundation

enum Paths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    static let shared = home.appendingPathComponent("Library/Caches/tab-mixer")
    /// Her köprünün (her tarayıcı profilinin) kendi durum dosyası ve komut soketi: <pid>.json, <pid>.sock.
    /// Ayrı oldukları için aynı anda açık iki tarayıcı birbirinin listesini ezmez.
    static let bridges = shared.appendingPathComponent("bridges")
    static func bridgeState(_ pid: pid_t) -> URL { bridges.appendingPathComponent("\(pid).json") }
    static func bridgeSocket(_ pid: pid_t) -> String { bridges.appendingPathComponent("\(pid).sock").path }

    /// 1.2.x köprüsünün tek soketi ve pid dosyası; güncellemeden sonra eski köprüyü kapatmak için.
    static let legacySocket = shared.appendingPathComponent("cmd.sock").path
    static let legacyBridgePID = shared.appendingPathComponent("bridge.pid").path

    /// Kullanıcının tarayıcıya "paketlenmemiş öğe" olarak yükleyeceği eklenti klasörü.
    static let extensionFolder = home.appendingPathComponent("Library/Application Support/Sound Mix/Chrome Extension")
    /// Eski adla (Tab Mixer) kurulanların eklenti klasörü; tarayıcı eklenti kartında yolu gösterdiği için taşındı.
    static let legacyExtensionFolder = home.appendingPathComponent("Library/Application Support/Tab Mixer/Chrome Extension")
}

/// Unix soketi adres yapısı.
func unixAddress(_ path: String) -> sockaddr_un? {
    var addr = sockaddr_un()
    addr.sun_family = sa_family_t(AF_UNIX)
    let bytes = path.utf8CString
    guard bytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
    withUnsafeMutableBytes(of: &addr.sun_path) { raw in
        bytes.withUnsafeBytes { raw.copyMemory(from: $0) }
    }
    return addr
}
