import AppKit
import SwiftUI

/// What the mouse does over the current slide in the presenter window.
enum PointerTool: String, CaseIterable, Identifiable {
    case none, laser, spotlight, magnifier, pen, highlighter, stamp
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: return "Mouse pointer: the audience sees your pointer on the slide"
        case .laser: return "Laser pointer (L)"
        case .spotlight: return "Spotlight (S)"
        case .magnifier: return "Magnifier (M)"
        case .pen: return "Pen (P)"
        case .highlighter: return "Highlighter (H)"
        case .stamp: return "Stamp (T)"
        }
    }

    var symbol: String {
        switch self {
        case .none: return "cursorarrow"
        case .laser: return "smallcircle.filled.circle"
        case .spotlight: return "circle.dashed.inset.filled"
        case .magnifier: return "plus.magnifyingglass"
        case .pen: return "pencil.tip"
        case .highlighter: return "highlighter"
        case .stamp: return "seal"
        }
    }

    enum SlideInput { case hoverOnly, full }

    /// How the presenter's slide listens to the mouse. The plain pointer only follows it (for the
    /// audience's arrow): clicks and the pointer's shape stay as they are, with no ripples.
    var slideInput: SlideInput { self == .none ? .hoverOnly : .full }

    /// Tools that follow the mouse while hovering. The plain pointer does too: the audience sees an
    /// arrow where the presenter's mouse is over the slide.
    var followsHover: Bool { self == .none || self == .laser || self == .spotlight || self == .magnifier || self == .stamp }
}

enum LaserStyle: String, CaseIterable, Identifiable {
    case dot, hand, wand, comet, plane
    var id: String { rawValue }
    var label: String {
        switch self {
        case .dot: return "Red dot"
        case .hand: return "Pointing hand"
        case .wand: return "Magic wand"
        case .comet: return "Comet trail"
        case .plane: return "Paper plane"
        }
    }
    var symbol: String {
        switch self {
        case .dot: return "smallcircle.filled.circle"
        case .hand: return "hand.point.up.left.fill"
        case .wand: return "wand.and.stars"
        case .comet: return "sparkle"
        case .plane: return "paperplane.fill"
        }
    }
    var usesTrail: Bool { self == .wand || self == .comet || self == .plane }
}

enum StampKind: String, CaseIterable, Identifiable {
    case check, cross, star, exclaim, ring, wow
    var id: String { rawValue }
    var label: String {
        switch self {
        case .check: return "Check"
        case .cross: return "Cross"
        case .star: return "Star"
        case .exclaim: return "Exclamation"
        case .ring: return "Circle"
        case .wow: return "WOW"
        }
    }
    var symbol: String {
        switch self {
        case .check: return "checkmark.circle.fill"
        case .cross: return "xmark.circle.fill"
        case .star: return "star.fill"
        case .exclaim: return "exclamationmark.circle.fill"
        case .ring: return "circle"
        case .wow: return "burst.fill"
        }
    }
    var color: Color {
        switch self {
        case .check: return Color(hex: 0x2FBF71)
        case .cross: return Color(hex: 0xE5352B)
        case .star: return Color(hex: 0xF5B301)
        case .exclaim: return Color(hex: 0xF57C00)
        case .ring: return Color(hex: 0xE5352B)
        case .wow: return Color(hex: 0xF5A524)
        }
    }
}

enum ReactionKind: String, CaseIterable, Identifiable {
    case confetti, applause, hearts
    var id: String { rawValue }
    var label: String {
        switch self {
        case .confetti: return "Confetti (1)"
        case .applause: return "Applause (2)"
        case .hearts: return "Hearts (3)"
        }
    }
    var symbol: String {
        switch self {
        case .confetti: return "party.popper.fill"
        case .applause: return "hands.clap.fill"
        case .hearts: return "heart.fill"
        }
    }
    var duration: TimeInterval { self == .confetti ? 3.2 : 2.8 }
}

