import Foundation

/// Chrome eklentisiyle stdin/stdout üzerinden konuşan native messaging köprüsü.
/// Eklentinin gönderdiği durumu dosyaya yazar; uygulamadan soketle gelen komutları eklentiye iletir.
enum NativeHost {
    private static let outputLock = NSLock()

    static func run() -> Never {
        try? FileManager.default.createDirectory(at: Paths.shared, withIntermediateDirectories: true)
        Thread.detachNewThread { serveCommands() }

        let input = FileHandle.standardInput
        while true {
            let header = input.readData(ofLength: 4)
            guard header.count == 4 else { break }
            let length = Int(header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }.littleEndian)
            let body = input.readData(ofLength: length)
            guard body.count == length else { break }
            if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
               message["type"] as? String == "state", let tabs = message["tabs"] {
                writeState(tabs)
            }
        }
        writeState([])
        unlink(Paths.socket)
        exit(0)
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

    private static func serveCommands() {
        unlink(Paths.socket)
        let server = socket(AF_UNIX, SOCK_STREAM, 0)
        guard server >= 0, var addr = unixAddress(Paths.socket) else { return }
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(server, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bound == 0, listen(server, 8) == 0 else { return }

        while true {
            let client = accept(server, nil, nil)
            guard client >= 0 else { continue }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = read(client, &buffer, buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            close(client)
            // Sadece geçerli JSON'u ilet
            if (try? JSONSerialization.jsonObject(with: data)) != nil { send(data) }
        }
    }
}
