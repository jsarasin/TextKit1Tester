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

    /// Clear all rows, retained snapshots, and unread counts. Re-added event
    /// types start enabled; the global recording switch is left unchanged.
    func clear() {
        types.removeAll()
        lookup.removeAll()
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
            EventDetail("NSRange.location", String(range.location)),
            EventDetail("NSRange.length", String(range.length))
        ])
    }

    static func notification(_ notification: Notification) -> [EventDetail] {
        var fields = [
            EventDetail("Notification.name", notification.name.rawValue),
            EventDetail("Notification.object", notification.object.map { String(reflecting: type(of: $0)) } ?? "nil")
        ]
        let info = (notification.userInfo ?? [:]).map {
            EventDetail(String(describing: $0.key), String(reflecting: $0.value))
        }.sorted { $0.name < $1.name }
        fields.append(EventDetail("Notification.userInfo", "\(info.count) fields", children: info))
        return fields
    }

    static func input(_ event: NSEvent) -> [EventDetail] {
        // AppKit raises NSInternalInconsistencyException when certain NSEvent
        // properties are read for the wrong event type.
        var fields = [
            EventDetail("type", String(describing: event.type)),
            EventDetail("windowNumber", String(event.windowNumber)),
            EventDetail("modifierFlags", String(describing: event.modifierFlags)),
            EventDetail("modifierFlags.rawValue", String(event.modifierFlags.rawValue))
        ]
        switch event.type {
        case .flagsChanged:
            fields.append(EventDetail("keyCode", String(event.keyCode)))
        case .keyDown, .keyUp:
            fields += [
                EventDetail("characters", String(reflecting: event.characters)),
                EventDetail("charactersIgnoringModifiers", String(reflecting: event.charactersIgnoringModifiers)),
                EventDetail("keyCode", String(event.keyCode)),
                EventDetail("isARepeat", String(event.isARepeat))
            ]
        case .leftMouseDown, .leftMouseUp,
             .rightMouseDown, .rightMouseUp,
             .otherMouseDown, .otherMouseUp:
            fields += [
                EventDetail("eventNumber", String(event.eventNumber)),
                EventDetail("locationInWindow", NSStringFromPoint(event.locationInWindow)),
                EventDetail("buttonNumber", String(event.buttonNumber)),
                EventDetail("clickCount", String(event.clickCount)),
                EventDetail("pressure", String(event.pressure))
            ]
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            fields += [
                EventDetail("eventNumber", String(event.eventNumber)),
                EventDetail("locationInWindow", NSStringFromPoint(event.locationInWindow)),
                EventDetail("buttonNumber", String(event.buttonNumber)),
                EventDetail("pressure", String(event.pressure)),
                EventDetail("deltaX", String(describing: event.deltaX)),
                EventDetail("deltaY", String(describing: event.deltaY)),
                EventDetail("deltaZ", String(describing: event.deltaZ))
            ]
        case .scrollWheel:
            fields += [
                EventDetail("locationInWindow", NSStringFromPoint(event.locationInWindow)),
                EventDetail("deltaX", String(describing: event.deltaX)),
                EventDetail("deltaY", String(describing: event.deltaY)),
                EventDetail("deltaZ", String(describing: event.deltaZ)),
                EventDetail("scrollingDeltaX", String(describing: event.scrollingDeltaX)),
                EventDetail("scrollingDeltaY", String(describing: event.scrollingDeltaY)),
                EventDetail("hasPreciseScrollingDeltas", String(event.hasPreciseScrollingDeltas)),
                EventDetail("phase", String(describing: event.phase)),
                EventDetail("momentumPhase", String(describing: event.momentumPhase)),
                EventDetail("isDirectionInvertedFromDevice", String(event.isDirectionInvertedFromDevice))
            ]
        default: break
        }
        return [EventDetail("event: NSEvent", String(reflecting: type(of: event)), children:
            fields.map { EventDetail("NSEvent.\($0.name)", $0.value, children: $0.children) }
        )]
    }
}

