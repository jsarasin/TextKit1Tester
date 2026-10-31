import AppKit

final class MainWindowController: NSWindowController {
    private let editor = EditorController()
    private let inspector = InspectorViewController()
    private let eventRecorder = EventRecorder()
    private lazy var eventTracker = EventTrackerViewController(recorder: eventRecorder)
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
        editor.onEvent = { [weak self] name, summary, details in
            self?.eventRecorder.record(name, summary: summary, details: details)
        }
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
            button("Insert Horizontal Rule", selector: #selector(insertHorizontalRule(_:))),
            button("Insert 4×4 Table", selector: #selector(insertTable(_:))),
            button("Apple Table Panel", selector: #selector(showTablePanel(_:))),
            button("List Panel", selector: #selector(showListPanel(_:)))
        ])
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 9
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(toolbar)

        // Fixed 50/50 layout. No NSSplitView, no divider and no adjustable
        // width preferences: both panes always occupy exactly half the window.
        let panes = NSView()
        panes.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(panes)

        let editorHost = NSView()
        editorHost.translatesAutoresizingMaskIntoConstraints = false
        let eventPanel = eventTracker.view
        let divider = EventTrackerResizeHandle()
        let eventHeight = eventPanel.heightAnchor.constraint(equalToConstant: 235)
        editorHost.addSubview(editor.scrollView)
        editorHost.addSubview(divider)
        editorHost.addSubview(eventPanel)
        editor.scrollView.translatesAutoresizingMaskIntoConstraints = false
        divider.translatesAutoresizingMaskIntoConstraints = false
        eventPanel.translatesAutoresizingMaskIntoConstraints = false
        // A draggable horizontal divider lets the event area grow or shrink,
        // without changing the permanent 50/50 inspector/editor columns.
        divider.onResize = { [weak editorHost] desiredHeight in
            guard let editorHost else { return }
            let maximum = max(110, editorHost.bounds.height - 160)
            eventHeight.constant = min(max(110, desiredHeight), maximum)
        }
        divider.currentHeight = { eventHeight.constant }
        NSLayoutConstraint.activate([
            editor.scrollView.topAnchor.constraint(equalTo: editorHost.topAnchor),
            editor.scrollView.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            editor.scrollView.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            editor.scrollView.bottomAnchor.constraint(equalTo: divider.topAnchor),
            divider.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: eventPanel.topAnchor),
            divider.heightAnchor.constraint(equalToConstant: 9),
            eventPanel.leadingAnchor.constraint(equalTo: editorHost.leadingAnchor),
            eventPanel.trailingAnchor.constraint(equalTo: editorHost.trailingAnchor),
            eventPanel.bottomAnchor.constraint(equalTo: editorHost.bottomAnchor),
            eventHeight
        ])

        let properties = inspector.view
        properties.translatesAutoresizingMaskIntoConstraints = false
        panes.addSubview(properties)
        panes.addSubview(editorHost)

        // Required equal widths plus edge constraints enforce 50/50 at every
        // window size. Never overwrite them in selection/resize callbacks.
        NSLayoutConstraint.activate([
            properties.leadingAnchor.constraint(equalTo: panes.leadingAnchor),
            properties.topAnchor.constraint(equalTo: panes.topAnchor),
            properties.bottomAnchor.constraint(equalTo: panes.bottomAnchor),

            editorHost.leadingAnchor.constraint(equalTo: properties.trailingAnchor),
            editorHost.trailingAnchor.constraint(equalTo: panes.trailingAnchor),
            editorHost.topAnchor.constraint(equalTo: panes.topAnchor),
            editorHost.bottomAnchor.constraint(equalTo: panes.bottomAnchor),

            properties.widthAnchor.constraint(equalTo: editorHost.widthAnchor)
        ])

        status.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        status.textColor = .secondaryLabelColor
        status.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(status)
        NSLayoutConstraint.activate([
            toolbar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            toolbar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            panes.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 10),
            panes.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 6),
            panes.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -6),
            status.topAnchor.constraint(equalTo: panes.bottomAnchor, constant: 6),
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
    @objc private func insertHorizontalRule(_ sender: Any?) { editor.insertHorizontalRule() }
    @objc private func insertTable(_ sender: Any?) { editor.insertTable() }
    @objc private func showTablePanel(_ sender: Any?) { editor.showTablePanel() }
    @objc private func showListPanel(_ sender: Any?) {
        window?.makeFirstResponder(editor.textView)
        editor.textView.orderFrontListPanel(nil)
    }
}


/// A thin, mouse-draggable split handle above the event list.
private final class EventTrackerResizeHandle: NSView {
    var currentHeight: (() -> CGFloat)?
    var onResize: ((CGFloat) -> Void)?
    private var dragStartY: CGFloat = 0
    private var heightAtDragStart: CGFloat = 0

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .resizeUpDown)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.midY, width: bounds.width, height: 1).fill()
    }

    override func mouseDown(with event: NSEvent) {
        dragStartY = event.locationInWindow.y
        heightAtDragStart = currentHeight?() ?? 235
    }

    override func mouseDragged(with event: NSEvent) {
        // The window's Y coordinates increase upwards. Dragging the handle
        // upwards increases the height of the bottom event panel.
        onResize?(heightAtDragStart + event.locationInWindow.y - dragStartY)
    }
}
