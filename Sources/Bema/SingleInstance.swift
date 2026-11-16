import AppKit

/// One Bema at a time. With two copies installed (a release in /Applications and another elsewhere),
/// macOS can start the second copy to open a deck or a bema:// link while the first is running, and the
/// deck then loads in a window the presenter isn't looking at. The second copy hands what it was asked to
/// open to the one already running, and quits.
enum SingleInstance {
    struct Instance: Equatable {
        let pid: pid_t
        let bundleURL: URL?
        let launched: Date?
    }

    /// The Bema already running that this one should defer to: the earliest launched other than itself.
    static func running(among others: [Instance], me: pid_t) -> Instance? {
        others.filter { $0.pid != me }
            .min { ($0.launched ?? .distantPast) < ($1.launched ?? .distantPast) }
    }

    @MainActor static func current() -> Instance? {
        let me = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .filter { !$0.isTerminated }
            .map { Instance(pid: $0.processIdentifier, bundleURL: $0.bundleURL, launched: $0.launchDate) }
        return running(among: others, me: me)
    }

    /// Sends decks and links to the running Bema.
    static func forward(_ urls: [URL], to other: Instance) {
        guard let app = other.bundleURL, !urls.isEmpty else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: config)
    }

    static func activate(_ other: Instance) {
        NSRunningApplication(processIdentifier: other.pid)?.activate()
    }
}
