import AppKit
import SwiftUI

/// Bema's "backstage" look: a dark ground that's easy on the eyes in a dim room,
/// one warm amber accent for live state, and red only for the laser and "live".
enum Theme {
    static var ground: Color { palette.ground }
    static var bar: Color { palette.bar }
    static var panel: Color { palette.panel }
    static var raised: Color { palette.raised }
    static var selected: Color { palette.selected }
    static var border: Color { palette.border }
    static var borderStrong: Color { palette.borderStrong }

    static var text: Color { palette.text }
    static var textBright: Color { palette.textBright }
    static var textSoft: Color { palette.textSoft }
    static var muted: Color { palette.muted }
    static var dim: Color { palette.dim }

    static var accent: Color { palette.accent }
    static var accentInk: Color { palette.accentInk }
    static let live = Color(hex: 0xFF5A4F)
    static let liveSoft = Color(hex: 0xFF8F87)
    static let liveBg = Color(hex: 0x3A1A1A)
    static let laser = Color(hex: 0xFF6B60)
    static let danger = Color(hex: 0xFFB4AE)
    static let dangerBg = Color(hex: 0x2A1617)
    static let dangerBorder = Color(hex: 0x4A2A2A)
    static let ok = Color(hex: 0x4BE3A0)
    static let okBg = Color(hex: 0x16352A)
    static var warnBg: Color { palette.warnBg }
    static var warnBorder: Color { palette.warnBorder }
    static var warnText: Color { palette.warnText }
    static var warnStrong: Color { palette.warnStrong }

    static var nsGround: NSColor { NSColor(ground) }
    static var nsBar: NSColor { NSColor(bar) }

    // MARK: Themes

    enum Name: String, CaseIterable, Identifiable {
        case backstage, daylight, contrast
        var id: String { rawValue }
        var label: String {
            switch self {
            case .backstage: return "Backstage (dark)"
            case .daylight: return "Daylight (bright rooms)"
            case .contrast: return "High contrast"
            }
        }
    }

    struct Palette {
        let ground, bar, panel, raised, selected, border, borderStrong: Color
        let text, textBright, textSoft, muted, dim: Color
        let accent, accentInk: Color
        let warnBg, warnBorder, warnText, warnStrong: Color
        let isDark: Bool
    }

    static var name: Name { Name(rawValue: UserDefaults.standard.string(forKey: "theme") ?? "") ?? .backstage }
    static var colorScheme: ColorScheme { palette.isDark ? .dark : .light }
    static var palette: Palette {
        switch name {
        case .backstage: return backstage
        case .daylight: return daylight
        case .contrast: return contrast
        }
    }

    static let backstage = Palette(
        ground: Color(hex: 0x0E1014), bar: Color(hex: 0x12151A), panel: Color(hex: 0x15181E), raised: Color(hex: 0x181B22),
        selected: Color(hex: 0x2B2F3A), border: Color(hex: 0x232731), borderStrong: Color(hex: 0x2A2F3A),
        text: Color(hex: 0xE9EBEF), textBright: Color(hex: 0xF2F4F7), textSoft: Color(hex: 0xC9CED6), muted: Color(hex: 0x9BA3AF), dim: Color(hex: 0x8A93A0),
        accent: Color(hex: 0xF5A524), accentInk: Color(hex: 0x1A1206),
        warnBg: Color(hex: 0x2A2113), warnBorder: Color(hex: 0x5A4520), warnText: Color(hex: 0xD8C9A8), warnStrong: Color(hex: 0xFFC35C),
        isDark: true)

    static let daylight = Palette(
        ground: Color(hex: 0xF3F4F6), bar: Color(hex: 0xFFFFFF), panel: Color(hex: 0xFFFFFF), raised: Color(hex: 0xF1F2F5),
        selected: Color(hex: 0xE2E5EA), border: Color(hex: 0xE1E4EA), borderStrong: Color(hex: 0xD0D5DD),
        text: Color(hex: 0x15181E), textBright: Color(hex: 0x0E1014), textSoft: Color(hex: 0x363C47), muted: Color(hex: 0x5A6271), dim: Color(hex: 0x666E7C),
        accent: Color(hex: 0xA85F00), accentInk: Color(hex: 0xFFFFFF),
        warnBg: Color(hex: 0xFFF4DC), warnBorder: Color(hex: 0xEED39B), warnText: Color(hex: 0x5E4510), warnStrong: Color(hex: 0x8A5500),
        isDark: false)

    static let contrast = Palette(
        ground: Color(hex: 0x000000), bar: Color(hex: 0x0A0A0A), panel: Color(hex: 0x0D0D0D), raised: Color(hex: 0x1A1A1A),
        selected: Color(hex: 0x3A3A3A), border: Color(hex: 0x5A5A5A), borderStrong: Color(hex: 0x7A7A7A),
        text: Color(hex: 0xFFFFFF), textBright: Color(hex: 0xFFFFFF), textSoft: Color(hex: 0xF2F2F2), muted: Color(hex: 0xD6D6D6), dim: Color(hex: 0xC2C2C2),
        accent: Color(hex: 0xFFC233), accentInk: Color(hex: 0x000000),
        warnBg: Color(hex: 0x2E2200), warnBorder: Color(hex: 0xFFC233), warnText: Color(hex: 0xFFF0C2), warnStrong: Color(hex: 0xFFD666),
        isDark: true)

