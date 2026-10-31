import AppKit

final class MainWindowController: NSWindowController {
    private let editor = EditorController()
    private let inspector = InspectorViewController()
    private let status = NSTextField(labelWithString: "")

    convenience init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1520, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "TextKit Inspector — Native TextKit 1 Laboratory"
        window.center()
        window.minSize = NSSize(width: 1000, height: 580)
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

        let split = NSSplitView()
        split.isVertical = true
        split.dividerStyle = .thin
        split.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(split)
        let editorHost = NSView()
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
        split.addArrangedSubview(inspector.view)
        split.addArrangedSubview(editorHost)
        inspector.view.widthAnchor.constraint(greaterThanOrEqualToConstant: 380).isActive = true
        editorHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 460).isActive = true

        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            split.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            split.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            split.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            status.topAnchor.constraint(equalTo: split.bottomAnchor, constant: 6),
            status.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 13),
            status.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -13),
            status.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -7),
            status.heightAnchor.constraint(equalToConstant: 17)
        ])
        // Start with a comfortable inspector width. The split divider remains freely draggable.
        // Position after Auto Layout installs the split-view geometry.
        DispatchQueue.main.async { [weak split] in
            split?.setPosition(535, ofDividerAt: 0)
        }
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
