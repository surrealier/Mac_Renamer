import AppKit
import RenamerCore
import SwiftUI

// MARK: - Model

/// Dialog state. Every edit recomputes the plan, which drives the live preview and the status line.
final class RenameModel: ObservableObject {
    @Published var prefix = "" { didSet { refresh() } }
    @Published var suffix = "" { didSet { refresh() } }
    @Published var removeStart = "" { didSet { refresh() } }
    @Published var removeEnd = "" { didSet { refresh() } }
    @Published var wildcard = false { didSet { refresh() } }
    @Published var useCounter = false { didSet { refresh() } }
    @Published var digits = 5 { didSet { refresh() } }
    @Published var start = 1 { didSet { refresh() } }
    @Published var sortOrder: SortOrder {
        didSet {
            SortOrder.current = sortOrder
            orderedURLs = sortOrder.sorted(sourceURLs)
            refresh()
        }
    }

    @Published private(set) var plan: RenamePlan
    @Published private(set) var optionsError: String? = nil

    let sourceURLs: [URL]
    private(set) var orderedURLs: [URL]

    init(urls: [URL]) {
        sourceURLs = urls
        let order = SortOrder.current
        sortOrder = order
        orderedURLs = order.sorted(urls)
        plan = .empty
        refresh()
    }

    var options: RenameOptions {
        RenameOptions(
            prefix: prefix,
            suffix: suffix,
            removeStart: removeStart,
            removeEnd: removeEnd,
            wildcard: wildcard,
            counter: useCounter
                ? CounterOptions(digits: digits.clamped(to: CounterOptions.digitsRange),
                                 start: start.clamped(to: CounterOptions.startRange))
                : nil
        )
    }

    var canApply: Bool { optionsError == nil && plan.renameCount > 0 }

    func refresh() {
        let opts = options
        optionsError = Validation.optionsError(opts)
        plan = RenameEngine.plan(orderedURLs, options: opts)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}

// MARK: - View

struct RenameDialogView: View {
    @ObservedObject var model: RenameModel
    var onCancel: () -> Void
    var onApply: () -> Void

    @FocusState private var prefixFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 9) {
                GridRow {
                    label("Prefix")
                    TextField("Added to the start", text: $model.prefix)
                        .focused($prefixFocused)
                }
                GridRow {
                    label("Suffix")
                    TextField("Added before the extension", text: $model.suffix)
                }

                Divider()

                GridRow {
                    label("Remove from start")
                    TextField("e.g. IMG_", text: $model.removeStart)
                }
                GridRow {
                    label("Remove from end")
                    TextField("Before the extension, e.g. _copy", text: $model.removeEnd)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    Toggle("Treat * as a wildcard   (_v* removes _v1, _v2, _v3 …)", isOn: $model.wildcard)
                }

                Divider()

                GridRow {
                    label("Counter")
                    Toggle("Add a number before the extension   (photo_00001.jpg)", isOn: $model.useCounter)
                }
                GridRow {
                    Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                    HStack(spacing: 6) {
                        Text("Digits")
                        TextField("", value: clampedBinding(\.digits, CounterOptions.digitsRange), format: .number)
                            .frame(width: 44)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $model.digits, in: CounterOptions.digitsRange)
                            .labelsHidden()
                        Text("Start at")
                            .padding(.leading, 14)
                        TextField("", value: clampedBinding(\.start, CounterOptions.startRange),
                                  format: .number.grouping(.never))
                            .frame(width: 84)
                            .multilineTextAlignment(.trailing)
                        Stepper("", value: $model.start, in: CounterOptions.startRange)
                            .labelsHidden()
                    }
                    .disabled(!model.useCounter)
                    .opacity(model.useCounter ? 1 : 0.45)
                }
                GridRow {
                    label("Order")
                    Picker("Order", selection: $model.sortOrder) {
                        ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
            }

            Table(model.plan.rows) {
                TableColumn("Original name") { row in
                    Text(row.originalName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(row.source.path)
                }
                TableColumn("New name") { row in
                    Text(row.newName)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(row.issue == nil ? Color.primary : Color.secondary)
                        .fontWeight(row.issue == nil ? .medium : .regular)
                }
                TableColumn("Note") { row in
                    Text(row.issue ?? "")
                        .lineLimit(1)
                        .foregroundStyle(.orange)
                        .help(row.issue ?? "")
                }
                .width(min: 60, ideal: 120)
            }
            .frame(minHeight: 220)

            HStack(spacing: 10) {
                status
                Spacer(minLength: 12)
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Rename", action: onApply)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canApply)
            }
        }
        .padding(20)
        .frame(minWidth: 600, idealWidth: 680, minHeight: 560, idealHeight: 640)
        .onAppear {
            DispatchQueue.main.async { prefixFocused = true }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }

    private func clampedBinding(_ keyPath: ReferenceWritableKeyPath<RenameModel, Int>,
                                _ range: ClosedRange<Int>) -> Binding<Int> {
        Binding(
            get: { model[keyPath: keyPath] },
            set: { model[keyPath: keyPath] = $0.clamped(to: range) }
        )
    }

    @ViewBuilder private var status: some View {
        let plan = model.plan
        if let error = model.optionsError {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else if plan.renameCount == 0 {
            Label("Nothing to rename — see the notes above.", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        } else {
            let n = plan.renameCount
            let skipped = plan.skipped.count
            Label("Ready — \(n) item\(n == 1 ? "" : "s") will be renamed" + (skipped > 0 ? ", \(skipped) skipped." : "."),
                  systemImage: "checkmark.circle.fill")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Window

final class RenameWindowController: NSWindowController, NSWindowDelegate {
    let model: RenameModel
    var onFinish: ((RenameResult) -> Void)?
    var onClose: (() -> Void)?

    init(urls: [URL]) {
        model = RenameModel(urls: urls)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)

        window.title = "Mac_Renamer — \(urls.count) selected"
        window.level = .floating            // stays above Finder, like the Windows dialog
        window.isReleasedWhenClosed = false
        window.contentMinSize = NSSize(width: 600, height: 560)
        window.delegate = self

        let root = RenameDialogView(
            model: model,
            onCancel: { [weak self] in self?.close() },
            onApply: { [weak self] in self?.apply() }
        )
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.minSize]   // let the user resize; SwiftUI only sets the minimum
        window.contentView = hosting
        window.setContentSize(NSSize(width: 680, height: 640))
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func present() {
        activateApp()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
    }

    func apply() {
        guard model.canApply else { return }
        // Re-plan at the moment of Apply so anything that changed on disk since the last
        // keystroke is taken into account.
        let urls = model.orderedURLs
        let options = model.options
        close()
        let result = RenameEngine.execute(RenameEngine.plan(urls, options: options))
        onFinish?(result)
    }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}

/// Brings the (menu-bar-only) app forward so its window takes keyboard focus from Finder.
/// The older call is used on purpose: on macOS 14+ the cooperative `activate()` can leave
/// Finder in front when the request comes from a hotkey.
func activateApp() {
    NSApp.activate(ignoringOtherApps: true)
}
