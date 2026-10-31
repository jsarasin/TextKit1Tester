# TextKit Inspector — native macOS learning laboratory

This is a standalone **AppKit + TextKit 1** Xcode application for inspecting the live Cocoa text system. It uses `NSTextStorage → NSLayoutManager → NSTextContainer → NSTextView`, hosted in an `NSScrollView`. The document has **one continuous vertical flow**, not pages. The inspector is a separate, dynamically populated AppKit panel.

## Open and build

1. On an Apple Silicon Mac with Xcode 16 or later, open **`TextKitInspector.xcodeproj`**.
2. Select the **TextKitInspector** scheme and **My Mac** destination.
3. Choose **Product → Run** (`⌘R`).

There are no package dependencies, accounts, plugins, or servers. The deployment target is macOS 15. Signing is disabled for local development; if Xcode requires signing for your environment, set your development team in target **Signing & Capabilities**. The app's sample image is bundled in Resources.

**Verification limitation:** The source was created and Swift syntax parsing was checked in a Linux environment. This environment does **not** contain Apple's AppKit SDK or `xcodebuild`, so this package has **not been compiled or run on macOS**. You may need to address Swift SDK/API compatibility diagnostics when first building in Xcode. It is supplied as a working-source project for macOS verification, not a verified `.app` binary.

## How to explore

- Click or select text on the left; inspect the live class/object sections on the right. Move into different table cells or select the image. Only applicable contextual classes appear.
- Expand **Selection**, **Text System**, **Text Formatting**, **Tables**, **Attachments & Images**, and **Attribute Runs** to inspect their live object classes. Dotted property paths expand hierarchically (for example, `padding → left → valueType`). Filter by category, class, property path, value, or description; matching ancestors expand automatically. Copy individual values from the context menu.
- Enter supported property values and press **Return**. Examples: font size `22`, foreground colour `#FF8800`, alignment `center`, image display width `300`, table padding `8`.
- Use **Reset Document** to load the formatted example including a real image attachment and a 4×4 native text table.
- Use **Apple Table Panel** to experiment with the operating system's table-editing UI.

## Event tracker

The editor's lower pane contains a live event tracker. One row appears for each
**event type** observed, with the latest summary and a right-side unread badge
counting occurrences since that type was selected or expanded. Expand a type to
see its latest captured payload as a property hierarchy. **Double-click** its
row to open a separate window with its **five most recent occurrences**, each
including a timestamp and expandable, selectable payload. No older occurrences
are stored, and there is no disk logging.

- **Pause All / Resume All** above the list stops or resumes recording globally.
- **Pause / Play** on a particular row independently suppresses or resumes that
  event type. Suppressed occurrences do not increment unread counts or history.
- Captured event families include key/mouse/drag/scroll `NSEvent` input;
  selection updates; text-change, begin/end editing and command callbacks;
  proposed text replacements; typing-attribute changes; text-storage
  will/did-process-editing notifications; scroll-bounds notifications; and
  TextKit 1 layout invalidation and completion delegate callbacks.
- High-frequency input is retained only in per-type five-entry ring buffers;
  UI redraws are coalesced per main-run-loop turn. Notifications' available
  `userInfo` and event-specific NSEvent fields are snapshotted at receipt.

## Inspection model

- **Always present:** selected range; object references; `NSScrollView`; `NSTextView`; `NSTextContainer`; `NSLayoutManager`; `NSTextStorage`; typing attributes.
- **Text context:** actual stored attribute dictionary, `NSFont`, colours, paragraph style, list objects and URLs when applicable.
- **Image context:** `NSTextAttachment`, `NSImage`, image representations, and file wrapper if present.
- **Table context:** `NSTextTableBlock`, inherited `NSTextBlock` geometry/border values, parent `NSTextTable`, derived row count, and layout manager block rectangles.
- **Selections:** mixed values across attributed runs and individual runs (display capped at 60 for responsiveness).

The labels **API**, **Stored**, **Derived**, and **Default** are intentionally different: derived values are calculations rather than AppKit properties. Object identity is only stable during one application run.

## Known scope boundaries

This is an educational prototype, **not a complete word processor or robust table-structure editor**. It has no persistent storage, no collaboration, and no custom row/column merge implementation. Only supported safe properties are editable; most internal layout diagnostics are read-only. Table editing of padding, borders, or background currently targets the active cell paragraph rather than automatically rewriting an entire multi-paragraph cell. Editing the image's display bounds preserves its image content but does not implement all possible file-wrapper semantics. Changes to the text view's inset are not integrated with the document undo stack. Class adapters are extensive for the focused TextKit components but cannot expose every possible inherited AppKit property.

Selection inspection at document end reads the preceding character for attribute context and reports that explicitly. A selection crossing a table or attachment reports attributes by runs; contextual object panels target the active inspection index, not every object in the selection.

## Source organization

- `App/` – app lifecycle, native window and split view.
- `Editor/` – explicitly created TextKit 1 graph, editing transactions, rich sample and inline objects.
- `Inspector/` – live snapshot model and collapsible, filterable property UI.
- `Events/` – bounded event recorder, expandable tracker and per-event history windows.
- `Resources/` – bundled sample PNG.

Reference: [Apple's Using Text Tables](https://developer.apple.com/library/archive/documentation/Cocoa/Conceptual/TextLayout/Articles/TextTables.html) and [NSAttributedString range(of:at:)](https://developer.apple.com/documentation/foundation/nsattributedstring).
