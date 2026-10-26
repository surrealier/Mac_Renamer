import AppKit

// Mac_Renamer — Finder batch prefix/suffix renamer (menu bar app).
//
// Select files/folders in Finder (or on the Desktop) and press ⌥F2. A small dialog lets you type
// a PREFIX and a SUFFIX with a live preview, then renames every selected item — keeping the
// original name, adding the prefix to the front and the suffix BEFORE the extension.
//
//   report.pdf  --(prefix "2024_", suffix "_final")-->  2024_report_final.pdf

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first ?? "" {
case "--version":
    print(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
    exit(0)
case "--snapshot":
    exit(Snapshot.run(outputDirectory: arguments.dropFirst().first ?? "."))
case "--uninstall":
    exit(Uninstall.run())
default:
    break // anything else (e.g. -psn_… from older launchers) is ignored
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
