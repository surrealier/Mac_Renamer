import Foundation
import ServiceManagement

/// "Start at Login" through ServiceManagement (shows up under System Settings › General › Login Items).
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static var needsApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    /// Only a real .app bundle can be a login item (not `swift run`).
    static var isRunningFromAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Like the Windows .exe: register on the first run only, so a later "turn off" stays off.
    static func enableOnFirstRun() {
        let defaults = UserDefaults.standard
        guard isRunningFromAppBundle, !defaults.bool(forKey: DefaultsKey.loginItemInitialized) else { return }
        defaults.set(true, forKey: DefaultsKey.loginItemInitialized)
        do {
            try set(enabled: true)
        } catch {
            NSLog("Mac_Renamer: could not add the login item: \(error.localizedDescription)")
        }
    }
}
