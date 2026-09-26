import AppKit
import SwiftUI

/// "A · macOS klasik": ince çizgi, beyaz yuvarlak tutamak.
struct VolumeSlider: View {
    let value: Double
    let onChange: (Double) -> Void
    var label: String = "Ses seviyesi"

    private let knob: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - knob, 1)
            let x = CGFloat(min(max(value, 0), 1)) * usable
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.16)).frame(height: 4)
                Capsule().fill(Color.primary.opacity(0.85)).frame(width: x + knob / 2, height: 4)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.15), lineWidth: 0.5))
                    .shadow(color: .black.opacity(0.45), radius: 1.5, y: 1)
                    .frame(width: knob, height: knob)
                    .offset(x: x)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                onChange(Double(min(max((drag.location.x - knob / 2) / usable, 0), 1)))
            })
        }
        .frame(height: 16)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue("%\(Int((value * 100).rounded()))")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onChange(min(value + 0.05, 1))
            case .decrement: onChange(max(value - 0.05, 0))
            @unknown default: break
            }
        }
    }
}

struct Percent: View {
    let value: Double
    var body: some View {
        Text("%\(Int((value * 100).rounded()))")
            .font(.system(size: 11).monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
    }
}

struct SectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct MenuContent: View {
    @EnvironmentObject var model: Model
    @AppStorage("chromeCollapsed") private var chromeCollapsed = false
    var onHeightChange: (CGFloat) -> Void = { _ in }
    var openSettings: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            systemSection
            Divider().padding(.vertical, 2)
            SectionHeader(title: "Uygulamalar")
            chromeRow
            if !chromeCollapsed { chromeVideos }
            ForEach(model.visibleApps) { app in
                AppRow(app: app)
            }
            if model.tapError {
                Text("Uygulama sesini ayarlamak için Sistem Ayarları › Gizlilik › Ses Kaydı'ndan Tab Mixer'a izin ver.")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider().padding(.vertical, 2)
            footer
        }
        .padding([.top, .horizontal], 12)
        .padding(.bottom, 5)
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
        .onPreferenceChange(HeightKey.self) { onHeightChange($0) }
    }

