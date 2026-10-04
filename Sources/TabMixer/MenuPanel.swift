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

        hosting.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView = Self.makeBackground(containing: hosting)
        panel.onCancel = { [weak self] in self?.closePanel() }

        if let button = statusItem.button {
            button.action = #selector(togglePanel)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        model.$tabs.combineLatest(model.$apps, model.$update)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateIcon() }
            .store(in: &cancellables)
        updateIcon()
    }

    /// macOS 26 ve sonrasında sistem menüleriyle aynı Liquid Glass. Saydamlık oranını sistem
    /// belirler; kullanıcının "Liquid Glass" ve "Saydamlığı azalt" ayarlarına kendisi uyar.
    /// Daha eski sürümlerde menü materyalli buzlu cam kullanılır.
    private static func makeBackground(containing hosting: NSView) -> NSView {
        let container = NSView()
        container.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: container.topAnchor),
        ])

        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = cornerRadius
            glass.contentView = container
            glass.wantsLayer = true
            return glass
        }

        let effect = NSVisualEffectView()
        effect.material = .menu
        effect.state = .active
        effect.blendingMode = .behindWindow
        effect.wantsLayer = true
        effect.layer?.cornerRadius = cornerRadius
        effect.layer?.cornerCurve = .continuous
        effect.layer?.masksToBounds = true
        effect.layer?.borderWidth = 0.5
        effect.layer?.borderColor = NSColor.white.withAlphaComponent(0.18).cgColor
        container.frame = effect.bounds
        effect.addSubview(container)
        return effect
    }

    private func updateIcon() {
        statusItem.button?.image = MenuBarIcon.image(active: model.isActive, badge: model.update != nil)
    }

    private var isOpen = false

    @objc private func togglePanel() {
        isOpen ? closePanel() : openPanel()
    }

    private func openPanel() {
        guard let button = statusItem.button, let buttonWindow = button.window,
              let screen = (buttonWindow.screen ?? NSScreen.main)?.visibleFrame else { return }
        model.panelOpen = true
        model.refresh(full: true)
        let height = max(hosting.fittingSize.height, contentHeight, 80)
        let buttonRect = buttonWindow.convertToScreen(button.convert(button.bounds, to: nil))
        var x = buttonRect.minX
        x = min(x, screen.maxX - Self.width - 8)
        let frame = NSRect(x: x, y: buttonRect.minY - 6 - height, width: Self.width, height: height)
        isOpen = true
        statusItem.button?.highlight(true)

        panel.setFrame(frame, display: true)
        panel.hasShadow = false
        panel.makeKeyAndOrderFront(nil)
        animateContent(show: true) { [weak self] in
            guard let self, self.isOpen else { return }
            self.panel.hasShadow = true
            self.panel.invalidateShadow()
        }

        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closePanel() }
        }
    }

    func closePanel() {
        guard isOpen else { return }
        isOpen = false
        model.panelOpen = false
        statusItem.button?.highlight(false)
        panel.hasShadow = false
        animateContent(show: false) { [weak self] in
            guard let self, !self.isOpen else { return }
            self.panel.orderOut(nil)
        }
        if let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
        }
    }

    /// Menü içeriğini katman düzeyinde soldurup kaydırır. Buzlu cam arka plan pencere
    /// şeffaflığı animasyonunu yok saydığı için pencereyi değil içeriği canlandırıyoruz.
    private func animateContent(show: Bool, completion: @escaping @MainActor () -> Void) {
        guard let layer = panel.contentView?.layer else { completion(); return }
        let lifted = CATransform3DMakeTranslation(0, 8, 0)
        let fromOpacity: Float = show ? 0 : 1
        let toOpacity: Float = show ? 1 : 0
        let fromTransform = show ? lifted : CATransform3DIdentity
        let toTransform = show ? CATransform3DIdentity : lifted

        CATransaction.begin()
        CATransaction.setCompletionBlock { MainActor.assumeIsolated { completion() } }
        let opacity = CABasicAnimation(keyPath: "opacity")
        opacity.fromValue = fromOpacity
        opacity.toValue = toOpacity
        let move = CABasicAnimation(keyPath: "transform")
        move.fromValue = fromTransform
        move.toValue = toTransform
        let group = CAAnimationGroup()
        group.animations = [opacity, move]
        group.duration = show ? 0.2 : 0.16
        group.timingFunction = CAMediaTimingFunction(name: show ? .easeOut : .easeIn)
        layer.opacity = toOpacity
        layer.transform = toTransform
        layer.add(group, forKey: "menuTransition")
        CATransaction.commit()
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
            window.title = "Sound Mix Kurulumu"
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
            window.title = "Sound Mix Ayarları"
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
