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

    static var isConnected: Bool { FileManager.default.fileExists(atPath: socketPath) }

    static func tabs() -> [ChromeTab] {
        struct State: Decodable { let tabs: [ChromeTab] }
        guard let data = try? Data(contentsOf: stateURL),
              let state = try? JSONDecoder().decode(State.self, from: data) else { return [] }
        return state.tabs
    }

    static func icon(for tab: ChromeTab) -> NSImage? {
        guard let base64 = tab.icon else { return nil }
        if let cached = iconCache[base64] { return cached }
        guard let data = Data(base64Encoded: base64), let image = NSImage(data: data) else { return nil }
        image.size = NSSize(width: 14, height: 14)
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
        _ = payload.withUnsafeBytes { write(fd, $0.baseAddress, payload.count) }
    }

    static func toggle(_ tab: ChromeTab) { send(["cmd": "toggle", "tabId": tab.tabId]) }
    static func focus(_ tab: ChromeTab) { send(["cmd": "focus", "tabId": tab.tabId]) }
    static func setVolume(_ tab: ChromeTab, _ value: Double) { send(["cmd": "volume", "tabId": tab.tabId, "value": value]) }
}
