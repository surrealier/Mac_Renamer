import Foundation

/// How an item's name is split before the affixes are applied.
public enum ItemKind: Sendable, Equatable {
    /// A regular file (or a symlink, which is renamed itself). The suffix goes before the extension.
    case file
    /// A plain folder. The whole name is the stem, so `my.folder` keeps its dot.
    case folder
    /// A folder that macOS shows as a single file (`.app`, `.rtfd`, `.pages`, `.photoslibrary`, …).
    /// Treated like a file so the bundle extension survives and the package still opens.
    case package
}

/// Optional auto-increment counter appended after the suffix (before the extension).
public struct CounterOptions: Sendable, Equatable {
    public static let digitsRange = 1...12
    public static let startRange = 0...9_999_999

    public var digits: Int
    public var start: Int

    public init(digits: Int = 5, start: Int = 1) {
        self.digits = digits
        self.start = start
    }

    /// Zero-padded counter for a 1-based position in the batch: digits 5, start 1, index 1 → `00001`.
    public func string(forIndex index: Int) -> String {
        let value = start + index - 1
        let raw = String(value.magnitude)
        let width = max(1, digits)
        let padded = raw.count >= width ? raw : String(repeating: "0", count: width - raw.count) + raw
        return value < 0 ? "-" + padded : padded
    }
}

/// Everything the user typed in the dialog.
public struct RenameOptions: Sendable, Equatable {
    public var prefix: String
    public var suffix: String
    /// Stripped from the start of the stem (case-insensitive, literal) before the prefix is added.
    public var removeStart: String
    /// Stripped from the end of the stem (case-insensitive) before the suffix is added.
    public var removeEnd: String
    /// When true, `*` in `removeEnd` matches any run of characters (`_v*` strips `_v1`, `_v12`, …).
    public var wildcard: Bool
    public var counter: CounterOptions?

    public init(prefix: String = "", suffix: String = "", removeStart: String = "",
                removeEnd: String = "", wildcard: Bool = false, counter: CounterOptions? = nil) {
        self.prefix = prefix
        self.suffix = suffix
        self.removeStart = removeStart
        self.removeEnd = removeEnd
        self.wildcard = wildcard
        self.counter = counter
    }

    public var hasRemove: Bool { !removeStart.isEmpty || !removeEnd.isEmpty }
}

public enum NameTransform {
    /// The new base name (no directory) for one item.
    ///
    /// Pipeline on the stem (name minus extension): strip `removeStart` / `removeEnd` if present,
    /// then `prefix + stem + suffix + counter`. The extension is preserved.
    ///
    ///     report.pdf  --(prefix "2024_", suffix "_final")-->  2024_report_final.pdf
    public static func newName(for name: String, kind: ItemKind, options: RenameOptions, index: Int = 1) -> String {
        let counter = options.counter?.string(forIndex: index) ?? ""

        var stem = name
        var ext = ""
        if kind != .folder, let dot = name.lastIndex(of: "."), name.index(after: dot) != name.endIndex {
            if dot == name.startIndex {
                // Dotfile (.gitignore): the whole name acts as the extension, so affixes are
                // prepended. Same behaviour as the Windows version; the preview shows the result.
                return options.prefix + options.suffix + counter + name
            }
            stem = String(name[..<dot])
            ext = String(name[name.index(after: dot)...])
        }

        if !options.removeStart.isEmpty, let rest = dropPrefix(of: stem, matching: options.removeStart) {
            stem = rest
        }
        if !options.removeEnd.isEmpty {
            stem = stripEnd(stem, pattern: options.removeEnd, wildcard: options.wildcard)
        }

        let newStem = options.prefix + stem + options.suffix + counter
        return ext.isEmpty ? newStem : newStem + "." + ext
    }

    /// Strips a trailing match from `stem`. `wildcard == false`: literal text.
    /// `wildcard == true`: `*` matches any run of characters, and the leftmost match that
    /// reaches the end of the stem is removed (`a_v1_v2` with `_v*` → `a`).
    public static func stripEnd(_ stem: String, pattern: String, wildcard: Bool) -> String {
        if wildcard && pattern.contains("*") {
            let s = Array(stem)
            let p = Array(pattern)
            for start in 0...s.count where globMatch(s[start...], p) {
                return String(s[..<start])
            }
            return stem
        }
        return dropSuffix(of: stem, matching: pattern) ?? stem
    }

    // MARK: - Character-level, case-insensitive matching
    //
    // Comparison is done per Character (grapheme cluster) with Swift's canonical equivalence,
    // so a Korean name stored decomposed (NFD, common on macOS) still matches text typed
    // composed (NFC) in the dialog.

    static func charsEqual(_ a: Character, _ b: Character) -> Bool {
        a == b || a.lowercased() == b.lowercased()
    }

    static func dropPrefix(of s: String, matching p: String) -> String? {
        var i = s.startIndex
        for pc in p {
            guard i < s.endIndex, charsEqual(s[i], pc) else { return nil }
            i = s.index(after: i)
        }
        return String(s[i...])
    }

    static func dropSuffix(of s: String, matching p: String) -> String? {
        var i = s.endIndex
        for pc in p.reversed() {
            guard i > s.startIndex else { return nil }
            let prev = s.index(before: i)
            guard charsEqual(s[prev], pc) else { return nil }
            i = prev
        }
        return String(s[..<i])
    }

    /// Whole-string glob match: `*` matches any run of characters (including none); everything
    /// else is literal and case-insensitive.
    static func globMatch(_ text: ArraySlice<Character>, _ pattern: [Character]) -> Bool {
        let t = Array(text)
        var ti = 0, pi = 0
        var starP = -1, starT = 0
        while ti < t.count {
            if pi < pattern.count, pattern[pi] == "*" {
                starP = pi
                starT = ti
                pi += 1
            } else if pi < pattern.count, charsEqual(pattern[pi], t[ti]) {
                ti += 1
                pi += 1
            } else if starP >= 0 {
                pi = starP + 1
                starT += 1
                ti = starT
            } else {
                return false
            }
        }
        while pi < pattern.count, pattern[pi] == "*" { pi += 1 }
        return pi == pattern.count
    }
}
