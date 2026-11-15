import AppKit
import ServiceManagement
import SwiftUI

/// The A2 mark as a menu bar template image: macOS tints it for light and dark menu bars.
enum MenuBarIcon {
    static let image: NSImage = {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let u = rect.width / 52          // the mark spans 52 units of its 64-unit grid
            func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.midX + (x - 32.5) * u, y: rect.midY + (y - 30) * u) }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineCap(.round)
            ctx.setLineWidth(8 * u)
            ctx.move(to: p(16, 8)); ctx.addLine(to: p(16, 52)); ctx.strokePath()
            ctx.addPath(CGPath(roundedRect: CGRect(origin: p(16, 25), size: CGSize(width: 33 * u, height: 27 * u)),
                               cornerWidth: 10 * u, cornerHeight: 10 * u, transform: nil))
            ctx.strokePath()
            ctx.setLineWidth(6 * u)
            ctx.move(to: p(26.5, 38.5)); ctx.addLine(to: p(38.5, 38.5)); ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Bema"
        return image
    }()
}

/// Open Bema when you log in (System Settings → General → Login Items lists it too).
@MainActor
final class LoginItem: ObservableObject {
    static let shared = LoginItem()
    @Published private(set) var enabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var error: String?

    func set(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            error = nil
        } catch {
            self.error = "Couldn't change Open at Login: \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
        enabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            error = "Allow Bema in System Settings → General → Login Items."
        }
    }
}
