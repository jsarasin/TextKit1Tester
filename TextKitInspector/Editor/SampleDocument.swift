import AppKit

/// Every visible image/table is real attributed-string content, not an overlay view.
enum SampleDocument {
    static func make(image: NSImage?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: "")
        let body = NSFont.systemFont(ofSize: 15)
        let title = NSFont.systemFont(ofSize: 29, weight: .bold)
        let heading = NSFont.systemFont(ofSize: 19, weight: .semibold)

        func append(_ text: String, font: NSFont = NSFont.systemFont(ofSize: 15),
                    extra: [NSAttributedString.Key: Any] = [:]) {
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.textColor]
            for (key, value) in extra { attrs[key] = value }
            result.append(NSAttributedString(string: text, attributes: attrs))
        }

        append("MacNote — TextKit 1 Laboratory\n", font: title)
        append("A continuous, native AppKit rich-text document. Move the caret through this example and inspect the actual objects on the right.\n\n", font: body)

        append("Formatting and paragraph styles\n", font: heading)
        append("Normal text, ", font: body)
        append("bold", font: NSFont.boldSystemFont(ofSize: 15))
        append(", ", font: body)
        append("italic", font: NSFontManager.shared.convert(body, toHaveTrait: .italicFontMask))
        append(", ", font: body)
        append("underlined", extra: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        append(", and ", font: body)
        append("Apple Developer documentation", extra: [
            .link: URL(string: "https://developer.apple.com/documentation/appkit/nstextview")!,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue
        ])
        append(". Try selecting across multiple styles.\n\n")

        let list = NSTextList(markerFormat: .disc, options: 0)
        for (i, text) in ["Document storage contains rich attributes", "The layout manager positions glyphs", "The container defines the layout region"].enumerated() {
            let ps = NSMutableParagraphStyle()
            ps.textLists = [list]
            ps.firstLineHeadIndent = 24
            ps.headIndent = 24
            append("• \(text)\n", extra: [.paragraphStyle: ps, .foregroundColor: i == 1 ? NSColor.systemBlue : NSColor.textColor])
        }
        append("\nEmbedded image attachment\n", font: heading)
        append("The technical illustration below is a real NSTextAttachment, represented by a single attachment character.\n")

        if let image {
            let attach = NSTextAttachment()
            attach.image = image
            let original = image.size
            let width: CGFloat = 410
            let height = max(20, width * original.height / max(original.width, 1))
            attach.bounds = NSRect(x: 0, y: 0, width: width, height: height)
            result.append(NSAttributedString(attachment: attach))
            append("\nImage caption: select the attachment character to inspect its object and display geometry.\n\n")
        }

        append("Native 4 × 4 text table\n", font: heading)
        append("Every cell is a paragraph whose style contains an NSTextTableBlock.\n")
        result.append(makeTable())
        append("\nAfter the table\n", font: heading)
        append("Text continues below the table with no page boundary. You can add arbitrarily more content, resize the window, and inspect new formatting and layout regions.\n\n")
        append("End of sample.\n", extra: [.foregroundColor: NSColor.secondaryLabelColor])
        return result
    }

    static func makeTable() -> NSAttributedString {
        let table = NSTextTable()
        table.numberOfColumns = 4
        table.collapsesBorders = true
        let values = [
            ["Material", "Quantity", "Dimension", "Status"],
            ["Steel plate", "2", "¼ in", "Ready"],
            ["Angle iron", "4", "2 in", "Cut"],
            ["Square tube", "1", "3 in", "Pending"]
        ]
        let contents = NSMutableAttributedString(string: "\n")
        for row in 0..<4 {
            for col in 0..<4 {
                let block = NSTextTableBlock(table: table, startingRow: row,
                                             rowSpan: 1, startingColumn: col, columnSpan: 1)
                block.setWidth(5, type: .absolute, for: .padding)
                block.setWidth(1, type: .absolute, for: .border)
                block.setBorderColor(.separatorColor)
                if row == 0 { block.backgroundColor = .controlBackgroundColor }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.lineSpacing = 2
                let font = row == 0 ? NSFont.boldSystemFont(ofSize: 12) : NSFont.systemFont(ofSize: 12)
                contents.append(NSAttributedString(string: values[row][col] + "\n", attributes: [
                    .font: font, .foregroundColor: NSColor.textColor, .paragraphStyle: style
                ]))
            }
        }
        contents.append(NSAttributedString(string: "\n"))
        return contents
    }
}
