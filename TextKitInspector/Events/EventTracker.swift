import AppKit

/// A readable, expandable snapshot. Values are captured when the event arrives:
/// no NSTextView or NSEvent references are retained by the recorder.
final class EventDetail: NSObject {
    let name: String
    let value: String
    let children: [EventDetail]

    init(_ name: String, _ value: String, children: [EventDetail] = []) {
        self.name = name
        self.value = value
        self.children = children
    }
}

final class EventOccurrence: NSObject {
    let date = Date()
    let summary: String
    let details: [EventDetail]

    init(summary: String, details: [EventDetail]) {
        self.summary = summary
        self.details = details
    }
}

final class EventTypeRecord: NSObject {
    let name: String
    var isEnabled = true
    var unreadCount = 0
    var history: [EventOccurrence] = []

    init(name: String) { self.name = name }
    var latest: EventOccurrence? { history.first }
}

/// In-memory ring buffers only. Paused events are dropped before any payload is retained.
final class EventRecorder {
    private(set) var types: [EventTypeRecord] = []
    private var lookup: [String: EventTypeRecord] = [:]
    var isEnabled = true { didSet { scheduleRefresh() } }
    var onChange: (() -> Void)?
    private var refreshScheduled = false

    func record(_ type: String, summary: String, details: [EventDetail]) {
        guard isEnabled else { return }
        let item: EventTypeRecord
        if let existing = lookup[type] {
            item = existing
        } else {
            item = EventTypeRecord(name: type)
            lookup[type] = item
            types.append(item)
        }
        guard item.isEnabled else { return }
        item.history.insert(EventOccurrence(summary: summary, details: details), at: 0)
        if item.history.count > 5 { item.history.removeLast(item.history.count - 5) }
        item.unreadCount += 1
        scheduleRefresh()
    }

    func inspect(_ item: EventTypeRecord) {
        guard item.unreadCount > 0 else { return }
        item.unreadCount = 0
        scheduleRefresh()
    }

    func setEnabled(_ enabled: Bool, for item: EventTypeRecord) {
        item.isEnabled = enabled
        scheduleRefresh()
    }

    /// Coalesce rapid key/mouse/layout events into one list refresh per run-loop turn.
    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshScheduled = false
            self.onChange?()
        }
    }
}

/// Event payload extraction is intentionally limited to information applicable to
/// the particular event family, avoiding NSEvent properties that throw for other types.
enum EventPayload {
    static func range(_ name: String, _ range: NSRange) -> EventDetail {
        EventDetail(name, NSStringFromRange(range), children: [
            EventDetail("location", String(range.location)),
            EventDetail("length", String(range.length))
        ])
    }

    static func notification(_ notification: Notification) -> [EventDetail] {
        var fields = [
            EventDetail("notification.name", notification.name.rawValue),
            EventDetail("notification.object", notification.object.map { String(reflecting: type(of: $0)) } ?? "nil")
        ]
        let info = (notification.userInfo ?? [:]).map {
            EventDetail(String(describing: $0.key), String(reflecting: $0.value))
        }.sorted { $0.name < $1.name }
        fields.append(EventDetail("userInfo", "\(info.count) fields", children: info))
        return fields
    }

    static func input(_ event: NSEvent) -> [EventDetail] {
        var fields = [
            EventDetail("type", String(describing: event.type)),
            EventDetail("timestamp", String(format: "%.6f", event.timestamp)),
            EventDetail("eventNumber", String(event.eventNumber)),
            EventDetail("windowNumber", String(event.windowNumber)),
            EventDetail("locationInWindow", NSStringFromPoint(event.locationInWindow)),
            EventDetail("modifierFlags", String(describing: event.modifierFlags)),
            EventDetail("modifierFlags.rawValue", String(event.modifierFlags.rawValue))
        ]
        switch event.type {
        case .keyDown, .keyUp:
            fields += [
                EventDetail("characters", String(reflecting: event.characters)),
                EventDetail("charactersIgnoringModifiers", String(reflecting: event.charactersIgnoringModifiers)),
                EventDetail("keyCode", String(event.keyCode)),
                EventDetail("isARepeat", String(event.isARepeat))
            ]
        case .leftMouseDown, .leftMouseUp, .leftMouseDragged,
             .rightMouseDown, .rightMouseUp, .rightMouseDragged,
             .otherMouseDown, .otherMouseUp, .otherMouseDragged:
            fields += [
                EventDetail("buttonNumber", String(event.buttonNumber)),
                EventDetail("clickCount", String(event.clickCount)),
                EventDetail("pressure", String(event.pressure)),
                EventDetail("deltaX", String(event.deltaX)),
                EventDetail("deltaY", String(event.deltaY)),
                EventDetail("deltaZ", String(event.deltaZ))
            ]
        case .scrollWheel:
            fields += [
                EventDetail("deltaX", String(event.deltaX)),
                EventDetail("deltaY", String(event.deltaY)),
                EventDetail("deltaZ", String(event.deltaZ)),
                EventDetail("scrollingDeltaX", String(event.scrollingDeltaX)),
                EventDetail("scrollingDeltaY", String(event.scrollingDeltaY)),
                EventDetail("hasPreciseScrollingDeltas", String(event.hasPreciseScrollingDeltas)),
                EventDetail("phase", String(describing: event.phase)),
                EventDetail("momentumPhase", String(describing: event.momentumPhase)),
                EventDetail("isDirectionInvertedFromDevice", String(event.isDirectionInvertedFromDevice))
            ]
        default: break
        }
        return fields
    }
}

