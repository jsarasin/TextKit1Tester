import AppKit

private final class ClickButton: NSButton {
    var pressed: (() -> Void)?
    @objc func clicked(_ sender: Any?) { pressed?() }
    convenience init(_ title: String, onPress: @escaping () -> Void) {
        self.init(title: title, target: nil, action: nil)
        self.pressed = onPress
        target = self
        action = #selector(clicked(_:))
        bezelStyle = .inline
    }
}

private final class EditField: NSTextField {
    var onApply: ((String) -> Void)?
    @objc func apply(_ sender: Any?) { onApply?(stringValue) }
    convenience init(_ value: String, onApply: @escaping (String) -> Void) {
        self.init(string: value)
        self.onApply = onApply
        self.target = self
        self.action = #selector(apply(_:))
        self.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
    }
}

private final class FlippedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

final class InspectorViewController: NSViewController, NSSearchFieldDelegate {
    var onEdit: ((PropertyAction, String) -> Void)?
    private var snapshot: InspectionSnapshot?
    private var expanded: Set<String> = ["context", "relationships", "tableCell", "table", "attachment", "font"]
    private var filter = ""
    private let scroll = NSScrollView()
    private let content = FlippedDocumentView()
    private let stack = NSStackView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let search = NSSearchField()
    private var renderQueued = false

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 445, height: 700))
        root.wantsLayer = true
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11)
        subtitleLabel.textColor = .secondaryLabelColor
        search.placeholderString = "Filter classes or properties…"
        search.delegate = self

        let header = NSStackView(views: [titleLabel, subtitleLabel, search])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        for item in [titleLabel, subtitleLabel, search] { item.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true }

        let expand = ClickButton("Expand All") { [weak self] in
            guard let self else { return }
            self.expanded = Set(self.snapshot?.groups.map(\.key) ?? [])
            self.render()
        }
        let collapse = ClickButton("Collapse All") { [weak self] in
            self?.expanded.removeAll()
            self?.render()
        }
        let controls = NSStackView(views: [expand, collapse])
        controls.orientation = .horizontal
        controls.spacing = 8
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)

        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.hasHorizontalScroller = false
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        content.frame = NSRect(x: 0, y: 0, width: 400, height: 600)
        scroll.documentView = content
        stack.orientation = .vertical
        stack.alignment = .width
        stack.distribution = .fill
        stack.spacing = 7
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 14),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -14),
            controls.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 12),
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 9),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        remeasure()
    }

    func controlTextDidChange(_ obj: Notification) {
        filter = search.stringValue
        render()
    }

    func update(_ new: InspectionSnapshot) {
        snapshot = new
        if !isViewLoaded { loadViewIfNeeded() }
        titleLabel.stringValue = new.summary
        subtitleLabel.stringValue = new.subtitle
        if !renderQueued {
            renderQueued = true
            DispatchQueue.main.async { [weak self] in
                self?.renderQueued = false
                self?.render()
            }
        }
    }

    private func render() {
        guard isViewLoaded, let snapshot else { return }
        let yOffset = scroll.contentView.bounds.origin.y
        for item in stack.arrangedSubviews { stack.removeArrangedSubview(item); item.removeFromSuperview() }
        for group in snapshot.groups {
            let matched = group.title.localizedCaseInsensitiveContains(filter)
                || group.properties.contains(where: {
                    $0.name.localizedCaseInsensitiveContains(filter) || $0.value.localizedCaseInsensitiveContains(filter)
                })
            if !filter.isEmpty && !matched { continue }
            stack.addArrangedSubview(groupView(group, searchActive: !filter.isEmpty))
        }
        remeasure()
        let maxOffset = max(0, (scroll.documentView?.frame.height ?? 0) - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(yOffset, maxOffset)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    private func remeasure() {
        guard isViewLoaded else { return }
        let width = max(260, scroll.contentView.bounds.width)
        content.frame.size.width = width
        let wanted = max(stack.fittingSize.height + 20, scroll.contentView.bounds.height)
        if abs(content.frame.height - wanted) > 0.5 { content.frame.size.height = wanted }
    }

    private func groupView(_ group: InspectionGroup, searchActive: Bool) -> NSView {
        let open = expanded.contains(group.key) || searchActive
        let outer = NSStackView()
        outer.orientation = .vertical
        outer.alignment = .width
        outer.spacing = 3
        outer.edgeInsets = NSEdgeInsets(top: 7, left: 7, bottom: 7, right: 7)
        outer.wantsLayer = true
        outer.layer?.cornerRadius = 6
        outer.layer?.borderWidth = 0.7
        outer.layer?.borderColor = NSColor.separatorColor.cgColor
        outer.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor

        let toggle = ClickButton((open ? "▾ " : "▸ ") + group.title) { [weak self] in
            guard let self else { return }
            if self.expanded.contains(group.key) { self.expanded.remove(group.key) }
            else { self.expanded.insert(group.key) }
            self.render()
        }
        toggle.font = .systemFont(ofSize: 12, weight: .semibold)
        toggle.alignment = .left
        outer.addArrangedSubview(toggle)

        if open {
            let identity = NSTextField(wrappingLabelWithString: group.object)
            identity.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            identity.textColor = .secondaryLabelColor
            identity.toolTip = group.object
            outer.addArrangedSubview(identity)
            if group.key == "tableCell" && filter.isEmpty,
               let row = Int(group.properties.first(where: { $0.name == "startingRow" })?.value ?? ""),
               let col = Int(group.properties.first(where: { $0.name == "startingColumn" })?.value ?? "") {
                outer.addArrangedSubview(tableGrid(selectedRow: row, selectedColumn: col))
            }
            for prop in group.properties where filter.isEmpty ||
                group.title.localizedCaseInsensitiveContains(filter) ||
                prop.name.localizedCaseInsensitiveContains(filter) || prop.value.localizedCaseInsensitiveContains(filter) {
                outer.addArrangedSubview(propertyView(prop))
            }
        }
        return outer
    }

    private func tableGrid(selectedRow: Int, selectedColumn: Int) -> NSView {
        let grid = NSGridView(views: (0..<4).map { r in
            (0..<4).map { c -> NSView in
                let cell = NSTextField(labelWithString: "\(r + 1),\(c + 1)")
                cell.font = .monospacedSystemFont(ofSize: 10, weight: r == selectedRow && c == selectedColumn ? .semibold : .regular)
                cell.alignment = .center
                cell.wantsLayer = true
                cell.layer?.cornerRadius = 3
                cell.layer?.backgroundColor = (r == selectedRow && c == selectedColumn
                    ? NSColor.selectedControlColor : NSColor.windowBackgroundColor).cgColor
                return cell
            }
        })
        grid.rowSpacing = 3
        grid.columnSpacing = 3
        return grid
    }

    private func propertyView(_ property: InspectedProperty) -> NSView {
        let line = NSStackView()
        line.orientation = .horizontal
        line.alignment = .centerY
        line.spacing = 6
        let label = NSTextField(labelWithString: property.name)
        label.font = .systemFont(ofSize: 10)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = property.explanation.isEmpty ? property.name : "\(property.name)\n\(property.explanation)"
        label.widthAnchor.constraint(equalToConstant: 144).isActive = true
        line.addArrangedSubview(label)

        if let action = property.action {
            let field = EditField(property.value) { [weak self] input in self?.onEdit?(action, input) }
            field.toolTip = "Edit: \(property.explanation)\nPress Return to apply."
            line.addArrangedSubview(field)
        } else {
            let field = NSTextField(labelWithString: property.value)
            field.font = .monospacedSystemFont(ofSize: 10, weight: .regular)
            field.lineBreakMode = .byTruncatingMiddle
            field.toolTip = property.value + (property.explanation.isEmpty ? "" : "\n" + property.explanation)
            line.addArrangedSubview(field)
            let copy = ClickButton("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(property.value, forType: .string) }
            copy.font = .systemFont(ofSize: 9)
            line.addArrangedSubview(copy)
        }
        let origin = NSTextField(labelWithString: property.origin.rawValue)
        origin.font = .systemFont(ofSize: 8)
        origin.textColor = .tertiaryLabelColor
        origin.widthAnchor.constraint(equalToConstant: 39).isActive = true
        line.addArrangedSubview(origin)
        return line
    }
}
