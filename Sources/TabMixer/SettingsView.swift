import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var model: Model
    @AppStorage("recentMinutes") private var recentMinutes = 10
    @AppStorage("showOtherApps") private var showOtherApps = true
    @AppStorage("checkUpdates") private var checkUpdates = true
    @State private var confirmReset = false
    @State private var confirmUninstall = false
    var openSetup: () -> Void = {}

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    var body: some View {
        Form {
            Section {
                Toggle("Mac açılınca başlat", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 }))
                Toggle(isOn: $checkUpdates) {
                    Text("Güncellemeleri denetle")
                    Text("Günde bir kez GitHub'daki son sürüme bakar, hiçbir veri göndermez.")
                }
                .onChange(of: checkUpdates) { model.checkForUpdate() }
            }

            Section("Liste") {
                Picker("Duraklatılan videolar listede kalsın", selection: $recentMinutes) {
                    Text("5 dakika").tag(5)
                    Text("10 dakika").tag(10)
                    Text("30 dakika").tag(30)
                    Text("1 saat").tag(60)
                }
                Toggle("Diğer uygulamaları da göster", isOn: $showOtherApps)
                LabeledContent {
                    Button("Hepsini %100 yap") { confirmReset = true }
                        .disabled(loweredApps.isEmpty)
                        .confirmationDialog("Bütün uygulama sesleri %100'e dönsün mü?", isPresented: $confirmReset) {
                            Button("%100 yap", role: .destructive) { model.resetGains() }
                        }
                } label: {
                    Text("Sesi kısılan uygulamalar")
                    Text(loweredApps.isEmpty ? "Yok. Menüden bir uygulamanın sesini kısarsan burada görünür ve hatırlanır." : loweredApps.joined(separator: ", "))
                }
            }

            Section {
                PermissionRow(
                    icon: "puzzlepiece.extension.fill",
                    tint: .blue,
                    title: "Chrome eklentisi",
                    status: extensionStatus,
                    summary: "Chrome'daki videoları bulur, hangisinin çaldığını ve ses seviyesini Sound Mix'e bildirir. Menüden verdiğin oynat, durdur ve ses komutlarını videoya iletir.",
                    details: [
                        ("checkmark", "Sadece sayfadaki video ve ses oynatıcılarına bakar."),
                        ("xmark", "Sayfa içeriğini, şifreleri, formları veya geçmişini okumaz."),
                        ("info.circle", "Chrome'un \"tüm sitelerdeki verileri okuma\" uyarısı, videoların çoğu zaman başka sitelerin içinde (iframe) oynamasından kaynaklanır."),
                    ],
                    actionTitle: model.extensionNeedsAttention ? "Onar…" : model.chromeConnected ? nil : "Kur…",
                    action: openSetup
                )
                PermissionRow(
                    icon: "waveform",
                    tint: .orange,
                    title: "Sistem Sesi Kaydı",
                    status: audioStatus,
                    summary: "Bir uygulamanın sesini kısabilmek için o uygulamanın sesini hoparlöre gitmeden önce alır, kısar ve öyle çalar. macOS'ta uygulama sesini ayrı ayarlamanın tek yolu bu.",
                    details: [
                        ("checkmark", "Sadece Mac'ten çıkan sese erişir, sen bir uygulamanın sesini %100'ün altına çektiğinde devreye girer."),
                        ("xmark", "Mikrofonu, kamerayı veya ekranı kapsamaz. Ses kaydedilmez, saklanmaz."),
                        ("info.circle", "İsteğe bağlı. Vermezsen sadece uygulama ses çubukları çalışmaz, videolar ve Mac sesi çalışmaya devam eder."),
                    ],
                    actionTitle: audioActionTitle,
                    action: {
                        if model.audioPermission == .notDetermined {
                            model.requestAudioPermission()
                        } else {
                            AudioPermission.openSystemSettings()
                        }
                    }
                )
            } header: {
                Text("İzinler ve gizlilik")
            } footer: {
                Label("Sound Mix veri toplamaz. Mikrofon, kamera, ekran kaydı veya dosyalarına erişim istemez.",
                      systemImage: "lock.shield")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section {
                LabeledContent("Sürüm", value: version)
                LabeledContent("Kaynak kodu") {
                    Link("GitHub", destination: URL(string: "https://github.com/omerfarukgzr/sound-mix")!)
                }
            }

            Section {
                LabeledContent {
                    Button("Sound Mix'i kaldır…", role: .destructive) { confirmUninstall = true }
                        .confirmationDialog("Sound Mix kaldırılsın mı?", isPresented: $confirmUninstall) {
                            Button("Kaldır", role: .destructive) { model.uninstall() }
                        } message: {
                            Text("Chrome eklentisi (Chrome ayrıca onay ister), Chrome köprüsü kaydı, Mac açılınca başlatma ve bütün ayarlar silinir. Kısılmış uygulama sesleri %100'e döner. Sound Mix.app çöpe taşınır ve uygulama kapanır.")
                        }
                } label: {
                    Text("Kaldır")
                    Text("Uygulamayı, Chrome eklentisini ve ayarlarını bu Mac'ten siler.")
                }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .scrollIndicators(.never)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var extensionStatus: PermissionStatus {
        // Geçici kopya Caches'te duruyor; macOS orayı temizleyince eklenti çalışmaz
        if model.extensionNeedsRepair { return .missing("Geçici klasörden yükleniyor") }
        if model.extensionOutdated { return .missing("Güncel değil") }
        return model.chromeConnected ? .granted("Bağlı") : .missing("Bağlı değil")
    }

    private var audioStatus: PermissionStatus {
        switch model.audioPermission {
        case .authorized: .granted("Verildi")
        case .denied: .missing("Reddedildi")
        case .notDetermined: .optional("Henüz verilmedi")
        case .unknown: model.tapError ? .missing("Verilmedi") : .optional("Bilinmiyor")
        }
    }

    private var audioActionTitle: String? {
        switch model.audioPermission {
        case .authorized: nil
        case .notDetermined: "İzin ver"
        case .denied, .unknown: "Sistem Ayarları…"
        }
    }

    /// "Chrome %60" gibi, sesi %100'ün altında tutulan uygulamalar.
    private var loweredApps: [String] {
        model.appGains
            .filter { $0.value < 0.999 }
            .sorted { $0.key < $1.key }
            .map { id, gain in "\(appName(id)) %\(Int((gain * 100).rounded()))" }
    }

    private func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID
    }
}

