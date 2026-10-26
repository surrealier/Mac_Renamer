import AppKit
import RenamerCore

/// `Mac_Renamer --selftest`: GUI integration test (the macOS counterpart of Windows_Renamer's
/// test_apply.ahk). Opens the real rename window on temporary files, types into the model,
/// presses Rename through the window controller and checks the result on disk, then undoes it.
/// Exit code 0 = pass. Run by CI.
enum SelfTest {
    static func run() -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()

        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("Mac_Renamer_selftest_\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        var failures: [String] = []
        func check(_ ok: Bool, _ what: String) {
            print("\(ok ? "PASS" : "FAIL")  \(what)")
            if !ok { failures.append(what) }
        }

        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.createDirectory(at: dir.appendingPathComponent("Draft.rtfd"), withIntermediateDirectories: true)
            _ = fm.createFile(atPath: dir.appendingPathComponent("Draft.rtfd/TXT.rtf").path, contents: Data("{\\rtf1}".utf8))
        } catch {
            print("FAIL  could not create the test folder: \(error)")
            return 1
        }
        let names = ["IMG_beach.jpg", "IMG_cake.jpg", "notes_v3.txt"]
        for name in names {
            _ = fm.createFile(atPath: dir.appendingPathComponent(name).path, contents: Data(name.utf8))
        }
        let urls = (names + ["Draft.rtfd"]).map { dir.appendingPathComponent($0) }

        SortOrder.current = .name
        let controller = RenameWindowController(urls: urls)
        var finished: RenameResult?
        controller.onFinish = { finished = $0 }
        controller.present()
        pump()

        check(controller.window?.isVisible == true, "rename window opens")
        check(controller.window?.title == "Mac_Renamer — 4 selected", "window title shows the count")
        check(!controller.model.canApply, "Rename is disabled until something is typed")

        let model = controller.model
        model.prefix = "2024_"
        model.removeStart = "IMG_"
        model.removeEnd = "_v*"
        model.wildcard = true
        model.useCounter = true
        model.digits = 3
        model.start = 1
        pump()

        let preview = model.plan.rows.map(\.newName)
        check(preview == ["2024_Draft001.rtfd", "2024_beach002.jpg", "2024_cake003.jpg", "2024_notes004.txt"],
              "live preview: \(preview)")
        check(model.canApply, "Rename is enabled")

        controller.apply()
        pump()

        check(controller.window?.isVisible != true, "window closes on Rename")
        check(finished?.renamedCount == 4, "4 items renamed (got \(finished?.renamedCount ?? -1))")
        let after = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
        check(after == ["2024_Draft001.rtfd", "2024_beach002.jpg", "2024_cake003.jpg", "2024_notes004.txt"],
              "files on disk: \(after)")
        let beach = try? String(contentsOf: dir.appendingPathComponent("2024_beach002.jpg"), encoding: .utf8)
        check(beach == "IMG_beach.jpg", "contents travel with the file")
        check(fm.fileExists(atPath: dir.appendingPathComponent("2024_Draft001.rtfd/TXT.rtf").path),
              "package keeps its .rtfd extension and contents")

        if let finished {
            let undo = RenameEngine.undo(finished.renamed)
            let restored = ((try? fm.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
            check(undo.renamedCount == 4 && restored == (names + ["Draft.rtfd"]).sorted(), "undo restores: \(restored)")
        }

        print(failures.isEmpty ? "selftest: all checks passed" : "selftest: \(failures.count) check(s) failed")
        return failures.isEmpty ? 0 : 1
    }

    private static func pump() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
    }
}
