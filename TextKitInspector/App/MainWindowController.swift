import AppKit

final class MainWindowController: NSWindowController {
    private let editor = EditorController()
    private let inspector = InspectorViewController()
    // Retain the native split-view controller for the window's lifetime.
    private let splitController = NSSplitViewController()
    private let status = NSTextField(labelWithString: "")

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1520, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "TextKit Inspector — Native TextKit 1 Laboratory"
        window.center()
                self.init(window: window)
        buildUI()
        editor.onContextChanged = { [weak self] in self?.refreshInspector() }
        inspector.onEdit = { [weak self] action, value in self?.editor.apply(action: action, text: value) }
        refreshInspector()
        window.makeFirstResponder(editor.textView)
    }

    private func button(_ name: String, selector: Selector) -> NSButton {
        let b = NSButton(title: name, target: self, action: selector)
        b.bezelStyle = .rounded
        b.font = .systemFont(ofSize: 12)
        return b
    }

    private func buildUI() {
        guard let window else { return }
        let content = NSView()
        window.contentView = content

        let toolbar = NSStackView(views: [
            button("Reset Document", selector: #selector(reset(_:))),
            button("Insert Image…", selector: #selector(insertImage(_:))),
            button("Insert 4×4 Table", selector: #selector(insertTable(_:))),
            button("Apple Table Panel", selector: #selector(showTablePanel(_:))),
            button("List Panel", selector: #selector(showListPanel(_:)))
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 9
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)

        // Use AppKit's split-view controller to manage pane sizing.
        // A generic NSSplitViewItem has no sidebar-specific width cap.
        let split = splitController.splitView
        split.isVertical = true
        split.dividerStyle = .thin
        splitController.view.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(splitController.view)
        let editorHost = NSView()
        // NSSplitView owns the pane widths. Never synthesize autoresizing-mask
        // constraints on this pane: they can force the divider back on drag.
        editorHost.translatesAutoresizingMaskIntoConstraints = false
        editorHost.addSubview(editor.scrollView)
        editor.scrollView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            editor.scrollView.topAnchor.constraint(equalTo: editorHost.topAnchor),
            editor.scrollView.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            editor.scrollView.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            editor.scrollView.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor)
        ])
        // The exhaustive property inspector lives to the LEFT of the document.
        // Drag the divider to make it wider; editing content stays on the right.
        let editorPaneController = NSViewController()
        editorPaneController.view = editorHost

        let inspectorItem = NSSplitViewItem(viewController: inspector)
        inspectorItem.minimumThickness = 0
        inspectorItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        inspectorItem.canCollapse = false
        inspectorItem.preferredThicknessFraction = 0.5

        let editorItem = NSSplitViewItem(viewController: editorPaneController)
        editorItem.minimumThickness = 0
        editorItem.maximumThickness = NSSplitViewItem.unspecifiedDimension
        editorItem.canCollapse = false

        splitController.addSplitViewItem(inspectorItem)
        splitController.addSplitViewItem(editorItem)

        // Let the split controller determine both pane widths, rather than
        // adopting the document text view's initial 780-point content size.
        for pane in [inspector.view, editorHost, editor.scrollView] {
            pane.setContentHuggingPriority(.defaultLow, for: .horizontal)
            pane.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            splitController.view.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            splitController.view.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            splitController.view.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            status.topAnchor.constraint(equalTo: splitController.view.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 13),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -13),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -7),
            status.heightAnchor.constraint(equalToConstant: 17)
        ])
    }

    private func refreshInspector() {
        let data = InspectionContext.snapshot(editor)
        inspector.update(data)
        status.stringValue = "UTF-16 characters: \(editor.textStorage.length)    " +
            "Selection: {\(editor.inspectionRange.location), \(editor.inspectionRange.length)}    " +
            "Engine: NSLayoutManager (TextKit 1)    No pagination"
    }

    @objc private func reset(_ sender: Any?) { editor.reset() }
    @objc private func insertImage(_ sender: Any?) { editor.insertImage() }
    @objc private func insertTable(_ sender: Any?) { editor.insertTable() }
    @objc private func showTablePanel(_ sender: Any?) { editor.showTablePanel() }
    @objc private func showListPanel(_ sender: Any?) {
        window?.makeFirstResponder(editor.textView)
        editor.textView.orderFrontListPanel(nil)
    }
}