enum PermissionStatus {
    case granted(String), missing(String), optional(String)

    var text: String {
        switch self { case .granted(let t), .missing(let t), .optional(let t): t }
    }

    var color: Color {
        switch self {
        case .granted: .green
        case .missing: .orange
        case .optional: .secondary
        }
    }

    var symbol: String {
        switch self {
        case .granted: "checkmark.circle.fill"
        case .missing: "exclamationmark.circle.fill"
        case .optional: "circle.dashed"
        }
    }
}

/// Bir iznin adı, durumu, ne işe yaradığı ve ayrıntıları.
struct PermissionRow: View {
    let icon: String
    let tint: Color
    let title: String
    let status: PermissionStatus
    let summary: String
    let details: [(String, String)]
    var actionTitle: String?
    var action: () -> Void = {}
    @State private var expanded = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 6).fill(tint))
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.body.weight(.medium))
                    Label(status.text, systemImage: status.symbol)
                        .font(.caption)
                        .foregroundStyle(status.color)
                }
                Spacer()
                if let actionTitle {
                    Button(actionTitle, action: action)
                }
            }
            Text(summary)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                expanded.toggle()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                    Text(expanded ? "Ayrıntıları gizle" : "Ayrıntılar")
                        .font(.callout)
                    Spacer()
                }
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.08 : 0)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hover = $0 }
            .padding(.horizontal, -8)
            .accessibilityLabel(expanded ? "Ayrıntıları gizle" : "Ayrıntıları göster")

            if expanded {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(details, id: \.1) { symbol, text in
                        Label {
                            Text(text).fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: symbol)
                                .foregroundStyle(symbol == "checkmark" ? .green : symbol == "xmark" ? .red : .secondary)
                        }
                        .font(.callout)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}
