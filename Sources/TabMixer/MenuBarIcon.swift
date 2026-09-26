import AppKit

/// Menü çubuğu ikonu: uygulama ikonundaki üç sürgünün tek renkli hali.
/// Bir şey çalarken tutamaklar dolu, çalmıyorken içi boş.
enum MenuBarIcon {
    static func image(active: Bool) -> NSImage {
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
            for row in rows {
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
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Tab Mixer"
        return image
    }
}
