import AppKit
import SwiftUI

/// Chrome eklentisini kurmak (ya da geçici kopyadan yüklenen eklentiyi onarmak) için adım adım yardımcı.
/// Eklenti klasörü Chrome'un eklentiler sayfasına sürüklenir; aynı eklenti tekrar sürüklenirse eskisinin yerine geçer.
struct SetupView: View {
    @EnvironmentObject var model: Model
    let onDone: () -> Void
    /// Onarım başladıysa yeni eklenti yüklenene kadar onarım metni kalsın
    @State private var repairing = false
    /// Kutu Chrome'a bırakıldığında çalışan köprü. Chrome eklentiyi yükleyince köprü yeni bir süreçle bağlanır;
    /// tercih dosyasını (Chrome onu ~10 sn gecikmeyle yazıyor) beklemeden bundan anlarız.
    @State private var droppedWithBridge: pid_t?? = nil

    private var reloadedAfterDrop: Bool {
        guard let before = droppedWithBridge, let now = model.bridgePID else { return false }
        return now != before
    }

    private var isDone: Bool { model.chromeConnected && (!model.extensionNeedsAttention || reloadedAfterDrop) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.title3.weight(.semibold))
                    Text(subtitle)
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if isDone {
                done
            } else {
                steps
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear { if model.extensionNeedsAttention { repairing = true } }
        .onChange(of: model.extensionNeedsAttention) { _, needed in if needed { repairing = true } }
        .onChange(of: isDone) { _, finished in if finished { repairing = false } }
    }

    /// Chrome'daki eklenti uygulamanın içindekinden eski; güncelleme gelmiş ama Chrome yükleyememiş.
    private var updating: Bool { repairing && !model.extensionNeedsRepair }

    private var title: String {
        if updating { return "Chrome eklentisine güncelleme geldi" }
        return repairing ? "Chrome eklentisini onar" : "Chrome eklentisini kur"
    }

    private var subtitle: String {
        if updating {
            let installed = ChromeBridge.extensionVersion().map { "Chrome'daki eklenti \($0), yeni sürüm \(Installer.bundledExtensionVersion ?? "?"). " } ?? ""
            return installed + "Sound Mix'in düzgün çalışması için eklentiyi güncellemen gerekiyor. Kutuyu Chrome'a sürüklemen yeterli, ayarların korunur."
        }
        if repairing {
            return "Eklenti şu an geçici bir klasörden yükleniyor, macOS orayı her an temizleyebilir. Kalıcı klasörden yeniden yükleyelim."
        }
        return "Sound Mix'in Chrome'daki videoları görebilmesi için bir kez gerekli."
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 14) {
            Step(number: 1, title: "Chrome'da eklentiler sayfasını aç") {
                Button {
                    openExtensionsPage()
                } label: {
                    Label("Eklentiler sayfasını aç", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
            }
            if repairing {
                Step(number: 2, title: "Aşağıdaki kutuyu Chrome'daki sayfanın üzerine sürükle") {
                    VStack(alignment: .leading, spacing: 6) {
                        ExtensionDragTile(onDrop: dropped)
                        Text(updating ? "Eski eklentinin yerine geçer, önce kaldırman gerekmez." : "Mevcut eklentinin yerine geçer, önce kaldırman gerekmez.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            } else {
                Step(number: 2, title: "Sağ üstteki \"Geliştirici modu\" anahtarını aç") { EmptyView() }
                Step(number: 3, title: "Aşağıdaki kutuyu Chrome'daki sayfanın üzerine sürükle") {
                    ExtensionDragTile(onDrop: dropped)
                }
            }

            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(droppedWithBridge == nil
                     ? "Eklenti bekleniyor… Yükledikten sonra açık video sekmelerini bir kez yenile."
                     : "Eklenti yükleniyor…")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func dropped() {
        droppedWithBridge = .some(model.bridgePID)
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Hazır! Eklenti bağlandı.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text("Açık video sekmelerini bir kez yenile. Videolar menü çubuğundaki Sound Mix ikonunda görünecek.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Kapat", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func openExtensionsPage() {
        guard let chrome = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Model.chromeID),
              let url = URL(string: "chrome://extensions") else { return }
        NSWorkspace.shared.open([url], withApplicationAt: chrome, configuration: NSWorkspace.OpenConfiguration())
    }
}

private struct Step<Content: View>: View {
    let number: Int
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.callout.weight(.semibold).monospacedDigit())
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.accentColor.opacity(0.18)))
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.body).fixedSize(horizontal: false, vertical: true)
                content
            }
        }
    }
}

/// Chrome'a sürüklenebilen eklenti klasörü kutusu.
private struct ExtensionDragTile: View {
    let onDrop: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: Paths.extensionFolder.path))
                .resizable().frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sound Mix eklentisi").font(.callout.weight(.medium))
                Text("Beni Chrome'a sürükle").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "hand.draw").foregroundStyle(.secondary)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.secondary))
        .overlay(FolderDragSource(url: Paths.extensionFolder, onDrop: onDrop))
        .help("Chrome'un eklentiler sayfasına sürükle")
    }
}

/// Klasörü Finder'daki gibi gerçek yoluyla sürükler. SwiftUI'nin onDrag'i klasörü her seferinde
/// Caches altında geçici bir kopyaya çeviriyordu; Chrome eklentiyi oradan yükleyince güncellemeler ulaşmıyordu.
private struct FolderDragSource: NSViewRepresentable {
    let url: URL
    let onDrop: () -> Void

    func makeNSView(context: Context) -> DragView { DragView(url: url, onDrop: onDrop) }
    func updateNSView(_ view: DragView, context: Context) {}

    final class DragView: NSView, NSDraggingSource {
        let url: URL
        let onDrop: () -> Void

        init(url: URL, onDrop: @escaping () -> Void) {
            self.url = url
            self.onDrop = onDrop
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError() }

        override func mouseDown(with event: NSEvent) {}

        override func mouseDragged(with event: NSEvent) {
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            icon.size = NSSize(width: 48, height: 48)
            let point = convert(event.locationInWindow, from: nil)
            item.setDraggingFrame(NSRect(x: point.x - 24, y: point.y - 24, width: 48, height: 48), contents: icon)
            beginDraggingSession(with: [item], event: event, source: self)
        }

        func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
            context == .outsideApplication ? [.copy, .link, .generic] : []
        }

        /// Bir yere bırakıldıysa (iptal edilmediyse) haber ver
        func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
            if !operation.isEmpty { onDrop() }
        }
    }
}
