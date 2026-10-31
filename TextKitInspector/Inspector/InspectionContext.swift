import AppKit

/// Inspector rows use explicit APIs. 'Derived' is never misrepresented as a native property.
enum PropertyAction: String {
    case fontSize, textColor, alignment, lineSpacing
    case tablePadding, tableBorder, tableBackground
    case attachmentWidth, attachmentHeight, textInset
}

enum PropertyOrigin: String { case live = "API", stored = "Stored", derived = "Derived", defaulted = "Default" }

struct InspectedProperty {
    let name: String
    let value: String
    let explanation: String
    let origin: PropertyOrigin
    let action: PropertyAction?

    init(_ name: String, _ value: String, _ explanation: String = "",
         _ origin: PropertyOrigin = .live, action: PropertyAction? = nil) {
        self.name = name
        self.value = value
        self.explanation = explanation
        self.origin = origin
        self.action = action
    }
}

struct InspectionGroup {
    let key: String
    let title: String
    let object: String
    var properties: [InspectedProperty]
}

struct InspectionSnapshot {
    let summary: String
    let subtitle: String
    let groups: [InspectionGroup]
}

/// Creates a fresh immutable view of the current text system; it never caches object values.
enum InspectionContext {
    static func snapshot(_ editor: EditorController) -> InspectionSnapshot {
        let view = editor.textView
        let storage = editor.textStorage
        let layout = editor.layoutManager
        let container = editor.textContainer
        let scroll = editor.scrollView
        let selection = editor.inspectionRange
        let count = storage.length
        let hasText = count > 0
        let characterIndex = hasText ? min(selection.location, count - 1) : 0
        let paragraphRange = hasText ? (storage.string as NSString).paragraphRange(
            for: NSRange(location: characterIndex, length: 0)) : NSRange(location: 0, length: 0)
        let activeAttributes = hasText ? storage.attributes(at: characterIndex, effectiveRange: nil) : [:]
        let explicitParagraphStyle = activeAttributes[.paragraphStyle] as? NSParagraphStyle
        let ps: NSParagraphStyle? = hasText ? (explicitParagraphStyle ?? NSParagraphStyle.default) : nil
        let block = ps?.textBlocks.compactMap { $0 as? NSTextTableBlock }.last
        let attachment = activeAttributes[.attachment] as? NSTextAttachment
        var groups: [InspectionGroup] = []
        func add(_ key: String, _ title: String, _ object: String, _ rows: [InspectedProperty]) {
            groups.append(InspectionGroup(key: key, title: title, object: object, properties: rows))
        }
        func p(_ name: String, _ value: Any, _ description: String = "",
               _ origin: PropertyOrigin = .live, _ action: PropertyAction? = nil) -> InspectedProperty {
            InspectedProperty(name, printable(value), description, origin, action: action)
        }
        func optional(_ any: Any?) -> String { any.map { printable($0) } ?? "nil" }
        let rangeString = range(selection)

        add("context", "Selection & Inspection Target", "Runtime inspection", [
            p("selectedRange", rangeString, "UTF-16 character units"),
            p("selectedRanges", view.selectedRanges.map { range($0.rangeValue) }.joined(separator: ", ")),
            p("inspectionIndex", hasText ? String(characterIndex) : "none", "At end of document, inspect preceding character", .derived),
            p("caretOrSelection", selection.length == 0 ? "Insertion point" : "Selected text", "Selection context", .derived),
            p("paragraphRange", range(paragraphRange), "NSString paragraph range", .derived),
            p("textLengthUTF16", count),
            p("selectionAffinity", String(describing: view.selectionAffinity)),
            p("firstResponder", view.window?.firstResponder === view ? "Text editor" : "Another control", "Inspector focus does not reset selection", .derived)
        ])

        var relationship: [InspectedProperty] = [
            p("NSScrollView → NSTextView", id(scroll) + " → " + id(view)),
            p("NSTextView → NSTextContainer", id(view) + " → " + id(container)),
            p("NSTextContainer → NSLayoutManager", id(container) + " → " + id(layout)),
            p("NSLayoutManager → NSTextStorage", id(layout) + " → " + id(storage))
        ]
        if let block {
            relationship.append(p("NSParagraphStyle → NSTextTableBlock", id(block)))
            relationship.append(p("NSTextTableBlock → NSTextTable", "\(id(block)) → \(id(block.table))"))
        }
        if let attachment { relationship.append(p("NSAttributedString → NSTextAttachment", id(attachment))) }
        add("relationships", "Object Relationships", "Actual live references", relationship)

        add("scroll", "NSScrollView / NSClipView", id(scroll), [
            p("frame", rect(scroll.frame)), p("bounds", rect(scroll.bounds)),
            p("documentVisibleRect", rect(scroll.documentVisibleRect)),
            p("contentView.bounds", rect(scroll.contentView.bounds)),
            p("documentView", optional(scroll.documentView.map(id))),
            p("hasVerticalScroller", scroll.hasVerticalScroller),
            p("hasHorizontalScroller", scroll.hasHorizontalScroller),
            p("autohidesScrollers", scroll.autohidesScrollers),
            p("verticalScrollPosition", scroll.contentView.bounds.origin.y)
        ])
        add("view", "NSTextView", id(view), [
            p("frame", rect(view.frame)), p("bounds", rect(view.bounds)),
            p("isEditable", view.isEditable), p("isSelectable", view.isSelectable),
            p("isRichText", view.isRichText), p("importsGraphics", view.importsGraphics),
            p("allowsUndo", view.allowsUndo),
            p("isVerticallyResizable", view.isVerticallyResizable),
            p("isHorizontallyResizable", view.isHorizontallyResizable),
            p("textContainerInset", size(view.textContainerInset), "Actual horizontal and vertical insets"),
            p("insetUniform (editable)", view.textContainerInset.width, "Apply a common inset in points", .derived, .textInset),
            p("minSize", size(view.minSize)), p("maxSize", size(view.maxSize)),
            p("backgroundColor", optional(view.backgroundColor)),
            p("isContinuousSpellCheckingEnabled", view.isContinuousSpellCheckingEnabled),
            p("usesFindBar", view.usesFindBar), p("usesFontPanel", view.usesFontPanel)
        ])
        add("container", "NSTextContainer", id(container), [
            p("size", size(container.size), "Very tall container for continuous layout"),
            p("widthTracksTextView", container.widthTracksTextView),
            p("heightTracksTextView", container.heightTracksTextView),
            p("lineFragmentPadding", container.lineFragmentPadding),
            p("lineBreakMode", String(describing: container.lineBreakMode)),
            p("exclusionPaths.count", container.exclusionPaths.count),
            p("layoutManager", optional(container.layoutManager.map(id))),
            p("textView", optional(container.textView.map(id)))
        ])
        var layoutRows = [
            p("numberOfGlyphs", layout.numberOfGlyphs),
            p("textContainers.count", layout.textContainers.count),
            p("usedRect", rect(layout.usedRect(for: container))),
            p("allowsNonContiguousLayout", layout.allowsNonContiguousLayout),
            p("usesFontLeading", layout.usesFontLeading)
        ]
        if hasText {
            let glyphs = layout.glyphRange(forCharacterRange: NSRange(location: characterIndex, length: 1), actualCharacterRange: nil)
            layoutRows.append(p("glyphRangeForCharacter", range(glyphs), "UTF-16 character → glyph conversion", .derived))
            if glyphs.length > 0 && glyphs.location < layout.numberOfGlyphs {
                var line = NSRange(location: 0, length: 0)
                let lineRect = layout.lineFragmentRect(forGlyphAt: glyphs.location, effectiveRange: &line)
                layoutRows += [
                    p("lineFragmentGlyphRange", range(line), "Line range in glyph indices", .derived),
                    p("lineFragmentRect", rect(lineRect), "Geometry in text container coordinates", .derived),
                    p("locationForGlyph", point(layout.location(forGlyphAt: glyphs.location)), "Position within line fragment", .derived),
                    p("glyphBoundingRect", rect(layout.boundingRect(forGlyphRange: glyphs, in: container)), "Actual glyph bounds", .derived)
                ]
            }
        }
        add("layout", "NSLayoutManager (TextKit 1)", id(layout), layoutRows)

        var storageRows = [
            p("length", storage.length, "UTF-16 code units"),
            p("stringPrefix", String(storage.string.prefix(100)), "Truncated preview", .derived),
            p("layoutManagers.count", storage.layoutManagers.count),
            p("editedRange", range(storage.editedRange)),
            p("changeInLength", storage.changeInLength)
        ]
        if hasText {
            var effective = NSRange(location: 0, length: 0)
            _ = storage.attributes(at: characterIndex, effectiveRange: &effective)
            storageRows.append(p("attributesEffectiveRange", range(effective), "Same attribute dictionary across this run", .derived))
            storageRows.append(p("attributesAtIndex.count", activeAttributes.count))
        }
        add("storage", "NSTextStorage / NSMutableAttributedString", id(storage), storageRows)

        add("typing", "NSTextView.typingAttributes", id(view),
            view.typingAttributes.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { key, value in
                p(key.rawValue, value, "Attributes applied to newly inserted text", .live,
                  key == .font ? .fontSize : key == .foregroundColor ? .textColor : nil)
            })

        if hasText {
            let string = storage.string as NSString
            add("character", "Character at Inspection Index", "UTF-16 offset \(characterIndex)", [
                p("character", string.substring(with: NSRange(location: characterIndex, length: 1))),
                p("UTF16 codeUnit", String(format: "U+%04X", string.character(at: characterIndex))),
                p("isParagraphBoundary", string.substring(with: NSRange(location: characterIndex, length: 1)) == "\n", "A newline can carry cell membership", .derived)
            ])
            let attrs = activeAttributes.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { key, value in
                p(key.rawValue, value, "Stored attributed-string key", .stored,
                  key == .font ? .fontSize : key == .foregroundColor ? .textColor : nil)
            }
            add("attributes", "NSAttributedString — Stored Attributes", "index \(characterIndex)", attrs)
        }

        if let font = (activeAttributes[.font] as? NSFont) ?? (view.typingAttributes[.font] as? NSFont) {
            let source: PropertyOrigin = activeAttributes[.font] != nil ? .stored : .defaulted
            add("font", "NSFont", id(font), [
                p("fontName", font.fontName, "PostScript font name", source),
                p("familyName", font.familyName ?? "nil", "Font family", source),
                p("pointSize", font.pointSize, "Font size in points", source, .fontSize),
                p("symbolicTraits", String(describing: font.fontDescriptor.symbolicTraits), "Weight, italic and other traits", source),
                p("fontDescriptor", font.fontDescriptor.postscriptName ?? "unknown", "Resolved font descriptor", .derived)
            ])
        }
        if let foreground = activeAttributes[.foregroundColor] as? NSColor {
            add("foreground", "NSColor — Foreground", id(foreground), [
                p("description", foreground),
                p("sRGB hex", hex(foreground), "Enter #RRGGBB", .derived, .textColor),
                p("colorSpace", String(describing: foreground.colorSpace))
            ])
        }
        if let background = activeAttributes[.backgroundColor] as? NSColor {
            add("background", "NSColor — Text Background", id(background), [
                p("description", background), p("sRGB hex", hex(background), "Display diagnostic", .derived)
            ])
        }
        if let ps {
            add("paragraph", "NSParagraphStyle", id(ps), [
                p("alignment", alignment(ps.alignment), "left / center / right / justified", explicitParagraphStyle == nil ? .defaulted : .stored, .alignment),
                p("firstLineHeadIndent", ps.firstLineHeadIndent),
                p("headIndent", ps.headIndent), p("tailIndent", ps.tailIndent),
                p("paragraphSpacing", ps.paragraphSpacing), p("paragraphSpacingBefore", ps.paragraphSpacingBefore),
                p("lineSpacing", ps.lineSpacing, "Spacing in points", explicitParagraphStyle == nil ? .defaulted : .stored, .lineSpacing),
                p("minimumLineHeight", ps.minimumLineHeight), p("maximumLineHeight", ps.maximumLineHeight),
                p("lineHeightMultiple", ps.lineHeightMultiple),
                p("lineBreakMode", String(describing: ps.lineBreakMode)),
                p("baseWritingDirection", String(describing: ps.baseWritingDirection)),
                p("defaultTabInterval", ps.defaultTabInterval),
                p("tabStops.count", ps.tabStops.count),
                p("textBlocks.count", ps.textBlocks.count), p("textLists.count", ps.textLists.count)
            ])
            for (i, list) in ps.textLists.enumerated() {
                add("list-\(i)", "NSTextList #\(i)", id(list), [
                    p("markerFormat", list.markerFormat.rawValue),
                    p("startingItemNumber", list.startingItemNumber),
                    p("isOrdered", list.isOrdered),
                    p("markerForItem1", list.marker(forItemNumber: 1))
                ])
            }
        }
        if let link = activeAttributes[.link] {
            add("link", "Hyperlink / .link attribute", "Stored URL or string", [
                p("link", link, "Open via standard NSTextView interaction", .stored),
                p("valueType", String(reflecting: type(of: link)), "Objective-C attributed value type", .derived)
            ])
        }
        if let attachment {
            var attachmentRows: [InspectedProperty] = [
                p("bounds", rect(attachment.bounds), "Displayed attachment rectangle in points"),
                p("displayWidth", attachment.bounds.width, "Enter point width", .derived, .attachmentWidth),
                p("displayHeight", attachment.bounds.height, "Enter point height", .derived, .attachmentHeight),
                p("fileType", optional(attachment.fileType)),
                p("contentsByteCount", attachment.contents?.count ?? 0),
                p("allowsTextAttachmentView", attachment.allowsTextAttachmentView),
                p("usesTextAttachmentView", attachment.usesTextAttachmentView),
                p("fileWrapper", optional(attachment.fileWrapper.map(id)))
            ]
            if let wrapper = attachment.fileWrapper {
                attachmentRows.append(p("fileWrapperName", wrapper.preferredFilename ?? wrapper.filename ?? "nil"))
                attachmentRows.append(p("fileWrapper.isRegularFile", wrapper.isRegularFile))
            }
            add("attachment", "NSTextAttachment", id(attachment), attachmentRows)
            if let image = attachment.image {
                add("image", "NSImage", id(image), [
                    p("size", size(image.size), "Logical image dimensions in points"),
                    p("representations.count", image.representations.count),
                    p("isValid", image.isValid),
                    p("name", image.name() ?? "nil")
                ])
                for (repIndex, rep) in image.representations.enumerated() {
                    var rows = [p("size", size(rep.size)),
                                p("pixelsWide", rep.pixelsWide), p("pixelsHigh", rep.pixelsHigh),
                                p("hasAlpha", rep.hasAlpha)]
                    if let bitmap = rep as? NSBitmapImageRep {
                        rows.append(p("bitsPerPixel", bitmap.bitsPerPixel))
                        rows.append(p("samplesPerPixel", bitmap.samplesPerPixel))
                        rows.append(p("colorSpaceName", bitmap.colorSpaceName.rawValue))
                    }
                    add("imageRep-\(repIndex)", String(describing: type(of: rep)), id(rep), rows)
                }
            }
        }

        if let block {
            add("tableCell", "NSTextTableBlock — Current Cell", id(block), [
                p("startingRow", block.startingRow), p("startingColumn", block.startingColumn),
                p("rowSpan", block.rowSpan), p("columnSpan", block.columnSpan),
                p("table", id(block.table)),
                p("backgroundColor", block.backgroundColor.map(hex) ?? "nil", "Enter #RRGGBB", .live, .tableBackground),
                p("verticalAlignment", String(describing: block.verticalAlignment))
            ] + blockProperties(block, actionForPadding: .tablePadding, actionForBorder: .tableBorder))

            let table = block.table
            var tableRows = [
                p("numberOfColumns", table.numberOfColumns),
                p("numberOfRows", rowCount(table, storage: storage), "Calculated from cell blocks", .derived),
                p("collapsesBorders", table.collapsesBorders),
                p("hidesEmptyCells", table.hidesEmptyCells),
                p("layoutAlgorithm", String(describing: table.layoutAlgorithm)),
                p("tableAttributedRange", range(storage.range(of: table, at: characterIndex)), "Range of this table", .derived),
                p("backgroundColor", table.backgroundColor.map(hex) ?? "nil")
            ]
            tableRows += blockProperties(table, actionForPadding: nil, actionForBorder: nil)
            add("table", "NSTextTable — Parent Table", id(table), tableRows)
            if layout.numberOfGlyphs > 0 {
                let g = layout.glyphRange(forCharacterRange: NSRange(location: characterIndex, length: 1), actualCharacterRange: nil)
                if g.length > 0 && g.location < layout.numberOfGlyphs {
                    add("cellGeometry", "Cell Layout — NSLayoutManager", "Measured for current glyph", [
                        p("layoutRect", rect(layout.layoutRect(for: block, at: g.location, effectiveRange: nil)), "Text content rectangle", .derived),
                        p("boundsRect", rect(layout.boundsRect(for: block, at: g.location, effectiveRange: nil)), "Includes cell padding and borders", .derived)
                    ])
                }
            }
        }

        if selection.length > 0 && NSMaxRange(selection) <= count {
            let runs = storage.attributedSubstring(from: selection)
            var common: [String: Set<String>] = [:]
            var seen = 0
            runs.enumerateAttributes(in: NSRange(location: 0, length: runs.length)) { values, subrange, _ in
                seen += 1
                for key in Set(values.keys.map(\.rawValue)).union(common.keys) {
                    let item = values.first(where: { $0.key.rawValue == key })?.value
                    if common[key] == nil && seen > 1 { common[key] = ["<absent>"] }
                    common[key, default: []].insert(item.map { printable($0) } ?? "<absent>")
                }
            }
            var selectionRows = [p("attributeRunCount", seen, "Distinct consecutive attribute dictionaries", .derived)]
            for (key, values) in common.sorted(by: { $0.key < $1.key }) {
                selectionRows.append(p(key, values.count == 1 ? (values.first ?? "") : "MIXED (\(values.count) values)",
                                       "Across selected range", .derived))
            }
            add("mixed", "Selection Attribute Summary", "Selected UTF-16 range", selectionRows)
            var n = 0
            runs.enumerateAttributes(in: NSRange(location: 0, length: runs.length)) { attributes, run, _ in
                if n < 60 {
                    add("run-\(n)", "Attribute Run #\(n + 1)", "Document range \(range(NSRange(location: selection.location + run.location, length: run.length)))",
                        [p("range", range(run), "Relative to selection", .derived)] +
                        attributes.sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { p($0.key.rawValue, $0.value, "Actual stored run attribute", .stored) })
                }
                n += 1
            }
            if n > 60 { add("run-overflow", "More attribute runs", "Truncated for UI responsiveness", [p("omitted", n - 60, "See source code to increase limit", .derived)]) }
        }
        let description = block.map { "Table cell R\($0.startingRow + 1) C\($0.startingColumn + 1)" }
            ?? (attachment != nil ? "Image attachment" : ps?.textLists.isEmpty == false ? "List paragraph" : "Text paragraph")
        return InspectionSnapshot(summary: selection.length == 0 ? "Caret at \(selection.location)" : "Selection \(rangeString)",
                                  subtitle: count == 0 ? "Empty document" : description,
                                  groups: groups)
    }