private final class EventTypeCell: NSTableCellView {
    let toggle = NSButton(title: "Pause", target: nil, action: nil)
    let eventName = NSTextField(labelWithString: "")
    let summary = NSTextField(labelWithString: "")
    let badge = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        toggle.bezelStyle = .rounded
        toggle.controlSize = .mini
        toggle.font = .systemFont(ofSize: 10)
        toggle.setContentHuggingPriority(.required, for: .horizontal)

        eventName.font = .systemFont(ofSize: 11, weight: .semibold)
        eventName.lineBreakMode = .byTruncatingTail
        eventName.setContentHuggingPriority(.defaultHigh, for: .horizontal)
        eventName.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        summary.font = .systemFont(ofSize: 11)
        summary.textColor = .secondaryLabelColor
        summary.lineBreakMode = .byTruncatingTail
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        badge.font = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        badge.textColor = .white
        badge.alignment = .center
        badge.wantsLayer = true
        badge.layer?.cornerRadius = 9
        badge.layer?.backgroundColor = NSColor.controlAccentColor.cgColor
        badge.setContentHuggingPriority(.required, for: .horizontal)
        badge.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [toggle, eventName, summary, badge])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -7),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),
            badge.heightAnchor.constraint(equalToConstant: 18)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }
}

private func detailCell(_ text: String, tooltip: String? = nil) -> NSTableCellView {
    let cell = NSTableCellView()
    let field = NSTextField(labelWithString: text)
    field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    field.lineBreakMode = .byTruncatingTail
    field.toolTip = tooltip ?? text
    field.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(field)
    NSLayoutConstraint.activate([
        field.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
        field.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
        field.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])
    return cell
}

/// A separate window for the last five snapshots of one event type.
final class EventHistoryWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let record: EventTypeRecord
    private let outline = NSOutlineView()

    init(record: EventTypeRecord) {
        self.record = record
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 830, height: 470),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "\(record.name) — Recent Events (max 5)"
        window.center()
        super.init(window: window)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        outline.headerView = nil
        outline.rowHeight = 25
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.delegate = self
        outline.dataSource = self
        scroll.documentView = outline
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        host.addSubview(scroll)
        window.contentView = host
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8)
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func reload() {
        let expanded = record.history.filter { outline.isItemExpanded($0) }
        outline.reloadData()
        for occurrence in expanded { outline.expandItem(occurrence) }
        if expanded.isEmpty {
            for occurrence in record.history { outline.expandItem(occurrence) }
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return record.history.count }
        if let occurrence = item as? EventOccurrence { return occurrence.details.count }
        return (item as? EventDetail)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return record.history[index] }
        if let occurrence = item as? EventOccurrence { return occurrence.details[index] }
        return (item as! EventDetail).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let occurrence = item as? EventOccurrence { return !occurrence.details.isEmpty }
        return !((item as? EventDetail)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let occurrence = item as? EventOccurrence {
            let date = DateFormatter.localizedString(from: occurrence.date, dateStyle: .none, timeStyle: .medium)
            return detailCell("\(date)     \(occurrence.summary)")
        }
        guard let detail = item as? EventDetail else { return nil }
        return detailCell("\(detail.name): \(detail.value)")
    }
}

