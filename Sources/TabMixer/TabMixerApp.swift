import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: Model?
    private var controller: MenuPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Uygulama zaten açıksa ikinci ikon ve ikinci tap (sesin çift çalması) olmasın diye sessizce çık
        guard SingleInstance.acquire() else {
            NSApp.terminate(nil)
            return
        }
        Installer.run()
        let model = Model()
        self.model = model
        controller = MenuPanelController(model: model)
        controller?.showSetupIfNeeded()
    }
}

/// Arayüzün tek kopya çalışmasını sağlar. Chrome köprüsü de aynı bundle ID ile çalıştığı için
/// süreç listesine değil kilit dosyasına bakıyoruz; kilit süreç ölünce çekirdek tarafından bırakılır.
@MainActor
enum SingleInstance {
    private static var fd: Int32 = -1

    static func acquire() -> Bool {
        try? FileManager.default.createDirectory(at: Paths.shared, withIntermediateDirectories: true)
        let path = Paths.shared.appendingPathComponent("app.lock").path
        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o644)
        guard descriptor >= 0 else { return true } // kilit açılamazsa çalışmayı engelleme
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            close(descriptor)
            return false
        }
        fd = descriptor // süreç boyunca açık kalmalı
        return true
    }
}
