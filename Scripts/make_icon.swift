// Renders Resources/AppIcon.icns: the Bema mark (A2: a b whose bowl is a screen, with the amber reading line)
// on a dark rounded square, following the macOS icon grid. Run: swift Scripts/make_icon.swift
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: size); ctx.scaleBy(x: 1, y: -1) // top-left origin

// macOS grid: 824 x 824 body inset 100, corner radius ~185, soft drop shadow.
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
ctx.addPath(CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil))
ctx.setFillColor(color(0x15181E).cgColor)
ctx.fillPath()
ctx.restoreGState()
ctx.addPath(CGPath(roundedRect: body.insetBy(dx: 2, dy: 2), cornerWidth: 183, cornerHeight: 183, transform: nil))
ctx.setStrokeColor(color(0x2A2F3A).cgColor); ctx.setLineWidth(4); ctx.strokePath()

// The mark (A2, "the reading line"), same geometry as site/brand/bema-mark.svg on a 64-unit grid:
// a lowercase b whose bowl is a screen, with the amber reading line inside. Centred in the body.
let u: CGFloat = 10.6
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: 512 + (x - 32.5) * u, y: 512 + (y - 30) * u) }
ctx.setStrokeColor(color(0xE9EBEF).cgColor)
ctx.setLineWidth(8 * u); ctx.setLineCap(.round)
ctx.move(to: p(16, 8)); ctx.addLine(to: p(16, 52)); ctx.strokePath()
ctx.addPath(CGPath(roundedRect: CGRect(origin: p(16, 25), size: CGSize(width: 33 * u, height: 27 * u)),
                   cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
ctx.strokePath()
ctx.setStrokeColor(color(0xF5A524).cgColor)
ctx.setLineWidth(5.5 * u)
ctx.move(to: p(26.5, 38.5)); ctx.addLine(to: p(38.5, 38.5)); ctx.strokePath()
image.unlockFocus()

let root = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let iconset = root.appendingPathComponent("build/AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256),
                   ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: out)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: px, height: px))
    NSGraphicsContext.restoreGraphicsState()
    try! out.representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
}
print(iconset.path)
