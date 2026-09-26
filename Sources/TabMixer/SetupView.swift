import AppKit
import SwiftUI

/// Chrome eklentisini kurmak için adım adım yardımcı.
/// Dosya seçme penceresi yerine eklenti klasörü Chrome'un eklentiler sayfasına sürüklenir.
struct SetupView: View {
    @EnvironmentObject var model: Model
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Chrome eklentisini kur").font(.title3.weight(.semibold))
                    Text("Tab Mixer'ın Chrome'daki videoları görebilmesi için bir kez gerekli.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            if model.chromeConnected {
                done
            } else {
                steps
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var steps: some View {
        VStack(alignment: .leading, spacing: 16) {
            Step(number: 1, title: "Chrome'da eklentiler sayfasını aç") {
                Button("Eklentiler sayfasını aç") { openExtensionsPage() }
            }
            Step(number: 2, title: "Sağ üstteki \"Geliştirici modu\" anahtarını aç") { EmptyView() }
            Step(number: 3, title: "Aşağıdaki kutuyu sürükleyip Chrome'daki sayfanın üzerine bırak") {
                ExtensionDragTile()
            }
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Eklenti bekleniyor… Yükledikten sonra açık video sekmelerini bir kez yenile.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private var done: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Hazır! Eklenti bağlandı.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.headline)
            Text("Açık video sekmelerini bir kez yenile. Videolar menü çubuğundaki Tab Mixer ikonunda görünecek.")
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
                Text(title).font(.body)
                content
            }
        }
    }
}

/// Chrome'a sürüklenebilen eklenti klasörü kutusu.
private struct ExtensionDragTile: View {
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: Paths.extensionFolder.path))
                    .resizable().frame(width: 36, height: 36)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Tab Mixer eklentisi").font(.callout.weight(.medium))
                    Text("Beni Chrome'a sürükle").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "hand.draw").foregroundStyle(.secondary)
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 10).strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4])).foregroundStyle(.secondary))
            .contentShape(Rectangle())
            .onDrag { NSItemProvider(contentsOf: Paths.extensionFolder) ?? NSItemProvider() }
            .help("Chrome'un eklentiler sayfasına sürükle")

            Button(copied ? "Yol kopyalandı" : "Sürükleme olmazsa: klasör yolunu kopyala") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Paths.extensionFolder.path, forType: .string)
                copied = true
            }
            .buttonStyle(.link)
            .font(.caption)
        }
    }
}
