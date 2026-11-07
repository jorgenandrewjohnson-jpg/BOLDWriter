import AppKit

/// The DOCX boundary uses ordinary PNG/JPEG media and point sizes (12,700 EMU/pt).
/// Other AppKit-decodable formats are normalized to PNG, not silently omitted.
enum DOCXImages {
    struct Image {
        let data: Data
        let extensionName: String
        let size: NSSize
    }

    static func validSize(_ size: NSSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= 100_000 && size.height <= 100_000
    }

    static func encode(_ attachment: NSTextAttachment) throws -> Image {
        let original = attachment.fileWrapper?.regularFileContents ?? attachment.contents
        let cellImage = (attachment.attachmentCell as? NSCell)?.image
        if let original, NSImage(data: original)?.isValid != true, attachment.image == nil {
            throw WriterError.message("A DOCX image format is unsupported. The document was not changed.")
        }
        guard let image = attachment.image ?? cellImage ?? original.flatMap(NSImage.init(data:)), image.isValid else {
            throw WriterError.message("A DOCX image could not be encoded. The document was not changed.")
        }
        let size = [attachment.bounds.size, attachment.attachmentCell?.cellSize() ?? .zero, image.size]
            .first(where: validSize) ?? NSSize(width: 144, height: 144)
        if let original, NSImage(data: original)?.isValid == true {
            if original.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) {
                return Image(data: original, extensionName: "png", size: size)
            }
            if original.starts(with: [0xff, 0xd8, 0xff]) {
                return Image(data: original, extensionName: "jpg", size: size)
            }
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw WriterError.message("A DOCX image could not be converted to PNG. The document was not changed.")
        }
        return Image(data: png, extensionName: "png", size: size)
    }

    static func applyWordPictureCrop(
        _ crop: WordPictureCrop,
        to attachment: NSTextAttachment
    ) throws {
        guard crop.hasValidGeometry else {
            throw WriterError.message(
                "A Word picture crop is invalid and cannot be rendered without changing it."
            )
        }

        guard !crop.isEmpty else {
            return
        }

        guard
            let sourceData =
                attachment.fileWrapper?
                    .regularFileContents
                ?? attachment.contents,
            let source =
                NSImage(
                    data:
                        sourceData
                ),
            source.isValid
        else {
            throw WriterError.message(
                "A Word picture crop could not be rendered because its original source image is unavailable."
            )
        }

        let cellImage =
            (attachment.attachmentCell
                as? NSCell)?
                .image

        let displaySize =
            [
                attachment.bounds.size,
                attachment.attachmentCell?
                    .cellSize()
                    ?? .zero,
                cellImage?.size
                    ?? .zero,
                source.size
            ]
            .first(
                where:
                    validSize
            )
            ?? source.size

        guard
            validSize(
                displaySize
            ),
            validSize(
                source.size
            )
        else {
            throw WriterError.message(
                "A Word picture crop has invalid image dimensions."
            )
        }

        let left =
            CGFloat(
                crop.left
            )
            / 100_000

        let top =
            CGFloat(
                crop.top
            )
            / 100_000

        let right =
            CGFloat(
                crop.right
            )
            / 100_000

        let bottom =
            CGFloat(
                crop.bottom
            )
            / 100_000

        let sourceRect =
            NSRect(
                x:
                    source.size.width
                    * left,
                y:
                    source.size.height
                    * bottom,
                width:
                    source.size.width
                    * (
                        1
                        - left
                        - right
                    ),
                height:
                    source.size.height
                    * (
                        1
                        - top
                        - bottom
                    )
            )

        guard
            validSize(
                sourceRect.size
            )
        else {
            throw WriterError.message(
                "A Word picture crop has an empty source rectangle."
            )
        }

        let display =
            NSImage(
                size:
                    displaySize
            )

        display.lockFocus()

        defer {
            display.unlockFocus()
        }

        NSColor.clear.setFill()

        NSBezierPath(
            rect:
                NSRect(
                    origin:
                        .zero,
                    size:
                        displaySize
                )
        )
        .fill()

        source.draw(
            in:
                NSRect(
                    origin:
                        .zero,
                    size:
                        displaySize
                ),
            from:
                sourceRect,
            operation:
                .copy,
            fraction:
                1,
            respectFlipped:
                true,
            hints:
                [
                    .interpolation:
                        NSImageInterpolation.high
                ]
        )

        attachment.attachmentCell =
            NSTextAttachmentCell(
                imageCell:
                    display
            )
    }

    static func attachment(data: Data, name: String, size: NSSize?) -> NSTextAttachment? {
        guard let image = NSImage(data: data), image.isValid else { return nil }
        let natural = validSize(image.size) ? image.size : NSSize(width: 144, height: 144)
        let displaySize = size.flatMap { validSize($0) ? $0 : nil } ?? natural
        image.size = displaySize
        // Keep the original encoded source in the attachment. The NSTextAttachment
        // bounds and cell carry the display size; exporting to a format with
        // different media requirements may create a derived representation, but
        // native edits and inline/floating conversion must not replace the source.
        let wrapper = FileWrapper(regularFileWithContents: data)
        wrapper.preferredFilename = name
        let attachment = NSTextAttachment(fileWrapper: wrapper)
        attachment.attachmentCell = NSTextAttachmentCell(imageCell: image)
        attachment.bounds = NSRect(origin: .zero, size: image.size)
        return attachment
    }
}
