// Renders the PowerPoint ribbon icons for the "Present with Bema" add-in: site/office/icon-<size>.png
// at the sizes Office asks for. The A2 mark on Bema's dark rounded tile, so it reads on light and dark ribbons.
// Run: swift Scripts/make_office_icons.swift .
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
for size in [16, 20, 24, 32, 40, 48, 64, 80, 128] {
    let S = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
    let tile = CGRect(x: 0, y: 0, width: S, height: S)
    ctx.addPath(CGPath(roundedRect: tile, cornerWidth: S * 0.22, cornerHeight: S * 0.22, transform: nil))
    ctx.setFillColor(color(0x15181E).cgColor); ctx.fillPath()
    // The mark on its 64-unit grid, filling about 70% of the tile; strokes a little heavier at tiny sizes.
    let u = S * 0.7 / 52
    let boost: CGFloat = size <= 20 ? 1.15 : 1
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: S / 2 + (x - 32.5) * u, y: S / 2 + (y - 30) * u) }
    ctx.setLineCap(.round)
    ctx.setStrokeColor(color(0xE9EBEF).cgColor); ctx.setLineWidth(8 * u * boost)
    ctx.move(to: p(16, 8)); ctx.addLine(to: p(16, 52)); ctx.strokePath()
    ctx.addPath(CGPath(roundedRect: CGRect(origin: p(16, 25), size: CGSize(width: 33 * u, height: 27 * u)), cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
    ctx.strokePath()
    ctx.setStrokeColor(color(0xF5A524).cgColor); ctx.setLineWidth(5.5 * u * boost)
    ctx.move(to: p(26.5, 38.5)); ctx.addLine(to: p(38.5, 38.5)); ctx.strokePath()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent("site/office/icon-\(size).png"))
}
print("ok")
