import XCTest
@testable import RenamerCore

final class NameTransformTests: XCTestCase {
    private func name(_ n: String, _ kind: ItemKind = .file, prefix: String = "", suffix: String = "",
                      removeStart: String = "", removeEnd: String = "", wildcard: Bool = false,
                      counter: CounterOptions? = nil, index: Int = 1) -> String {
        NameTransform.newName(for: n, kind: kind,
                              options: RenameOptions(prefix: prefix, suffix: suffix, removeStart: removeStart,
                                                     removeEnd: removeEnd, wildcard: wildcard, counter: counter),
                              index: index)
    }

    // MARK: prefix / suffix (ported from the Windows suite)

    func testNormalFileSuffixBeforeExtension() {
        XCTAssertEqual(name("report.pdf", prefix: "2024_", suffix: "_final"), "2024_report_final.pdf")
    }

    func testAnotherExtension() {
        XCTAssertEqual(name("data.xlsx", prefix: "2024_", suffix: "_final"), "2024_data_final.xlsx")
    }

    func testNoExtensionFile() {
        XCTAssertEqual(name("README", prefix: "2024_", suffix: "_final"), "2024_README_final")
    }

    func testDotfile() {
        XCTAssertEqual(name(".gitignore", prefix: "2024_", suffix: "_final"), "2024__final.gitignore")
    }

    func testFolder() {
        XCTAssertEqual(name("sub", .folder, prefix: "2024_", suffix: "_final"), "2024_sub_final")
    }

    func testPrefixOnly() {
        XCTAssertEqual(name("report.pdf", prefix: "img_"), "img_report.pdf")
    }

    func testSuffixOnly() {
        XCTAssertEqual(name("report.pdf", suffix: "_v2"), "report_v2.pdf")
    }

    // MARK: macOS-specific splitting

    func testFolderWithDotKeepsWholeName() {
        XCTAssertEqual(name("my.folder", .folder, prefix: "2024_", suffix: "_final"), "2024_my.folder_final")
    }

    func testPackageKeepsBundleExtension() {
        XCTAssertEqual(name("Notes.app", .package, prefix: "old_", suffix: "_v1"), "old_Notes_v1.app")
        XCTAssertEqual(name("Draft.rtfd", .package, suffix: "_final"), "Draft_final.rtfd")
    }

    func testOnlyLastExtensionIsKept() {
        XCTAssertEqual(name("archive.tar.gz", suffix: "_bak"), "archive.tar_bak.gz")
    }

    func testTrailingDotHasNoExtension() {
        XCTAssertEqual(name("file.", prefix: "p_"), "p_file.")
    }

    func testDotfileWithExtension() {
        XCTAssertEqual(name(".config.json", prefix: "2024_", suffix: "_final"), "2024_.config_final.json")
    }

    func testUnicodeNames() {
        XCTAssertEqual(name("사진.jpg", prefix: "2024_", suffix: "_최종"), "2024_사진_최종.jpg")
        XCTAssertEqual(name("café 🎉.png", suffix: "_x"), "café 🎉_x.png")
    }

    // MARK: counter

    func testCounterAppendedAfterSuffix() {
        XCTAssertEqual(name("file.png", suffix: "_", counter: CounterOptions(digits: 5, start: 1)), "file_00001.png")
    }

    func testCounterWithoutSuffixText() {
        XCTAssertEqual(name("photo.jpg", counter: CounterOptions(digits: 3, start: 42)), "photo042.jpg")
    }

    func testCounterWithPrefixAndSuffix() {
        XCTAssertEqual(name("a.txt", prefix: "p_", suffix: "_s", counter: CounterOptions(digits: 3, start: 7)),
                       "p_a_s007.txt")
    }

    func testCounterFormatFiveDigits() {
        XCTAssertEqual(CounterOptions(digits: 5, start: 1).string(forIndex: 1), "00001")
    }

    func testCounterStartOffset() {
        XCTAssertEqual(CounterOptions(digits: 3, start: 10).string(forIndex: 5), "014")
    }

    func testCounterWiderThanDigits() {
        XCTAssertEqual(CounterOptions(digits: 2, start: 99).string(forIndex: 3), "101")
    }

    func testCounterFollowsIndex() {
        XCTAssertEqual(name("b.png", suffix: "_", counter: CounterOptions(digits: 4, start: 1), index: 2), "b_0002.png")
    }

    func testNoCounterOptionsMeansNoNumber() {
        XCTAssertEqual(name("shot.png", suffix: "_", index: 3), "shot_.png")
    }

    // MARK: remove

