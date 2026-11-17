import AppKit
import ApplicationServices
import os

/// How the "Present with Bema" button in PowerPoint reaches Bema without PowerPoint's
/// "add-in wants to open Bema.app" prompt. PowerPoint blocks its add-ins from connecting to anything
/// on the Mac and asks before every link, but an add-in may open a dialog. So the button opens a tiny
/// dialog titled "Opening Bema…"; Bema, watching PowerPoint through Accessibility, closes it and
/// presents the deck in front. If Bema doesn't close it, the add-in falls back to the bema:// link.
enum PowerPointButtonDialog {
    /// The dialog page's own title (site/office/present.html).
    static let marker = "Opening Bema"
    /// PowerPoint for Mac titles an add-in's dialog with the add-in's name (the manifest's DisplayName).
    static let addinName = "Bema"

    /// A dialog (never a deck's window) titled with Bema's add-in name or the page's title.
    static func isBemaDialog(title: String?, subrole: String?) -> Bool {
        guard subrole == kAXDialogSubrole as String, let title else { return false }
        let t = title.trimmingCharacters(in: .whitespaces)
        return t == addinName || t.localizedCaseInsensitiveContains(marker)
    }
}

/// Watches PowerPoint's windows while the Bema button is installed and Bema has Accessibility.
@MainActor
final class PowerPointButtonWatcher {
    static let shared = PowerPointButtonWatcher()
    /// What the button did, never the deck's name or location.
    nonisolated static let log = Logger(subsystem: "dev.getbema.Bema", category: "powerpoint-button")

    private var observer: AXObserver?
    private var watchedPID: pid_t = 0
    private var workspaceObservers: [Any] = []
    private var lastHandled = Date.distantPast

    /// Start or stop to match whether the button is installed and PowerPoint is running.
    func update() {
        if workspaceObservers.isEmpty {
            let center = NSWorkspace.shared.notificationCenter
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { note in
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    guard app?.bundleIdentifier == PowerPointController.bundleID else { return }
                    MainActor.assumeIsolated { PowerPointButtonWatcher.shared.update() }
                })
            }
        }
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: PowerPointController.bundleID).first?.processIdentifier
        guard PowerPointAddin.isInstalled, AXIsProcessTrusted(), let pid else { stop(); return }
        guard pid != watchedPID || observer == nil else { return }
        stop()
        start(pid: pid)
    }

    private func start(pid: pid_t) {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, element, _, _ in
            MainActor.assumeIsolated { PowerPointButtonWatcher.shared.windowAppeared(element) }
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else {
            Self.log.error("Couldn't watch PowerPoint's windows")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXObserverAddNotification(created, app, kAXWindowCreatedNotification as CFString, nil)
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
        watchedPID = pid
        Self.log.notice("Watching PowerPoint for the Bema button")
    }

    func stop() {
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode) }
        observer = nil
        watchedPID = 0
    }

    /// A new PowerPoint window. Its title may arrive after the page loads, so look again shortly.
    private func windowAppeared(_ window: AXUIElement) {
        for delay in [0.0, 0.15, 0.4, 0.8] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.check(window) }
        }
    }

    private func check(_ window: AXUIElement) {
        let title: String? = AX.attribute(window, kAXTitleAttribute)
        let subrole: String? = AX.attribute(window, kAXSubroleAttribute)
        guard PowerPointButtonDialog.isBemaDialog(title: title, subrole: subrole) else { return }
        // One click opens one dialog; ignore the repeat looks at the same window.
        guard Date().timeIntervalSince(lastHandled) > 1.5 else { return }
        lastHandled = Date()
        Self.log.notice("PowerPoint button: dialog seen, presenting the deck in front")
        if let close: AXUIElement = AX.attribute(window, kAXCloseButtonAttribute) {
            AXUIElementPerformAction(close, kAXPressAction as CFString)
        }
        NSApp.activate()
        PresenterModel.shared.presentOpenDeck()
    }
}
