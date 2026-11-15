// Renders site/brand/bema-avatar.png (1024×1024): the A2 mark on Bema's dark ground, filling the square,
// for the GitHub organization's profile picture and other square avatars.
// Run: swift Scripts/make_avatar.swift .
import AppKit

func color(_ hex: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
}
let S: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: S); ctx.scaleBy(x: 1, y: -1)
ctx.setFillColor(color(0x0E1014).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: S, height: S))
// The mark on its 64-unit grid, about 58% of the square so it survives GitHub's round crops.
let u = S * 0.58 / 52
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: S / 2 + (x - 32.5) * u, y: S / 2 + (y - 30) * u) }
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xE9EBEF).cgColor); ctx.setLineWidth(8 * u)
ctx.move(to: p(16, 8)); ctx.addLine(to: p(16, 52)); ctx.strokePath()
ctx.addPath(CGPath(roundedRect: CGRect(origin: p(16, 25), size: CGSize(width: 33 * u, height: 27 * u)), cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
ctx.strokePath()
ctx.setStrokeColor(color(0xF5A524).cgColor); ctx.setLineWidth(5.5 * u)
ctx.move(to: p(26.5, 38.5)); ctx.addLine(to: p(38.5, 38.5)); ctx.strokePath()
NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".").appendingPathComponent("site/brand/bema-avatar.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print(out.path)