/// A pen or highlighter stroke. Points are normalized to the slide (0...1, top-left origin),
/// so the same stroke draws correctly on the presenter preview and the audience display.
struct Stroke: Identifiable {
    let id = UUID()
    let tool: PointerTool
    var points: [CGPoint]
}

struct Stamp: Identifiable {
    let id = UUID()
    let kind: StampKind
    let point: CGPoint
}

struct Ripple: Identifiable {
    let id = UUID()
    let point: CGPoint
    let start: Date
}

struct TrailPoint {
    let point: CGPoint
    let time: Date
}

struct Reaction {
    let kind: ReactionKind
    let start: Date
    let seed: UInt64
}

/// Small deterministic random numbers, so animated particles look the same on every redraw.
struct SeededRandom {
    private var state: UInt64
    init(_ seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
    mutating func next() -> Double {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return Double((state >> 11) & ((1 << 53) - 1)) / Double(1 << 53)
    }
}

// MARK: - Drawing

/// Draws drawings, stamps, the pointer and effects. Used both on the presenter's current slide
/// and over the slide on the audience display.
struct AnnotationCanvas: View {
    @EnvironmentObject private var model: PresenterModel
    /// Over the audience's slide. The plain pointer is drawn only there: the presenter has the real one.
    var audience = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !model.effectsAnimating)) { timeline in
            Canvas { ctx, size in
                let now = timeline.date
                for stroke in model.strokes + (model.activeStroke.map { [$0] } ?? []) {
                    draw(stroke, in: &ctx, size: size)
                }
                for stamp in model.stamps { draw(stamp, in: &ctx, size: size) }
                if let p = model.laserPoint {
                    let center = CGPoint(x: p.x * size.width, y: p.y * size.height)
                    switch model.tool {
                    case .spotlight: drawSpotlight(at: center, in: &ctx, size: size)
                    case .magnifier: drawMagnifier(at: center, normalized: p, in: &ctx, size: size)
                    case .laser: drawLaser(at: center, in: &ctx, size: size, now: now)
                    case .stamp: drawStampPreview(at: center, in: &ctx, size: size)
                    case .none where audience: drawArrow(at: center, in: &ctx, size: size)
                    default: break
                    }
                }
                for ripple in model.ripples { drawRipple(ripple, in: &ctx, size: size, now: now) }
                if let reaction = model.reaction { drawReaction(reaction, in: &ctx, size: size, now: now) }
            }
        }
        .allowsHitTesting(false)
    }

    /// A Mac arrow pointer with its tip at `tip`, sized to the slide like a pointer on a screen that size.
    private func drawArrow(at tip: CGPoint, in ctx: inout GraphicsContext, size: CGSize) {
        let path = PointerArrow.path(tip: tip, height: PointerArrow.height(forSlideHeight: size.height))
        var layer = ctx
        layer.addFilter(.shadow(color: .black.opacity(0.35), radius: 2, y: 1))
        layer.fill(path, with: .color(.black))
        ctx.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: max(2, PointerArrow.height(forSlideHeight: size.height) / 8), lineJoin: .round))
        ctx.fill(path, with: .color(.black))
    }

    private func pt(_ p: CGPoint, _ size: CGSize) -> CGPoint { CGPoint(x: p.x * size.width, y: p.y * size.height) }

    private func circle(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2))
    }

    private func draw(_ stroke: Stroke, in ctx: inout GraphicsContext, size: CGSize) {
        guard let first = stroke.points.first else { return }
        var path = Path()
        path.move(to: pt(first, size))
        if stroke.points.count == 1 { path.addLine(to: CGPoint(x: first.x * size.width + 0.1, y: first.y * size.height)) }
        for p in stroke.points.dropFirst() { path.addLine(to: pt(p, size)) }
        switch stroke.tool {
        case .highlighter:
            ctx.stroke(path, with: .color(Color(red: 1, green: 0.92, blue: 0).opacity(0.42)),
                       style: StrokeStyle(lineWidth: max(size.width * 0.022, 8), lineCap: .round, lineJoin: .round))
        default:
            ctx.stroke(path, with: .color(Color(red: 0.9, green: 0.1, blue: 0.1)),
                       style: StrokeStyle(lineWidth: max(size.width * 0.0035, 2), lineCap: .round, lineJoin: .round))
        }
    }

    private func draw(_ stamp: Stamp, in ctx: inout GraphicsContext, size: CGSize) {
        let c = pt(stamp.point, size)
        let s = max(size.width * 0.06, 22)
        switch stamp.kind {
        case .ring:
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - s * 1.3, y: c.y - s * 0.85, width: s * 2.6, height: s * 1.7)),
                       with: .color(stamp.kind.color), style: StrokeStyle(lineWidth: max(size.width * 0.005, 3), lineCap: .round))
        case .wow:
            var burst = ctx.resolve(Image(systemName: "burst.fill"))
            burst.shading = .color(stamp.kind.color)
            ctx.draw(burst, in: CGRect(x: c.x - s * 1.1, y: c.y - s * 1.1, width: s * 2.2, height: s * 2.2))
            ctx.draw(Text("WOW!").font(.system(size: s * 0.55, weight: .black)).foregroundColor(.white), at: c)
        default:
            var img = ctx.resolve(Image(systemName: stamp.kind.symbol))
            img.shading = .color(stamp.kind.color)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.35), radius: 4, y: 2))
            shadowed.draw(img, in: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
        }
    }

    private func drawStampPreview(at c: CGPoint, in ctx: inout GraphicsContext, size: CGSize) {
        let s = max(size.width * 0.06, 22)
        var img = ctx.resolve(Image(systemName: model.stampKind == .ring ? "circle" : model.stampKind.symbol))
        img.shading = .color(model.stampKind.color.opacity(0.4))
        ctx.draw(img, in: CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
    }

    private func drawSpotlight(at c: CGPoint, in ctx: inout GraphicsContext, size: CGSize) {
        let r = max(size.width * 0.12, 60)
        var path = Path(CGRect(origin: .zero, size: size))
        path.addPath(circle(c, r))
        ctx.drawLayer { layer in
            layer.addFilter(.blur(radius: r * 0.12))
            layer.fill(path, with: .color(.black.opacity(0.68)), style: FillStyle(eoFill: true))
        }
    }

    private func drawMagnifier(at c: CGPoint, normalized p: CGPoint, in ctx: inout GraphicsContext, size: CGSize) {
        let r = max(size.width * 0.11, 55)
        let zoom: CGFloat = 2.2
        let lens = circle(c, r)
        var shadow = ctx
        shadow.addFilter(.shadow(color: .black.opacity(0.45), radius: 12, y: 6))
        shadow.fill(lens, with: .color(.white))
        if let image = model.image(for: model.current, width: size.width * zoom) {
            ctx.drawLayer { layer in
                layer.clip(to: lens)
                let rect = CGRect(x: c.x - p.x * size.width * zoom, y: c.y - p.y * size.height * zoom,
                                  width: size.width * zoom, height: size.height * zoom)
                layer.draw(Image(nsImage: image).resizable(), in: rect)
            }
        }
        ctx.stroke(lens, with: .color(.white), lineWidth: 4)
        ctx.stroke(circle(c, r + 2), with: .color(.black.opacity(0.25)), lineWidth: 1)
    }

    private func drawLaser(at c: CGPoint, in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let r = max(size.width * 0.007, 5)
        let trail = model.laserTrail.filter { now.timeIntervalSince($0.time) < 0.6 }
        switch model.laserStyle {
        case .dot:
            ctx.fill(circle(c, r * 2.4), with: .color(.red.opacity(0.18)))
            ctx.fill(circle(c, r * 1.5), with: .color(.red.opacity(0.35)))
            ctx.fill(circle(c, r), with: .color(Color(red: 1, green: 0.1, blue: 0.1)))
            ctx.fill(circle(c, r * 0.4), with: .color(.white.opacity(0.8)))
        case .hand:
            let s = max(size.width * 0.045, 28)
            // The fingertip sits near the symbol's top-left corner. A dark outline keeps it visible on white slides.
            let rect = CGRect(x: c.x - s * 0.18, y: c.y - s * 0.04, width: s, height: s)
            var outline = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            outline.shading = .color(Color(hex: 0x14161B))
            for (dx, dy) in [(-1.5, 0.0), (1.5, 0.0), (0.0, -1.5), (0.0, 1.5)] {
                ctx.draw(outline, in: rect.offsetBy(dx: dx, dy: dy))
            }
            var img = ctx.resolve(Image(systemName: "hand.point.up.left.fill"))
            img.shading = .color(.white)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.45), radius: 5, y: 2))
            shadowed.draw(img, in: rect)
        case .wand:
            for (i, t) in trail.enumerated() {
                let age = now.timeIntervalSince(t.time) / 0.6
                var rnd = SeededRandom(UInt64(i) &* 7919 &+ UInt64(t.time.timeIntervalSince1970 * 1000))
                let q = pt(t.point, size)
                let jitter = CGPoint(x: q.x + CGFloat(rnd.next() - 0.5) * r * 6, y: q.y + CGFloat(rnd.next() - 0.5) * r * 6 + CGFloat(age) * r * 4)
                var star = ctx.resolve(Image(systemName: "sparkle"))
                star.shading = .color([Color(hex: 0xFFD54F), Color(hex: 0xFFFFFF), Color(hex: 0x80DEEA)][i % 3].opacity(1 - age))
                let ss = r * (2.6 - 1.6 * age)
                ctx.draw(star, in: CGRect(x: jitter.x - ss / 2, y: jitter.y - ss / 2, width: ss, height: ss))
            }
            let s = max(size.width * 0.04, 26)
            var wand = ctx.resolve(Image(systemName: "wand.and.stars"))
            wand.shading = .color(.white)
            var shadowed = ctx
            shadowed.addFilter(.shadow(color: .black.opacity(0.5), radius: 4, y: 2))
            shadowed.draw(wand, in: CGRect(x: c.x - s * 0.15, y: c.y - s * 0.12, width: s, height: s))
        case .comet:
            let pts = trail.map { pt($0.point, size) } + [c]
            if pts.count > 1 {
                for i in 1..<pts.count {
                    let f = CGFloat(i) / CGFloat(pts.count)
                    var seg = Path(); seg.move(to: pts[i - 1]); seg.addLine(to: pts[i])
                    ctx.stroke(seg, with: .color(Color(hex: 0xFF8A3D).opacity(Double(f) * 0.9)),
                               style: StrokeStyle(lineWidth: r * 2.2 * f, lineCap: .round))
                }
            }
            ctx.fill(circle(c, r * 2.2), with: .color(Color(hex: 0xFFB74D).opacity(0.35)))
            ctx.fill(circle(c, r * 1.1), with: .color(Color(hex: 0xFFF3E0)))
        case .plane:
            for (i, t) in trail.enumerated() where i % 2 == 0 {
                let age = now.timeIntervalSince(t.time) / 0.6
                ctx.fill(circle(pt(t.point, size), r * 0.35), with: .color(.white.opacity(0.8 * (1 - age))))
            }
            var angle = Angle.degrees(-45)
            if let last = trail.last {
                let q = pt(last.point, size)
                if hypot(c.x - q.x, c.y - q.y) > 1 { angle = .radians(atan2(c.y - q.y, c.x - q.x)) }
            }
            let s = max(size.width * 0.04, 26)
            var plane = ctx.resolve(Image(systemName: "paperplane.fill"))
            plane.shading = .color(.white)
            var layer = ctx
            layer.translateBy(x: c.x, y: c.y)
            layer.rotate(by: angle + .degrees(45)) // the symbol points up-right
            layer.addFilter(.shadow(color: .black.opacity(0.5), radius: 4, y: 2))
            layer.draw(plane, in: CGRect(x: -s / 2, y: -s / 2, width: s, height: s))
        }
    }

    private func drawRipple(_ ripple: Ripple, in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSince(ripple.start) / 0.7
        guard t >= 0, t < 1 else { return }
        let c = pt(ripple.point, size)
        let r = max(size.width * 0.01, 8) + CGFloat(t) * max(size.width * 0.035, 30)
        ctx.stroke(circle(c, r), with: .color(Theme.accent.opacity(0.9 * (1 - t))), lineWidth: 3)
        ctx.stroke(circle(c, r * 0.6), with: .color(.white.opacity(0.6 * (1 - t))), lineWidth: 2)
    }

    private func drawReaction(_ reaction: Reaction, in ctx: inout GraphicsContext, size: CGSize, now: Date) {
        let t = now.timeIntervalSince(reaction.start)
        guard t >= 0, t < reaction.kind.duration else { return }
        var rnd = SeededRandom(reaction.seed)
        switch reaction.kind {
        case .confetti:
            let colors: [Color] = [Color(hex: 0xF5A524), Color(hex: 0xFF5A4F), Color(hex: 0x4BE3A0), Color(hex: 0x5B9DFF), Color(hex: 0xC792EA), .white]
            for i in 0..<140 {
                let x0 = rnd.next(), vx = (rnd.next() - 0.5) * 0.25, delay = rnd.next() * 0.6
                let vy = 0.15 + rnd.next() * 0.35, spin = (rnd.next() - 0.5) * 12, w = 6 + rnd.next() * 8
                let tt = t - delay
                guard tt > 0 else { continue }
                let x = (x0 + vx * tt) * size.width
                let y = (-0.05 + vy * tt + 0.18 * tt * tt) * size.height
                guard y < size.height + 20 else { continue }
                var layer = ctx
                layer.translateBy(x: x, y: y)
                layer.rotate(by: .radians(spin * tt))
                layer.opacity = min(1, (reaction.kind.duration - t) / 0.6)
                layer.fill(Path(CGRect(x: -w / 2, y: -w / 4, width: w, height: w / 2)), with: .color(colors[i % colors.count]))
            }
        case .applause, .hearts:
            let symbol = reaction.kind == .applause ? "hands.clap.fill" : "heart.fill"
            let tint = reaction.kind == .applause ? Color(hex: 0xFFC35C) : Color(hex: 0xFF5A7A)
            for _ in 0..<26 {
                let x0 = 0.05 + rnd.next() * 0.9, delay = rnd.next() * 1.2, speed = 0.25 + rnd.next() * 0.3
                let s = max(size.width * 0.035, 22) * CGFloat(0.7 + rnd.next() * 0.8), wobble = rnd.next() * 6
                let tt = t - delay
                guard tt > 0 else { continue }
                let x = (x0 + 0.02 * sin(tt * 4 + wobble)) * size.width
                let y = size.height * (1.05 - speed * tt)
                var img = ctx.resolve(Image(systemName: symbol))
                img.shading = .color(tint)
                var layer = ctx
                layer.opacity = max(0, min(1, (1.6 - tt) / 0.5))
                layer.addFilter(.shadow(color: .black.opacity(0.3), radius: 3, y: 1))
                layer.draw(img, in: CGRect(x: x - s / 2, y: y - s / 2, width: s, height: s))
            }
        }
    }
}

