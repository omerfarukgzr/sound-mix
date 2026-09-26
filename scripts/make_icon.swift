// Tab Mixer uygulama ikonunu çizer (tasarım: "C3 · Koyu, dolu çizgi").
// Kullanım: swift scripts/make_icon.swift <çıktı.png>
import AppKit

let px: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"

// Tasarımdaki 100'lük koordinatları macOS ikon ızgarasına (824px kare, 100px kenar boşluğu) çevir.
func m(_ u: CGFloat) -> CGFloat { 100 + (u - 4) * 824 / 92 }
func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: m(x), y: px - m(y)) }
let unit: CGFloat = 824 / 92

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(px), pixelsHigh: Int(px), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

let dark = NSColor(srgbRed: 0x1d / 255, green: 0x1d / 255, blue: 0x1f / 255, alpha: 1)
let orange = NSColor(srgbRed: 1, green: 0x7a / 255, blue: 0x1a / 255, alpha: 1)

// Zemin
let bg = NSBezierPath(roundedRect: CGRect(x: 100, y: 100, width: 824, height: 824), xRadius: 21 * unit, yRadius: 21 * unit)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: NSColor.black.withAlphaComponent(0.3).cgColor)
dark.setFill()
bg.fill()
ctx.restoreGState()

func line(_ y: CGFloat, from x1: CGFloat, to x2: CGFloat, _ color: NSColor) {
    let p = NSBezierPath()
    p.move(to: pt(x1, y))
    p.line(to: pt(x2, y))
    p.lineWidth = 4 * unit
    p.lineCapStyle = .round
    color.setStroke()
    p.stroke()
}

func knob(_ x: CGFloat, _ y: CGFloat, _ color: NSColor) {
    let r = 7 * unit
    let c = pt(x, y)
    let circle = NSBezierPath(ovalIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
    color.setFill()
    circle.fill()
    circle.lineWidth = 3 * unit
    dark.setStroke()
    circle.stroke()
}

let dim = NSColor.white.withAlphaComponent(0.28)
for y: CGFloat in [34, 50, 66] { line(y, from: 26, to: 74, dim) }
line(34, from: 26, to: 60, .white)
line(66, from: 26, to: 54, .white)
line(50, from: 26, to: 38, orange)
knob(60, 34, .white)
knob(38, 50, orange)
knob(54, 66, .white)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