    private var systemSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Ses").font(.system(size: 13, weight: .semibold))
                Spacer()
                Text(model.outputName).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            if model.systemVolumeAvailable {
                HStack(spacing: 6) {
                    Image(systemName: "speaker.fill").font(.system(size: 11)).foregroundStyle(.secondary)
                    VolumeSlider(value: model.systemVolume, onChange: model.setSystemVolume, label: "Mac ses seviyesi")
                    Percent(value: model.systemVolume)
                }
            } else {
                Text("Bu çıkış cihazının sesi buradan ayarlanamıyor.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private var chromeRow: some View {
        HStack(spacing: 6) {
            Button {
                chromeCollapsed.toggle()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(chromeCollapsed ? 0 : 90))
                    .frame(width: 16, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(chromeCollapsed ? "Chrome videolarını göster" : "Chrome videolarını gizle")

            Image(nsImage: model.chromeIcon).resizable().frame(width: 16, height: 16)
            HStack(spacing: 4) {
                Text("Chrome")
                if chromeCollapsed && !model.tabs.isEmpty {
                    Text(model.playingTabs.isEmpty ? "· \(model.tabs.count) video" : "· \(model.playingTabs.count) çalıyor")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            .frame(width: 118, alignment: .leading)
            .lineLimit(1)
            VolumeSlider(value: model.gain(Model.chromeID), onChange: { model.setGain(Model.chromeID, $0) }, label: "Chrome ses seviyesi")
            Percent(value: model.gain(Model.chromeID))
        }
        .font(.system(size: 13))
    }

    private var chromeVideos: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !model.chromeConnected {
                Text("Chrome kapalı veya Tab Mixer eklentisi yüklü değil. Kurulum için Ayarlar'a bak.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else if model.tabs.isEmpty {
                Text("Son 10 dakikada oynatılan video yok.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                if !model.playingTabs.isEmpty {
                    SectionHeader(title: "Çalıyor")
                    ForEach(model.playingTabs) { VideoRow(tab: $0) }
                }
                if !model.pausedTabs.isEmpty {
                    SectionHeader(title: "Duraklatıldı").padding(.top, 2)
                    ForEach(model.pausedTabs) { VideoRow(tab: $0) }
                }
            }
        }
        .padding(.leading, 10)
        .overlay(alignment: .leading) {
            Rectangle().fill(Color.primary.opacity(0.14)).frame(width: 1)
        }
        .padding(.leading, 12)
    }

    private var footer: some View {
        HStack {
            FooterButton(action: openSettings) {
                Label("Ayarlar…", systemImage: "gearshape")
            }
            .keyboardShortcut(",", modifiers: .command)
            Spacer()
            FooterButton(action: { NSApp.terminate(nil) }) {
                Label("Çık", systemImage: "power")
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.horizontal, -6)
    }
}

/// Alttaki sade yazı butonları: görünüm aynı, tıklanan alan geniş, üzerine gelince hafif vurgu.
struct FooterButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            label
                .font(.system(size: 12))
                .foregroundStyle(hover ? Color.primary : Color.secondary)
                .padding(.horizontal, 8)
                .frame(height: 24)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(hover ? 0.1 : 0)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct VideoRow: View {
    @EnvironmentObject var model: Model
    let tab: ChromeTab
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                Button { ChromeBridge.toggle(tab) } label: {
                    HStack(spacing: 7) {
                        Group {
                            if let icon = ChromeBridge.icon(for: tab) {
                                Image(nsImage: icon).resizable()
                            } else {
                                Image(systemName: "play.rectangle").resizable().foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 14, height: 14)
                        Text(cleanTitle)
                            .font(.system(size: 12.5))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 4)
                        if !tab.playing {
                            Text(ago(tab.lastActiveDate))
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(tab.playing ? "Duraklat" : "Oynat")
                .accessibilityLabel("\(tab.title ?? "Video"), \(tab.playing ? "duraklat" : "oynat")")

                Button { ChromeBridge.focus(tab) } label: {
                    Image(systemName: "arrow.up.forward.square")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Sekmeye git")
                .accessibilityLabel("Sekmeye git")
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(hover ? Color.primary.opacity(0.08) : .clear))
            .onHover { hover = $0 }

            HStack(spacing: 6) {
                VolumeSlider(value: model.videoVolume(tab), onChange: { model.setVideoVolume(tab, $0) }, label: "Video ses seviyesi")
                Percent(value: model.videoVolume(tab))
            }
            .padding(.leading, 25)
            .padding(.trailing, 4)
        }
        .padding(.bottom, 3)
    }

    /// YouTube'un başa eklediği "(8) " gibi bildirim sayısını at.
    private var cleanTitle: String {
        (tab.title ?? "Adsız sekme").replacingOccurrences(of: #"^\(\d+\)\s*"#, with: "", options: .regularExpression)
    }

    private func ago(_ date: Date) -> String {
        let minutes = Int(Date().timeIntervalSince(date) / 60)
        return minutes < 1 ? "az önce" : "\(minutes) dk"
    }
}

struct AppRow: View {
    @EnvironmentObject var model: Model
    let app: AudioApp

    var body: some View {
        HStack(spacing: 6) {
            Color.clear.frame(width: 16, height: 20)
            Image(nsImage: app.icon).resizable().frame(width: 16, height: 16)
            Text(app.name).lineLimit(1).frame(width: 118, alignment: .leading)
            VolumeSlider(value: model.gain(app.bundleID), onChange: { model.setGain(app.bundleID, $0) }, label: "\(app.name) ses seviyesi")
            Percent(value: model.gain(app.bundleID))
        }
        .font(.system(size: 13))
    }
}

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