/// The plain pointer over the presenter's slide: reports where the mouse is so the audience sees an
/// arrow there, and nothing else.
struct PointerHoverInput: View {
    @EnvironmentObject private var model: PresenterModel

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let loc):
                        model.movePointer(to: CGPoint(x: min(max(loc.x / max(geo.size.width, 1), 0), 1),
                                                      y: min(max(loc.y / max(geo.size.height, 1), 0), 1)))
                    case .ended: model.laserPoint = nil
                    }
                }
        }
    }
}

/// Mouse input over the presenter's current slide: hover moves the pointer, clicking stamps,
/// dragging draws.
struct AnnotationInput: View {
    @EnvironmentObject private var model: PresenterModel
    @State private var pressStarted = false

    var body: some View {
        GeometryReader { geo in
            Color.clear
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let loc): model.movePointer(to: normalize(loc, geo.size))
                    case .ended: model.laserPoint = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .local)
                        .onChanged { value in
                            let p = normalize(value.location, geo.size)
                            if !pressStarted {
                                pressStarted = true
                                if model.tool != .pen && model.tool != .highlighter { model.addRipple(at: p) }
                            }
                            model.movePointer(to: p)
                            guard model.tool == .pen || model.tool == .highlighter else { return }
                            if model.activeStroke == nil {
                                model.activeStroke = Stroke(tool: model.tool, points: [p])
                            } else {
                                model.activeStroke?.points.append(p)
                            }
                        }
                        .onEnded { value in
                            pressStarted = false
                            if model.tool == .stamp { model.placeStamp(at: normalize(value.location, geo.size)) }
                            model.commitStroke()
                        }
                )
                .onHover { inside in
                    if inside { NSCursor.crosshair.push() } else { NSCursor.pop() }
                }
        }
    }

    private func normalize(_ p: CGPoint, _ size: CGSize) -> CGPoint {
        CGPoint(x: min(max(p.x / max(size.width, 1), 0), 1), y: min(max(p.y / max(size.height, 1), 0), 1))
    }
}

