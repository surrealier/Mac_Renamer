import AppKit
import RenamerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var dialog: RenameWindowController?
    private var lastRenamed: [RenamedItem] = []

    private let renameItem = NSMenuItem(title: "Rename Finder Selection…", action: #selector(AppDelegate.renameFromMenu), keyEquivalent: "")
    private let undoItem = NSMenuItem(title: "Undo Last Rename", action: #selector(AppDelegate.undoLastRename), keyEquivalent: "")
    private let loginMenuItem = NSMenuItem(title: "Start at Login", action: #selector(AppDelegate.toggleLoginItem), keyEquivalent: "")
    private var hotKeyItems: [HotKeyPreset: NSMenuItem] = [:]

    private static let finderBundleID = "com.apple.finder"

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()

        GlobalHotKey.shared.onPress = { [weak self] in self?.renameFinderSelection() }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(frontmostAppChanged(_:)),
            name: NSWorkspace.didActivateApplicationNotification, object: nil
        )
        updateHotKey()

        // Finder › right-click › Services (or Quick Actions) › Rename with Mac_Renamer
        NSApp.servicesProvider = self
        NSUpdateDynamicServices()

        LoginItem.enableOnFirstRun()

        // Give a launch that came with files (service, drop on the icon) a moment to open its
        // dialog first, so the welcome never covers it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in self?.showWelcomeIfNeeded() }
    }

    /// Files dropped on the app icon, or `open -a Mac_Renamer <files>`.
    func application(_ application: NSApplication, open urls: [URL]) {
        let files = urls.filter(\.isFileURL).map(\.standardizedFileURL)
        if !files.isEmpty { showDialog(for: files) }
    }

    /// Double-clicking the app while it is already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showWelcome() }
        return true
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "character.cursor.ibeam", accessibilityDescription: "Mac_Renamer")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Mac_Renamer — select files in Finder, then press \(HotKeyPreset.current.title)"
        }

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        renameItem.target = self
        menu.addItem(renameItem)
        undoItem.target = self
        menu.addItem(undoItem)
        menu.addItem(.separator())

        let hotKeyMenu = NSMenu()
        for preset in HotKeyPreset.allCases {
            let mi = NSMenuItem(title: preset == .off ? "Off" : "\(preset.title) while Finder is active",
                                action: #selector(chooseHotKey(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = preset.rawValue
            hotKeyMenu.addItem(mi)
            hotKeyItems[preset] = mi
        }
        let hotKeyParent = NSMenuItem(title: "Hotkey", action: nil, keyEquivalent: "")
        hotKeyParent.submenu = hotKeyMenu
        menu.addItem(hotKeyParent)

        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        let permission = NSMenuItem(title: "Finder Permission…", action: #selector(openAutomationSettings), keyEquivalent: "")
        permission.target = self
        menu.addItem(permission)
        menu.addItem(.separator())

        let about = NSMenuItem(title: "About Mac_Renamer", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(NSMenuItem(title: "Quit Mac_Renamer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        item.menu = menu
        statusItem = item
        refreshMenu()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refreshMenu()
    }

    private func refreshMenu() {
        let preset = HotKeyPreset.current
        if let key = preset.menuKeyEquivalent {
            renameItem.keyEquivalent = key.key
            renameItem.keyEquivalentModifierMask = key.modifiers
        } else {
            renameItem.keyEquivalent = ""
        }
        undoItem.isEnabled = !lastRenamed.isEmpty
        undoItem.title = lastRenamed.isEmpty
            ? "Undo Last Rename"
            : "Undo Last Rename (\(lastRenamed.count) item\(lastRenamed.count == 1 ? "" : "s"))"
        for (p, mi) in hotKeyItems { mi.state = p == preset ? .on : .off }
        loginMenuItem.isEnabled = LoginItem.isRunningFromAppBundle
        loginMenuItem.state = LoginItem.isEnabled ? .on : .off
        statusItem?.button?.toolTip = preset == .off
            ? "Mac_Renamer — select files in Finder, then use this menu"
            : "Mac_Renamer — select files in Finder, then press \(preset.title)"
    }

    // MARK: Hotkey (live only while Finder is frontmost)

    @objc private func frontmostAppChanged(_ note: Notification) {
        let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
        updateHotKey(frontmost: app)
    }

    private func updateHotKey(frontmost: NSRunningApplication? = NSWorkspace.shared.frontmostApplication) {
        let preset = HotKeyPreset.current
        if frontmost?.bundleIdentifier == Self.finderBundleID, preset != .off {
            GlobalHotKey.shared.register(preset)
        } else {
            GlobalHotKey.shared.unregister()
        }
    }

    @objc private func chooseHotKey(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let preset = HotKeyPreset(rawValue: raw) else { return }
        HotKeyPreset.current = preset
        GlobalHotKey.shared.unregister()
        updateHotKey()
        refreshMenu()
    }

    // MARK: Renaming

    @objc private func renameFromMenu() {
        renameFinderSelection()
    }

    func renameFinderSelection() {
        switch FinderSelection.current() {
        case .success(let urls):
            if urls.isEmpty {
                ResultPresenter.message(
                    "No files or folders are selected.",
                    info: "Select items in Finder (or on the Desktop), then press \(HotKeyPreset.current.title) again."
                )
            } else {
                showDialog(for: urls)
            }
        case .failure(.notAuthorized):
            askForFinderPermission()
        case .failure(.finderNotRunning):
            ResultPresenter.message("Finder is not running.", info: "Open a Finder window, select some items and try again.")
        case .failure(.scriptFailed(let message)):
            ResultPresenter.message("Couldn't read the Finder selection.", info: message)
        }
    }

    func showDialog(for urls: [URL]) {
        dialog?.close()
        let controller = RenameWindowController(urls: urls)
        controller.onFinish = { [weak self] result in self?.finished(result) }
        controller.onClose = { [weak self, weak controller] in
            guard let self, let controller, self.dialog === controller else { return }
            self.dialog = nil
        }
        dialog = controller
        controller.present()
    }

    private func finished(_ result: RenameResult) {
        if !result.renamed.isEmpty {
            lastRenamed = result.renamed
        }
        if ResultPresenter.show(result, offerUndo: true) {
            undoLastRename()
        }
    }

    @objc private func undoLastRename() {
        let items = lastRenamed
        guard !items.isEmpty else { return }
        lastRenamed = []
        let result = RenameEngine.undo(items)
        ResultPresenter.show(result, verb: "restored", offerUndo: false)
    }

    private func askForFinderPermission() {
        let alert = NSAlert()
        alert.messageText = "Mac_Renamer needs permission to read the Finder selection."
        alert.informativeText = """
        Open System Settings › Privacy & Security › Automation and turn on “Finder” under Mac_Renamer.

        Tip: right-click the files › Services › Rename with Mac_Renamer works without this permission.
        """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        activateApp()
        if alert.runModal() == .alertFirstButtonReturn {
            FinderSelection.openAutomationSettings()
        }
    }

    // MARK: Services

    /// NSServices entry point (NSMessage "renameFiles" in Info.plist).
    @objc func renameFiles(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        var urls = (pboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        if urls.isEmpty,
           let paths = pboard.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            urls = paths.map { URL(fileURLWithPath: $0) }
        }
        guard !urls.isEmpty else {
            error.pointee = "No files were passed to Mac_Renamer." as NSString
            return
        }
        showDialog(for: urls.map(\.standardizedFileURL))
    }

    // MARK: Other menu items

    @objc private func toggleLoginItem() {
        let enable = !LoginItem.isEnabled
        do {
            try LoginItem.set(enabled: enable)
        } catch {
            ResultPresenter.message("Couldn't change the login item.", info: error.localizedDescription)
        }
        if enable && LoginItem.needsApproval {
            ResultPresenter.message("Almost there",
                                    info: "Approve Mac_Renamer in System Settings › General › Login Items.",
                                    style: .informational)
        }
        refreshMenu()
    }

    @objc private func openAutomationSettings() {
        FinderSelection.openAutomationSettings()
    }

    @objc private func showAbout() {
        activateApp()
        let credits = NSMutableAttributedString(
            string: "Batch-add a prefix/suffix to files right inside Finder.\n",
            attributes: [.font: NSFont.systemFont(ofSize: 11)]
        )
        credits.append(NSAttributedString(
            string: "github.com/surrealier/Mac_Renamer",
            attributes: [.link: URL(string: "https://github.com/surrealier/Mac_Renamer")!,
                         .font: NSFont.systemFont(ofSize: 11)]
        ))
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        credits.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: credits.length))
        NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
    }

    private func showWelcomeIfNeeded() {
        guard dialog == nil, !UserDefaults.standard.bool(forKey: DefaultsKey.welcomeShown) else { return }
        UserDefaults.standard.set(true, forKey: DefaultsKey.welcomeShown)
        showWelcome()
    }

    private func showWelcome() {
        let hotKey = HotKeyPreset.current == .off ? "the menu bar icon" : HotKeyPreset.current.title
        ResultPresenter.message(
            "Mac_Renamer is running in the menu bar.",
            info: """
            Select files in Finder and press \(hotKey) — or right-click them › Services › Rename with Mac_Renamer.

            The first time, macOS asks whether Mac_Renamer may control Finder. Click OK so it can read your selection.
            """,
            style: .informational
        )
    }
}
