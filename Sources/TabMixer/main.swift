import Foundation

// Chrome, native messaging köprüsünü başlatırken eklentinin adresini argüman olarak verir.
// Bu durumda arayüzü açmadan sadece köprü olarak çalışırız.
if CommandLine.arguments.contains(where: { $0.hasPrefix("chrome-extension://") }) {
    NativeHost.run()
} else {
    TabMixerApp.main()
}
