import AppKit
import SwiftUI

/// Ayarlar sayfaları; pencerenin üstündeki sekmelerle aynı sırada.
enum SettingsPage: Int, CaseIterable, Identifiable {
    case general, list, chrome, audio, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: "Genel"
        case .list: "Liste"
        case .chrome: "Tarayıcı"
        case .audio: "Ses İzni"
        case .about: "Hakkında"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .list: "list.bullet"
        case .chrome: "puzzlepiece.extension"
        case .audio: "waveform"
        case .about: "info.circle"
        }
    }

    var subtitle: String {
        switch self {
        case .general: "Sistem davranışı, güncellemeler ve tüm ayar sayfaları."
        case .list: "Menüde hangi videoların ve uygulamaların görüneceği."
        case .chrome: "Tarayıcıdaki videoları Sound Mix'e bağlayan eklenti."
        case .audio: "Uygulamaların sesini ayrı ayrı kısabilmek için gereken izin."
        case .about: "Sürüm, kaynak kodu ve kaldırma."
        }
    }
}

/// Ayarlar penceresi: üstte sistem tarzı sekmeler, her sekmede bir SwiftUI sayfası.
/// Sekme değişince pencere, sayfanın boyuna göre üst kenarı sabit kalarak büyür ya da küçülür.
@MainActor
final class SettingsController: NSTabViewController {
    init(model: Model, openSetup: @escaping () -> Void) {
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.crossfade, .allowUserInteraction]
        for page in SettingsPage.allCases {
            let view = SettingsPageView(page: page, select: { [weak self] in self?.select($0) }, openSetup: openSetup)
                .environmentObject(model)
            let host = NSHostingController(rootView: view)
            host.sizingOptions = [.preferredContentSize]
            host.title = page.title
            let item = NSTabViewItem(viewController: host)
            item.label = page.title
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: page.title)
            addTabViewItem(item)
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    static func makeWindow(model: Model, openSetup: @escaping () -> Void) -> NSWindow {
        let window = NSWindow(contentViewController: SettingsController(model: model, openSetup: openSetup))
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    func select(_ page: SettingsPage) {
        loadViewIfNeeded() // pencere henüz açılmadıysa seçim yoksa kaybolur
        selectedTabViewItemIndex = page.rawValue
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        guard let size = tabViewItem?.viewController?.view.fittingSize, let window = view.window else { return }
        let content = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        var frame = window.frame
        frame.origin.y += frame.height - content.height
        frame.size = content.size
        window.setFrame(frame, display: true, animate: true)
    }
}

struct SettingsPageView: View {
    let page: SettingsPage
    var select: (SettingsPage) -> Void = { _ in }
    var openSetup: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(page.title).font(.system(size: 20, weight: .bold))
                Text(page.subtitle).font(.system(size: 12.5)).foregroundStyle(.secondary)
            }
            switch page {
            case .general: GeneralPage(select: select)
            case .list: ListPage()
            case .chrome: ChromePage(openSetup: openSetup)
            case .audio: AudioPage()
            case .about: AboutPage()
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 22)
        .frame(width: 560, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .toggleStyle(.switch)
    }
}

// MARK: Sayfalar

struct GeneralPage: View {
    @EnvironmentObject var model: Model
    var select: (SettingsPage) -> Void
    @AppStorage("recentMinutes") private var recentMinutes = 10

    var body: some View {
        Card {
            SettingRow("Mac açılınca başlat", "Oturum açıldığında Sound Mix menü çubuğunda otomatik görünür.") {
                Toggle("", isOn: Binding(get: { model.launchAtLogin }, set: { model.launchAtLogin = $0 })).labelsHidden()
            }
        }

        SectionLabel("Güncellemeler")
        UpdateCard()

        SectionLabel("Menü")
        Card {
            NavRow(.list, "Duraklatılan videolar ve diğer uygulamalar", value: RecentChoice.label(recentMinutes), select: select)
            NavRow(.chrome, "Eklenti durumu ve gizlilik", value: model.extensionStatus.text, select: select)
            NavRow(.audio, "Sistem Sesi Kaydı izni", value: model.audioStatus.text, select: select)
            NavRow(.about, "Sürüm, kaynak kodu ve kaldırma", value: UpdateChecker.currentVersion, select: select)
        }
    }
}

