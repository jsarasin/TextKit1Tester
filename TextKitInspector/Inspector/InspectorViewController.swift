import AppKit

/// A native, expandable two-column property grid. Rows are backed by actual
/// InspectionSnapshot data, never by a parallel set of display-only values.
private enum InspectorEntry {
    case group(InspectionGroup)
    case property(InspectedProperty)
    case cellGrid(row: Int, column: Int, rows: Int, columns: Int)
}

private final class InspectorNode: NSObject {
    let key: String
    let entry: InspectorEntry
    var children: [InspectorNode]

    init(key: String, entry: InspectorEntry, children: [InspectorNode] = []) {
        self.key = key
        self.entry = entry
        self.children = children
    }
}

private final class InspectorEditField: NSTextField {
    var onApply: ((String) -> Void)?

    @objc private func submit(_ sender: Any?) {
        onApply?(stringValue)
    }

    convenience init(value: String, onApply: @escaping (String) -> Void) {
        self.init(string: value)
        self.onApply = onApply
        target = self
        action = #selector(submit(_:))
        font = .systemFont(ofSize: 13)
        alignment = .left
        lineBreakMode = .byTruncatingMiddle
    }
}

/// AppKit may temporarily assign zero width to NSOutlineView cell views while
/// measuring columns. Size child controls from their actual row frame instead
/// of constraining both edges with positive insets (which is unsatisfiable at 0).
private final class FlexibleInspectorCell: NSTableCellView {
    var trailingBadge: NSTextField?
    var accentBar: NSBox?
    var embeddedContent: NSView?

    override func layout() {
        super.layout()
        let width = max(0, bounds.width)
        let height = max(0, bounds.height)
        let startX: CGFloat = accentBar == nil ? 6 : 15

        if let accentBar {
            accentBar.frame = NSRect(
                x: 4, y: max(0, (height - 17) / 2),
                width: 5, height: min(17, height)
            )
        }

        if let embeddedContent {
            let fitting = embeddedContent.fittingSize
            embeddedContent.frame = NSRect(
                x: 6, y: max(0, (height - fitting.height) / 2),
                width: fitting.width, height: fitting.height
            )
        }

        if let trailingBadge {
            let badgeWidth = min(width, max(0, ceil(trailingBadge.intrinsicContentSize.width) + 2))
            trailingBadge.frame = NSRect(
                x: max(0, width - badgeWidth - 8), y: 0,
                width: badgeWidth, height: height
            )
            textField?.frame = NSRect(
                x: startX, y: 0,
                width: max(0, trailingBadge.frame.minX - startX - 7),
                height: height
            )
        } else if embeddedContent == nil {
            textField?.frame = NSRect(
                x: startX, y: 0,
                width: max(0, width - startX - 6),
                height: height
            )
        }
    }
}

