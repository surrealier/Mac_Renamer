import Foundation

public enum Validation {
    /// Characters macOS does not allow in a file name. `:` is the classic Mac path separator
    /// (Finder shows it as `/`), so it is blocked too.
    public static let illegalCharacters: Set<Character> = ["/", ":", "\u{0}"]

    /// Longest name APFS and HFS+ accept, in UTF-8 bytes.
    public static let maxNameBytes = 255

    /// Checks the dialog input as a whole. Returns a message for the status line, or nil when OK.
    public static func optionsError(_ options: RenameOptions) -> String? {
        if options.prefix.isEmpty && options.suffix.isEmpty && options.counter == nil && !options.hasRemove {
            return "Enter something to add or remove."
        }
        if (options.prefix + options.suffix).contains(where: { illegalCharacters.contains($0) }) {
            return "Illegal characters not allowed:  /  :"
        }
        return nil
    }

    /// Per-item checks on the resulting name. Returns the skip reason, or nil when OK.
    public static func resultNameError(_ newName: String, original: String) -> String? {
        if newName.isEmpty {
            return "resulting name is empty"
        }
        if newName == "." || newName == ".." {
            return "“.” and “..” are reserved names"
        }
        if newName.contains(where: { illegalCharacters.contains($0) }) {
            return "name contains / or :"
        }
        if newName.utf8.count > maxNameBytes {
            return "name is too long (over \(maxNameBytes) bytes)"
        }
        if newName.hasPrefix(".") && !original.hasPrefix(".") {
            return "name would start with a period and become hidden"
        }
        return nil
    }
}
