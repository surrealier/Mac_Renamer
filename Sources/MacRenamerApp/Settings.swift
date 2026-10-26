import AppKit
import Carbon.HIToolbox

enum DefaultsKey {
    static let hotKey = "hotKeyPreset"
    static let sortOrder = "sortOrder"
    static let loginItemInitialized = "loginItemInitialized"
    static let welcomeShown = "welcomeShown"
}

/// The hotkey choices offered in the menu. It is only live while Finder is the frontmost app.
enum HotKeyPreset: String, CaseIterable {
    case optionF2
    case controlOptionR
    case off

    static var current: HotKeyPreset {
        get { HotKeyPreset(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.hotKey) ?? "") ?? .optionF2 }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.hotKey) }
    }

    var title: String {
        switch self {
        case .optionF2: return "⌥F2"
        case .controlOptionR: return "⌃⌥R"
        case .off: return "Off"
        }
    }

    /// Carbon key code + modifier mask for RegisterEventHotKey.
    var carbon: (keyCode: UInt32, modifiers: UInt32)? {
        switch self {
        case .optionF2: return (UInt32(kVK_F2), UInt32(optionKey))
        case .controlOptionR: return (UInt32(kVK_ANSI_R), UInt32(controlKey | optionKey))
        case .off: return nil
        }
    }

    /// Shown next to the "Rename Finder Selection…" menu item.
    var menuKeyEquivalent: (key: String, modifiers: NSEvent.ModifierFlags)? {
        switch self {
        case .optionF2:
            guard let scalar = UnicodeScalar(UInt32(NSF2FunctionKey)) else { return nil }
            return (String(Character(scalar)), [.option])
        case .controlOptionR:
            return ("r", [.control, .option])
        case .off:
            return nil
        }
    }
}

/// Order of the items in the dialog, which is also the order the counter follows.
enum SortOrder: String, CaseIterable, Identifiable {
    case name
    case dateModified
    case dateCreated

    var id: String { rawValue }

    static var current: SortOrder {
        get { SortOrder(rawValue: UserDefaults.standard.string(forKey: DefaultsKey.sortOrder) ?? "") ?? .name }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: DefaultsKey.sortOrder) }
    }

    var title: String {
        switch self {
        case .name: return "Name"
        case .dateModified: return "Date Modified"
        case .dateCreated: return "Date Created"
        }
    }

    func sorted(_ urls: [URL]) -> [URL] {
        switch self {
        case .name:
            // Finder's own ordering: "file2" before "file10", case- and accent-aware.
            return urls.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        case .dateModified:
            return sortByDate(urls, key: .contentModificationDateKey)
        case .dateCreated:
            return sortByDate(urls, key: .creationDateKey)
        }
    }

    private func sortByDate(_ urls: [URL], key: URLResourceKey) -> [URL] {
        let dated = urls.map { url -> (URL, Date) in
            let values = try? url.resourceValues(forKeys: [key])
            let date = (key == .creationDateKey ? values?.creationDate : values?.contentModificationDate) ?? .distantPast
            return (url, date)
        }
        return dated.sorted { a, b in
            if a.1 != b.1 { return a.1 < b.1 }
            return a.0.lastPathComponent.localizedStandardCompare(b.0.lastPathComponent) == .orderedAscending
        }.map(\.0)
    }
}
