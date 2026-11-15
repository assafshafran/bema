import Foundation
import Sparkle
import SwiftUI

/// Automatic updates with Sparkle: a check once a day against https://getbema.dev/appcast.xml,
/// only the app's version is sent, and an update installs only with a valid EdDSA signature.
/// Only release builds update: development builds have no feed URL, and tests never start the updater.
@MainActor
final class Updates: ObservableObject {
    static let shared = Updates()

    private let controller: SPUStandardUpdaterController?
    @Published private(set) var canCheck = false

    private init() {
        if Self.isActive {
            let c = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
            controller = c
            c.updater.publisher(for: \.canCheckForUpdates).receive(on: RunLoop.main).assign(to: &$canCheck)
        } else {
            controller = nil
        }
    }

    /// A release build with a feed and a signing key, not running under XCTest.
    static var isActive: Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let feed = info["SUFeedURL"] as? String ?? ""
        let key = info["SUPublicEDKey"] as? String ?? ""
        let testing = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
            || NSClassFromString("XCTestCase") != nil
        return !feed.isEmpty && !key.isEmpty && !testing
    }

    var isAvailable: Bool { controller != nil }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            controller?.updater.automaticallyChecksForUpdates = newValue
            objectWillChange.send()
        }
    }
}