/// A transparent, click-through window placed exactly over the slide on the audience display.
/// It floats above PowerPoint's slideshow, including when that is full screen.
@MainActor
final class AudienceOverlay {
    private var window: NSPanel?

    func show(over frame: CGRect, model: PresenterModel) {
        let w = window ?? makeWindow(model: model)
        window = w
        if w.frame != frame { w.setFrame(frame, display: true) }
        if !w.isVisible { w.orderFrontRegardless() }
    }

    func hide() { window?.orderOut(nil) }

    private func makeWindow(model: PresenterModel) -> NSPanel {
        // A non-activating panel: a plain NSWindow from a regular app doesn't join the Space
        // that another display is showing, even with .canJoinAllSpaces.
        let w = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        w.hidesOnDeactivate = false
        w.becomesKeyOnlyIfNeeded = true
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.ignoresMouseEvents = true
        w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        w.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: AudienceLayer().environmentObject(model))
        host.wantsLayer = true
        host.layer?.backgroundColor = .clear
        w.contentView = host
        return w
    }
}

/// The arrow the audience sees for the plain pointer: the classic Mac pointer shape.
enum PointerArrow {
    /// About 3.5% of the slide's height: a normal pointer on a 1080-line screen.
    static func height(forSlideHeight h: CGFloat) -> CGFloat { max(16, h * 0.035) }

    /// Outline in units of the pointer's height, tip at (0, 0).
    static let outline: [CGPoint] = [
        CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 0.80), CGPoint(x: 0.19, y: 0.62), CGPoint(x: 0.31, y: 0.90),
        CGPoint(x: 0.42, y: 0.85), CGPoint(x: 0.30, y: 0.58), CGPoint(x: 0.55, y: 0.58),
    ]

    static func path(tip: CGPoint, height: CGFloat) -> Path {
        var path = Path()
        path.addLines(outline.map { CGPoint(x: tip.x + $0.x * height, y: tip.y + $0.y * height) })
        path.closeSubpath()
        return path
    }
}
