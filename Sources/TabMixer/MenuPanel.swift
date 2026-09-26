import AppKit
import Combine
import SwiftUI

/// Menü çubuğu ikonu ve açılan menü paneli.
/// SwiftUI'nin MenuBarExtra penceresi içerik küçülünce boyutunu düzgün güncellemediği için
/// paneli kendimiz yönetiyoruz: yumuşak köşeli buzlu cam, içeriğe göre boy, üst kenar sabit.
@MainActor
final class MenuPanelController: NSObject {
    private let model: Model
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let panel: MenuPanel
    private var hosting: NSHostingView<AnyView>!
    private var settingsWindow: NSWindow?
    private var setupWindow: NSWindow?
    private var outsideClickMonitor: Any?
    private var cancellables: Set<AnyCancellable> = []
    private var contentHeight: CGFloat = 0

    static let width: CGFloat = 340
    static let cornerRadius: CGFloat = 12

    init(model: Model) {
        self.model = model
        panel = MenuPanel()
        super.init()

        let content = MenuContent(
            onHeightChange: { [weak self] height in self?.fit(height: height) },
            openSettings: { [weak self] in self?.showSettings() }
        )
        .environmentObject(model)
        hosting = NSHostingView(rootView: AnyView(content))
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: hosting, queue: .main) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.fit(height: self.hosting.frame.height)
            }
        }

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = Self.cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor

        hosting.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: effect.topAnchor),
        ])
        panel.contentView = effect
        panel.onCancel = { [weak self] in self?.closePanel() }

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.$tabs.combineLatest(model.$apps)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(active: model.isActive)
    }

    private var isOpen = false

    @objc private func togglePanel() {
        isOpen ? closePanel() : openPanel()
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window else { return }
        model.refresh(full: true)
        let height = max(hosting.fittingSize.height, contentHeight, 80)
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        let screen = buttonWindow.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        var x = buttonRect.minX
        x = min(x, screen.maxX - Self.width - 8)
        let frame = NSRect(x: x, y: buttonRect.minY - 6 - height, width: Self.width, height: height)
        isOpen = true
        statusItem.button?.highlight(true)

        // Hafifçe yukarıdan kayarak belir
        panel.alphaValue = 0
        panel.setFrame(frame.offsetBy(dx: 0, dy: 8), display: true)
        panel.makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(frame, display: true)
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    func closePanel() {
        guard isOpen else { return }
        isOpen = false
        statusItem.button?.highlight(false)
        // Yumuşakça sol
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isOpen else { return }
                self.panel.orderOut(nil)
                self.panel.alphaValue = 1
            }
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// İçerik yüksekliği değişince paneli üst kenarı sabit kalacak şekilde yeniden boyutlandır.
    private func fit(height: CGFloat) {
        guard height > 0 else { return }
        contentHeight = height
        guard isOpen else { return }
        var frame = panel.frame
        guard abs(frame.height - height) > 0.5 else { return }
        frame.origin.y += frame.height - height
        frame.size.height = height
        panel.setFrame(frame, display: false)
        panel.contentView?.needsLayout = true
        panel.contentView?.layoutSubtreeIfNeeded()
        panel.display()
    }

    func showSetupIfNeeded() {
        // Köprü birkaç saniye içinde bağlanmazsa kurulum yardımcısını göster
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self, !self.model.chromeConnected else { return }
            self.showSetup()
        }
    }

    func showSetup() {
        closePanel()
        if setupWindow == nil {
            let view = SetupView(onDone: { [weak self] in self?.setupWindow?.close() }).environmentObject(model)
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Tab Mixer Kurulumu"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            setupWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        setupWindow?.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        closePanel()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(openSetup: { [weak self] in self?.showSetup() }).environmentObject(model))
            let window = NSWindow(contentViewController: controller)
            window.title = "Tab Mixer Ayarları"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}

/// Kenarlıksız, odak alabilen, uygulamayı öne getirmeyen panel.
final class MenuPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        isMovable = false
        hidesOnDeactivate = false
    }

    override var canBecomeKey: Bool { true }

    var onCancel: () -> Void = {}

    override func cancelOperation(_ sender: Any?) { onCancel() }
}