/// "Duraklatılan videolar listede kalsın" seçenekleri.
enum RecentChoice {
    static let minutes = [5, 10, 30, 60]
    static func label(_ minutes: Int) -> String { minutes % 60 == 0 ? "\(minutes / 60) saat" : "\(minutes) dk" }
}

struct ListPage: View {
    @EnvironmentObject var model: Model
    @AppStorage("recentMinutes") private var recentMinutes = 10
    @AppStorage("showOtherApps") private var showOtherApps = true
    @State private var confirmReset = false

    var body: some View {
        Card {
            SettingRow("Duraklatılan videolar listede kalsın", "Çalmayı bırakan videolar ve uygulamalar bu süre sonunda menüden kalkar.") {
                Picker("", selection: $recentMinutes) {
                    ForEach(RecentChoice.minutes, id: \.self) { Text(RecentChoice.label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
            SettingRow("Diğer uygulamaları da göster", "Kapalıyken menüde sadece tarayıcı ve videoları görünür.") {
                Toggle("", isOn: $showOtherApps).labelsHidden()
            }
        }

        SectionLabel("Uygulama sesleri")
        Card {
            SettingRow("Sesi kısılan uygulamalar",
                       loweredApps.isEmpty ? "Yok. Menüden bir uygulamanın sesini kısarsan burada görünür ve hatırlanır." : loweredApps.joined(separator: ", ")) {
                Button("Hepsini %100 yap") { confirmReset = true }
                    .disabled(loweredApps.isEmpty)
                    .confirmationDialog("Bütün uygulama sesleri %100'e dönsün mü?", isPresented: $confirmReset) {
                        Button("%100 yap", role: .destructive) { model.resetGains() }
                    }
            }
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

struct ChromePage: View {
    @EnvironmentObject var model: Model
    var openSetup: () -> Void

    var body: some View {
        Card {
            SettingRow("\(model.browser.name) eklentisi", statusDetail, status: model.extensionStatus) {
                if model.extensionOutdated {
                    Button("Güncelle…", action: openSetup)
                } else if model.extensionNeedsRepair {
                    Button("Onar…", action: openSetup)
                } else if !model.browserConnected {
                    Button("Kur…", action: openSetup)
                }
            }
        }

        SectionLabel("Ne yapar")
        Card {
            InfoRow("checkmark", .green, "Sadece video ve ses oynatıcılarına bakar",
                    "Hangi videonun çaldığını ve sesini Sound Mix'e bildirir, menüden verdiğin komutları videoya iletir.")
            InfoRow("xmark", .red, "Sayfa içeriğini okumaz", "Şifreleri, formları ve geçmişini görmez.")
            InfoRow("info.circle", .secondary, "\"Tüm sitelerdeki verileri okuma\" uyarısı",
                    "Videolar çoğu zaman başka sitelerin içinde (iframe) oynadığı için tarayıcı bu izni böyle adlandırır.")
        }
    }

    private var statusDetail: String {
        if model.extensionNeedsRepair { return "Geçici bir klasörden yükleniyor. Onar ile kalıcı klasöre taşı." }
        if model.extensionOutdated { return "Eklentiye güncelleme geldi. Güncelle'ye basıp kutuyu \(model.browser.name) sayfasına sürükle." }
        return model.browserConnected ? "\(model.connectedBrowsers.map(\.name).joined(separator: ", ")) ile bağlı ve çalışıyor." : "Bir tarayıcıya bağlı değil. Kurulum yardımcısıyla yükle."
    }
}

struct AudioPage: View {
    @EnvironmentObject var model: Model

    var body: some View {
        Card {
            SettingRow("Sistem Sesi Kaydı", statusDetail, status: model.audioStatus) {
                switch model.audioPermission {
                case .authorized: EmptyView()
                case .notDetermined: Button("İzin ver") { model.requestAudioPermission() }
                case .denied, .unknown: Button("Sistem Ayarları…") { AudioPermission.openSystemSettings() }
                }
            }
        }

        SectionLabel("Neden gerekli")
        Card {
            InfoRow("checkmark", .green, "Sadece Mac'ten çıkan sese erişir",
                    "Bir uygulamanın sesini %100'ün altına çektiğinde devreye girer. macOS'ta uygulama sesini ayrı ayarlamanın tek yolu bu.")
            InfoRow("xmark", .red, "Kayıt yapmaz", "Mikrofonu, kamerayı veya ekranı kapsamaz. Ses kaydedilmez, saklanmaz.")
            InfoRow("info.circle", .secondary, "İsteğe bağlı",
                    "Vermezsen sadece uygulama ses çubukları çalışmaz. Videolar ve Mac sesi çalışmaya devam eder.")
        }
    }

    private var statusDetail: String {
        switch model.audioPermission {
        case .authorized: "Verildi. Uygulama ses çubukları çalışıyor."
        case .denied: "Reddedildi. Sistem Ayarları'ndan açabilirsin."
        case .notDetermined: "Henüz sorulmadı."
        case .unknown: model.tapError ? "Verilmemiş görünüyor." : "Durum bilinmiyor."
        }
    }
}

struct AboutPage: View {
    @EnvironmentObject var model: Model
    @State private var confirmUninstall = false

    var body: some View {
        Card {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sound Mix").font(.system(size: 15, weight: .semibold))
                    Text("Sürüm \(UpdateChecker.currentVersion)").font(.system(size: 12)).foregroundStyle(.secondary)
                    Text("Tarayıcı videolarını ve uygulama seslerini menü çubuğundan yönet.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(14)
        }

        SectionLabel("Kaynak")
        Card {
            LinkRow("GitHub", "Kaynak kodu ve sürüm notları", url: "https://github.com/omerfarukgzr/sound-mix")
            LinkRow("Lisans", "MIT. Veri toplamaz, analitik kullanmaz.", url: "https://github.com/omerfarukgzr/sound-mix/blob/main/LICENSE")
        }

        SectionLabel("Kaldır")
        Card {
            SettingRow("Sound Mix'i kaldır", "Uygulamayı, tarayıcı eklentisini ve ayarlarını bu Mac'ten siler.") {
                Button("Kaldır…", role: .destructive) { confirmUninstall = true }
                    .confirmationDialog("Sound Mix kaldırılsın mı?", isPresented: $confirmUninstall) {
                        Button("Kaldır", role: .destructive) { model.uninstall() }
                    } message: {
                        Text("Tarayıcı eklentisi (tarayıcı ayrıca onay ister), köprü kaydı, Mac açılınca başlatma ve bütün ayarlar silinir. Kısılmış uygulama sesleri %100'e döner. Sound Mix.app çöpe taşınır ve uygulama kapanır.")
                    }
            }
        }
    }
}

/// Genel sayfasındaki güncelleme kartı: durum, son ve sonraki denetim, otomatik denetim anahtarı, sürüm notları.
struct UpdateCard: View {
    @EnvironmentObject var model: Model
    @AppStorage("checkUpdates") private var checkUpdates = true

    var body: some View {
        Card {
            status
            // "3 dk önce" gibi yazılar pencere açıkken de güncel kalsın
            TimelineView(.periodic(from: .now, by: 30)) { context in
                HStack(alignment: .top, spacing: 0) {
                    stat("Son denetim", last(now: context.date))
                    Divider().frame(height: 34)
                    stat("Sonraki denetim", next(now: context.date))
                }
                .padding(.vertical, 10)
            }
            SettingRow("Otomatik denetle", "Açılışta, 4 saatte bir ve menüyü açtığında GitHub'daki son sürüme bakar. Hiçbir veri göndermez.") {
                Toggle("", isOn: $checkUpdates).labelsHidden()
                    .onChange(of: checkUpdates) { model.checkForUpdate() }
            }
            LinkRow("Sürüm notları", "\(UpdateChecker.currentVersion) sürümünde neler değişti", url: UpdateChecker.releaseNotesURL.absoluteString)
        }
    }

    private var status: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 26))
                .foregroundStyle(tint)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13.5, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let update = model.update {
                Button(model.updateStatus == .installing ? "Güncelleniyor…" : "Güncelle") { model.installUpdate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.updateStatus == .installing)
                    .help("\(update.version) sürümünü indirip kurar ve Sound Mix'i yeniden başlatır")
            } else {
                Button(model.checkingUpdate ? "Denetleniyor…" : "Şimdi denetle") { model.checkForUpdate(force: true) }
                    .disabled(model.checkingUpdate || !checkUpdates)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var symbol: String {
        if model.updateStatus == .failed || model.updateCheckFailed { return "exclamationmark.triangle.fill" }
        if model.update != nil { return "arrow.down.circle.fill" }
        return checkUpdates ? "checkmark.seal.fill" : "pause.circle.fill"
    }

    private var tint: Color {
        if model.updateStatus == .failed || model.updateCheckFailed { return .orange }
        if model.update != nil { return .accentColor }
        return checkUpdates ? .green : .secondary
    }

    private var title: String {
        if model.updateStatus == .failed { return "Güncelleme kurulamadı" }
        if let update = model.update { return "Yeni sürüm var: \(update.version)" }
        if model.updateCheckFailed { return "GitHub'a ulaşılamadı" }
        return model.lastUpdateCheck == nil ? "Henüz denetlenmedi" : "Sound Mix güncel"
    }

    private var detail: String {
        let current = "Kullandığın sürüm \(UpdateChecker.currentVersion)."
        if model.updateStatus == .failed { return current + " İndirip elle kurmak için Releases sayfasını aç." }
        if model.update != nil { return current + " Güncelle'ye basınca indirilir, doğrulanır ve kurulur." }
        if model.updateCheckFailed { return current + " İnternet bağlantını kontrol edip tekrar dene." }
        if let latest = UpdateChecker.latestKnownVersion, model.lastUpdateCheck != nil {
            return current + " GitHub'daki son sürüm \(latest)."
        }
        return current
    }

    private func stat(_ label: String, _ value: (main: String, sub: String)) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(value.main).font(.system(size: 13, weight: .medium))
            Text(value.sub).font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
    }

    private func last(now: Date) -> (main: String, sub: String) {
        guard let date = model.lastUpdateCheck else { return ("Hiç", "Henüz GitHub'a sorulmadı") }
        return (Self.day(date, now: now), date.formatted(.relative(presentation: .named, unitsStyle: .wide).locale(Self.locale)))
    }

    /// Denetim, son denetimin üzerinden 4 saat geçtikten sonraki ilk saatlik turda yapılır;
    /// 1 saat geçtiyse menü açılınca da yapılır.
    private func next(now: Date) -> (main: String, sub: String) {
        guard checkUpdates else { return ("Kapalı", "Otomatik denetim kapalı") }
        guard let last = model.lastUpdateCheck else { return ("Birazdan", "Açılıştan kısa süre sonra") }
        let due = last.addingTimeInterval(UpdateChecker.interval)
        guard due > now else { return ("Birazdan", "Bir saat içinde") }
        return (Self.day(due, now: now), "civarı ya da menüyü açınca")
    }

    private static let locale = Locale(identifier: "tr_TR")

    /// "Bugün 11:29", "Dün 09:10", "Yarın 11:29", yoksa "8 Ekim 14:05".
    private static func day(_ date: Date, now: Date) -> String {
        let calendar = Calendar.current
        let time = date.formatted(Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(locale))
        if calendar.isDate(date, inSameDayAs: now) { return "Bugün \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { return "Dün \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) { return "Yarın \(time)" }
        return date.formatted(Date.FormatStyle().day().month(.wide).locale(locale)) + " " + time
    }
}

// MARK: Durumlar

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

extension Model {
    var extensionStatus: PermissionStatus {
        // Geçici kopya Caches'te duruyor; macOS orayı temizleyince eklenti çalışmaz
        if extensionNeedsRepair { return .missing("Geçici klasörde") }
        if extensionOutdated { return .missing("Güncelleme var") }
        return browserConnected ? .granted("Bağlı") : .missing("Bağlı değil")
    }

    var audioStatus: PermissionStatus {
        switch audioPermission {
        case .authorized: .granted("Verildi")
        case .denied: .missing("Reddedildi")
        case .notDetermined: .optional("Verilmedi")
        case .unknown: tapError ? .missing("Verilmedi") : .optional("Bilinmiyor")
        }
    }
}

// MARK: Parçalar

/// Yuvarlak köşeli kart; içindeki satırların arasına çizgi koyar.
struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        _VariadicView.Tree(DividedRows()) { content }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.primary.opacity(0.09), lineWidth: 0.5))
    }
}

/// Kartın satırlarını alt alta dizer, aralarına çizgi koyar (macOS 14'te Group(subviews:) yok).
struct DividedRows: _VariadicView_MultiViewRoot {
    func body(children: _VariadicView.Children) -> some View {
        VStack(spacing: 0) {
            ForEach(children) { child in
                if child.id != children.first?.id { Divider().padding(.leading, 14) }
                child
            }
        }
    }
}

struct SectionLabel: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, 4)
            .padding(.bottom, -10)
    }
}