final class EventTrackerViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let recorder: EventRecorder
    private let outline = NSOutlineView()
    private let globalButton = NSButton()
    private var historyWindows: [String: EventHistoryWindowController] = [:]

    init(recorder: EventRecorder) {
        self.recorder = recorder
        super.init(nibName: nil, bundle: nil)
        recorder.onChange = { [weak self] in self?.reload() }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    override func loadView() {
        let host = NSView()
        self.view = host

        let heading = NSTextField(labelWithString: "EVENT TRACKER")
        heading.font = .systemFont(ofSize: 11, weight: .semibold)
        heading.textColor = .secondaryLabelColor

        globalButton.target = self
        globalButton.action = #selector(toggleGlobal(_:))
        globalButton.bezelStyle = .rounded
        globalButton.controlSize = .small
        syncGlobalButton()

        let hint = NSTextField(labelWithString: "Double-click an event for its last 5 occurrences")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor

        let header = NSStackView(views: [heading, globalButton, hint])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 10
        header.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(header)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        outline.headerView = nil
        outline.rowHeight = 26
        outline.selectionHighlightStyle = .regular
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Events"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.delegate = self
        outline.dataSource = self
        outline.target = self
        outline.doubleAction = #selector(openHistory(_:))
        scroll.documentView = outline
        host.addSubview(scroll)

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: host.topAnchor, constant: 8),
            header.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 9),
            header.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -8),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 6),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 7),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -7),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -6)
        ])
        reload()
    }

    private func reload() {
        guard isViewLoaded else { return }
        syncGlobalButton()
        let expanded = recorder.types.filter { outline.isItemExpanded($0) }
        outline.reloadData()
        for event in expanded { outline.expandItem(event) }
        for controller in historyWindows.values { controller.reload() }
    }

    private func syncGlobalButton() {
        globalButton.title = recorder.isEnabled ? "Pause All" : "Resume All"
        globalButton.toolTip = recorder.isEnabled ? "Stop recording every event" : "Resume enabled event types"
    }

    @objc private func toggleGlobal(_ sender: NSButton) {
        recorder.isEnabled.toggle()
    }

    @objc private func toggleType(_ sender: NSButton) {
        guard recorder.types.indices.contains(sender.tag) else { return }
        let item = recorder.types[sender.tag]
        recorder.setEnabled(!item.isEnabled, for: item)
    }

    @objc private func openHistory(_ sender: Any?) {
        let row = outline.clickedRow >= 0 ? outline.clickedRow : outline.selectedRow
        guard row >= 0, var item = outline.item(atRow: row) else { return }
        while !(item is EventTypeRecord) {
            guard let parent = outline.parent(forItem: item) else { return }
            item = parent
        }
        guard let record = item as? EventTypeRecord else { return }
        recorder.inspect(record)
        let controller: EventHistoryWindowController
        if let existing = historyWindows[record.name] {
            controller = existing
        } else {
            controller = EventHistoryWindowController(record: record)
            historyWindows[record.name] = controller
        }
        controller.reload()
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        guard outline.selectedRow >= 0,
              let item = outline.item(atRow: outline.selectedRow) else { return }
        var current: Any = item
        while !(current is EventTypeRecord) {
            guard let parent = outline.parent(forItem: current) else { return }
            current = parent
        }
        if let record = current as? EventTypeRecord { recorder.inspect(record) }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        for item in recorder.types where outline.isItemExpanded(item) {
            recorder.inspect(item)
        }
    }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        if item == nil { return recorder.types.count }
        if let type = item as? EventTypeRecord { return type.latest?.details.count ?? 0 }
        return (item as? EventDetail)?.children.count ?? 0
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        if item == nil { return recorder.types[index] }
        if let type = item as? EventTypeRecord { return type.latest!.details[index] }
        return (item as! EventDetail).children[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        if let type = item as? EventTypeRecord { return !(type.latest?.details.isEmpty ?? true) }
        return !((item as? EventDetail)?.children.isEmpty ?? true)
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let type = item as? EventTypeRecord {
            let cell = EventTypeCell(frame: .zero)
            cell.eventName.stringValue = type.name
            cell.eventName.toolTip = type.name
            cell.summary.stringValue = type.latest?.summary ?? ""
            cell.summary.toolTip = type.latest?.summary
            cell.toggle.title = type.isEnabled ? "Pause" : "Play"
            cell.toggle.toolTip = type.isEnabled ? "Suppress this event type" : "Record this event type"
            cell.toggle.target = self
            cell.toggle.action = #selector(toggleType(_:))
            cell.toggle.tag = recorder.types.firstIndex(where: { $0 === type }) ?? -1
            cell.badge.stringValue = " \(type.unreadCount) "
            cell.badge.isHidden = type.unreadCount == 0
            return cell
        }
        guard let detail = item as? EventDetail else { return nil }
        return detailCell("\(detail.name): \(detail.value)")
    }
}
