import AppKit
import SwiftUI

/// `Mac_Renamer --snapshot <dir>` renders the real dialog off-screen into PNGs for the README
/// (docs/dialog.png and the frames of docs/demo.gif). Used by the docs workflow in CI.
enum Snapshot {
    static func run(outputDirectory: String) -> Int32 {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)

        let fm = FileManager.default
        let out = URL(fileURLWithPath: outputDirectory, isDirectory: true)
        let framesDir = out.appendingPathComponent("frames", isDirectory: true)
        let samples = fm.temporaryDirectory.appendingPathComponent("Mac_Renamer_snapshot_\(UUID().uuidString)")
        do {
            try fm.createDirectory(at: framesDir, withIntermediateDirectories: true)
            try fm.createDirectory(at: samples, withIntermediateDirectories: true)
        } catch {
            fputs("snapshot: \(error.localizedDescription)\n", stderr)
            return 1
        }
        defer { try? fm.removeItem(at: samples) }

        let names = ["report.pdf", "data.xlsx", "photo.jpg", "notes.txt"]
        let urls = names.map { samples.appendingPathComponent($0) }
        for url in urls { _ = fm.createFile(atPath: url.path, contents: Data()) }

        SortOrder.current = .name
        let model = RenameModel(urls: urls)
        model.sortOrder = .name
        let window = makeWindow(model: model, count: urls.count)

        // demo.gif frames: type the prefix, then the suffix, then hold on the result
        var frame = 0
        func capture(hold: Int = 1) -> Bool {
            settle()
            guard let png = render(window) else { return false }
            for _ in 0..<hold {
                let url = framesDir.appendingPathComponent(String(format: "frame_%03ld.png", frame))
                guard (try? png.write(to: url)) != nil else { return false }
                frame += 1
            }
            return true
        }

        var ok = capture(hold: 4)
        for ch in "2024_" where ok {
            model.prefix.append(ch)
            ok = capture()
        }
        ok = ok && capture(hold: 2)
        for ch in "_final" where ok {
            model.suffix.append(ch)
            ok = capture()
        }
        ok = ok && capture(hold: 14)

        // the still image for the README
        if ok, let png = render(window) {
            ok = (try? png.write(to: out.appendingPathComponent("dialog.png"))) != nil
        } else {
            ok = false
        }
        window.close()

        if !ok {
            fputs("snapshot: rendering failed\n", stderr)
            return 1
        }
        print("snapshot: wrote \(frame) frames and dialog.png to \(out.path)")
        return 0
    }

    private static func makeWindow(model: RenameModel, count: Int) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 680, height: 600),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Mac_Renamer — \(count) selected"
        window.isReleasedWhenClosed = false
        let view = RenameDialogView(model: model, onCancel: {}, onApply: {})
        let hosting = NSHostingView(rootView: view)
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.setContentSize(NSSize(width: 680, height: 600))
        // Draw it as the active window (colored traffic lights, blue default button), the way
        // it looks after pressing ⌥F2.
        NSApp.finishLaunching()
        activateApp()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        settle()
        return window
    }

    private static func settle() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.25))
    }

    /// Draws the window (title bar included) into a 2× bitmap.
    private static func render(_ window: NSWindow) -> Data? {
        guard let frameView = window.contentView?.superview ?? window.contentView else { return nil }
        frameView.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let bounds = frameView.bounds
        let scale: CGFloat = 2
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(bounds.width * scale),
            pixelsHigh: Int(bounds.height * scale),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}

/// `Mac_Renamer --uninstall`: removes the login item and the saved settings (used by uninstall.sh).
enum Uninstall {
    static func run() -> Int32 {
        if LoginItem.isRunningFromAppBundle {
            try? LoginItem.set(enabled: false)
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
        }
        print("Mac_Renamer: removed the login item and saved settings.")
        return 0
    }
}
