import AppKit
import SwiftUI

/// Bema shows in the Dock (and the app switcher) only while its presenter window is open. The rest of the
/// time it lives in the menu bar, so it can keep running for ⌃⌥P, the PowerPoint button and links without
/// taking a place in the Dock. With the menu bar icon turned off it always stays in the Dock: it quits when
/// its window closes, and the Dock is then the only way back.
enum DockIcon {
    static func policy(presenterWindowOpen: Bool, menuBarIconOn: Bool) -> NSApplication.ActivationPolicy {
        presenterWindowOpen || !menuBarIconOn ? .regular : .accessory
    }

    /// The presenter window is open: on screen, or minimised to the Dock.
    @MainActor static var presenterWindowOpen: Bool {
        NSApp.windows.contains { w in
            w.identifier?.rawValue.hasPrefix("main") == true && (w.isVisible || w.isMiniaturized)
        }
    }

    @MainActor static var menuBarIconOn: Bool {
        UserDefaults.standard.object(forKey: "showMenuBar") as? Bool ?? true
    }

    /// Applies the right policy if it changed. Cheap, so it runs after every event.
    @MainActor static func update() {
        let wanted = policy(presenterWindowOpen: presenterWindowOpen, menuBarIconOn: menuBarIconOn)
        guard NSApp.activationPolicy() != wanted, NSApp.activationPolicy() != .prohibited else { return }
        NSApp.setActivationPolicy(wanted)
        // Coming back to the Dock: bring Bema forward so its menus show.
        if wanted == .regular { NSApp.activate() }
    }
}

/// SwiftUI's window opener, kept from the first Bema view that appears (the presenter window or the menu
/// bar panel), so the presenter window can open again after it was closed.
@MainActor enum MainWindowRef {
    static var opener: OpenWindowAction?
}
