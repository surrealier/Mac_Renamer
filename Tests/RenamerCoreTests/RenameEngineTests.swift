import XCTest
@testable import RenamerCore
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

final class RenameEngineTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac_renamer_test_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // restore permissions first so the read-only test folder can be removed
        if let items = FileManager.default.enumerator(atPath: dir.path) {
            for case let rel as String in items {
                chmod(dir.appendingPathComponent(rel).path, 0o755)
            }
        }
        try? FileManager.default.removeItem(at: dir)
    }

    // MARK: helpers

    @discardableResult
    private func mk(_ name: String, _ contents: String = "", in folder: URL? = nil) -> URL {
        let url = (folder ?? dir).appendingPathComponent(name)
        _ = FileManager.default.createFile(atPath: url.path, contents: Data(contents.utf8))
        return url
    }

    private func mkdir(_ name: String, in folder: URL? = nil) -> URL {
        let url = (folder ?? dir).appendingPathComponent(name, isDirectory: true)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func exists(_ name: String, in folder: URL? = nil) -> Bool {
        FileManager.default.fileExists(atPath: (folder ?? dir).appendingPathComponent(name).path)
    }

    private func read(_ name: String) -> String {
        (try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8)) ?? ""
    }

    private func listing(_ folder: URL? = nil) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: (folder ?? dir).path)) ?? []).sorted()
    }

    // MARK: basic batch (ported)

    func testBatchRenameOnDisk() {
        let files = [mk("report.pdf"), mk("data.xlsx"), mk("README")]
        let r = RenameEngine.rename(files, options: RenameOptions(prefix: "2024_", suffix: "_final"))
        XCTAssertEqual(r.renamedCount, 3)
        XCTAssertTrue(r.skipped.isEmpty)
        XCTAssertTrue(r.failed.isEmpty)
        XCTAssertTrue(exists("2024_report_final.pdf"))
        XCTAssertTrue(exists("2024_data_final.xlsx"))
        XCTAssertTrue(exists("2024_README_final"))
        XCTAssertFalse(exists("report.pdf"))
    }

    func testFolderRenameOnDisk() {
        let folder = mkdir("my.folder")
        mk("inside.txt", "keep", in: folder)
        let r = RenameEngine.rename([folder], options: RenameOptions(prefix: "2024_", suffix: "_final"))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertTrue(exists("2024_my.folder_final/inside.txt"))
    }

    // MARK: collisions (ported)

    func testExistingTargetIsSkippedNotClobbered() {
        let src = mk("alpha.txt", "SOURCE")
        mk("p_alpha.txt", "ORIGINAL")
        let r = RenameEngine.rename([src], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(r.renamedCount, 0)
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertTrue(exists("alpha.txt"))
        XCTAssertEqual(read("p_alpha.txt"), "ORIGINAL")
    }

    func testTargetCreatedAfterPlanningIsNeverOverwritten() {
        let src = mk("late.txt", "SOURCE")
        let plan = RenameEngine.plan([src], options: RenameOptions(prefix: "x_"))
        XCTAssertEqual(plan.renameCount, 1)
        mk("x_late.txt", "SOMEONE ELSE")          // appears between preview and Apply
        let r = RenameEngine.execute(plan)
        XCTAssertEqual(r.renamedCount, 0)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertEqual(read("x_late.txt"), "SOMEONE ELSE")
        XCTAssertEqual(read("late.txt"), "SOURCE")
    }

    func testDuplicateTargetsInsideBatch() {
        let a = mk("a_v1.txt", "one"), b = mk("a_v2.txt", "two")
        let r = RenameEngine.rename([a, b], options: RenameOptions(removeEnd: "_v*", wildcard: true))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(r.skipped.count, 1)
        XCTAssertTrue(r.skipped[0].reason.contains("a_v1.txt"))
        XCTAssertEqual(read("a.txt"), "one")
        XCTAssertEqual(read("a_v2.txt"), "two")
    }

    func testDuplicateTargetsDifferingOnlyByCase() {
        let a = mk("A_v1.txt"), b = mk("a_v2.txt")
        let r = RenameEngine.rename([a, b], options: RenameOptions(prefix: "x_", removeEnd: "_v*", wildcard: true))
        XCTAssertEqual(r.renamedCount, 1, "x_A.txt and x_a.txt are the same name on a default APFS volume")
        XCTAssertEqual(r.skipped.count, 1)
    }

    // MARK: partial failure isolation (ported)

    func testOneFailureDoesNotAbortTheBatch() {
        struct FailOne: FileOperations {
            let live = LiveFileOperations()
            let blocked: String
            func itemKind(at url: URL) -> ItemKind? { live.itemKind(at: url) }
            func moveItem(at source: URL, to destination: URL) throws {
                if source.lastPathComponent == blocked { throw FileSystemError(EACCES) }
                try live.moveItem(at: source, to: destination)
            }
        }
        let locked = mk("locked.dat"), ok = mk("keep.dat")
        let ops = FailOne(blocked: "locked.dat")
        let r = RenameEngine.rename([locked, ok], options: RenameOptions(prefix: "x_"), fileOps: ops)
        XCTAssertTrue(exists("x_keep.dat"))
        XCTAssertTrue(exists("locked.dat"))
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertTrue(r.failed[0].reason.contains("errno \(EACCES)"))
    }

    func testReadOnlyFolderFailsJustThatItem() throws {
        try XCTSkipIf(geteuid() == 0, "root ignores folder permissions")
        let ro = mkdir("readonly")
        let locked = mk("locked.dat", in: ro), ok = mk("keep.dat")
        chmod(ro.path, 0o555)
        let r = RenameEngine.rename([locked, ok], options: RenameOptions(prefix: "x_"))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertTrue(exists("x_keep.dat"))
        XCTAssertTrue(exists("locked.dat", in: ro))
    }

    // MARK: counter / remove / wildcard on disk (ported)

    func testCounterOnDisk() {
        let files = [mk("shot1.png"), mk("shot2.png")]
        let r = RenameEngine.rename(files, options: RenameOptions(suffix: "_", counter: CounterOptions(digits: 4, start: 1)))
        XCTAssertEqual(r.renamedCount, 2)
        XCTAssertTrue(exists("shot1_0001.png"))
        XCTAssertTrue(exists("shot2_0002.png"))
    }

    func testRemoveOnDisk() {
        let f = mk("PRE_keep.txt")
        let r = RenameEngine.rename([f], options: RenameOptions(removeStart: "PRE_"))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertTrue(exists("keep.txt"))
        XCTAssertFalse(exists("PRE_keep.txt"))
    }

    func testWildcardOnDisk() {
        let files = [mk("verA_v1.txt"), mk("verB_v22.txt")]
        let r = RenameEngine.rename(files, options: RenameOptions(removeEnd: "_v*", wildcard: true))
        XCTAssertEqual(r.renamedCount, 2)
        XCTAssertTrue(exists("verA.txt"))
        XCTAssertTrue(exists("verB.txt"))
    }

    // MARK: case-only, chains, swaps

    func testCaseOnlyRenameGoesThroughTemp() {
        let f = mk("IMG_a.txt", "data")
        let r = RenameEngine.rename([f], options: RenameOptions(prefix: "img_", removeStart: "IMG_"))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(listing(), ["img_a.txt"])
        XCTAssertEqual(read("img_a.txt"), "data")
    }

    func testChainWhereTargetIsAnotherSource() {
        let x = mk("x.txt", "X"), px = mk("p_x.txt", "PX")
        let plan = RenameEngine.plan([x, px], options: RenameOptions(prefix: "p_"))
        XCTAssertTrue(plan.needsTwoPass)
        let r = RenameEngine.execute(plan)
        XCTAssertEqual(r.renamedCount, 2)
        XCTAssertEqual(read("p_x.txt"), "X")
        XCTAssertEqual(read("p_p_x.txt"), "PX")
        XCTAssertEqual(listing(), ["p_p_x.txt", "p_x.txt"])
    }

    func testTargetThatStaysPutBlocksTheRename() {
        // p_x.txt is not in the batch, so it is a real existing file and must win.
        let x = mk("x.txt", "X")
        mk("p_x.txt", "STAY")
        let r = RenameEngine.rename([x], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(r.renamedCount, 0)
        XCTAssertEqual(read("p_x.txt"), "STAY")
    }

    func testBlockedChainIsResolvedToAFixedPoint() {
        // a → b is only allowed if b moves; b → c is blocked by an unselected c, so a must stay too.
        let a = mk("a"), b = mk("b")
        mk("c", "C")
        struct MapOps: FileOperations {
            let live = LiveFileOperations()
            func itemKind(at url: URL) -> ItemKind? { live.itemKind(at: url) }
            func moveItem(at s: URL, to d: URL) throws { try live.moveItem(at: s, to: d) }
        }
        let proposals = [
            RenameEngine.Proposal(index: 1, source: a, newName: "b", issue: nil),
            RenameEngine.Proposal(index: 2, source: b, newName: "c", issue: nil),
        ]
        let plan = RenameEngine.buildPlan(proposals, fileOps: MapOps())
        XCTAssertEqual(plan.renameCount, 0)
        XCTAssertEqual(plan.skipped.count, 2)
    }

    func testSwapTwoNamesViaUndoPlan() {
        let a = mk("a.txt", "A"), b = mk("b.txt", "B")
        // swap: a.txt -> b.txt, b.txt -> a.txt
        let r = RenameEngine.undo([RenamedItem(from: b, to: a), RenamedItem(from: a, to: b)])
        XCTAssertEqual(r.renamedCount, 2)
        XCTAssertEqual(read("a.txt"), "B")
        XCTAssertEqual(read("b.txt"), "A")
        XCTAssertEqual(listing(), ["a.txt", "b.txt"])
    }

    func testFailedSecondPassRestoresOriginalName() {
        struct FailIntoTarget: FileOperations {
            let live = LiveFileOperations()
            func itemKind(at url: URL) -> ItemKind? { live.itemKind(at: url) }
            func moveItem(at s: URL, to d: URL) throws {
                if d.lastPathComponent == "p_p_x.txt" { throw FileSystemError(EIO) }
                try live.moveItem(at: s, to: d)
            }
        }
        let x = mk("x.txt", "X"), px = mk("p_x.txt", "PX")
        let r = RenameEngine.rename([x, px], options: RenameOptions(prefix: "p_"), fileOps: FailIntoTarget())
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertEqual(read("p_x.txt"), "X")
        // p_x.txt could not reach p_p_x.txt and its old name is now taken by x.txt, so it stays
        // under a visible temp name that the failure message points to. Nothing is lost.
        let leftover = listing().filter { $0.hasPrefix("~macrenamer-") }
        XCTAssertEqual(leftover.count, 1)
        XCTAssertEqual(read(leftover[0]), "PX")
        XCTAssertTrue(r.failed[0].reason.contains(leftover[0]))
    }

    func testFailedSecondPassRestoresWhenTheOldNameIsFree() {
        struct FailIntoTarget: FileOperations {
            let live = LiveFileOperations()
            func itemKind(at url: URL) -> ItemKind? { live.itemKind(at: url) }
            func moveItem(at s: URL, to d: URL) throws {
                if d.lastPathComponent == "p_x.txt" { throw FileSystemError(EIO) }
                try live.moveItem(at: s, to: d)
            }
        }
        let x = mk("x.txt", "X"), px = mk("p_x.txt", "PX")
        let r = RenameEngine.rename([x, px], options: RenameOptions(prefix: "p_"), fileOps: FailIntoTarget())
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(r.failed.count, 1)
        XCTAssertEqual(read("x.txt"), "X", "x.txt went back to its own name")
        XCTAssertEqual(read("p_p_x.txt"), "PX")
        XCTAssertFalse(listing().contains { $0.hasPrefix("~macrenamer-") }, "no temp files left behind")
    }

    // MARK: skip reasons

    func testNoChangeIsSkipped() {
        let f = mk("report.pdf")
        let r = RenameEngine.rename([f], options: RenameOptions(removeStart: "XYZ_"))
        XCTAssertEqual(r.renamedCount, 0)
        XCTAssertEqual(r.skipped.first?.reason, "no change")
    }

    func testMissingSourceIsSkipped() {
        let ghost = dir.appendingPathComponent("ghost.txt")
        let r = RenameEngine.rename([ghost], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(r.skipped.first?.reason, "source not found")
    }

    func testResultThatWouldBeHiddenIsSkipped() {
        let f = mk("photo.jpg")
        let r = RenameEngine.rename([f], options: RenameOptions(removeEnd: "*", wildcard: true))
        XCTAssertEqual(r.renamedCount, 0)
        XCTAssertTrue(exists("photo.jpg"))
        XCTAssertEqual(r.skipped.count, 1)
    }

    // MARK: preview

    func testPreviewRowsDoNotTouchTheDisk() {
        let a = mk("report.pdf"), b = mk("alpha.txt")
        mk("p_alpha.txt")
        let plan = RenameEngine.plan([a, b], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(plan.rows.map(\.newName), ["p_report.pdf", "p_alpha.txt"])
        XCTAssertNil(plan.rows[0].issue)
        XCTAssertEqual(plan.rows[1].issue, "an item with that name already exists")
        XCTAssertEqual(plan.renameCount, 1)
        XCTAssertTrue(exists("report.pdf"))
    }

    func testSymlinkIsRenamedItself() throws {
        let target = mk("target.txt", "T")
        let link = dir.appendingPathComponent("link.txt")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let r = RenameEngine.rename([link], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(r.renamedCount, 1)
        XCTAssertEqual(listing(), ["p_link.txt", "target.txt"])
    }

    // MARK: undo

    func testUndoRestoresOriginalNames() {
        let files = [mk("one.txt", "1"), mk("two.txt", "2")]
        let r = RenameEngine.rename(files, options: RenameOptions(prefix: "2024_"))
        XCTAssertEqual(listing(), ["2024_one.txt", "2024_two.txt"])
        let u = RenameEngine.undo(r.renamed)
        XCTAssertEqual(u.renamedCount, 2)
        XCTAssertEqual(listing(), ["one.txt", "two.txt"])
        XCTAssertEqual(read("one.txt"), "1")
    }

    func testUndoOfAChainRestoresContents() {
        let x = mk("x.txt", "X"), px = mk("p_x.txt", "PX")
        let r = RenameEngine.rename([x, px], options: RenameOptions(prefix: "p_"))
        XCTAssertEqual(r.renamedCount, 2)
        let u = RenameEngine.undo(r.renamed)
        XCTAssertEqual(u.renamedCount, 2)
        XCTAssertEqual(read("x.txt"), "X")
        XCTAssertEqual(read("p_x.txt"), "PX")
    }

    func testUndoSkipsItemsThatWereMovedAway() throws {
        let f = mk("one.txt")
        let r = RenameEngine.rename([f], options: RenameOptions(prefix: "2024_"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("2024_one.txt"))
        let u = RenameEngine.undo(r.renamed)
        XCTAssertEqual(u.renamedCount, 0)
        XCTAssertEqual(u.skipped.first?.reason, "source not found")
    }
}
