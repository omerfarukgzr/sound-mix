import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @AppStorage("recentMinutes") private var recentMinutes = 10
    @AppStorage("showOtherApps") private var showOtherApps = true
    @State private var confirmReset = false
    var openSetup: () -> Void = {}

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Mac açılınca başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
            }

            Section("Liste") {
                Picker("Duraklatılan videolar listede kalsın", selection: $recentMinutes) {
                    Text("5 dakika").tag(5)
                    Text("10 dakika").tag(10)
                    Text("30 dakika").tag(30)
                    Text("1 saat").tag(60)
                }
                Toggle("Diğer uygulamaları da göster", isOn: $showOtherApps)
            }

            Section("Chrome eklentisi") {
                LabeledContent("Durum") {
                    if model.chromeConnected {
                        Label("Bağlı", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 10) {
                            Text("Bağlı değil").foregroundStyle(.secondary)
                            Button("Kur…", action: openSetup)
                        }
                    }
                }
            }

            Section("Uygulama sesleri") {
                LabeledContent("Ses Kaydı izni") {
                    HStack(spacing: 10) {
                        if model.tapError {
                            Text("Verilmedi").foregroundStyle(.orange)
                        } else {
                            Text("İlk kullanımda sorulur").foregroundStyle(.secondary)
                        }
                        Button("Aç…") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture")!)
                        }
                    }
                }
                LabeledContent("Değiştirilen sesler") {
                    HStack(spacing: 10) {
                        Text(changedCount == 0 ? "Yok" : "\(changedCount) uygulama").foregroundStyle(.secondary)
                        Button("Sıfırla") { confirmReset = true }
                            .disabled(changedCount == 0)
                            .confirmationDialog("Bütün uygulama sesleri %100'e dönsün mü?", isPresented: $confirmReset) {
                                Button("Sıfırla", role: .destructive) { model.resetGains() }
                            }
                    }
                }
            }

            Section {
                LabeledContent("Sürüm", value: version)
                LabeledContent("Kaynak kodu") {
                    Link("GitHub", destination: URL(string: "https://github.com/omerfarukgzr/tab-mixer")!)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var changedCount: Int {
        model.appGains.values.filter { $0 < 0.999 }.count
    }
}
