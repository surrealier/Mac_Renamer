import AppKit

enum FinderSelectionError: Error {
    /// The user said no (or has not been asked yet) under Privacy & Security › Automation.
    case notAuthorized
    case finderNotRunning
    case scriptFailed(String)
}

/// Reads the items selected in the frontmost Finder window — the active tab, or the Desktop when
/// the Desktop has focus — by asking Finder over Apple Events.
///
/// The first call makes macOS ask "Mac_Renamer wants access to control Finder".
enum FinderSelection {
    private static let source = """
    tell application "Finder"
        set theItems to selection as alias list
    end tell
    set out to {}
    repeat with f in theItems
        set end of out to POSIX path of (contents of f)
    end repeat
    return out
    """

    static func current() -> Result<[URL], FinderSelectionError> {
        guard let script = NSAppleScript(source: source) else {
            return .failure(.scriptFailed("The selection script could not be compiled."))
        }
        var errorInfo: NSDictionary?
        let descriptor = script.executeAndReturnError(&errorInfo)
        if let errorInfo {
            let code = (errorInfo[NSAppleScript.errorNumber] as? NSNumber)?.intValue ?? 0
            let message = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            switch code {
            case -1743, -1744: return .failure(.notAuthorized)   // errAEEventNotPermitted / wouldRequireUserConsent
            case -600, -609: return .failure(.finderNotRunning)  // procNotFound / connectionInvalid
            default: return .failure(.scriptFailed("\(message) (\(code))"))
            }
        }

        var urls: [URL] = []
        let count = descriptor.numberOfItems
        if count > 0 {
            for i in 1...count {
                if let path = descriptor.atIndex(i)?.stringValue, !path.isEmpty {
                    urls.append(URL(fileURLWithPath: path).standardizedFileURL)
                }
            }
        }
        return .success(urls)
    }

    /// Privacy & Security › Automation in System Settings.
    static func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
