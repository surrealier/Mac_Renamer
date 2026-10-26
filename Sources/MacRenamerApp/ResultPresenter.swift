import AppKit
import RenamerCore

/// The summary shown after a batch, with an Undo button when something was renamed.
enum ResultPresenter {
    /// Returns true when the user clicked "Undo".
    @discardableResult
    static func show(_ result: RenameResult, verb: String = "renamed", offerUndo: Bool) -> Bool {
        let alert = NSAlert()
        let n = result.renamedCount
        alert.messageText = "\(n) item\(n == 1 ? "" : "s") \(verb)."
        alert.informativeText = (section(result.skipped, "Skipped") + section(result.failed, "Failed"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        alert.alertStyle = result.hasProblems ? .warning : .informational
        alert.addButton(withTitle: "OK")
        if offerUndo && n > 0 {
            alert.addButton(withTitle: "Undo")
        }
        activateApp()
        return alert.runModal() == .alertSecondButtonReturn
    }

    static func section(_ items: [RenameIssue], _ label: String) -> String {
        guard !items.isEmpty else { return "" }
        var text = "\n\n\(label) (\(items.count)):"
        for item in items.prefix(15) {
            text += "\n  • \(item.source.lastPathComponent)  →  \(item.reason)"
        }
        if items.count > 15 {
            text += "\n  … and \(items.count - 15) more"
        }
        return text
    }

    static func message(_ text: String, info: String = "", style: NSAlert.Style = .warning) {
        let alert = NSAlert()
        alert.messageText = text
        alert.informativeText = info
        alert.alertStyle = style
        alert.addButton(withTitle: "OK")
        activateApp()
        alert.runModal()
    }
}
