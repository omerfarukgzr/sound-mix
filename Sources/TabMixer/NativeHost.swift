import Foundation

/// Chrome eklentisiyle stdin/stdout üzerinden konuşan native messaging köprüsü.
/// Eklentinin gönderdiği durumu kendi dosyasına yazar; uygulamadan kendi soketiyle gelen komutları eklentiye iletir.
/// Her tarayıcı profili ayrı bir köprü başlatır; dosyalar pid'le adlandırıldığı için birbirine karışmaz.
enum NativeHost {
    private static let outputLock = NSLock()
    /// Chrome'un eklentiden köprüye izin verdiği en büyük mesaj 64 MB; bizim durum mesajlarımız birkaç KB.
    private static let maxMessage = 4 * 1024 * 1024
    private static let maxCommand = 64 * 1024

    static func run() -> Never {
        for folder in [Paths.shared, Paths.bridges] {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }
        if let server = openSocket() { Thread.detachNewThread { serveCommands(server) } }
        // Durum dosyası köprünün yaşadığını da gösterir; eklenti ilk durumu göndermeden önce de bağlı görünsün
        writeState([])

        let input = FileHandle.standardInput
        // Run loop olmadığı için autorelease pool kendiliğinden boşalmıyor; her mesajda elle boşaltıyoruz.
        while autoreleasepool(invoking: { readMessage(from: input) }) {}
        unlink(Paths.bridgeSocket(getpid()))
        unlink(Paths.bridgeState(getpid()).path)
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
            writeState(tabs, version: message["version"] as? String)
        }
        return true
    }

    private static func writeState(_ tabs: Any, version: String? = nil) {
        var state: [String: Any] = ["tabs": tabs]
        if let version, version.count <= 32 { state["version"] = version }
        guard let data = try? JSONSerialization.data(withJSONObject: state) else { return }
        try? data.write(to: Paths.bridgeState(getpid()), options: .atomic)
    }

    private static func send(_ data: Data) {
        outputLock.lock()
        defer { outputLock.unlock() }
        var length = UInt32(data.count).littleEndian
        FileHandle.standardOutput.write(Data(bytes: &length, count: 4))
        FileHandle.standardOutput.write(data)
    }

    /// Bu köprünün komut soketini açar. Aynı pid'li çökmüş bir köprüden kalan dosya varsa silinir.
    private static func openSocket() -> Int32? {
        let path = Paths.bridgeSocket(getpid())
        unlink(path)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0, var addr = unixAddress(path) else { return nil }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(server, 8) == 0 else { close(server); return nil }
        chmod(path, 0o600)
        return server
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
