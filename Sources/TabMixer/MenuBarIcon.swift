import AppKit

/// Menü çubuğu ikonu: uygulama ikonundaki üç sürgünün tek renkli hali.
/// Bir şey çalarken tutamaklar dolu, çalmıyorken içi boş. Yeni sürüm varsa sağ altta indirme rozeti.
enum MenuBarIcon {
    static func image(active: Bool, badge: Bool = false) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let rows: [(y: CGFloat, knob: CGFloat)] = [(4.5, 12), (9, 5.5), (13.5, 10)]
            for row in rows {
                let track = NSBezierPath()
                track.move(to: NSPoint(x: 2, y: row.y))
                track.line(to: NSPoint(x: 16, y: row.y))
                track.lineWidth = 1.6
                track.lineCapStyle = .round
                NSColor.black.setStroke()
                track.stroke()
            }
            // Rozet varken alttaki sürgünün tutamağı yerine rozet durur; yarım tutamak görünmesin
            for row in badge ? Array(rows.dropLast()) : rows {
                let r: CGFloat = 2.0
                let knobRect = NSRect(x: row.knob - r, y: row.y - r, width: 2 * r, height: 2 * r)
                // Tutamağın etrafındaki çizgiyi sil, sürgü "kesik" görünsün
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: knobRect.insetBy(dx: -1.0, dy: -1.0)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                let knob = NSBezierPath(ovalIn: active ? knobRect : knobRect.insetBy(dx: 0.5, dy: 0.5))
                NSColor.black.set()
                if active {
                    knob.fill()
                } else {
                    knob.lineWidth = 1.2
                    knob.stroke()
                }
            }
            if badge { drawDownloadBadge() }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = badge ? "Sound Mix, yeni sürüm var" : "Sound Mix"
        return image
    }

    /// Sağ alt köşede içi oyuk aşağı oklu dolu daire. Çevresi silinir ki sürgülerden ayrı dursun.
    private static func drawDownloadBadge() {
        let circle = NSRect(x: 10.5, y: 10.5, width: 7.5, height: 7.5)
        let context = NSGraphicsContext.current
        context?.compositingOperation = .clear
        NSBezierPath(ovalIn: circle.insetBy(dx: -1.1, dy: -1.1)).fill()
        context?.compositingOperation = .sourceOver
        NSColor.black.set()
        NSBezierPath(ovalIn: circle).fill()

        // Ok saydam kalsın: menü çubuğu rengine göre ters renkte görünür
        let x = circle.midX
        let arrow = NSBezierPath()
        arrow.move(to: NSPoint(x: x, y: circle.minY + 1.8))
        arrow.line(to: NSPoint(x: x, y: circle.maxY - 1.8))
        arrow.move(to: NSPoint(x: x - 1.8, y: circle.maxY - 3.6))
        arrow.line(to: NSPoint(x: x, y: circle.maxY - 1.8))
        arrow.line(to: NSPoint(x: x + 1.8, y: circle.maxY - 3.6))
        arrow.lineWidth = 1.1
        arrow.lineCapStyle = .round
        arrow.lineJoinStyle = .round
        context?.compositingOperation = .clear
        arrow.stroke()
        context?.compositingOperation = .sourceOver
    }
}
