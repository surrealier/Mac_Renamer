import XCTest
@testable import RenamerCore

final class ValidationTests: XCTestCase {
    // MARK: dialog input

    func testEverythingEmptyIsRejected() {
        XCTAssertNotNil(Validation.optionsError(RenameOptions()))
    }

    func testSlashIsRejected() {
        XCTAssertNotNil(Validation.optionsError(RenameOptions(prefix: "a/b")))
    }

    func testColonIsRejected() {
        XCTAssertNotNil(Validation.optionsError(RenameOptions(suffix: "x:y")))
    }

    func testCleanAffixesAreOK() {
        XCTAssertNil(Validation.optionsError(RenameOptions(prefix: "good_", suffix: "_ok")))
    }

    func testCharactersWindowsForbidsAreFineOnMac() {
        XCTAssertNil(Validation.optionsError(RenameOptions(prefix: "a*b?", suffix: "<\"|>\\")))
    }

    func testCounterAloneIsEnough() {
        XCTAssertNil(Validation.optionsError(RenameOptions(counter: CounterOptions())))
    }

    func testRemoveAloneIsEnough() {
        XCTAssertNil(Validation.optionsError(RenameOptions(removeStart: "IMG_")))
        XCTAssertNil(Validation.optionsError(RenameOptions(removeEnd: "_copy")))
    }

    // MARK: resulting names

    func testEmptyResultIsRejected() {
        XCTAssertNotNil(Validation.resultNameError("", original: "a"))
    }

    func testDotAndDotDotAreRejected() {
        XCTAssertNotNil(Validation.resultNameError(".", original: "a"))
        XCTAssertNotNil(Validation.resultNameError("..", original: "a"))
    }

    func testTooLongIsRejected() {
        XCTAssertNotNil(Validation.resultNameError(String(repeating: "a", count: 256), original: "a"))
        XCTAssertNil(Validation.resultNameError(String(repeating: "a", count: 255), original: "a"))
        // 86 Hangul syllables = 258 UTF-8 bytes
        XCTAssertNotNil(Validation.resultNameError(String(repeating: "가", count: 86), original: "a"))
    }

    func testBecomingHiddenIsRejected() {
        XCTAssertNotNil(Validation.resultNameError(".jpg", original: "photo.jpg"))
        XCTAssertNil(Validation.resultNameError(".env_old", original: ".env"))
    }

    func testNormalResultIsOK() {
        XCTAssertNil(Validation.resultNameError("2024_report_final.pdf", original: "report.pdf"))
    }
}
