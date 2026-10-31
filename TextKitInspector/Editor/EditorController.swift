import AppKit
import UniformTypeIdentifiers

/// Owns the real TextKit 1 graph and editing transactions.
final class EditorController: NSObject, NSTextViewDelegate {
    let textView: InspectorTextView
    let scrollView: NSScrollView
    let textStorage: NSTextStorage
    let layoutManager: NSLayoutManager
    let textContainer: NSTextContainer
    var onContextChanged: (() -> Void)?
    private(set) var inspectionRange = NSRange(location: 0, length: 0)

    override init() {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        let text = InspectorTextView(frame: NSRect(x: 0, y: 0, width: 780, height: 900), textContainer: container)
        let scroll = NSScrollView()
        textView = text
        scrollView = scroll
        textStorage = storage
        layoutManager = layout
        textContainer = container
        super.init()

        text.isRichText = true
        text.importsGraphics = true
        text.isEditable = true
        text.isSelectable = true
        text.allowsUndo = true
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.minSize = NSSize(width: 0, height: 0)
        text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                              height: CGFloat.greatestFiniteMagnitude)
        text.textContainerInset = NSSize(width: 32, height: 30)
        text.font = .systemFont(ofSize: 15)
        text.backgroundColor = .textBackgroundColor
        text.delegate = self
        text.selectionDidMove = { [weak self] in self?.changed() }

        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = true
        scroll.documentView = text
        scroll.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(contentMoved),
            name: NSView.boundsDidChangeNotification, object: scroll.contentView)
        NotificationCenter.default.addObserver(self, selector: #selector(storageEdited),
            name: NSTextStorage.didProcessEditingNotification, object: storage)
        NotificationCenter.default.addObserver(self, selector: #selector(typingChanged),
            name: NSTextView.didChangeTypingAttributesNotification, object: text)
        reset()
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func contentMoved(_ notification: Notification) { onContextChanged?() }
    @objc private func storageEdited(_ notification: Notification) { onContextChanged?() }
    @objc private func typingChanged(_ notification: Notification) { onContextChanged?() }

    private func changed() {
        inspectionRange = textView.selectedRange()
        onContextChanged?()
    }

    func textViewDidChangeSelection(_ notification: Notification) { changed() }
    func textDidChange(_ notification: Notification) { changed() }

    func reset() {
        let image = Bundle.main.url(forResource: "SampleImage", withExtension: "png")
            .flatMap { NSImage(contentsOf: $0) }
        guard textView.shouldChangeText(in: NSRange(location: 0, length: textStorage.length),
                                        replacementString: nil) else { return }
        textStorage.setAttributedString(SampleDocument.make(image: image))
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.didChangeText()
        textView.undoManager?.removeAllActions()
        changed()
    }

    func insertTable() { replaceSelected(with: SampleDocument.makeTable()) }

    func insertHorizontalRule() {
        let selection = textView.rangeForUserTextChange
        guard selection.location != NSNotFound,
              NSMaxRange(selection) <= textStorage.length else { return }

        // A rule is a block-level element, represented by an attachment
        // character in its own paragraph. Avoid introducing a blank paragraph
        // when the caret already sits at a paragraph boundary.
        let text = textStorage.string as NSString
        let needsLeadingNewline = selection.location > 0 &&
            text.character(at: selection.location - 1) != 10
        let afterSelection = NSMaxRange(selection)
        let needsTrailingNewline = afterSelection == textStorage.length ||
            text.character(at: afterSelection) != 10

        let insertion = NSMutableAttributedString(string: "")
        if needsLeadingNewline {
            insertion.append(NSAttributedString(string: "\n"))
        }
        insertion.append(SampleDocument.makeHorizontalRule())
        if needsTrailingNewline {
            insertion.append(NSAttributedString(string: "\n"))
        }
        replaceSelected(with: insertion)
    }

    func insertImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let image = NSImage(contentsOf: url) else { return }
        let attachment = NSTextAttachment()
        attachment.image = image
        let width = min(image.size.width, 440)
        attachment.bounds = CGRect(x: 0, y: 0, width: width,
                                   height: width * image.size.height / max(1, image.size.width))
        replaceSelected(with: NSAttributedString(attachment: attachment))
    }

    func showTablePanel() {
        NSApp.keyWindow?.makeFirstResponder(textView)
        textView.orderFrontTablePanel(nil)
    }

    private func replaceSelected(with content: NSAttributedString) {
        let range = textView.rangeForUserTextChange
        guard range.location != NSNotFound,
              range.location + range.length <= textStorage.length,
              textView.shouldChangeText(in: range, replacementString: nil) else { return }
        let old = textStorage.attributedSubstring(from: range)
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(range: NSRange(location: range.location, length: content.length),
                           replacement: old, inverse: content)
        }
        textStorage.replaceCharacters(in: range, with: content)
        textView.setSelectedRange(NSRange(location: range.location + content.length, length: 0))
        textView.didChangeText()
        changed()
    }

    private func restore(range: NSRange, replacement: NSAttributedString, inverse: NSAttributedString) {
        guard NSMaxRange(range) <= textStorage.length else { return }
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(range: NSRange(location: range.location, length: replacement.length),
                           replacement: inverse, inverse: replacement)
        }
        textStorage.replaceCharacters(in: range, with: replacement)
        textView.setSelectedRange(NSRange(location: range.location + replacement.length, length: 0))
        textView.didChangeText()
        changed()
    }

    private func modify(range: NSRange, _ change: (NSMutableAttributedString) -> Void) {
        guard range.length > 0, NSMaxRange(range) <= textStorage.length else { return }
        let original = textStorage.attributedSubstring(from: range)
        let changedText = NSMutableAttributedString(attributedString: original)
        change(changedText)
        guard textView.shouldChangeText(in: range, replacementString: nil) else { return }
        textView.undoManager?.registerUndo(withTarget: self) { target in
            target.restore(range: range, replacement: original, inverse: changedText)
        }
        textStorage.replaceCharacters(in: range, with: changedText)
        textView.didChangeText()
        onContextChanged?()
    }

    /// Edits only supported safe properties; geometry/object identity fields are read-only.
    func apply(action: PropertyAction, text: String) {
        let selected = inspectionRange
        let index = min(selected.location, max(textStorage.length - 1, 0))
        let textNSString = textStorage.string as NSString
        let paragraph = textStorage.length > 0 ? textNSString.paragraphRange(for: NSRange(location: index, length: 0)) : NSRange(location: 0, length: 0)

        switch action {
        case .fontSize:
            guard let size = Double(text), (6...144).contains(size) else { return }
            if selected.length == 0 {
                let old = textView.typingAttributes
                var attrs = old
                let font = (old[.font] as? NSFont) ?? .systemFont(ofSize: 15)
                attrs[.font] = NSFontManager.shared.convert(font, toSize: CGFloat(size))
                textView.typingAttributes = attrs
            } else {
                modify(range: selected) { mutable in
                    var runs: [(NSRange, NSFont)] = []
                    mutable.enumerateAttribute(.font, in: NSRange(location: 0, length: mutable.length)) { value, run, _ in
                        runs.append((run, (value as? NSFont) ?? .systemFont(ofSize: 15)))
                    }
                    for (run, font) in runs {
                        mutable.addAttribute(.font, value: NSFontManager.shared.convert(font, toSize: CGFloat(size)), range: run)
                    }
                }
            }
        case .textColor:
            guard let color = NSColor(hex: text) else { return }
            if selected.length == 0 {
                var attrs = textView.typingAttributes
                attrs[.foregroundColor] = color
                textView.typingAttributes = attrs
            } else {
                modify(range: selected) { $0.addAttribute(.foregroundColor, value: color,
                                                          range: NSRange(location: 0, length: $0.length)) }
            }
        case .alignment, .lineSpacing:
            guard paragraph.length > 0 else { return }
            modify(range: paragraph) { mutable in
                let style = ((mutable.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy()
                             as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                switch action {
                case .alignment:
                    switch text.lowercased() {
                    case "left": style.alignment = .left
                    case "right": style.alignment = .right
                    case "center": style.alignment = .center
                    case "justified": style.alignment = .justified
                    default: return
                    }
                case .lineSpacing:
                    guard let value = Double(text), (0...80).contains(value) else { return }
                    style.lineSpacing = CGFloat(value)
                default: break
                }
                mutable.addAttribute(.paragraphStyle, value: style,
                                     range: NSRange(location: 0, length: mutable.length))
            }
        case .tablePadding, .tableBorder, .tableBackground:
            guard paragraph.length > 0,
                  let oldStyle = textStorage.attribute(.paragraphStyle, at: index, effectiveRange: nil) as? NSParagraphStyle,
                  let block = oldStyle.textBlocks.last(where: { $0 is NSTextTableBlock }) as? NSTextTableBlock,
                  let copy = block.copy() as? NSTextTableBlock else { return }
            if action == .tableBackground {
                guard let color = NSColor(hex: text) else { return }
                copy.backgroundColor = color
            } else {
                guard let size = Double(text), (0...40).contains(size) else { return }
                copy.setWidth(CGFloat(size), type: .absolute,
                              for: action == .tablePadding ? .padding : .border)
            }
            // Replace the paragraph style, rather than mutating shared blocks in-place.
            // For a multi-paragraph cell, this updates its current paragraph only.
            modify(range: paragraph) { mutable in
                let style = (oldStyle.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                style.textBlocks = oldStyle.textBlocks.map { $0 === block ? copy : $0 }
                mutable.addAttribute(.paragraphStyle, value: style,
                                     range: NSRange(location: 0, length: mutable.length))
            }
            layoutManager.invalidateLayout(forCharacterRange: paragraph, actualCharacterRange: nil)
        case .attachmentWidth, .attachmentHeight:
            guard textStorage.length > 0,
                  let attachment = textStorage.attribute(.attachment, at: index, effectiveRange: nil) as? NSTextAttachment,
                  let dimension = Double(text), (12...1500).contains(dimension) else { return }
            let newAttachment = NSTextAttachment()
            newAttachment.contents = attachment.contents
            newAttachment.fileType = attachment.fileType
            newAttachment.image = attachment.image
            var rect = attachment.bounds
            if action == .attachmentWidth { rect.size.width = CGFloat(dimension) }
            else { rect.size.height = CGFloat(dimension) }
            newAttachment.bounds = rect
            modify(range: NSRange(location: index, length: 1)) {
                $0.addAttribute(.attachment, value: newAttachment, range: NSRange(location: 0, length: 1))
            }
        case .textInset:
            guard let inset = Double(text), (0...200).contains(inset) else { return }
            textView.textContainerInset = NSSize(width: CGFloat(inset), height: CGFloat(inset))
            onContextChanged?()
        }
    }
}

private extension NSColor {
    convenience init?(hex: String) {
        let value = hex.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "#", with: "")
        guard value.count == 6, let number = UInt64(value, radix: 16) else { return nil }
        self.init(calibratedRed: CGFloat((number >> 16) & 255) / 255,
                  green: CGFloat((number >> 8) & 255) / 255,
                  blue: CGFloat(number & 255) / 255, alpha: 1)
    }
}
