import AppKit

/// Tracks selection updates during text drag as well as ordinary keyboard and mouse moves.
final class InspectorTextView: NSTextView {
    var selectionDidMove: (() -> Void)?
    var onInputEvent: ((String, String, [EventDetail]) -> Void)?

    private func report(_ name: String, _ event: NSEvent) {
        let summary: String
        switch event.type {
        case .keyDown, .keyUp:
            summary = "keyCode \(event.keyCode)  \(String(reflecting: event.characters))"
        case .scrollWheel:
            summary = "delta=(\(event.scrollingDeltaX), \(event.scrollingDeltaY))"
        case .flagsChanged:
            summary = "modifiers=\(event.modifierFlags.rawValue) keyCode=\(event.keyCode)"
        default:
            summary = "position=\(NSStringFromPoint(event.locationInWindow))"
        }
        onInputEvent?(name, summary, EventPayload.input(event))
    }

    override func keyDown(with event: NSEvent) {
        report("keyDown", event)
        super.keyDown(with: event)
    }

    override func flagsChanged(with event: NSEvent) {
        report("flagsChanged", event)
        super.flagsChanged(with: event)
    }

    override func mouseDown(with event: NSEvent) {
        report("mouseDown", event)
        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        report("mouseDragged", event)
        super.mouseDragged(with: event)
    }

    override func rightMouseDown(with event: NSEvent) {
        report("rightMouseDown", event)
        super.rightMouseDown(with: event)
    }

    override func rightMouseUp(with event: NSEvent) {
        report("rightMouseUp", event)
        super.rightMouseUp(with: event)
    }

    override func rightMouseDragged(with event: NSEvent) {
        report("rightMouseDragged", event)
        super.rightMouseDragged(with: event)
    }

    override func otherMouseDown(with event: NSEvent) {
        report("otherMouseDown", event)
        super.otherMouseDown(with: event)
    }

    override func otherMouseUp(with event: NSEvent) {
        report("otherMouseUp", event)
        super.otherMouseUp(with: event)
    }

    override func otherMouseDragged(with event: NSEvent) {
        report("otherMouseDragged", event)
        super.otherMouseDragged(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        report("scrollWheel", event)
        super.scrollWheel(with: event)
    }

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        selectionDidMove?()
    }

    override func mouseUp(with event: NSEvent) {
        report("mouseUp", event)
        super.mouseUp(with: event)
        selectionDidMove?()
    }

    override func keyUp(with event: NSEvent) {
        report("keyUp", event)
        super.keyUp(with: event)
        selectionDidMove?()
    }
}
