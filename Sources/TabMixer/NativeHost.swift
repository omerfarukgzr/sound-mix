import Foundation

/// Chrome eklentisiyle stdin/stdout üzerinden konuşan native messaging köprüsü.
/// Eklentinin gönderdiği durumu dosyaya yazar; uygulamadan soketle gelen komutları eklentiye iletir.
enum NativeHost {
    private static let outputLock = NSLock()
    /// Chrome'un eklentiden köprüye izin verdiği en büyük mesaj 64 MB; bizim durum mesajlarımız birkaç KB.
    private static let maxMessage = 4 * 1024 * 1024
    private static let maxCommand = 64 * 1024

    static func run() -> Never {
        try? FileManager.default.createDirectory(at: Paths.shared, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: Paths.shared.path)
        let owned = openSocket()
        if let owned { Thread.detachNewThread { serveCommands(owned.fd) } }

        let input = FileHandle.standardInput
        // Run loop olmadığı için autorelease pool kendiliğinden boşalmıyor; her mesajda elle boşaltıyoruz.
        while autoreleasepool(invoking: { readMessage(from: input) }) {}
        // Eklenti yeniden yüklenince yeni köprü soketi çoktan devralmış olabilir; o zaman onun dosyalarına dokunma
        if let owned, socketID() == owned.id {
            writeState([])
            unlink(Paths.bridgePID)
            unlink(Paths.socket)
        }
        exit(0)
    }

    /// Bir mesaj okur; akış bittiyse veya mesaj geçersizse false döner.
    private static func readMessage(from input: FileHandle) -> Bool {
        let header = input.readData(ofLength: 4)
        guard header.count == 4 else { return false }
        let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
        guard length <= maxMessage else { return false }
        let body = input.readData(ofLength: length)
        guard body.count == length else { return false }
        if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           message["type"] as? String == "state", let tabs = message["tabs"] {
            writeState(tabs)
        }
        return true
    }

    private static func writeState(_ tabs: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: ["tabs": tabs]) else { return }
        try? data.write(to: Paths.state, options: .atomic)
    }

    private static func send(_ data: Data) {
        outputLock.lock()
        defer { outputLock.unlock() }
        var length = UInt32(data.count).littleEndian
        FileHandle.standardOutput.write(Data(bytes: &length, count: 4))
        FileHandle.standardOutput.write(data)
    }

    /// Soket dosyasının kimliği (cihaz + inode); başka bir köprü yeniden bağlarsa değişir.
    private struct SocketID: Equatable { let dev: dev_t; let ino: ino_t }

    private static func socketID() -> SocketID? {
        var info = stat()
        guard stat(Paths.socket, &info) == 0 else { return nil }
        return SocketID(dev: info.st_dev, ino: info.st_ino)
    }

    /// Komut soketini açar (eskisini devralır) ve pid dosyasını yazar.
    private static func openSocket() -> (fd: Int32, id: SocketID)? {
        unlink(Paths.socket)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0, var addr = unixAddress(Paths.socket) else { return nil }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(server, 8) == 0, let id = socketID() else { close(server); return nil }
        chmod(Paths.socket, 0o600)
        try? "\(getpid())".write(toFile: Paths.bridgePID, atomically: true, encoding: .utf8)
        return (server, id)
    }

    private static func serveCommands(_ server: Int32) {
        while true { autoreleasepool {
            let client = accept(server, nil, nil)
            guard client >= 0 else {
                // EMFILE gibi kalıcı hatalarda döngü işlemciyi yakmasın
                if errno != EINTR { usleep(100_000) }
                return
            }
            defer { close(client) }
            // Bağlanıp hiçbir şey göndermeyen istemci diğer komutları sonsuza kadar bekletmesin
            var timeout = timeval(tv_sec: 1, tv_usec: 0)
            setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while data.count <= maxCommand {
                let count = read(client, &buffer, buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            guard data.count <= maxCommand else { return }
            // Sadece geçerli JSON'u ilet
            if (try? JSONSerialization.jsonObject(with: data)) != nil { send(data) }
        } }
    }
}