/// Links only actual Apple system APIs; custom inspector-only callbacks
/// and arbitrary notification payload keys intentionally have no link.
private enum AppleDocumentation {
    static let root = "https://developer.apple.com/documentation/"
    static let known: [String: String] = [
        "NSView.boundsDidChangeNotification": "appkit/nsview/boundsdidchangenotification",
        "NSTextStorage.willProcessEditingNotification": "appkit/nstextstorage/willprocesseditingnotification",
        "NSTextStorage.didProcessEditingNotification": "appkit/nstextstorage/didprocesseditingnotification",
        "NSTextView.didChangeTypingAttributesNotification": "appkit/nstextview/didchangetypingattributesnotification",
        "NSTextViewDelegate.textViewDidChangeSelection(_:)": "appkit/nstextviewdelegate/textviewdidchangeselection%28_%3A%29",
        "NSTextViewDelegate.textView(_:doCommandBy:)": "appkit/nstextviewdelegate/textview%28_%3Adocommandby%3A%29",
        "NSTextViewDelegate.textView(_:shouldChangeTextIn:replacementString:)": "appkit/nstextviewdelegate/textview%28_%3Ashouldchangetextin%3Areplacementstring%3A%29",
        "NSTextDelegate.textDidChange(_:)": "appkit/nstextdelegate/textdidchange%28_%3A%29",
        "NSTextDelegate.textDidBeginEditing(_:)": "appkit/nstextdelegate/textdidbeginediting%28_%3A%29",
        "NSTextDelegate.textDidEndEditing(_:)": "appkit/nstextdelegate/textdidendediting%28_%3A%29",
        "NSLayoutManagerDelegate.layoutManagerDidInvalidateLayout(_:)": "appkit/nslayoutmanagerdelegate/layoutmanagerdidinvalidatelayout%28_%3A%29",
        "NSLayoutManagerDelegate.layoutManager(_:didCompleteLayoutFor:atEnd:)": "appkit/nslayoutmanagerdelegate/layoutmanager%28_%3Adidcompletelayoutfor%3Aatend%3A%29",
        "Notification.name": "foundation/notification/name",
        "Notification.object": "foundation/notification/object",
        "Notification.userInfo": "foundation/notification/userinfo",
        "NSRange.location": "foundation/nsrange/location",
        "NSRange.length": "foundation/nsrange/length",
        "NSTextStorage.editedMask": "appkit/nstextstorage/editedmask",
        "NSTextStorage.editedRange": "appkit/nstextstorage/editedrange",
        "NSTextStorage.changeInLength": "appkit/nstextstorage/changeinlength",
        "NSTextStorage.length": "foundation/nsattributedstring/length",
        "NSTextView.selectedRanges": "appkit/nstextview/selectedranges",
        "NSTextView.selectedRange()": "appkit/nstextview/selectedrange",
        "NSTextView.typingAttributes": "appkit/nstextview/typingattributes",
        "NSClipView.bounds": "appkit/nsview/bounds",
        "NSLayoutManager.textContainers.count": "appkit/nslayoutmanager/textcontainers",
        "NSTextContainer.size": "appkit/nstextcontainer/size"
    ]
    private static let eventFields: Set<String> = [
        "type", "windowNumber", "modifierFlags", "characters",
        "charactersIgnoringModifiers", "keyCode", "isARepeat",
        "eventNumber", "locationInWindow", "buttonNumber", "clickCount",
        "pressure", "deltaX", "deltaY", "deltaZ", "scrollingDeltaX",
        "scrollingDeltaY", "hasPreciseScrollingDeltas", "phase",
        "momentumPhase", "isDirectionInvertedFromDevice"
    ]
    private static let responderMethods: Set<String> = [
        "keyDown", "keyUp", "flagsChanged", "mouseDown", "mouseUp",
        "mouseDragged", "rightMouseDown", "rightMouseUp",
        "rightMouseDragged", "otherMouseDown", "otherMouseUp",
        "otherMouseDragged", "scrollWheel"
    ]