    /// Large numbers (timer, slide count): tight, tabular digits.
    static func numeral(_ size: CGFloat, _ weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

/// Small spaced capitals used for section labels ("ON SCREEN", "UP NEXT").
struct CapsLabel: View {
    let text: String
    var color: Color = Theme.muted

    init(_ text: String, color: Color = Theme.muted) {
        self.text = text
        self.color = color
    }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(1.3)
            .foregroundStyle(color)
    }
}

/// A key hint like "B".
struct Keycap: View {
    let key: String
    var body: some View {
        Text(key)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Theme.dim)
            .padding(.horizontal, 5).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color(hex: 0x343A46)))
    }
}

// MARK: - Buttons

/// Square icon button. `filled` uses the accent (the main "next" action).
struct IconButtonStyle: ButtonStyle {
    var filled = false
    var tint: Color? = nil
    var size: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, filled: filled, tint: tint, size: size)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let filled: Bool
        let tint: Color?
        let size: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(filled ? Theme.accentInk : (tint ?? Theme.text))
                .frame(width: size, height: size)
                .background(RoundedRectangle(cornerRadius: 9).fill(filled ? Theme.accent : Theme.raised))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(filled ? Color.clear : Theme.borderStrong))
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
        }
    }
}

/// Text button in the bar. Kinds match the design: accent (primary), normal, danger, warning.
struct PillButtonStyle: ButtonStyle {
    enum Kind { case accent, normal, danger, warning }
    var kind: Kind = .normal
    var height: CGFloat = 36

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, kind: kind, height: height)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let kind: Kind
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            let (fg, bg, stroke): (Color, Color, Color) = {
                switch kind {
                case .accent: return (Theme.accentInk, Theme.accent, .clear)
                case .normal: return (Theme.text, Theme.raised, Theme.borderStrong)
                case .danger: return (Theme.danger, Theme.dangerBg, Theme.dangerBorder)
                case .warning: return (Color(hex: 0xFFE2A8), Color(hex: 0x3A2D15), Color(hex: 0x6B5326))
                }
            }()
            configuration.label
                .font(.system(size: 13, weight: kind == .normal ? .medium : .semibold))
                .foregroundStyle(fg)
                .padding(.horizontal, 14)
                .frame(height: height)
                .background(RoundedRectangle(cornerRadius: 9).fill(bg))
                .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(stroke))
                .opacity(enabled ? (configuration.isPressed ? 0.75 : 1) : 0.4)
                .contentShape(Rectangle())
        }
    }
}

/// A button inside a segmented group (pointer tools, Notes/Prompter).
struct SegmentButtonStyle: ButtonStyle {
    var isOn: Bool
    var onColor: Color = Theme.text
    var width: CGFloat? = 38
    var height: CGFloat = 30

    func makeBody(configuration: Configuration) -> some View {
        StyledLabel(configuration: configuration, isOn: isOn, onColor: onColor, width: width, height: height)
    }

    private struct StyledLabel: View {
        let configuration: Configuration
        let isOn: Bool
        let onColor: Color
        let width: CGFloat?
        let height: CGFloat
        @Environment(\.isEnabled) private var enabled

        var body: some View {
            configuration.label
                .font(.system(size: 13, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? onColor : Theme.muted)
                .padding(.horizontal, width == nil ? 12 : 0)
                .frame(width: width, height: height)
                .background(RoundedRectangle(cornerRadius: 7).fill(isOn ? Theme.selected : Color.clear))
                .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.4)
                .contentShape(Rectangle())
        }
    }
}

/// The container for a segmented group.
struct SegmentGroup<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        HStack(spacing: 2) { content }
            .padding(3)
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.borderStrong))
    }
}

/// Bema's mark: a screen on a stand with the amber "live" dot.
struct BemaMark: View {
    var size: CGFloat = 30
    var body: some View {
        Canvas { ctx, s in
            let u = s.width / 32
            let screen = Path(roundedRect: CGRect(x: 3 * u, y: 6 * u, width: 20 * u, height: 14 * u), cornerRadius: 2.5 * u)
            ctx.stroke(screen, with: .color(Theme.text), lineWidth: 2 * u)
            var stand = Path()
            stand.move(to: CGPoint(x: 9 * u, y: 26 * u)); stand.addLine(to: CGPoint(x: 17 * u, y: 26 * u))
            stand.move(to: CGPoint(x: 13 * u, y: 20 * u)); stand.addLine(to: CGPoint(x: 13 * u, y: 26 * u))
            ctx.stroke(stand, with: .color(Theme.text), style: StrokeStyle(lineWidth: 2 * u, lineCap: .round))
            ctx.fill(Path(ellipseIn: CGRect(x: 21 * u, y: 5 * u, width: 8 * u, height: 8 * u)), with: .color(Theme.accent))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
