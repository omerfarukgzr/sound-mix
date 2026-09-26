import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @AppStorage("recentMinutes") private var recentMinutes = 10
    @AppStorage("showOtherApps") private var showOtherApps = true
    @State private var confirmReset = false
    @State private var copied = false

    var body: some View {
        Form {
            Section("Genel") {
                Toggle("Mac açılınca başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }

            Section("Liste") {
                Picker("Duraklatılanları göster", selection: $recentMinutes) {
                    Text("5 dakika").tag(5)
                    Text("10 dakika").tag(10)
                    Text("30 dakika").tag(30)
                    Text("1 saat").tag(60)
                }
                Toggle("Chrome dışındaki uygulamaları göster", isOn: $showOtherApps)
            }

            Section {
                LabeledContent("Durum") {
                    Label(model.chromeConnected ? "Bağlı" : "Bağlı değil",
                          systemImage: model.chromeConnected ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(model.chromeConnected ? .green : .orange)
                }
                HStack {
                    Button("Klasörü Finder'da göster") {
                        NSWorkspace.shared.activateFileViewerSelecting([Paths.extensionFolder])
                    }
                    Button(copied ? "Kopyalandı" : "Yolu kopyala") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(Paths.extensionFolder.path, forType: .string)
                        copied = true
                    }
                }
            } header: {
                Text("Chrome eklentisi")
            } footer: {
                if !model.chromeConnected {
                    Text("""
                    Kurulum: Chrome'da chrome://extensions sayfasını aç, sağ üstten Geliştirici modu'nu aç, \
                    "Paketlenmemiş öğe yükle"ye bas. Açılan pencerede ⌘⇧G'ye basıp kopyaladığın yolu yapıştır \
                    ve klasörü seç.
                    """)
                    .font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section {
                Button("Ses Kaydı iznini aç") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                }
                Button("Uygulama seslerini %100'e sıfırla", role: .destructive) { confirmReset = true }
                    .confirmationDialog("Bütün uygulama sesleri %100'e dönsün mü?", isPresented: $confirmReset) {
                        Button("Sıfırla", role: .destructive) { model.resetGains() }
                    }
            } header: {
                Text("Uygulama sesleri")
            } footer: {
                Text("Uygulama seslerini ayarlamak için macOS'un Ses Kaydı iznini Tab Mixer'a vermen gerekiyor.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}
