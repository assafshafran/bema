import AppKit
import Foundation

/// The "Present with Bema" button on PowerPoint's Home tab: an Office add-in served from
/// https://getbema.dev/office/. Installing it puts its manifest (bundled with Bema) in the folder
/// PowerPoint for Mac loads add-ins from; PowerPoint shows the button after it restarts.
enum PowerPointAddin {
    static let fileName = "bema-powerpoint-button.xml"

    /// PowerPoint for Mac's add-in folder.
    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef", isDirectory: true)
    }

    static var installedURL: URL { folder.appendingPathComponent(fileName) }
    static var isInstalled: Bool { FileManager.default.fileExists(atPath: installedURL.path) }

    static var bundledManifest: URL? { Bundle.main.url(forResource: "PowerPointAddin", withExtension: "xml") }

    enum Failure: LocalizedError {
        case noPowerPoint, missingManifest, cantWrite(String)
        var errorDescription: String? {
            switch self {
            case .noPowerPoint: return "PowerPoint isn't installed, so there's nowhere to add the button."
            case .missingManifest: return "This copy of Bema doesn't include the PowerPoint button. Download Bema from getbema.dev."
            case .cantWrite(let why): return "Couldn't add the button to PowerPoint: \(why)"
            }
        }
    }

    static func install() throws {
        guard PowerPointController.isInstalled else { throw Failure.noPowerPoint }
        guard let source = bundledManifest else { throw Failure.missingManifest }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            if FileManager.default.fileExists(atPath: installedURL.path) { try FileManager.default.removeItem(at: installedURL) }
            try FileManager.default.copyItem(at: source, to: installedURL)
        } catch let error as NSError where error.code == NSFileWriteNoPermissionError || error.code == NSFileReadNoPermissionError
                    || (error.domain == NSPOSIXErrorDomain && error.code == Int(EPERM)) {
            throw Failure.cantWrite("macOS didn't let Bema into PowerPoint's folder. Allow it in System Settings → Privacy & Security → Files & Folders → Bema → Microsoft PowerPoint, then try again.")
        } catch {
            throw Failure.cantWrite(error.localizedDescription)
        }
        // macOS can ask for access while the copy is already refused: make sure the file really landed.
        guard FileManager.default.fileExists(atPath: installedURL.path) else {
            throw Failure.cantWrite("macOS may still be asking for permission. Allow Bema to access PowerPoint's data, then try again.")
        }
    }

    static func remove() throws {
        guard isInstalled else { return }
        do { try FileManager.default.removeItem(at: installedURL) } catch { throw Failure.cantWrite(error.localizedDescription) }
    }
}

extension PresenterModel {
    func installPowerPointButton() {
        do {
            try PowerPointAddin.install()
            PowerPointButtonWatcher.shared.update()
            notice = SlideshowApps.isRunning(PowerPointController.bundleID)
                ? "The Bema button is added. Quit and reopen PowerPoint, then find Present with Bema on the Home tab."
                : "The Bema button is added. Open PowerPoint and find Present with Bema on the Home tab."
        } catch {
            notice = error.localizedDescription
        }
    }

    func removePowerPointButton() {
        do {
            try PowerPointAddin.remove()
            PowerPointButtonWatcher.shared.update()
            notice = "The Bema button is removed from PowerPoint. It disappears after PowerPoint restarts."
        } catch {
            notice = error.localizedDescription
        }
    }
}
