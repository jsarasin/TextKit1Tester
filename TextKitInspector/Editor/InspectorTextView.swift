import AppKit

/// Tracks selection updates during text drag as well as ordinary keyboard and mouse moves.
final class InspectorTextView: NSTextView {
    var selectionDidMove: (() -> Void)?

    override func setSelectedRange(_ charRange: NSRange,
                                   affinity: NSSelectionAffinity,
                                   stillSelecting flag: Bool) {
        super.setSelectedRange(charRange, affinity: affinity, stillSelecting: flag)
        selectionDidMove?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        selectionDidMove?()
    }

    override func keyUp(with event: NSEvent) {
        super.keyUp(with: event)
        selectionDidMove?()
    }
}