    func testRemoveLeadingText() {
        XCTAssertEqual(name("IMG_photo.jpg", removeStart: "IMG_"), "photo.jpg")
    }

    func testRemoveTrailingText() {
        XCTAssertEqual(name("photo_copy.jpg", removeEnd: "_copy"), "photo.jpg")
    }

    func testRemoveBothEndsAndAddPrefix() {
        XCTAssertEqual(name("IMG_photo_old.png", prefix: "new_", removeStart: "IMG_", removeEnd: "_old"), "new_photo.png")
    }

    func testRemoveNotPresentIsNoOp() {
        XCTAssertEqual(name("report.pdf", removeStart: "XYZ_"), "report.pdf")
    }

    func testRemoveIsCaseInsensitive() {
        XCTAssertEqual(name("img_a.txt", removeStart: "IMG_"), "a.txt")
    }

    func testRemoveKeepsExtension() {
        XCTAssertEqual(name("IMG_1234.JPEG", removeStart: "IMG_"), "1234.JPEG")
    }

    func testRemoveNeverTouchesExtension() {
        XCTAssertEqual(name("notes.txt", removeEnd: "txt"), "notes.txt")
    }

    func testRemoveMatchesDecomposedKorean() {
        // Finder often stores Hangul decomposed (NFD); the dialog types it composed (NFC).
        let nfdStem = "사진_report".decomposedStringWithCanonicalMapping
        XCTAssertNotEqual(Array(nfdStem.unicodeScalars).count, Array("사진_report".unicodeScalars).count)
        XCTAssertEqual(name(nfdStem + ".jpg", removeStart: "사진_"), "report.jpg")
        XCTAssertEqual(name("report_사본.jpg".decomposedStringWithCanonicalMapping, removeEnd: "_사본"), "report.jpg")
    }

    func testRemoveDoesNotSplitACharacter() {
        // "é" written as e + combining accent is one Character; removing "e" must not break it.
        XCTAssertEqual(name("e\u{301}tude.txt", removeStart: "e"), "e\u{301}tude.txt")
    }

    // MARK: wildcard

    func testWildcardStripsV2() {
        XCTAssertEqual(name("photo_v2.jpg", removeEnd: "_v*", wildcard: true), "photo.jpg")
    }

    func testWildcardStripsV10() {
        XCTAssertEqual(name("report_v10.pdf", removeEnd: "_v*", wildcard: true), "report.pdf")
    }

    func testWildcardNoMatchIsNoOp() {
        XCTAssertEqual(name("plain.txt", removeEnd: "_v*", wildcard: true), "plain.txt")
    }

    func testWildcardOffMeansLiteral() {
        XCTAssertEqual(name("photo_v2.jpg", removeEnd: "_v*", wildcard: false), "photo_v2.jpg")
        XCTAssertEqual(name("photo_v*.jpg", removeEnd: "_v*", wildcard: false), "photo.jpg")
    }

    func testWildcardIsCaseInsensitive() {
        XCTAssertEqual(name("clip_V3.mp4", removeEnd: "_v*", wildcard: true), "clip.mp4")
    }

    func testWildcardKeepsExtensionAndAddsPrefix() {
        XCTAssertEqual(name("img_v5.PNG", prefix: "new_", removeEnd: "_v*", wildcard: true), "new_img.PNG")
    }

    func testWildcardTakesLeftmostMatch() {
        XCTAssertEqual(name("a_v1_v2.txt", removeEnd: "_v*", wildcard: true), "a.txt")
    }

    func testWildcardInTheMiddle() {
        XCTAssertEqual(name("scan (copy 3).pdf", removeEnd: " (copy*)", wildcard: true), "scan.pdf")
        XCTAssertEqual(name("scan (copy 3) x.pdf", removeEnd: " (copy*)", wildcard: true), "scan (copy 3) x.pdf")
    }

    func testWildcardOtherCharactersAreLiteral() {
        XCTAssertEqual(name("a.b_v1.txt", removeEnd: ".b_v*", wildcard: true), "a.txt")
        XCTAssertEqual(name("ab_v1.txt", removeEnd: ".b_v*", wildcard: true), "ab_v1.txt")
    }

    func testWildcardWithKorean() {
        XCTAssertEqual(name("보고서_수정본3.hwp".decomposedStringWithCanonicalMapping, removeEnd: "_수정*", wildcard: true),
                       "보고서.hwp")
    }

    func testLoneStarRemovesWholeStem() {
        XCTAssertEqual(name("photo.jpg", prefix: "x", removeEnd: "*", wildcard: true), "x.jpg")
    }
}
