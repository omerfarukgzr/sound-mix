import Foundation

enum Paths {
    private static let home = FileManager.default.homeDirectoryForCurrentUser

    /// Uygulama ile Chrome köprüsünün paylaştığı durum dosyası ve komut soketi.
    static let shared = home.appendingPathComponent("Library/Caches/tab-mixer")
    static let state = shared.appendingPathComponent("state.json")
    static let socket = shared.appendingPathComponent("cmd.sock").path
    /// Soketi o an tutan köprünün pid'i; uygulama köprünün yaşayıp yaşamadığına buradan bakar.
    static let bridgePID = shared.appendingPathComponent("bridge.pid").path

    /// Kullanıcının Chrome'a "paketlenmemiş öğe" olarak yükleyeceği eklenti klasörü.
    static let extensionFolder = home.appendingPathComponent("Library/Application Support/Tab Mixer/Chrome Extension")

    static let nativeHostsFolder = home.appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")
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
