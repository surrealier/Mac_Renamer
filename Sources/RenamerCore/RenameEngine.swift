import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

// MARK: - Results

public struct RenameIssue: Sendable, Equatable {
    public let source: URL
    public let reason: String

    public init(source: URL, reason: String) {
        self.source = source
        self.reason = reason
    }
}

public struct RenamedItem: Sendable, Equatable {
    public let from: URL
    public let to: URL

    public init(from: URL, to: URL) {
        self.from = from
        self.to = to
    }
}

public struct RenameResult: Sendable {
    public var renamed: [RenamedItem] = []
    public var skipped: [RenameIssue] = []
    public var failed: [RenameIssue] = []

    public init() {}

    public var renamedCount: Int { renamed.count }
    public var hasProblems: Bool { !skipped.isEmpty || !failed.isEmpty }
}

/// One line of the live preview.
public struct PreviewRow: Identifiable, Sendable, Equatable {
    public let id: Int
    public let source: URL
    public let originalName: String
    public let newName: String
    /// Why this item will be skipped (shown next to the name), or nil when it will be renamed.
    public let issue: String?
}

/// Everything that will happen, worked out without touching the disk.
public struct RenamePlan: Sendable {
    public struct Entry: Sendable, Equatable {
        public let index: Int
        public let source: URL
        public let destination: URL
        /// Only the letter case (or Unicode normalization) changes, so the rename goes through a
        /// temporary name — on a case-insensitive volume the target "already exists" as itself.
        public let caseOnly: Bool
    }

    public var entries: [Entry]
    public var skipped: [RenameIssue]
    public var rows: [PreviewRow]
    /// Some target equals another source in the batch, so everything is moved via temporary
    /// names first (src → tmp, then tmp → dst).
    public var needsTwoPass: Bool

    public init(entries: [Entry] = [], skipped: [RenameIssue] = [], rows: [PreviewRow] = [], needsTwoPass: Bool = false) {
        self.entries = entries
        self.skipped = skipped
        self.rows = rows
        self.needsTwoPass = needsTwoPass
    }

    public static let empty = RenamePlan()

    public var renameCount: Int { entries.count }
}

// MARK: - File system access

/// The few file system calls the engine needs. Swappable so tests can inject failures.
public protocol FileOperations {
    /// nil when nothing exists at `url` (a broken symlink still counts as existing).
    func itemKind(at url: URL) -> ItemKind?
    /// Renames `source` to `destination` and must fail, never overwrite, if the destination exists.
    func moveItem(at source: URL, to destination: URL) throws
}

extension FileOperations {
    func itemExists(at url: URL) -> Bool { itemKind(at: url) != nil }
}

public struct FileSystemError: LocalizedError, Equatable {
    public let code: Int32

    public init(_ code: Int32) { self.code = code }

    public var errorDescription: String? {
        "\(String(cString: strerror(code))) (errno \(code))"
    }
}

public struct LiveFileOperations: FileOperations {
    public init() {}

    public func itemKind(at url: URL) -> ItemKind? {
        // attributesOfItem uses lstat, so a symlink is reported (and renamed) as itself.
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        guard (attrs[.type] as? FileAttributeType) == .typeDirectory else { return .file }
        #if os(macOS)
        if let values = try? url.resourceValues(forKeys: [.isPackageKey]), values.isPackage == true {
            return .package
        }
        #endif
        return .folder
    }

    public func moveItem(at source: URL, to destination: URL) throws {
        let status: Int32 = source.withUnsafeFileSystemRepresentation { src in
            destination.withUnsafeFileSystemRepresentation { dst in
                guard let src, let dst else { return EINVAL }
                #if canImport(Darwin)
                // Atomic "rename unless the target exists" (macOS 10.12+).
                let renameExcl: UInt32 = 0x0000_0004 // RENAME_EXCL
                return renamex_np(src, dst, renameExcl) == 0 ? 0 : errno
                #else
                // Linux fallback (used by the test suite only): check, then rename.
                var st = stat()
                if lstat(dst, &st) == 0 { return EEXIST }
                return rename(src, dst) == 0 ? 0 : errno
                #endif
            }
        }
        if status != 0 { throw FileSystemError(status) }
    }
}

// MARK: - Engine

public enum RenameEngine {
    /// Works out the batch for `urls` (in that order — the counter follows it).
    public static func plan(_ urls: [URL], options: RenameOptions,
                            fileOps: FileOperations = LiveFileOperations()) -> RenamePlan {
        var proposals: [Proposal] = []
        for (i, url) in urls.enumerated() {
            let index = i + 1
            let name = url.lastPathComponent
            guard let kind = fileOps.itemKind(at: url) else {
                proposals.append(Proposal(index: index, source: url, newName: name, issue: "source not found"))
                continue
            }
            let newName = NameTransform.newName(for: name, kind: kind, options: options, index: index)
            let issue = Validation.resultNameError(newName, original: name)
            proposals.append(Proposal(index: index, source: url, newName: newName, issue: issue))
        }
        return buildPlan(proposals, fileOps: fileOps)
    }