    static func url(for symbol: String, eventType: String? = nil) -> URL? {
        if let path = known[symbol] { return URL(string: root + path) }

        if symbol.hasPrefix("InspectorTextView."), symbol.hasSuffix("(with:)") {
            // This application's text view overrides NSResponder APIs.
            let method = String(symbol.dropFirst("InspectorTextView.".count)
                                      .dropLast("(with:)".count))
            guard responderMethods.contains(method) else { return nil }
            return URL(string: root + "appkit/nsresponder/\(method.lowercased())%28with%3A%29")
        }

        if symbol.hasPrefix("NSEvent.") {
            let property = String(symbol.dropFirst("NSEvent.".count))
            if property == "modifierFlags.rawValue" {
                return URL(string: root + "appkit/nsevent/modifierflags")
            }
            guard eventFields.contains(property) else { return nil }
            return URL(string: root + "appkit/nsevent/\(property.lowercased())")
        }

        if symbol == "event: NSEvent" || symbol == "parameter.event" {
            return URL(string: root + "appkit/nsevent")
        }
        if symbol == "API.methodOrNotification", let eventType {
            return url(for: eventType)
        }
        // These are parameters, not standalone properties: show their
        // declaring method's parameter documentation instead.
        if let eventType, let method = known[eventType],
           ["affectedCharRange", "replacementString", "commandSelector",
            "sender.object", "layoutManager.object",
            "textContainer (NSTextContainer?)", "atEnd"].contains(symbol) {
            return URL(string: root + method)
        }
        return nil
    }
}

/// A lightweight button that opens the exact Apple API page in the user's
/// default browser without activating the outline row's double-click action.
private final class AppleDocumentationButton: NSButton {
    private var documentationURL: URL?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        image = NSImage(systemSymbolName: "info.circle",
                        accessibilityDescription: "Apple Developer Documentation")
        imagePosition = .imageOnly
        isBordered = false
        focusRingType = .none
        target = self
        action = #selector(openDocumentation(_:))
        setAccessibilityLabel("Open Apple Developer documentation")
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 19),
            heightAnchor.constraint(equalToConstant: 19)
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    func configure(symbol: String, eventType: String? = nil) {
        documentationURL = AppleDocumentation.url(for: symbol, eventType: eventType)
        isHidden = documentationURL == nil
        toolTip = documentationURL == nil ? nil : "Open Apple documentation for \(symbol)"
    }

    @objc private func openDocumentation(_ sender: Any?) {
        guard let documentationURL else { return }
        NSWorkspace.shared.open(documentationURL)
    }
}

private final class EventTypeCell: NSTableCellView {
    let toggle = NSButton(title: "Pause", target: nil, action: nil)
    let eventName = NSTextField(labelWithString: "")
    let documentationButton = AppleDocumentationButton(frame: .zero)
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

        let stack = NSStackView(views: [toggle, eventName, documentationButton, summary, badge])
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

private func detailCell(_ detail: EventDetail, eventType: String?) -> NSTableCellView {
    let cell = NSTableCellView()
    let field = NSTextField(labelWithString: "\(detail.name): \(detail.value)")
    field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    field.lineBreakMode = .byTruncatingTail
    field.toolTip = "\(detail.name): \(detail.value)"
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    let info = AppleDocumentationButton(frame: .zero)
    info.configure(symbol: detail.name, eventType: eventType)
    let stack = NSStackView(views: [field, info])
    stack.orientation = .horizontal
    stack.alignment = .centerY
    stack.spacing = 5
    stack.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 3),
        stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
        stack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
    ])
    return cell
}

/// History values wrap instead of truncating, so captured values remain readable
/// and selectable, even when the payload is wider than the window.
private func historyCell(_ text: String,
                         documentationSymbol: String? = nil,
                         eventType: String? = nil) -> NSTableCellView {
    let cell = NSTableCellView()
    let field = NSTextField(wrappingLabelWithString: text)
    field.isSelectable = true
    field.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
    field.maximumNumberOfLines = 0
    field.toolTip = text
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

    let info = AppleDocumentationButton(frame: .zero)
    if let documentationSymbol {
        info.configure(symbol: documentationSymbol, eventType: eventType)
    } else {
        info.isHidden = true
    }
    let stack = NSStackView(views: [field, info])
    stack.orientation = .horizontal
    stack.alignment = .top
    stack.spacing = 5
    stack.translatesAutoresizingMaskIntoConstraints = false
    cell.addSubview(stack)
    NSLayoutConstraint.activate([
        stack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 4),
        stack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -5),
        stack.topAnchor.constraint(equalTo: cell.topAnchor, constant: 4),
        stack.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4)
    ])
    return cell
}

