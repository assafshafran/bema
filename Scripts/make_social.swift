// Renders site/brand/bema-social.png (1280×640): the social preview for the GitHub repository and the
// website's share card. The A2 mark, the name and the one-line pitch on Bema's dark ground.
// Run: swift Scripts/make_social.swift .
import AppKit

func color(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let W: CGFloat = 1280, H: CGFloat = 640
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(W), pixelsHigh: Int(H), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
ctx.translateBy(x: 0, y: H); ctx.scaleBy(x: 1, y: -1) // top-left origin

// Ground.
ctx.setFillColor(color(0x0E1014).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
// A thin amber reading line across the top edge.
ctx.setFillColor(color(0xF5A524).cgColor); ctx.fill(CGRect(x: 0, y: 0, width: W, height: 6))

// The A2 mark on a 64-unit grid (site/brand/bema-mark.svg), in a tile on the left.
let tile = CGRect(x: 112, y: 200, width: 240, height: 240)
ctx.addPath(CGPath(roundedRect: tile, cornerWidth: 54, cornerHeight: 54, transform: nil))
ctx.setFillColor(color(0x15181E).cgColor); ctx.fillPath()
ctx.addPath(CGPath(roundedRect: tile.insetBy(dx: 1, dy: 1), cornerWidth: 53, cornerHeight: 53, transform: nil))
ctx.setStrokeColor(color(0x2A2F3A).cgColor); ctx.setLineWidth(2); ctx.strokePath()
let u: CGFloat = 3.0
func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: tile.midX + (x - 32.5) * u, y: tile.midY + (y - 30) * u) }
ctx.setLineCap(.round)
ctx.setStrokeColor(color(0xE9EBEF).cgColor); ctx.setLineWidth(8 * u)
ctx.move(to: p(16, 8)); ctx.addLine(to: p(16, 52)); ctx.strokePath()
ctx.addPath(CGPath(roundedRect: CGRect(origin: p(16, 25), size: CGSize(width: 33 * u, height: 27 * u)), cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
ctx.strokePath()
ctx.setStrokeColor(color(0xF5A524).cgColor); ctx.setLineWidth(5.5 * u)
ctx.move(to: p(26.5, 38.5)); ctx.addLine(to: p(38.5, 38.5)); ctx.strokePath()

// Text (drawn with AppKit in a flipped context).
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
func draw(_ s: String, _ font: NSFont, _ c: NSColor, at x: CGFloat, _ y: CGFloat, width: CGFloat = 800, kern: CGFloat = 0) {
    let style = NSMutableParagraphStyle(); style.lineSpacing = font.pointSize * 0.18
    let attr = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: c, .kern: kern, .paragraphStyle: style])
    attr.draw(with: CGRect(x: x, y: y, width: width, height: 400), options: [.usesLineFragmentOrigin])
}
let left: CGFloat = 416
draw("Bema", .systemFont(ofSize: 96, weight: .bold), color(0xF2F4F7), at: left, 178, kern: -2)
draw("A presenter view you control,\nfor PowerPoint and Keynote on Mac.", .systemFont(ofSize: 40, weight: .medium), color(0xC9CED6), at: left, 300, width: 780)
draw("Voice-following prompter  ·  hidden from screen shares  ·  open source", .systemFont(ofSize: 24, weight: .regular), color(0x9BA3AF), at: left, 430, width: 800)
draw("getbema.dev", .monospacedSystemFont(ofSize: 24, weight: .semibold), color(0xF5A524), at: left, 488)

NSGraphicsContext.restoreGraphicsState()
let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".").appendingPathComponent("site/brand/bema-social.png")
try! rep.representation(using: .png, properties: [:])!.write(to: out)
print(out.path)