    /// Carries out a plan. Each item succeeds or fails on its own; a failure never stops the batch.
    public static func execute(_ plan: RenamePlan, fileOps: FileOperations = LiveFileOperations()) -> RenameResult {
        var result = RenameResult()
        result.skipped = plan.skipped

        if plan.needsTwoPass {
            var staged: [(tmp: URL, entry: RenamePlan.Entry)] = []
            for entry in plan.entries {
                do {
                    let tmp = temporaryURL(near: entry.source, seed: entry.index, fileOps: fileOps)
                    try fileOps.moveItem(at: entry.source, to: tmp)
                    staged.append((tmp, entry))
                } catch {
                    result.failed.append(RenameIssue(source: entry.source, reason: describe(error)))
                }
            }
            for (tmp, entry) in staged {
                do {
                    try fileOps.moveItem(at: tmp, to: entry.destination)
                    result.renamed.append(RenamedItem(from: entry.source, to: entry.destination))
                } catch {
                    var reason = describe(error)
                    do {
                        try fileOps.moveItem(at: tmp, to: entry.source) // put it back
                    } catch {
                        // Its old name was taken by another item of the batch meanwhile. Nothing is
                        // lost: say where it is so the user can find it.
                        reason += " — left as “\(tmp.lastPathComponent)”"
                    }
                    result.failed.append(RenameIssue(source: entry.source, reason: reason))
                }
            }
        } else {
            for entry in plan.entries {
                do {
                    if entry.caseOnly {
                        let tmp = temporaryURL(near: entry.source, seed: entry.index, fileOps: fileOps)
                        try fileOps.moveItem(at: entry.source, to: tmp)
                        do {
                            try fileOps.moveItem(at: tmp, to: entry.destination)
                        } catch {
                            try? fileOps.moveItem(at: tmp, to: entry.source)
                            throw error
                        }
                    } else {
                        try fileOps.moveItem(at: entry.source, to: entry.destination)
                    }
                    result.renamed.append(RenamedItem(from: entry.source, to: entry.destination))
                } catch {
                    result.failed.append(RenameIssue(source: entry.source, reason: describe(error)))
                }
            }
        }
        return result
    }

    /// Plan + execute in one call.
    public static func rename(_ urls: [URL], options: RenameOptions,
                              fileOps: FileOperations = LiveFileOperations()) -> RenameResult {
        execute(plan(urls, options: options, fileOps: fileOps), fileOps: fileOps)
    }

    /// Puts the items of an earlier result back under their original names, with the same
    /// safety rules (never overwrites; swaps go through temporary names).
    public static func undo(_ items: [RenamedItem], fileOps: FileOperations = LiveFileOperations()) -> RenameResult {
        let proposals = items.enumerated().map { i, item -> Proposal in
            let exists = fileOps.itemExists(at: item.to)
            return Proposal(index: i + 1, source: item.to, newName: item.from.lastPathComponent,
                            issue: exists ? nil : "source not found")
        }
        return execute(buildPlan(proposals, fileOps: fileOps), fileOps: fileOps)
    }

    // MARK: Planning

    struct Proposal {
        let index: Int
        let source: URL
        let newName: String
        let issue: String?
    }

    /// Lookup key for "is this the same name?". APFS and HFS+ are case- and
    /// normalization-insensitive by default, so keys fold both.
    static func key(_ url: URL) -> String {
        url.standardizedFileURL.path.precomposedStringWithCanonicalMapping.lowercased()
    }

    static func buildPlan(_ proposals: [Proposal], fileOps: FileOperations) -> RenamePlan {
        var issues: [Int: String] = [:]
        var candidates: [RenamePlan.Entry] = []
        var targetOwner: [String: URL] = [:]

        // 1) name-level checks, then duplicate targets inside the batch (first one wins)
        for p in proposals {
            if let issue = p.issue {
                issues[p.index] = issue
                continue
            }
            if p.newName == p.source.lastPathComponent {
                issues[p.index] = "no change"
                continue
            }
            let destination = p.source.deletingLastPathComponent().appendingPathComponent(p.newName)
            let keyDst = key(destination)
            if let owner = targetOwner[keyDst] {
                issues[p.index] = "same new name as \(owner.lastPathComponent)"
                continue
            }
            targetOwner[keyDst] = p.source
            candidates.append(RenamePlan.Entry(index: p.index, source: p.source, destination: destination,
                                               caseOnly: keyDst == key(p.source)))
        }

        // 2) targets already on disk. Allowed only when that item is itself being renamed away
        //    in this batch; repeat until stable, because skipping one item can block another.
        var changed = true
        while changed {
            changed = false
            let moving = Set(candidates.map { key($0.source) })
            candidates.removeAll { entry in
                let keyDst = key(entry.destination)
                guard keyDst != key(entry.source), fileOps.itemExists(at: entry.destination),
                      !moving.contains(keyDst) else { return false }
                issues[entry.index] = "an item with that name already exists"
                changed = true
                return true
            }
        }

        let moving = Set(candidates.map { key($0.source) })
        let needsTwoPass = candidates.contains { entry in
            let keyDst = key(entry.destination)
            return keyDst != key(entry.source) && moving.contains(keyDst)
        }

        var rows: [PreviewRow] = []
        var skipped: [RenameIssue] = []
        for p in proposals {
            let issue = issues[p.index]
            rows.append(PreviewRow(id: p.index, source: p.source, originalName: p.source.lastPathComponent,
                                   newName: p.newName, issue: issue))
            if let issue { skipped.append(RenameIssue(source: p.source, reason: issue)) }
        }
        return RenamePlan(entries: candidates, skipped: skipped, rows: rows, needsTwoPass: needsTwoPass)
    }

    static func temporaryURL(near source: URL, seed: Int, fileOps: FileOperations) -> URL {
        let dir = source.deletingLastPathComponent()
        let pid = ProcessInfo.processInfo.processIdentifier
        var n = 1
        while true {
            // Visible on purpose (like the Windows version's ~winrename_*.tmp): if something ever
            // goes wrong mid-batch, the user can still see and recover the item.
            let candidate = dir.appendingPathComponent("~macrenamer-\(pid)-\(seed)-\(n).tmp")
            if !fileOps.itemExists(at: candidate) { return candidate }
            n += 1
        }
    }

    static func describe(_ error: Error) -> String {
        if let e = error as? LocalizedError, let text = e.errorDescription { return text }
        return error.localizedDescription
    }
}
