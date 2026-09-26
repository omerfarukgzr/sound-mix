import AppKit

// Chrome, native messaging köprüsünü başlatırken eklentinin adresini argüman olarak verir.
// Bu durumda arayüzü açmadan sadece köprü olarak çalışırız.
if CommandLine.arguments.contains(where: { $0.hasPrefix("chrome-extension://") }) {
    NativeHost.run()
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
