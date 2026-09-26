import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var model: Model?
    private var controller: MenuPanelController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Installer.run()
        let model = Model()
        self.model = model
        controller = MenuPanelController(model: model)
        controller?.showSetupIfNeeded()
    }
}