final class InspectorViewController: NSViewController, NSSearchFieldDelegate,
                                     NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onEdit: ((PropertyAction, String) -> Void)?

    private var snapshot: InspectionSnapshot?
    private var expanded: Set<String> = [
        "context", "relationships", "tableCell", "table", "attachment", "font"
    ]
    private var filter = ""
    private var nodes: [InspectorNode] = []
    private var restoringExpansion = false
    private var renderQueued = false

    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let search = NSSearchField()
    private let scroll = NSScrollView()
    private let outline = NSOutlineView()
    private let nameColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("property"))
    private let valueColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("value"))

    override func loadView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 530, height: 700))
        root.translatesAutoresizingMaskIntoConstraints = false
        view = root

        titleLabel.font = .systemFont(ofSize: 17, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        subtitleLabel.font = .systemFont(ofSize: 13)
        subtitleLabel.textColor = .secondaryLabelColor
        search.font = .systemFont(ofSize: 13)
        search.placeholderString = "Filter classes or properties…"
        search.delegate = self

        let header = NSStackView(views: [titleLabel, subtitleLabel, search])
        header.orientation = .vertical
        header.alignment = .leading
        header.spacing = 7
        header.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(header)
        for item in [titleLabel, subtitleLabel, search] {
            item.widthAnchor.constraint(equalTo: header.widthAnchor).isActive = true
        }

        let expand = NSButton(title: "Expand All", target: self, action: #selector(expandAll(_:)))
        let collapse = NSButton(title: "Collapse All", target: self, action: #selector(collapseAll(_:)))
        expand.bezelStyle = .inline
        collapse.bezelStyle = .inline
        expand.font = .systemFont(ofSize: 12)
        collapse.font = .systemFont(ofSize: 12)
        let controls = NSStackView(views: [expand, collapse])
        controls.orientation = .horizontal
        controls.spacing = 10
        controls.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(controls)

        // Native AppKit outline/table control: disclosure triangles, a table
        // header, user-adjustable column widths, keyboard navigation, and
        // visible-row reuse rather than rebuilding hundreds of stack views.
        nameColumn.title = "Property"
        nameColumn.width = 195
        nameColumn.minWidth = 0
        valueColumn.title = "Value"
        valueColumn.width = 330
        valueColumn.minWidth = 0
        outline.addTableColumn(nameColumn)
        outline.addTableColumn(valueColumn)
        outline.outlineTableColumn = nameColumn
        outline.autoresizesOutlineColumn = false
        outline.indentationPerLevel = 12
        outline.rowHeight = 30
        outline.allowsColumnResizing = true
        outline.allowsColumnReordering = false
        outline.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outline.headerView = NSTableHeaderView()
        outline.usesAlternatingRowBackgroundColors = true
        outline.dataSource = self
        outline.delegate = self

        let contextMenu = NSMenu()
        let copyItem = NSMenuItem(title: "Copy Value", action: #selector(copySelectedValue(_:)), keyEquivalent: "")
        copyItem.target = self
        contextMenu.addItem(copyItem)
        outline.menu = contextMenu

        scroll.documentView = outline
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: root.topAnchor, constant: 14),
            header.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            header.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            controls.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            controls.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.topAnchor.constraint(equalTo: controls.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        ])
    }

    func controlTextDidChange(_ notification: Notification) {
        filter = search.stringValue
        render()
    }

    func update(_ new: InspectionSnapshot) {
        snapshot = new
        loadViewIfNeeded()
        titleLabel.stringValue = new.summary
        subtitleLabel.stringValue = new.subtitle
        guard !renderQueued else { return }
        renderQueued = true
        DispatchQueue.main.async { [weak self] in
            self?.renderQueued = false
            self?.render()
        }
    }

    @objc private func expandAll(_ sender: Any?) {
        expanded = Set(snapshot?.groups.map(\.key) ?? [])
        render()
    }

    @objc private func collapseAll(_ sender: Any?) {
        expanded.removeAll()
        render()
    }

    /// Rebuild the lightweight row model, retaining which sections were open
    /// and the outline's vertical scroll position.
    private func render() {
        guard isViewLoaded, let snapshot else { return }
        let oldOffset = scroll.contentView.bounds.origin.y
        let term = filter.trimmingCharacters(in: .whitespacesAndNewlines)

        let rows = Int(snapshot.groups.first(where: { $0.key == "table" })?
            .properties.first(where: { $0.name == "numberOfRows" })?.value ?? "") ?? 4
        let columns = Int(snapshot.groups.first(where: { $0.key == "table" })?
            .properties.first(where: { $0.name == "numberOfColumns" })?.value ?? "") ?? 4

        nodes = snapshot.groups.compactMap { group -> InspectorNode? in
            let groupMatches = group.title.localizedCaseInsensitiveContains(term) ||
                               group.object.localizedCaseInsensitiveContains(term)
            let matchingProperties = group.properties.enumerated().filter { _, property in
                term.isEmpty || groupMatches ||
                property.name.localizedCaseInsensitiveContains(term) ||
                property.value.localizedCaseInsensitiveContains(term) ||
                property.explanation.localizedCaseInsensitiveContains(term)
            }
            guard term.isEmpty || groupMatches || !matchingProperties.isEmpty else { return nil }
            let children = matchingProperties.map { index, property in
                InspectorNode(key: "\(group.key)-property-\(index)", entry: .property(property))
            }
            let groupNode = InspectorNode(key: group.key, entry: .group(group), children: children)
            if group.key == "tableCell" && term.isEmpty,
               let row = Int(group.properties.first(where: { $0.name == "startingRow" })?.value ?? ""),
               let column = Int(group.properties.first(where: { $0.name == "startingColumn" })?.value ?? "") {
                groupNode.children.insert(
                    InspectorNode(key: "table-cell-map",
                                  entry: .cellGrid(row: row, column: column, rows: rows, columns: columns)),
                    at: 0
                )
            }
            return groupNode
        }

        restoringExpansion = true
        outline.reloadData()
        for node in nodes where !node.children.isEmpty && (term.isEmpty ? expanded.contains(node.key) : true) {
            outline.expandItem(node)
        }
        restoringExpansion = false

        // Clamp after rows change so scrolling a long table selection cannot
        // leave the inspector below its newly shortened content.
        let maxY = max(0, outline.bounds.height - scroll.contentView.bounds.height)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(oldOffset, maxY)))
        scroll.reflectScrolledClipView(scroll.contentView)
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        (item as? InspectorNode)?.children.count ?? nodes.count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if let parent = item as? InspectorNode { return parent.children[index] }
        return nodes[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? InspectorNode)?.children.isEmpty == false
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !restoringExpansion,
              let node = notification.userInfo?["NSObject"] as? InspectorNode else { return }
        expanded.insert(node.key)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !restoringExpansion,
              let node = notification.userInfo?["NSObject"] as? InspectorNode else { return }
        expanded.remove(node.key)
    }

    func outlineView(_ outlineView: NSOutlineView, heightOfRowByItem item: Any) -> CGFloat {
        guard let node = item as? InspectorNode else { return 30 }
        switch node.entry {
        case .group: return 34
        case .property: return 31
        case let .cellGrid(_, _, rows, _): return CGFloat(min(max(rows, 1), 6) * 25 + 10)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? InspectorNode, let tableColumn else { return nil }
        let isName = tableColumn === nameColumn

        switch node.entry {
        case let .group(group):
            if isName { return classHeaderCell(group) }
            return textCell(group.object,
                            font: .monospacedSystemFont(ofSize: 11, weight: .regular),
                            alignment: .left, color: .secondaryLabelColor)
        case let .property(property):
            if isName {
                let tooltip = property.explanation.isEmpty ? property.name :
                    "\(property.name)\n\(property.explanation)"
                if property.name.contains(" → ") {
                    return relationshipCell(property.name, tooltip: tooltip)
                }
                return textCell(property.name, font: .systemFont(ofSize: 13),
                                alignment: .right, color: .secondaryLabelColor,
                                tooltip: tooltip)
            }
            return valueCell(property)
        case let .cellGrid(row, column, rows, columns):
            if isName {
                return textCell("Cell map", font: .systemFont(ofSize: 13),
                                alignment: .right, color: .secondaryLabelColor)
            }
            return gridCell(row: row, column: column, rows: rows, columns: columns)
        }
    }

    // Each class has a stable colour in the inspector. The coloured rail keeps
    // label text at system contrast levels in both light and dark appearances.
    private func classAccent(for key: String) -> NSColor {
        switch key {
        case "scroll": return .systemPurple
        case "view", "typing": return .systemBlue
        case "container": return .systemTeal
        case "layout", "cellGeometry": return .systemOrange
        case "storage", "character", "attributes", "mixed": return .systemGreen
        case "font": return .systemIndigo
        case "paragraph": return .systemBrown
        case "tableCell": return .systemRed
        case "table": return .systemPink
        case "attachment": return .systemYellow
        case "image": return .systemCyan
        case "foreground", "background": return .systemMint
        case "link": return .systemBlue
        default:
            if key.hasPrefix("list-") { return .systemBrown }
            if key.hasPrefix("imageRep-") { return .systemCyan }
            if key.hasPrefix("run-") { return .systemGreen }
            return .systemGray
        }
    }

    private func classAccent(named name: String) -> NSColor? {
        switch name {
        case "NSScrollView", "NSClipView": return .systemPurple
        case "NSTextView": return .systemBlue
        case "NSTextContainer": return .systemTeal
        case "NSLayoutManager": return .systemOrange
        case "NSTextStorage", "NSMutableAttributedString", "NSAttributedString": return .systemGreen
        case "NSFont": return .systemIndigo
        case "NSParagraphStyle", "NSTextList": return .systemBrown
        case "NSTextTableBlock": return .systemRed
        case "NSTextTable": return .systemPink
        case "NSTextAttachment": return .systemYellow
        case "NSImage": return .systemCyan
        case "NSColor": return .systemMint
        default: return nil
        }
    }

    private func classHeaderCell(_ group: InspectionGroup) -> NSView {
        let cell = FlexibleInspectorCell()
        let bar = NSBox()
        bar.boxType = .custom
        bar.borderType = .noBorder
        bar.cornerRadius = 3
        bar.fillColor = classAccent(for: group.key)

        let title = NSTextField(labelWithString: group.title)
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = .labelColor
        title.lineBreakMode = .byTruncatingMiddle
        title.toolTip = group.title

        cell.addSubview(bar)
        cell.addSubview(title)
        cell.accentBar = bar
        cell.textField = title
        return cell
    }

    /// Colour the names in object-reference chains using the same palette
    /// as the class headers. No syntax-colouring is applied to actual values.
    private func relationshipCell(_ label: String, tooltip: String) -> NSView {
        let cell = textCell(label, font: .systemFont(ofSize: 13),
                            alignment: .right, color: .secondaryLabelColor,
                            tooltip: tooltip)
        guard let textField = (cell as? NSTableCellView)?.textField else { return cell }
        let styled = NSMutableAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: NSColor.secondaryLabelColor
        ])
        let nsLabel = label as NSString
        var searchStart = 0
        for part in label.components(separatedBy: " → ") {
            let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let color = classAccent(named: name), searchStart < nsLabel.length {
                let remaining = NSRange(location: searchStart, length: nsLabel.length - searchStart)
                let match = nsLabel.range(of: name, options: [], range: remaining)
                if match.location != NSNotFound {
                    styled.addAttributes([
                        .foregroundColor: color,
                        .font: NSFont.systemFont(ofSize: 13, weight: .semibold)
                    ], range: match)
                    searchStart = NSMaxRange(match)
                }
            }
        }
        textField.attributedStringValue = styled
        textField.alignment = .right
        return cell
    }

    private func textCell(_ value: String, font: NSFont, alignment: NSTextAlignment,
                          color: NSColor, tooltip: String? = nil) -> NSView {
        let cell = FlexibleInspectorCell()
        let label = NSTextField(labelWithString: value)
        label.font = font
        label.alignment = alignment
        label.textColor = color
        label.lineBreakMode = .byTruncatingMiddle
        label.toolTip = tooltip ?? value
        cell.addSubview(label)
        cell.textField = label
        return cell
    }

    private func valueCell(_ property: InspectedProperty) -> NSView {
        let cell = FlexibleInspectorCell()
        let value: NSTextField
        if let action = property.action {
            let editable = InspectorEditField(value: property.value) { [weak self] input in
                self?.onEdit?(action, input)
            }
            editable.toolTip = "Editable: \(property.explanation)\nPress Return to apply."
            value = editable
        } else {
            let label = NSTextField(labelWithString: property.value)
            label.font = .systemFont(ofSize: 13)
            label.alignment = .left
            label.lineBreakMode = .byTruncatingMiddle
            label.toolTip = property.value +
                (property.explanation.isEmpty ? "" : "\n" + property.explanation)
            value = label
        }

        let origin = NSTextField(labelWithString: property.origin.rawValue)
        origin.font = .systemFont(ofSize: 10)
        origin.alignment = .right
        origin.textColor = .tertiaryLabelColor

        cell.addSubview(value)
        cell.addSubview(origin)
        cell.textField = value
        cell.trailingBadge = origin
        return cell
    }

    /// The small cell map is a specialized value view inside the same grid.
    /// Cap its dimensions; the actual source table can have more rows/columns.
    private func gridCell(row: Int, column: Int, rows: Int, columns: Int) -> NSView {
        let cell = FlexibleInspectorCell()
        let displayRows = min(max(rows, 1), 6)
        let displayColumns = min(max(columns, 1), 6)
        let grid = NSGridView(views: (0..<displayRows).map { r in
            (0..<displayColumns).map { c -> NSView in
                let field = NSTextField(labelWithString: "\(r + 1),\(c + 1)")
                field.font = .monospacedSystemFont(ofSize: 11,
                    weight: (r == row && c == column) ? .semibold : .regular)
                field.alignment = .center
                field.wantsLayer = true
                field.layer?.cornerRadius = 3
                field.layer?.backgroundColor = (r == row && c == column
                    ? NSColor.selectedControlColor : NSColor.controlBackgroundColor).cgColor
                field.widthAnchor.constraint(greaterThanOrEqualToConstant: 34).isActive = true
                field.heightAnchor.constraint(equalToConstant: 23).isActive = true
                return field
            }
        })
        grid.rowSpacing = 2
        grid.columnSpacing = 2
        cell.wantsLayer = true
        cell.layer?.masksToBounds = true
        cell.addSubview(grid)
        cell.embeddedContent = grid
        return cell
    }

    @objc private func copySelectedValue(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, let node = outline.item(atRow: row) as? InspectorNode else { return }
        let value: String
        switch node.entry {
        case let .property(property): value = property.value
        case let .group(group): value = group.object
        case .cellGrid: return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