/// Başlık, açıklama ve sağda bir kontrol. Durum verilirse başlığın yanında renkli rozet çıkar.
struct SettingRow<Control: View>: View {
    let title: String
    let detail: String
    var status: PermissionStatus?
    @ViewBuilder let control: Control

    init(_ title: String, _ detail: String, status: PermissionStatus? = nil, @ViewBuilder control: () -> Control) {
        self.title = title
        self.detail = detail
        self.status = status
        self.control = control()
    }

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    if let status {
                        Label(status.text, systemImage: status.symbol)
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(status.color)
                    }
                }
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            control
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }
}

/// Başka bir ayar sayfasına giden satır: ikon, başlık, açıklama, değer ve ok.
struct NavRow: View {
    let page: SettingsPage
    let detail: String
    let value: String
    let select: (SettingsPage) -> Void
    @State private var hover = false

    init(_ page: SettingsPage, _ detail: String, value: String, select: @escaping (SettingsPage) -> Void) {
        self.page = page
        self.detail = detail
        self.value = value
        self.select = select
    }

    var body: some View {
        Button { select(page) } label: {
            HStack(spacing: 12) {
                Image(systemName: page.symbol)
                    .font(.system(size: 15))
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(page.title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value).font(.system(size: 12.5)).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(hover ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct InfoRow: View {
    let symbol: String, tint: Color, title: String, detail: String
    init(_ symbol: String, _ tint: Color, _ title: String, _ detail: String) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}

struct LinkRow: View {
    let title: String, detail: String, url: String
    @State private var hover = false
    init(_ title: String, _ detail: String, url: String) {
        self.title = title
        self.detail = detail
        self.url = url
    }

    var body: some View {
        Button { NSWorkspace.shared.open(URL(string: url)!) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold))
                    Text(detail).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.primary.opacity(hover ? 0.05 : 0))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}