    private static func blockProperties(_ block: NSTextBlock, actionForPadding: PropertyAction?,
                                        actionForBorder: PropertyAction?) -> [InspectedProperty] {
        var rows: [InspectedProperty] = []
        for (layer, label, action) in [(NSTextBlock.Layer.padding, "padding", actionForPadding),
                                      (.border, "border", actionForBorder),
                                      (.margin, "margin", nil)] {
            for (edge, edgeName) in [(NSRectEdge.minX, "left"), (.maxX, "right"),
                                     (.minY, "bottom"), (.maxY, "top")] {
                rows.append(InspectedProperty("\(label).\(edgeName)", "\(block.width(for: layer, edge: edge))",
                                              "Text block layer edge, points or percentage", .live, action: action))
                rows.append(InspectedProperty("\(label).\(edgeName).valueType", "\(block.widthValueType(for: layer, edge: edge))"))
            }
        }
        rows.append(InspectedProperty("contentWidth", "\(block.contentWidth)"))
        return rows
    }

    private static func rowCount(_ table: NSTextTable, storage: NSTextStorage) -> Int {
        var rows = 0
        guard storage.length > 0 else { return 0 }
        storage.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: storage.length)) { value, _, _ in
            guard let ps = value as? NSParagraphStyle else { return }
            for block in ps.textBlocks {
                if let cell = block as? NSTextTableBlock, cell.table === table {
                    rows = max(rows, cell.startingRow + cell.rowSpan)
                }
            }
        }
        return rows
    }

    private static func id(_ object: AnyObject) -> String {
        let address = Unmanaged.passUnretained(object).toOpaque()
        return "\(type(of: object)) @ \(address)"
    }
    private static func range(_ value: NSRange) -> String { "{\(value.location), \(value.length)}" }
    private static func size(_ value: NSSize) -> String { String(format: "%.2f × %.2f pt", value.width, value.height) }
    private static func point(_ value: NSPoint) -> String { String(format: "(%.2f, %.2f)", value.x, value.y) }
    private static func rect(_ value: NSRect) -> String {
        String(format: "(%.2f, %.2f), %.2f × %.2f", value.minX, value.minY, value.width, value.height)
    }
    private static func alignment(_ value: NSTextAlignment) -> String {
        switch value {
        case .left: return "left"
        case .right: return "right"
        case .center: return "center"
        case .justified: return "justified"
        case .natural: return "natural"
        @unknown default: return "\(value.rawValue)"
        }
    }
    private static func hex(_ color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.deviceRGB) else { return String(describing: color) }
        return String(format: "#%02X%02X%02X", Int(rgb.redComponent * 255), Int(rgb.greenComponent * 255), Int(rgb.blueComponent * 255))
    }
    private static func printable(_ value: Any) -> String {
        if let color = value as? NSColor { return hex(color) }
        if let font = value as? NSFont { return "\(font.fontName) \(font.pointSize) pt" }
        if let style = value as? NSParagraphStyle { return "NSParagraphStyle \(id(style))" }
        if let attachment = value as? NSTextAttachment { return "NSTextAttachment \(id(attachment))" }
        if let url = value as? URL { return url.absoluteString }
        if let number = value as? NSNumber { return number.stringValue }
        if let str = value as? String { return str.replacingOccurrences(of: "\n", with: "\\n") }
        return String(describing: value)
    }
}