/// A separate window for the last five snapshots of one event type.
final class EventHistoryWindowController: NSWindowController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let record: EventTypeRecord
    private let outline = NSOutlineView()

    init(record: EventTypeRecord) {
        self.record = record
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 830, height: 470),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: false)
        panel.title = "Event History"
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.center()
        super.init(window: panel)
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        outline.headerView = nil
        outline.rowHeight = 25
        outline.usesAutomaticRowHeights = true
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("History"))
        column.resizingMask = .autoresizingMask
        outline.addTableColumn(column)
        outline.outlineTableColumn = column
        outline.delegate = self
        outline.dataSource = self
        scroll.documentView = outline
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let host = NSView()
        let title = NSTextField(labelWithString: record.name)
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byTruncatingTail
        title.toolTip = record.name
        title.translatesAutoresizingMaskIntoConstraints = false
        let titleDocumentation = AppleDocumentationButton(frame: .zero)
        titleDocumentation.configure(symbol: record.name)
        let titleRow = NSStackView(views: [title, titleDocumentation])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 5
        titleRow.translatesAutoresizingMaskIntoConstraints = false
        title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        host.addSubview(titleRow)
        host.addSubview(scroll)
        panel.contentView = host
        NSLayoutConstraint.activate([
            titleRow.topAnchor.constraint(equalTo: host.topAnchor, constant: 12),
            titleRow.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 12),
            titleRow.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -12),
            scroll.topAnchor.constraint(equalTo: titleRow.bottomAnchor, constant: 10),
            scroll.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -8),
            scroll.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: 8),
            scroll.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -8)
        ])
        reload()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) unavailable") }

    /// Keep the utility panel above its owning main window, not merely above
    /// other windows on the desktop.
    func show(above parent: NSWindow?) {
        guard let panel = window else { return }
        if let parent, panel.parent !== parent {
            panel.parent?.removeChildWindow(panel)
            parent.addChildWindow(panel, ordered: .above)
        }
        showWindow(nil)
        panel.orderFront(nil)
    }

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
            let index = record.history.firstIndex(where: { $0 === occurrence }) ?? 0
            return historyCell("Occurrence \(index + 1) — \(occurrence.summary)")
        }
        guard let detail = item as? EventDetail else { return nil }
        return historyCell("\(detail.name): \(detail.value)",
                           documentationSymbol: detail.name, eventType: record.name)
    }
}

final class EventTrackerViewController: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    private let recorder: EventRecorder
    private let outline = NSOutlineView()
    private let globalButton = NSButton()
    private let clearButton = NSButton()
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

        let hint = NSTextField(labelWithString: "Double-click for last 5 occurrences")
        hint.font = .systemFont(ofSize: 10)
        hint.textColor = .tertiaryLabelColor
        hint.lineBreakMode = .byTruncatingTail
        hint.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        clearButton.title = "Clear"
        clearButton.target = self
        clearButton.action = #selector(clearEvents(_:))
        clearButton.bezelStyle = .rounded
        clearButton.controlSize = .small
        clearButton.toolTip = "Clear the event list and all retained histories"

        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [heading, globalButton, hint, spacer, clearButton])
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
            header.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -9),
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

    @objc private func clearEvents(_ sender: NSButton) {
        for controller in historyWindows.values {
            if let panel = controller.window {
                panel.parent?.removeChildWindow(panel)
            }
            controller.close()
        }
        historyWindows.removeAll()
        recorder.clear()
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
        controller.show(above: view.window)
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

    private func parentEventType(for detail: EventDetail) -> String? {
        var current: Any = detail
        while let parent = outline.parent(forItem: current) {
            if let type = parent as? EventTypeRecord { return type.name }
            current = parent
        }
        return nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        if let type = item as? EventTypeRecord {
            let cell = EventTypeCell(frame: .zero)
            cell.eventName.stringValue = type.name
            cell.eventName.toolTip = type.name
            cell.documentationButton.configure(symbol: type.name)
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
        return detailCell(detail, eventType: parentEventType(for: detail))
    }
}
