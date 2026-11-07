import AppKit

/// Let AppKit keep importing text, styles, lists, and other existing structures.
/// Replace image markup with unique text markers first, then put the recovered
/// attachments at those exact positions; AppKit otherwise drops some drawings.
enum DOCXImporter {
    struct ImportedDocument {
        let text: NSAttributedString
        let comments: [DocumentComment]
        let bookmarks: [DocumentBookmark]
        let namedStyles: [NamedStyleDefinition]
        let page: PageSettings
        let sections: [DocumentSection]
        let floatingImages: [FloatingImage]
        let floatingImageWarning: String?
    }

    private struct FloatingImageMarker {
        let marker: String
        var image: FloatingImage
    }

    static func trackChangesEnabled(
        from data: Data
    ) throws -> Bool {
        let entries =
            try DOCXPackage.entries(in: data)

        let parts =
            Dictionary(
                uniqueKeysWithValues:
                    entries.map {
                        ($0.path, $0.data)
                    }
            )

        var mainPart = "word/document.xml"

        if let rootData = parts["_rels/.rels"] {
            let root =
                try DOCXPackage.xml(rootData)

            if let relationship =
                DOCXPackage.descendants(in:root,named:"Relationship")
                .compactMap({
                    $0 as? XMLElement
                })
                .first(where: {
                    $0.attribute(
                        forName: "Type"
                    )?
                    .stringValue?
                    .hasSuffix(
                        "/officeDocument"
                    ) == true
                }),
               relationship.attribute(
                    forName: "TargetMode"
               )?.stringValue != "External",
               let target =
                    relationship.attribute(
                        forName: "Target"
                    )?.stringValue,
               let resolved =
                    DOCXPackage.target(
                        target,
                        relativeTo: ""
                    ) {

                mainPart = resolved
            }
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[relationshipPath]
        else {
            return false
        }

        let relationships =
            try DOCXPackage.xml(
                relationshipData
            )

        guard
            let settingsRelationship =
                try relationships.nodes(
                    forXPath:
                        "//*[local-name()='Relationship' and contains(@Type, '/settings')]"
                )
                .compactMap({
                    $0 as? XMLElement
                })
                .first,
            settingsRelationship
                .attribute(
                    forName: "TargetMode"
                )?
                .stringValue != "External",
            let target =
                settingsRelationship
                    .attribute(
                        forName: "Target"
                    )?
                    .stringValue,
            let settingsPath =
                DOCXPackage.target(
                    target,
                    relativeTo: mainPart
                ),
            let settingsData =
                parts[settingsPath]
        else {
            return false
        }

        let settings =
            try DOCXPackage.xml(
                settingsData
            )

        guard
            let node =
                DOCXPackage.descendants(in:settings,named:"trackRevisions")
                .first as? XMLElement
        else {
            return false
        }

        let rawValue =
            node.attributes?
                .first {
                    $0.localName == "val"
                        || $0.name == "val"
                        || $0.name == "w:val"
                }?
                .stringValue?
                .lowercased()

        guard let rawValue else {
            return true
        }

        return ![
            "0",
            "false",
            "off",
            "no"
        ].contains(rawValue)
    }

    static func text(
        from data: Data
    ) throws -> NSAttributedString {
        try importedDocument(
            from:
                data
        )
        .text
    }

    static func importedDocument(
        from data: Data
    ) throws -> ImportedDocument {
        let importedNamedStyles = try DOCXStyleCatalog.read(from: data)
        var entries = try DOCXPackage.entries(in: data)
        let parts = Dictionary(uniqueKeysWithValues: entries.map { ($0.path, $0.data) })
        var mainPart = "word/document.xml"
        if let rootData = parts["_rels/.rels"] {
            let root = try DOCXPackage.xml(rootData)
            if let relationship = DOCXPackage.descendants(in:root,named:"Relationship").compactMap({ $0 as? XMLElement })
                .first(where: { $0.attribute(forName: "Type")?.stringValue?.hasSuffix("/officeDocument") == true }),
               relationship.attribute(forName: "TargetMode")?.stringValue != "External",
               let target = relationship.attribute(forName: "Target")?.stringValue,
               let path = DOCXPackage.target(target, relativeTo: "") { mainPart = path }
        }
        guard let mainIndex = entries.firstIndex(where: { $0.path == mainPart }) else {
            throw WriterError.message("The DOCX document part is missing.")
        }
        let xml = try DOCXPackage.xml(entries[mainIndex].data)
        var floatingImageWarnings: [String] = []

        var importedPage = try importPageSettings(
                documentXML:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let footnoteReplacements =
            try prepareFootnotes(
                xml:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let endnoteReplacements =
            try prepareEndnotes(
                xml:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        // Word stores paragraph-formatting revisions in
        // w:pPrChange. Duplicate only simple body paragraphs here
        // so AppKit can parse both the previous and proposed
        // paragraph properties natively. Lists and paragraphs with
        // nested/structured revisions are deliberately left alone
        // in this first interoperability pass.
        let paragraphPropertyChanges =
            try prepareParagraphPropertyChanges(
                in:
                    xml
            )

        // Word stores formatting-only revisions as
        // w:rPrChange rather than text w:del/w:ins revisions.
        // Normalize those changes into BOLD's paired revision
        // representation before the ordinary revision pass.
        try prepareRunPropertyChanges(
            in:
                xml
        )

        try materializeInheritedWordParagraphFormatting(
            in:
                xml,
            parts:
                parts,
            mainPart:
                mainPart
        )

        try materializeInheritedWordRunFormatting(
            in:
                xml,
            parts:
                parts,
            mainPart:
                mainPart
        )

        let importedWordRunFlags =
            try prepareWordRunFlags(
                in:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        // Unwrap revisions before collecting drawing nodes.
        // prepareTrackedChanges replaces revision children with
        // copies; collecting drawings first leaves stale nodes
        // for images located inside w:ins / w:del.
        let trackedChangeReplacements =
            try prepareTrackedChanges(
                in:
                    xml
            )

        let importedWordFields =
            try prepareWordFields(
                in:
                    xml
            )

        let candidates =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='drawing' or local-name()='pict' or local-name()='AlternateContent']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        let containers =
            candidates.filter {
                node in

                var parent =
                    node.parent

                while let ancestor =
                    parent {
                    if [
                        "drawing",
                        "pict",
                        "AlternateContent"
                    ]
                    .contains(
                        ancestor.localName
                            ?? ""
                    ) {
                        return false
                    }

                    parent =
                        ancestor.parent
                }

                return true
            }

        let trackedWhitespaceReplacements =
            trackedChangeReplacements.isEmpty
                ? []
                : try prepareTrackedWhitespace(in: xml)

        let directory = (mainPart as NSString).deletingLastPathComponent
        let relPath = (directory.isEmpty ? "" : directory + "/") + "_rels/" + (mainPart as NSString).lastPathComponent + ".rels"
        var relationships: [String: String] = [:]
        if let relData = parts[relPath] {
            for case let relationship as XMLElement in try DOCXPackage.xml(relData).nodes(forXPath: "//*[local-name()='Relationship']") {
                guard relationship.attribute(forName: "Type")?.stringValue?.hasSuffix("/image") == true,
                      relationship.attribute(forName: "TargetMode")?.stringValue != "External",
                      let id = relationship.attribute(forName: "Id")?.stringValue,
                      let target = relationship.attribute(forName: "Target")?.stringValue,
                      let path = DOCXPackage.target(target, relativeTo: mainPart) else { continue }
                guard relationships[id] == nil else {
                    throw WriterError.message("The DOCX contains duplicate image relationship identifiers. Import stopped because the intended artwork target is ambiguous.")
                }
                relationships[id] = path
            }
        }
        struct ImportedVMLShape {
            let startMarker: String
            let endMarker: String
            let shape: WordVMLShape
        }

        func vmlDescendants(
            of node: XMLNode
        ) -> [XMLElement] {
            var result: [XMLElement] = []

            for child in node.children ?? [] {
                guard let element = child as? XMLElement else {
                    continue
                }

                result.append(element)
                result.append(
                    contentsOf:
                        vmlDescendants(
                            of: element
                        )
                )
            }

            return result
        }

        func vmlAttribute(
            _ name: String,
            on element: XMLElement
        ) -> String? {
            element.attributes?
                .first {
                    (
                        $0.localName
                        ?? $0.name
                        ?? ""
                    )
                    .lowercased()
                    == name.lowercased()
                }?
                .stringValue
        }

        var vmlShapeReplacements:
            [ImportedVMLShape] = []
        var handledVMLContainers = Set<ObjectIdentifier>()

        for container in containers
        where (
            container.localName
            ?? ""
        )
        .lowercased()
        == "pict" {
            let descendants =
                vmlDescendants(
                    of: container
                )

            guard
                let shapeElement =
                    descendants.first(
                        where: {
                            [
                                "rect",
                                "roundrect",
                                "oval"
                            ]
                            .contains(
                                (
                                    $0.localName
                                    ?? ""
                                )
                                .lowercased()
                            )
                        }
                    ),
                let textBox =
                    vmlDescendants(
                        of: shapeElement
                    )
                    .first(
                        where: {
                            (
                                $0.localName
                                ?? ""
                            )
                            .lowercased()
                            == "textbox"
                        }
                    )
            else {
                continue
            }

            let textNodes =
                vmlDescendants(
                    of: textBox
                )
                .filter {
                    (
                        $0.localName
                        ?? ""
                    )
                    .lowercased()
                    == "t"
                }

            guard
                let firstText = textNodes.first,
                let lastText = textNodes.last
            else {
                continue
            }

            let startMarker =
                "BOLDVMLSTART"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of: "-",
                        with: ""
                    )

            let endMarker =
                "BOLDVMLEND"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of: "-",
                        with: ""
                    )

            firstText.stringValue =
                startMarker
                + (
                    firstText.stringValue
                    ?? ""
                )

            lastText.stringValue =
                (
                    lastText.stringValue
                    ?? ""
                )
                + endMarker

            let shape =
                WordVMLShape(
                    shapeKind:
                        shapeElement.localName
                        ?? "rect",
                    shapeID:
                        vmlAttribute(
                            "id",
                            on: shapeElement
                        ),
                    style:
                        vmlAttribute(
                            "style",
                            on: shapeElement
                        ),
                    fillColor:
                        vmlAttribute(
                            "fillcolor",
                            on: shapeElement
                        ),
                    strokeColor:
                        vmlAttribute(
                            "strokecolor",
                            on: shapeElement
                        ),
                    strokeWeight:
                        vmlAttribute(
                            "strokeweight",
                            on: shapeElement
                        ),
                    textBoxInset:
                        vmlAttribute(
                            "inset",
                            on: textBox
                        )
                )

            guard shape.isSupportedTextShape else {
                continue
            }

            vmlShapeReplacements.append(
                ImportedVMLShape(
                    startMarker: startMarker,
                    endMarker: endMarker,
                    shape: shape
                )
            )
            handledVMLContainers.insert(ObjectIdentifier(container))
        }

        var replacements: [(String, NSTextAttachment, WordPictureCrop?)] = []
        var opaqueDrawingMarkers: [(String, WordOpaqueDrawing)] = []
        var floatingImageMarkers: [FloatingImageMarker] = []
        var imageAltTextByMarker: [String: WordPictureAltText] = [:]
        for container in containers {
            let root = container.copy() as! XMLElement
            let scoped = XMLDocument(rootElement: root)
            let references = try scoped.nodes(forXPath: ".//*[local-name()='blip' or local-name()='svgBlip' or local-name()='imagedata']").compactMap { $0 as? XMLElement }
            let hasUnsupportedGraphic = try scoped.nodes(forXPath:
                ".//*[local-name()='chart' or local-name()='relIds']").count > 0
            if references.isEmpty || hasUnsupportedGraphic {
                if handledVMLContainers.contains(ObjectIdentifier(container)) { continue }
                // Preserve the drawing and its bounded internal package closure.
                var ancestor: XMLNode? = container
                while let element = ancestor as? XMLElement {
                    for namespace in element.namespaces ?? [] {
                        if !(root.namespaces ?? []).contains(where: { $0.name == namespace.name }) {
                            root.addNamespace(namespace.copy() as! XMLNode)
                        }
                    }
                    ancestor = element.parent
                }
                let drawing = try DOCXOpaqueDrawingPackage.capture(
                    root: root, isRunChild: container.parent?.localName == "r",
                    mainPart: mainPart, packageParts: parts
                )
                let marker = "BOLDOPAQUEDRAWING" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
                let text = XMLElement(name: "w:t", stringValue: marker)
                text.addNamespace(XMLNode.namespace(withName: "w", stringValue: "http://schemas.openxmlformats.org/wordprocessingml/2006/main") as! XMLNode)
                guard let parent = container.parent as? XMLElement else { throw CocoaError(.fileReadCorruptFile) }
                if parent.localName == "r" { parent.replaceChild(at: container.index, with: text) }
                else {
                    let run = XMLElement(name: "w:r")
                    run.addNamespace(XMLNode.namespace(withName: "w", stringValue: "http://schemas.openxmlformats.org/wordprocessingml/2006/main") as! XMLNode)
                    run.addChild(text)
                    parent.replaceChild(at: container.index, with: run)
                }
                opaqueDrawingMarkers.append((marker, drawing))
                continue
            }
            // WordCraft's read_drawing/nv_alt retains the nonvisual image title
            // and description separately. Keep these with the chosen picture.
            var imageAltText: WordPictureAltText?
            var recovered: (NSTextAttachment, WordPictureCrop?, Data, String)?
            for reference in references {
                // AlternateContent and DrawingML extensions can contain a raster
                // fallback. Try every embedded candidate before reporting failure.
                let id = reference.attributes?.first { ["embed", "id"].contains($0.localName ?? "") }?.stringValue
                guard let id, let path = relationships[id], let bytes = parts[path] else { continue }
                var drawing: XMLNode = reference
                while let parent = drawing.parent, drawing !== container,
                      !["drawing", "pict"].contains(drawing.localName ?? "") { drawing = parent }
                let size = try imageSize(in: drawing)
                if let attachment = DOCXImages.attachment(data: bytes, name: (path as NSString).lastPathComponent, size: size) {
                    let nonVisual = try drawing.nodes(forXPath: ".//*[local-name()='docPr' or local-name()='cNvPr']")
                        .compactMap { $0 as? XMLElement }.first
                    let altTitle = nonVisual?.attribute(forName: "title")?.stringValue ?? ""
                    let altDescription = nonVisual?.attribute(forName: "descr")?.stringValue ?? ""
                    if !altTitle.isEmpty || !altDescription.isEmpty {
                        imageAltText = WordPictureAltText(title: altTitle, alternativeDescription: altDescription)
                    }
                    recovered = (attachment, try wordPictureCrop(for: reference), bytes,
                                  (path as NSString).lastPathComponent)
                    break
                }
            }
            guard let recovered else {
                throw WriterError.message("A DOCX image is missing, externally linked, or in an unsupported format. Import was stopped so the image would not be silently lost; the original file was not changed.")
            }
            let marker = "BOLDIMAGE" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            imageAltTextByMarker[marker] = imageAltText
            let text = XMLElement(name: "w:t", stringValue: marker)
            text.addNamespace(XMLNode.namespace(withName: "w", stringValue: "http://schemas.openxmlformats.org/wordprocessingml/2006/main") as! XMLNode)
            guard let parent = container.parent as? XMLElement else { throw CocoaError(.fileReadCorruptFile) }
            // Common drawing/pict/AlternateContent is a run child. If an alternate
            // branch wraps the run itself, retain a valid run at its insertion site.
            if parent.localName == "r" { parent.replaceChild(at: container.index, with: text) }
            else {
                let run = XMLElement(name: "w:r")
                run.addNamespace(XMLNode.namespace(withName: "w", stringValue: "http://schemas.openxmlformats.org/wordprocessingml/2006/main") as! XMLNode)
                run.addChild(text)
                parent.replaceChild(at: container.index, with: run)
            }
            if let anchorNode = try scoped.nodes(forXPath: ".//*[local-name()='anchor']").first {
                if floatingImageMarkers.count >= 500 {
                    floatingImageWarnings.append("DOCX floating pictures beyond BOLD Writer's 500-object document limit were retained inline.")
                    replacements.append((marker, recovered.0, recovered.1))
                    continue
                }
                if var image = try importedFloatingImage(in: anchorNode, bytes: recovered.2,
                                                         assetName: recovered.3,
                                                         warning: { floatingImageWarnings.append($0) }) {
                    image.altTitle = imageAltText?.title
                    image.altDescription = imageAltText?.alternativeDescription
                    image.sourceCrop = recovered.1.map(FloatingImage.SourceCrop.init)
                    floatingImageMarkers.append(FloatingImageMarker(marker: marker, image: image))
                    replacements.append((marker, recovered.0, recovered.1))
                } else {
                    // Keep the image visible as an inline attachment when a
                    // DrawingML property cannot be represented faithfully.
                    replacements.append((marker, recovered.0, recovered.1))
                }
            } else {
                replacements.append((marker, recovered.0, recovered.1))
            }
        }
        let importedParagraphStyles =
            try prepareNamedParagraphStyles(
                in:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let importedParagraphLineSpacing =
            try prepareParagraphLineSpacing(
                in:
                    xml
            )

        let importedParagraphTabs = try prepareParagraphTabs(in: xml)

        let importedParagraphPagination =
            try prepareParagraphPagination(
                in:
                    xml
            )

        let importedParagraphWordMetadata =
            try prepareParagraphWordMetadata(
                in:
                    xml
            )

        let importedParagraphBorders =
            try prepareParagraphBorders(
                in:
                    xml
            )
        let importedParagraphShading =
            try prepareParagraphShading(
                in:
                    xml
            )

        let importedTables =
            try prepareTables(
                in:
                    xml
            )

        let importedComments =
            try prepareComments(
                in:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let allBookmarkNamesForHyperlinks =
            try allBookmarkNamesForHyperlinkValidation(
                in:
                    xml
            )

        let importedBookmarks =
            try prepareBookmarks(
                in:
                    xml
            )

        let importedHyperlinks =
            try prepareHyperlinks(
                in:
                    xml,
                bookmarkNames: allBookmarkNamesForHyperlinks,
                parts:
                    parts,
                mainPart:
                    mainPart
            )

        let bookmarkLookup = Set(importedBookmarks.map { $0.name.lowercased() })
        for imported in importedWordFields {
            let parts = imported.field.instruction.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, ["REF", "PAGEREF"].contains(parts[0].uppercased()),
               !bookmarkLookup.contains(String(parts[1]).lowercased()) {
                throw WriterError.message("A Word REF/PAGEREF field targets a missing bookmark.")
            }
        }

        let importedSections =
            try prepareSections(
                in:
                    xml,
                parts:
                    parts,
                mainPart:
                    mainPart,
                fallbackPage:
                    importedPage
            )

        // w:noColumnBalance is document-global Word compatibility
        // state. Preserve ImportedDocument.page's established geometry
        // and furniture semantics while carrying this single global flag.
        if importedSections
            .firstPage
            .noColumnBalance != nil {

            importedPage.noColumnBalance =
                importedSections
                    .firstPage
                    .noColumnBalance
        }

        if replacements.isEmpty
            && opaqueDrawingMarkers.isEmpty
            && vmlShapeReplacements.isEmpty
            && footnoteReplacements.isEmpty
            && endnoteReplacements.isEmpty
            && importedWordFields.isEmpty
            && importedTables.isEmpty
            && trackedChangeReplacements.isEmpty
            && paragraphPropertyChanges.isEmpty
            && importedComments.isEmpty
            && importedBookmarks.isEmpty
            && importedHyperlinks.isEmpty
            && importedParagraphStyles.isEmpty
            && importedParagraphLineSpacing.isEmpty
            && importedParagraphPagination.isEmpty
            && importedParagraphWordMetadata.isEmpty
            && importedParagraphBorders.isEmpty
            && importedParagraphShading.isEmpty
            && importedWordRunFlags.isEmpty
            && importedSections.boundaries.isEmpty {
            let result = NSMutableAttributedString(
                attributedString: try nativeText(data)
            )
            try restoreListMetadata(
                documentXML: xml,
                parts: parts,
                mainPart: mainPart,
                into: result
            )

            removeSyntheticFinalParagraphBreak(
                from: result
            )

            return ImportedDocument(
                text:
                    result,
                comments:
                    [],
                bookmarks:
                    [],
                namedStyles:
                    importedNamedStyles,
                page:
                    importedPage,
                sections:
                    DocumentSection.normalized(
                        [
                            DocumentSection(
                                location:
                                    0,
                                page:
                                    importedSections.firstPage
                            )
                        ],
                        textLength:
                            result.length,
                        fallbackPage:
                            importedPage
                    ),
                floatingImages: [],
                floatingImageWarning: floatingImageWarnings.isEmpty ? nil : Array(Set(floatingImageWarnings)).sorted().joined(separator: " ")
            )
        }

        entries[mainIndex].data = xml.xmlData
        let result = NSMutableAttributedString(attributedString: try nativeText(ZipArchiveWriter.archive(entries)))

        // Restore list metadata while the temporary DOCX import markers
        // still match the mutated Word XML exactly. Tracked revisions,
        // images, footnotes, and protected whitespace can all introduce
        // temporary marker text. Once those markers are replaced, locating
        // the corresponding numbered paragraph by its XML text is no longer
        // reliable. A second restoration pass later remains useful after
        // structured tables have been rebuilt.
        try restoreListMetadata(
            documentXML: xml,
            parts: parts,
            mainPart: mainPart,
            into: result
        )

        for (marker, drawing) in opaqueDrawingMarkers {
            let range = (result.string as NSString).range(of: marker, options: .literal)
            guard range.location != NSNotFound else {
                throw WriterError.message("An unsupported Word drawing position could not be recovered. Import stopped without changing the source file.")
            }
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes[.boldWriterWordOpaqueDrawing] = drawing
            result.replaceCharacters(in: range, with: NSAttributedString(
                string: WordOpaqueDrawing.markerText, attributes: attributes
            ))
        }

        let floatingMarkerSet = Set(floatingImageMarkers.map(\.marker))
        for (marker, attachment, pictureCrop) in replacements where !floatingMarkerSet.contains(marker) {
            let range = (result.string as NSString).range(of: marker, options: .literal)
            guard range.location != NSNotFound else {
                throw WriterError.message("A DOCX image position could not be recovered. Import was stopped without changing the original file.")
            }
            var attributes = result.attributes(at: range.location, effectiveRange: nil)
            attributes[.attachment] = attachment
            attributes[.boldWriterInlineImageDisplaySize] =
                "\(attachment.bounds.width),\(attachment.bounds.height)" as NSString
            if let altText = imageAltTextByMarker[marker] {
                attributes[.boldWriterWordPictureAltText] = altText
            }
            if let pictureCrop {
                try DOCXImages.applyWordPictureCrop(
                    pictureCrop,
                    to:
                        attachment
                )

                attributes[.boldWriterWordPictureCrop] =
                    pictureCrop
            }
            result.replaceCharacters(in: range, with: NSAttributedString(string: "\u{fffc}", attributes: attributes))
        }

        var locatedFloating: [(location: Int, markerLength: Int, image: FloatingImage)] = []
        for item in floatingImageMarkers {
            let range = (result.string as NSString).range(of: item.marker, options: .literal)
            guard range.location != NSNotFound else {
                throw WriterError.message("A floating DOCX picture anchor could not be matched to its text position. Import stopped without changing the source file.")
            }
            locatedFloating.append((range.location, range.length, item.image))
        }
        for item in locatedFloating.sorted(by: { $0.location > $1.location }) {
            result.deleteCharacters(in: NSRange(location: item.location, length: item.markerLength))
        }
        var importedFloatingImages = locatedFloating.map { item -> FloatingImage in
            var image = item.image
            image.anchorLocation = item.location - locatedFloating.filter { $0.location < item.location }.reduce(0) { $0 + $1.markerLength }
            return image
        }
        for image in importedFloatingImages {
            Self.markFloatingAnchorBoundary(image, in: result)
        }

        for importedVMLShape in vmlShapeReplacements {
            let startRange =
                (
                    result.string
                    as NSString
                )
                .range(
                    of:
                        importedVMLShape.startMarker
                )

            let endRange =
                (
                    result.string
                    as NSString
                )
                .range(
                    of:
                        importedVMLShape.endMarker
                )

            guard
                startRange.location != NSNotFound,
                endRange.location != NSNotFound,
                startRange.location < endRange.location
            else {
                throw WriterError.message(
                    "A Word VML textbox boundary marker was lost during DOCX import."
                )
            }

            let contentLength =
                endRange.location
                - NSMaxRange(
                    startRange
                )

            guard contentLength > 0 else {
                throw WriterError.message(
                    "A Word VML textbox contains no recoverable text."
                )
            }

            result.deleteCharacters(
                in: endRange
            )

            result.deleteCharacters(
                in: startRange
            )

            let contentRange =
                NSRange(
                    location: startRange.location,
                    length: contentLength
                )

            guard
                NSMaxRange(contentRange)
                <= result.length
            else {
                throw WriterError.message(
                    "A Word VML textbox range became invalid during DOCX import."
                )
            }

            result.addAttribute(
                .boldWriterWordVMLShape,
                value:
                    importedVMLShape.shape,
                range:
                    contentRange
            )
        }

        for (index, replacement) in footnoteReplacements.enumerated() {
            let range = (result.string as NSString).range(of: replacement.0)
            guard range.location != NSNotFound else { throw WriterError.message("A DOCX footnote reference could not be recovered.") }
            result.replaceCharacters(in: range, with: Footnotes.marker(replacement.1, number: index + 1))
        }

        for (index, replacement) in endnoteReplacements.enumerated() {
            let range = (result.string as NSString).range(of: replacement.0)
            guard range.location != NSNotFound else { throw WriterError.message("A DOCX endnote reference could not be recovered.") }
            result.replaceCharacters(in: range, with: Endnotes.marker(replacement.1, number: index + 1))
        }
        restoreTrackedWhitespace(
            trackedWhitespaceReplacements,
            into: result
        )

        try restoreTrackedChanges(
            trackedChangeReplacements,
            into: result
        )

        try restoreTables(importedTables, into: result)

        try restoreListMetadata(
            documentXML: xml,
            parts: parts,
            mainPart: mainPart,
            into: result
        )
        try restoreChecklistMetadata(
            parts: parts,
            into: result
        )

        try restoreNamedParagraphStyles(
            importedParagraphStyles,
            into:
                result
        )

        try restoreParagraphLineSpacing(
            importedParagraphLineSpacing,
            into:
                result
        )

        try restoreParagraphTabs(importedParagraphTabs, into: result)

        try restoreWordRunFlags(
            importedWordRunFlags,
            into:
                result
        )

        try restoreParagraphPagination(
            importedParagraphPagination,
            into:
                result
        )

        try restoreParagraphWordMetadata(
            importedParagraphWordMetadata,
            into:
                result
        )

        try restoreParagraphBorders(
            importedParagraphBorders,
            into:
                result
        )
        try restoreParagraphShading(
            importedParagraphShading,
            into:
                result
        )

        removeSyntheticFinalParagraphBreak(
            from: result
        )

        try restoreParagraphPropertyChanges(
            paragraphPropertyChanges,
            into:
                result
        )

        let bookmarkMarkers =
            importedBookmarks.flatMap {
                [
                    $0.startMarker,
                    $0.endMarker
                ]
            }

        let hyperlinkMarkers =
            importedHyperlinks.flatMap {
                [
                    $0.startMarker,
                    $0.endMarker
                ]
            }

        let commentMarkers =
            importedComments.flatMap {
                comment -> [String] in

                [
                    comment.startMarker,
                    comment.endMarker,
                    comment.referenceMarker
                ]
                .compactMap {
                    $0
                }
            }

        let fieldMarkers = importedWordFields.flatMap {
            [$0.startMarker, $0.endMarker]
        }

        let sections =
            try restoreSections(
                importedSections,
                additionalMarkers:
                    bookmarkMarkers
                    + hyperlinkMarkers
                    + commentMarkers
                    + fieldMarkers,
                fallbackPage:
                    importedPage,
                into:
                    result
            )

        let comments =
            try restoreComments(
                importedComments,
                additionalMarkers:
                    bookmarkMarkers
                    + hyperlinkMarkers
                    + fieldMarkers,
                into:
                    result
            )

        let bookmarks =
            try restoreBookmarks(
                importedBookmarks,
                additionalMarkers:
                    hyperlinkMarkers
                    + fieldMarkers,
                into:
                    result
            )

        let restoredNames = Dictionary(uniqueKeysWithValues: bookmarks.map { ($0.id, $0.name) })
        let bookmarkAliases = Dictionary(uniqueKeysWithValues: importedBookmarks.compactMap { bookmark in
            restoredNames[bookmark.identity].map { (bookmark.name.lowercased(), $0) }
        })
        try restoreHyperlinks(
            importedHyperlinks,
            bookmarkAliases: bookmarkAliases,
            into: result
        )

        try restoreWordFields(
            importedWordFields,
            into:
                result
        )

        Self.resolveFloatingAnchorBoundaries(&importedFloatingImages, in: result)

        return ImportedDocument(
            text:
                result,
            comments:
                comments,
            bookmarks:
                bookmarks,
            namedStyles:
                importedNamedStyles,
            page:
                importedPage,
            sections:
                sections,
            floatingImages: importedFloatingImages,
            floatingImageWarning: floatingImageWarnings.isEmpty ? nil : Array(Set(floatingImageWarnings)).sorted().joined(separator: " ")
        )
    }

    /// Imports the common, faithfully representable DrawingML subset. Unsupported
    /// geometry is reported and retained as an inline attachment by the caller.
    private static let floatingAnchorBoundaryAttribute = NSAttributedString.Key(
        "BOLDWriterTemporaryDOCXFloatingAnchorBoundary"
    )

    private static func markFloatingAnchorBoundary(
        _ image: FloatingImage,
        in text: NSMutableAttributedString
    ) {
        guard text.length > 0 else { return }
        let location = min(max(0, image.anchorLocation), text.length)
        let attachesAfterCharacter = location > 0
        let probe = attachesAfterCharacter ? location - 1 : location
        let range = (text.string as NSString).rangeOfComposedCharacterSequence(at: probe)
        var boundaries = text.attribute(
            floatingAnchorBoundaryAttribute,
            at: range.location,
            effectiveRange: nil
        ) as? [String: Bool] ?? [:]
        boundaries[image.id.uuidString] = attachesAfterCharacter
        text.addAttribute(floatingAnchorBoundaryAttribute, value: boundaries, range: range)
    }

    private static func resolveFloatingAnchorBoundaries(
        _ images: inout [FloatingImage],
        in text: NSMutableAttributedString
    ) {
        guard text.length > 0 else { return }
        var resolvedLocations: [String: Int] = [:]
        let fullRange = NSRange(location: 0, length: text.length)
        text.enumerateAttribute(floatingAnchorBoundaryAttribute, in: fullRange) { value, range, _ in
            guard let boundaries = value as? [String: Bool] else { return }
            for (identity, followsCharacter) in boundaries {
                resolvedLocations[identity] = followsCharacter ? NSMaxRange(range) : range.location
            }
        }
        for index in images.indices {
            if let location = resolvedLocations[images[index].id.uuidString] {
                images[index].anchorLocation = min(max(0, location), text.length)
            } else {
                // If normalization removed the adjacent character, retain the image
                // and clamp its last known logical boundary into the imported text.
                images[index].anchorLocation = min(max(0, images[index].anchorLocation), text.length)
            }
        }
        text.removeAttribute(floatingAnchorBoundaryAttribute, range: fullRange)
    }

    private static func importedFloatingImage(in node: XMLNode, bytes: Data, assetName: String,
                                              warning: (String) -> Void) throws -> FloatingImage? {
        guard let copiedElement = node.copy() as? XMLElement else { return nil }
        let scoped = XMLDocument(rootElement: copiedElement)
        guard let root = node as? XMLElement else { return nil }
        guard root.attribute(forName: "simplePos")?.stringValue != "1" else {
            warning("Word simplePos coordinates cannot currently be mapped to BOLD Writer's page/text coordinate frames; that picture was retained inline.")
            return nil
        }
        guard root.attribute(forName: "allowOverlap")?.stringValue != "0" else {
            warning("A Word floating picture has overlap restrictions that BOLD Writer cannot currently enforce; that picture was retained inline.")
            return nil
        }
        func element(_ name: String) throws -> XMLElement? {
            try scoped.nodes(forXPath: ".//*[local-name()='\(name)']").first as? XMLElement
        }
        guard let horizontal = try element("positionH"), let vertical = try element("positionV"),
              let hRef = horizontal.attribute(forName: "relativeFrom")?.stringValue,
              let vRef = vertical.attribute(forName: "relativeFrom")?.stringValue,
              let hPosition = try axisPosition(in: horizontal), let vPosition = try axisPosition(in: vertical),
              let extent = try element("extent"),
              let cx = Double(extent.attribute(forName: "cx")?.stringValue ?? ""),
              let cy = Double(extent.attribute(forName: "cy")?.stringValue ?? "") else {
            warning("A Word floating picture uses missing or aligned positioning data that BOLD Writer cannot map exactly; it was retained inline.")
            return nil
        }
        func horizontalPositionReference(_ value: String) -> FloatingImage.PositionReference? {
            switch value {
            case "page": return .page
            case "margin": return .margins
            case "paragraph": return .paragraph
            case "character": return .character
            default: return nil
            }
        }
        func verticalPositionReference(_ value: String) -> FloatingImage.PositionReference? {
            switch value {
            case "page": return .page
            case "margin": return .margins
            case "paragraph": return .paragraph
            case "line": return .line
            default: return nil
            }
        }
        guard let xReference = horizontalPositionReference(hRef), let yReference = verticalPositionReference(vRef) else {
            warning("Word column/line or another unsupported position reference cannot be represented exactly; that picture was retained inline.")
            return nil
        }
        func horizontalAlignment(_ value: String?) -> FloatingImage.HorizontalAlignment? {
            switch value {
            case "left": return .left
            case "center": return .center
            case "right": return .right
            default: return nil
            }
        }
        func verticalAlignment(_ value: String?) -> FloatingImage.VerticalAlignment? {
            switch value {
            case "top": return .top
            case "center": return .center
            case "bottom": return .bottom
            default: return nil
            }
        }
        let hAlignment = horizontalAlignment(hPosition.alignment)
        let vAlignment = verticalAlignment(vPosition.alignment)
        if (hPosition.alignment != nil && (hAlignment == nil || (hRef != "page" && hRef != "margin")))
            || (vPosition.alignment != nil && (vAlignment == nil || (vRef != "page" && vRef != "margin"))) {
            warning("Word aligned positioning is supported only for left/center/right or top/center/bottom relative to page or margins; that picture was retained inline.")
            return nil
        }
        let wrapNodes = try scoped.nodes(forXPath: ".//*[starts-with(local-name(), 'wrap')]").compactMap { $0 as? XMLElement }
        guard let wrap = wrapNodes.first else {
            warning("A Word floating picture uses an unknown wrapping mode; it was retained inline.")
            return nil
        }
        let wrapping: FloatingImage.Wrapping
        switch wrap.localName {
        case "wrapNone": wrapping = .none
        case "wrapSquare": wrapping = .square
        case "wrapTight": wrapping = .tight
        case "wrapThrough": wrapping = .through
        case "wrapTopAndBottom": wrapping = .topAndBottom
        default:
            warning("A Word floating picture uses an unsupported wrapping mode; it was retained inline.")
            return nil
        }
        var importedPolygon: FloatingImage.WrapPolygon?
        if wrapping == .tight || wrapping == .through {
            let polygonNodes = try wrap.nodes(forXPath: "./*[local-name()='wrapPolygon']")
            guard polygonNodes.count <= 1 else {
                warning("A Word Tight Wrap picture has multiple wrap polygons; its artwork was retained inline rather than changing its text flow.")
                return nil
            }
            if let polygon = polygonNodes.first as? XMLElement {
                let vertices = (polygon.children ?? []).compactMap { $0 as? XMLElement }
                guard (3...(FloatingImage.WrapPolygon.maximumPoints + 1)).contains(vertices.count),
                      vertices.first?.localName == "start",
                      vertices.dropFirst().allSatisfy({ $0.localName == "lineTo" }) else {
                    warning("A Word Tight Wrap picture has an unsupported polygon; its artwork was retained inline rather than changing its text flow.")
                    return nil
                }
                var points: [FloatingImage.WrapPolygon.Point] = []
                for vertex in vertices {
                    guard let x = vertex.attribute(forName: "x")?.stringValue.flatMap(Int.init),
                          let y = vertex.attribute(forName: "y")?.stringValue.flatMap(Int.init) else {
                        warning("A Word Tight Wrap picture has malformed polygon coordinates; its artwork was retained inline.")
                        return nil
                    }
                    points.append(.init(x: x, y: y))
                }
                if points.count > 3, points.first == points.last { points.removeLast() }
                let edited: Bool
                switch polygon.attribute(forName: "edited")?.stringValue ?? "0" {
                case "1", "true", "on": edited = true
                case "0", "false", "off": edited = false
                default:
                    warning("A Word Tight Wrap picture has an unknown polygon editing flag; its artwork was retained inline.")
                    return nil
                }
                let parsed = FloatingImage.WrapPolygon(edited: edited, points: points)
                guard parsed.isValid else {
                    warning("A Word Tight Wrap picture has out-of-range polygon coordinates; its artwork was retained inline.")
                    return nil
                }
                importedPolygon = parsed
            }
        }
        if wrapping == .through {
            warning("Word Through Wrap artwork and its polygon were retained, but BOLD Writer's native text preview conservatively keeps text out of internal openings.")
        }
        if let effect = try scoped.nodes(forXPath: ".//*[local-name()='effectExtent']").first as? XMLElement {
            var effectValues: [Double] = []
            for key in ["l", "t", "r", "b"] {
                let value = Double(effect.attribute(forName: key)?.stringValue ?? "0")
                guard let value, value.isFinite, value >= 0, value <= 254_000_000, value.rounded() == value else {
                    warning("A Word floating picture has malformed effect extents; it was retained inline.")
                    return nil
                }
                effectValues.append(value)
            }
            if effectValues.contains(where: { abs($0) > 0.5 }), Set(effectValues.map { Int($0.rounded()) }).count > 1 {
                warning("This Word image has asymmetric effect extents that BOLD Writer cannot preserve exactly; its artwork and anchor were imported, but its wrap clearance may differ.")
            }
        }
        let side: FloatingImage.WrapSide
        switch wrap.attribute(forName: "wrapText")?.stringValue ?? "bothSides" {
        case "left": side = .leftOnly
        case "right": side = .rightOnly
        case "largest": side = .largestSide
        case "bothSides": side = .both
        default:
            warning("A Word floating picture uses an unknown wrap-side value; it was retained inline.")
            return nil
        }
        func distance(_ name: String) -> Double? {
            guard let raw = root.attribute(forName: name)?.stringValue else { return 0 }
            guard let value = Double(raw), value.isFinite, value >= 0, value.rounded() == value else { return nil }
            return value / 12_700
        }
        guard let topDistance = distance("distT"), let rightDistance = distance("distR"),
              let bottomDistance = distance("distB"), let leftDistance = distance("distL") else {
            warning("A Word floating picture has malformed text-distance values; it was retained inline.")
            return nil
        }
        let distances = [topDistance, rightDistance, bottomDistance, leftDistance]
        guard distances.allSatisfy({ $0 <= 288 }) else {
            warning("A Word floating picture's text distance exceeds BOLD Writer's supported range; that picture was retained inline.")
            return nil
        }
        let wrapDistances = FloatingImage.WrapDistances(
            top: topDistance,
            right: rightDistance,
            bottom: bottomDistance,
            left: leftDistance
        )
        guard cx > 0, cy > 0, cx <= 254_000_000, cy <= 254_000_000,
              cx.rounded() == cx, cy.rounded() == cy else {
            warning("A Word floating picture has invalid dimensions; it was retained inline.")
            return nil
        }
        let rotationNode = try scoped.nodes(forXPath: ".//*[local-name()='xfrm'][@rot]").first as? XMLElement
        let rawRotation = rotationNode?.attribute(forName: "rot")?.stringValue ?? "0"
        guard let rotationEmu = Double(rawRotation), rotationEmu.isFinite, abs(rotationEmu) <= 2_160_000_000,
              rotationEmu.rounded() == rotationEmu else {
            warning("A Word floating picture has an invalid rotation value; it was retained inline.")
            return nil
        }
        let rotation = rotationEmu / 60_000
        let behind = root.attribute(forName: "behindDoc")?.stringValue == "1"
        let rawZOrder = root.attribute(forName: "relativeHeight")?.stringValue ?? "0"
        guard let zOrder = Int(rawZOrder), zOrder >= 0 else {
            warning("A Word floating picture has invalid stacking-order metadata; it was retained inline.")
            return nil
        }
        let aspectLock = try scoped.nodes(forXPath: ".//*[local-name()='graphicFrameLocks' or local-name()='picLocks'][@noChangeAspect]").first as? XMLElement
        let preservesAspect = aspectLock?.attribute(forName: "noChangeAspect")?.stringValue != "0"
        let hOffset = hPosition.offset ?? 0
        let vOffset = vPosition.offset ?? 0
        let x = hOffset / 12_700, y = vOffset / 12_700
        guard x >= 0, y >= 0, x <= 20_000, y <= 20_000,
              bytes.count <= 100 * 1024 * 1024 else {
            warning("A Word floating picture has offsets or image data outside BOLD Writer's safe supported range; it was retained inline.")
            return nil
        }
        let logicalAnchor: FloatingImage.Anchor = hRef == "character" ? .character : .paragraph
        return FloatingImage(assetName: assetName, imageData: bytes, pageIndex: 0, anchor: logicalAnchor,
                             anchorLocation: 0, x: x, y: y, anchorOffsetX: x,
                             anchorOffsetY: y, horizontalPositionReference: xReference,
                             verticalPositionReference: yReference,
                             horizontalAlignment: hAlignment, verticalAlignment: vAlignment,
                             width: cx / 12_700, height: cy / 12_700, rotationDegrees: rotation,
                             preservesAspectRatio: preservesAspect,
                             wrapping: wrapping, wrapDistance: topDistance,
                             wrapSide: side, layer: behind ? .behindText : .inFrontOfText,
                             zOrder: zOrder, positionLocked: root.attribute(forName: "locked")?.stringValue == "1",
                             wrapDistances: wrapDistances, wrapPolygon: importedPolygon)
    }

    private struct ParsedAxisPosition {
        let offset: Double?
        let alignment: String?
    }

    private static func axisPosition(in element: XMLElement) throws -> ParsedAxisPosition? {
        let offsets = try element.nodes(forXPath: "./*[local-name()='posOffset']")
        let alignments = try element.nodes(forXPath: "./*[local-name()='align']")
        guard (offsets.count == 1 && alignments.isEmpty) || (offsets.isEmpty && alignments.count == 1) else { return nil }
        if offsets.count == 1 {
            guard let value = try offset(in: element) else { return nil }
            return ParsedAxisPosition(offset: value, alignment: nil)
        }
        guard let value = alignments.first?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return ParsedAxisPosition(offset: nil, alignment: value)
    }

    private static func offset(in element: XMLElement) throws -> Double? {
        if let raw = try element.nodes(forXPath: "./*[local-name()='posOffset']").first?.stringValue,
           let value = Double(raw), value.isFinite, abs(value) <= 254_000_000, value.rounded() == value { return value }
        return nil
    }


    private struct ImportedTrackedWhitespace {
        let marker: String
        let value: String
    }

    private struct ImportedTrackedChange {
        let startMarker: String
        let endMarker: String
        let id: UUID
        let kind: TrackChangeRecord.Kind
        let author: String
        let date: Date
    }

    private struct ImportedParagraphPropertyChange {
        let previousMarker: String
        let proposedMarker: String
        let id: UUID
        let author: String
        let date: Date
    }

    private struct ImportedComment {
        let startMarker: String?
        let endMarker: String?
        let referenceMarker: String?
        let text: String
        let author: String
        let date: Date
    }

    private struct ImportedBookmark {
        let identity: UUID
        let startMarker: String
        let endMarker: String
        let name: String
    }

    private struct ImportedHyperlink {
        let startMarker: String
        let endMarker: String
        let target: String
    }

    private struct ImportedParagraphStyle {
        let marker: String
        let semanticStyle: WriterStyle?
        let wordStyle: WordParagraphStyle?
    }


    private struct ImportedWordRunFlags {
        let startMarker: String
        let endMarker: String
        let smallCaps: Bool?
        let hidden: Bool?
        let noProof: Bool?
        let rtl: Bool?
        let complexScript: Bool?
        let complexScriptBold: Bool?
        let complexScriptItalic: Bool?
        let complexScriptSize: Int?
        let runFonts: WordRunFonts?
        let characterStyle: WordCharacterStyle?
        let runBorder: WordRunBorder?
        let runShading: WordRunShading?
        let highlight: String?
        let singleStrike: Bool?
        let doubleStrike: Bool?
        let allCaps: Bool?
        let characterScale: Int?
        let underlineVariant: String?
        let language: String?
        let wordLanguage: WordLanguage?
        let kernThreshold: Int?
        let emphasis: String?
        let specVanish: Bool?
        let webHidden: Bool?
        let baselineOffset: Double?
        let outline: Bool?
        let shadow: Bool?
        let emboss: Bool?
        let imprint: Bool?
        let superscript: Int?
        let kern: Double?
    }

    private static func wordStyleDependencyGraph(
        parts: [String: Data],
        mainPart: String,
        rootStyleID: String
    ) throws -> [WordStyleDependency] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func childValue(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[
                    relationshipPath
                ]
        else {
            return []
        }

        let relationships =
            try DOCXPackage.xml(
                relationshipData
            )

        let styleRelationships =
            DOCXPackage.descendants(in:relationships,named:"Relationship")
            .compactMap {
                $0 as? XMLElement
            }
            .filter {
                relationship in

                relationship.attribute(
                    forName:
                        "Type"
                )?
                .stringValue?
                .hasSuffix(
                    "/styles"
                ) == true
                    && relationship.attribute(
                        forName:
                            "TargetMode"
                    )?
                    .stringValue
                        != "External"
            }

        guard
            styleRelationships.count == 1,
            let relationship =
                styleRelationships.first,
            let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
            let stylePath =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let styleData =
                parts[
                    stylePath
                ]
        else {
            return []
        }

        let stylesXML =
            try DOCXPackage.xml(
                styleData
            )

        let definitions =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']/*[local-name()='style']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        var byID:
            [String: XMLElement] = [:]

        for definition in definitions {
            guard
                let styleID =
                    attribute(
                        definition,
                        "styleId"
                    ),
                !styleID.isEmpty
            else {
                continue
            }

            byID[
                styleID
            ] = definition
        }

        func dependency(
            _ definition: XMLElement
        ) -> WordStyleDependency? {
            guard
                let styleID =
                    attribute(
                        definition,
                        "styleId"
                    ),
                !styleID.isEmpty
            else {
                return nil
            }

            let rawType =
                attribute(
                    definition,
                    "type"
                )?
                .lowercased()

            let kind:
                WordStyleDependency.Kind

            if rawType == "character" {
                kind = .character
            } else {
                kind = .paragraph
            }

            return WordStyleDependency(
                kind:
                    kind,
                styleID:
                    styleID,
                name:
                    childValue(
                        definition,
                        "name"
                    ),
                basedOn:
                    childValue(
                        definition,
                        "basedOn"
                    ),
                linkedStyleID:
                    childValue(
                        definition,
                        "link"
                    ),
                nextStyleID:
                    childValue(
                        definition,
                        "next"
                    )
            )
        }

        var visited:
            Set<String> = []

        var result:
            [WordStyleDependency] = []

        func walk(
            _ styleID: String
        ) {
            guard
                !styleID.isEmpty,
                !visited.contains(
                    styleID
                ),
                let definition =
                    byID[
                        styleID
                    ],
                let parsed =
                    dependency(
                        definition
                    )
            else {
                return
            }

            visited.insert(
                styleID
            )

            // The root style itself is already carried by the
            // paragraph/run attribute model. Store only dependencies.
            if styleID != rootStyleID {
                result.append(
                    parsed
                )
            }

            if let basedOn =
                parsed.basedOn,
               !basedOn.isEmpty {

                walk(
                    basedOn
                )
            }

            if let linked =
                parsed.linkedStyleID,
               !linked.isEmpty {

                walk(
                    linked
                )
            }

            if let next =
                parsed.nextStyleID,
               !next.isEmpty {

                walk(
                    next
                )
            }
        }

        walk(
            rootStyleID
        )

        return result
    }

    private static func materializeInheritedWordParagraphFormatting(
        in xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func child(
            _ element: XMLElement,
            named name: String
        ) -> XMLElement? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func elementChildren(
            _ element: XMLElement?
        ) -> [XMLElement] {
            element?
                .children?
                .compactMap {
                    $0 as? XMLElement
                }
                ?? []
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[
                    relationshipPath
                ]
        else {
            return
        }

        let relationships =
            try DOCXPackage.xml(
                relationshipData
            )

        let styleRelationships =
            DOCXPackage.descendants(in:relationships,named:"Relationship")
            .compactMap {
                $0 as? XMLElement
            }
            .filter {
                relationship in

                relationship.attribute(
                    forName:
                        "Type"
                )?
                .stringValue?
                .hasSuffix(
                    "/styles"
                ) == true
                    && relationship.attribute(
                        forName:
                            "TargetMode"
                    )?
                    .stringValue
                        != "External"
            }

        guard
            styleRelationships.count == 1,
            let relationship =
                styleRelationships.first,
            let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
            let stylePath =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let styleData =
                parts[
                    stylePath
                ]
        else {
            return
        }

        let stylesXML =
            try DOCXPackage.xml(
                styleData
            )

        let definitions =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']/*[local-name()='style']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        var paragraphStyles:
            [String: XMLElement] = [:]

        for definition in definitions {
            guard
                attribute(
                    definition,
                    "type"
                )?
                .lowercased()
                    == "paragraph",
                let styleID =
                    attribute(
                        definition,
                        "styleId"
                    ),
                !styleID.isEmpty
            else {
                continue
            }

            paragraphStyles[
                styleID
            ] = definition
        }

        let defaultProperties =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='docDefaults']"
                    + "/*[local-name()='pPrDefault']"
                    + "/*[local-name()='pPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }
            .first

        func inheritedProperties(
            for styleID: String?,
            visited:
                inout Set<String>
        ) -> [XMLElement] {
            guard
                let styleID,
                !styleID.isEmpty,
                !visited.contains(
                    styleID
                ),
                let definition =
                    paragraphStyles[
                        styleID
                    ]
            else {
                return []
            }

            visited.insert(
                styleID
            )

            let basedOn =
                child(
                    definition,
                    named:
                        "basedOn"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }

            var result =
                inheritedProperties(
                    for:
                        basedOn,
                    visited:
                        &visited
                )

            if let properties =
                child(
                    definition,
                    named:
                        "pPr"
                ) {

                result.append(
                    contentsOf:
                        elementChildren(
                            properties
                        )
                )
            }

            return result
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        for paragraph in paragraphs {
            var properties =
                child(
                    paragraph,
                    named:
                        "pPr"
                )

            let styleID =
                properties
                    .flatMap {
                        child(
                            $0,
                            named:
                                "pStyle"
                        )
                    }
                    .flatMap {
                        attribute(
                            $0,
                            "val"
                        )
                    }

            var inherited:
                [XMLElement] = []

            inherited.append(
                contentsOf:
                    elementChildren(
                        defaultProperties
                    )
            )

            var visited:
                Set<String> = []

            inherited.append(
                contentsOf:
                    inheritedProperties(
                        for:
                            styleID,
                        visited:
                            &visited
                    )
            )

            guard
                !inherited.isEmpty
            else {
                continue
            }

            if properties == nil {
                let replacement =
                    XMLElement(
                        name:
                            "w:pPr"
                    )

                paragraph.insertChild(
                    replacement,
                    at:
                        0
                )

                properties =
                    replacement
            }

            guard
                let properties
            else {
                continue
            }

            let directNames =
                Set(
                    elementChildren(
                        properties
                    )
                    .compactMap {
                        $0.localName
                    }
                )

            var emitted:
                Set<String> = []

            for inheritedElement
                in inherited.reversed() {

                guard
                    let name =
                        inheritedElement.localName,
                    name != "pStyle",
                    !directNames.contains(
                        name
                    ),
                    !emitted.contains(
                        name
                    )
                else {
                    continue
                }

                emitted.insert(
                    name
                )

                guard
                    let copied =
                        inheritedElement.copy()
                            as? XMLElement
                else {
                    continue
                }

                let insertionIndex =
                    child(
                        properties,
                        named:
                            "pStyle"
                    ) == nil
                        ? 0
                        : 1

                properties.insertChild(
                    copied,
                    at:
                        insertionIndex
                )
            }
        }
    }

    private static func materializeInheritedWordRunFormatting(
        in xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func child(
            _ element: XMLElement,
            named name: String
        ) -> XMLElement? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func elementChildren(
            _ element: XMLElement?
        ) -> [XMLElement] {
            element?
                .children?
                .compactMap {
                    $0 as? XMLElement
                }
                ?? []
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[
                    relationshipPath
                ]
        else {
            return
        }

        let relationships =
            try DOCXPackage.xml(
                relationshipData
            )

        let styleRelationships =
            DOCXPackage.descendants(in:relationships,named:"Relationship")
            .compactMap {
                $0 as? XMLElement
            }
            .filter {
                relationship in

                relationship.attribute(
                    forName:
                        "Type"
                )?
                .stringValue?
                .hasSuffix(
                    "/styles"
                ) == true
                    && relationship.attribute(
                        forName:
                            "TargetMode"
                    )?
                    .stringValue
                        != "External"
            }

        guard
            styleRelationships.count == 1,
            let relationship =
                styleRelationships.first,
            let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
            let stylePath =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let styleData =
                parts[
                    stylePath
                ]
        else {
            return
        }

        let stylesXML =
            try DOCXPackage.xml(
                styleData
            )

        let definitions =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']/*[local-name()='style']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        var characterStyles:
            [String: XMLElement] = [:]

        var paragraphStyles:
            [String: XMLElement] = [:]

        for definition in definitions {
            guard
                let type =
                    attribute(
                        definition,
                        "type"
                    )?
                    .lowercased(),
                let styleID =
                    attribute(
                        definition,
                        "styleId"
                    ),
                !styleID.isEmpty
            else {
                continue
            }

            if type == "character" {
                characterStyles[
                    styleID
                ] = definition
            } else if type == "paragraph" {
                paragraphStyles[
                    styleID
                ] = definition
            }
        }

        let defaultProperties =
            try stylesXML.nodes(
                forXPath:
                    "/*[local-name()='styles']"
                    + "/*[local-name()='docDefaults']"
                    + "/*[local-name()='rPrDefault']"
                    + "/*[local-name()='rPr']"
            )
            .compactMap {
                $0 as? XMLElement
            }
            .first

        func styleRunProperties(
            styleID: String?,
            definitions:
                [String: XMLElement],
            visited:
                inout Set<String>
        ) -> [XMLElement] {
            guard
                let styleID,
                !styleID.isEmpty,
                !visited.contains(
                    styleID
                ),
                let definition =
                    definitions[
                        styleID
                    ]
            else {
                return []
            }

            visited.insert(
                styleID
            )

            let basedOn =
                child(
                    definition,
                    named:
                        "basedOn"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }

            var result =
                styleRunProperties(
                    styleID:
                        basedOn,
                    definitions:
                        definitions,
                    visited:
                        &visited
                )

            if let properties =
                child(
                    definition,
                    named:
                        "rPr"
                ) {

                result.append(
                    contentsOf:
                        elementChildren(
                            properties
                        )
                )
            }

            return result
        }

        func containingParagraph(
            for run: XMLElement
        ) -> XMLElement? {
            var current =
                run.parent

            while let node =
                current {

                if node.localName
                    == "p" {

                    return node
                        as? XMLElement
                }

                if node.localName
                    == "body" {

                    return nil
                }

                current =
                    node.parent
            }

            return nil
        }

        let runs =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']//*[local-name()='r']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        for run in runs {
            var ancestor =
                run.parent

            var historical =
                false

            while let current =
                ancestor {

                if current.localName
                    == "rPrChange" {

                    historical =
                        true
                    break
                }

                ancestor =
                    current.parent
            }

            if historical {
                continue
            }

            var properties =
                child(
                    run,
                    named:
                        "rPr"
                )

            let characterStyleID =
                properties
                    .flatMap {
                        child(
                            $0,
                            named:
                                "rStyle"
                        )
                    }
                    .flatMap {
                        attribute(
                            $0,
                            "val"
                        )
                    }

            var paragraphStyleID:
                String?

            if let paragraph =
                containingParagraph(
                    for:
                        run
                ),
               let paragraphProperties =
                child(
                    paragraph,
                    named:
                        "pPr"
                ),
               let paragraphStyle =
                child(
                    paragraphProperties,
                    named:
                        "pStyle"
                ) {

                paragraphStyleID =
                    attribute(
                        paragraphStyle,
                        "val"
                    )
            }

            var inherited:
                [XMLElement] = []

            inherited.append(
                contentsOf:
                    elementChildren(
                        defaultProperties
                    )
            )

            var paragraphVisited:
                Set<String> = []

            inherited.append(
                contentsOf:
                    styleRunProperties(
                        styleID:
                            paragraphStyleID,
                        definitions:
                            paragraphStyles,
                        visited:
                            &paragraphVisited
                    )
            )

            var characterVisited:
                Set<String> = []

            inherited.append(
                contentsOf:
                    styleRunProperties(
                        styleID:
                            characterStyleID,
                        definitions:
                            characterStyles,
                        visited:
                            &characterVisited
                    )
            )

            guard
                !inherited.isEmpty
            else {
                continue
            }

            if properties == nil {
                let replacement =
                    XMLElement(
                        name:
                            "w:rPr"
                    )

                run.insertChild(
                    replacement,
                    at:
                        0
                )

                properties =
                    replacement
            }

            guard
                let properties
            else {
                continue
            }

            let directNames =
                Set(
                    elementChildren(
                        properties
                    )
                    .compactMap {
                        $0.localName
                    }
                )

            var emitted:
                Set<String> = []

            for inheritedElement
                in inherited.reversed() {

                guard
                    let name =
                        inheritedElement.localName,
                    name != "rStyle",
                    !directNames.contains(
                        name
                    ),
                    !emitted.contains(
                        name
                    )
                else {
                    continue
                }

                emitted.insert(
                    name
                )

                guard
                    let copied =
                        inheritedElement.copy()
                            as? XMLElement
                else {
                    continue
                }

                let insertionIndex =
                    child(
                        properties,
                        named:
                            "rStyle"
                    ) == nil
                        ? 0
                        : 1

                properties.insertChild(
                    copied,
                    at:
                        insertionIndex
                )
            }
        }
    }

    private static func prepareWordRunFlags(
        in xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws -> [ImportedWordRunFlags] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func child(
            _ element: XMLElement,
            named name: String
        ) -> XMLElement? {
            element.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func optionalEnabled(
            _ element: XMLElement?
        ) -> Bool? {
            guard
                let element
            else {
                return nil
            }

            guard
                let raw =
                    attribute(
                        element,
                        "val"
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()
            else {
                return true
            }

            return ![
                "0",
                "false",
                "off",
                "no"
            ]
            .contains(
                raw
            )
        }

        func hasAncestor(
            _ node: XMLNode,
            named name: String
        ) -> Bool {
            var parent =
                node.parent

            while let current =
                parent {

                if current.localName
                    == name {

                    return true
                }

                parent =
                    current.parent
            }

            return false
        }

        var characterStylesByID:
            [String: WordCharacterStyle] = [:]

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        if let relationshipData =
            parts[
                relationshipPath
            ] {

            let relationships =
                try DOCXPackage.xml(
                    relationshipData
                )

            let styleRelationships =
                DOCXPackage.descendants(in:relationships,named:"Relationship")
                .compactMap {
                    $0 as? XMLElement
                }
                .filter {
                    relationship in

                    relationship.attribute(
                        forName:
                            "Type"
                    )?
                    .stringValue?
                    .hasSuffix(
                        "/styles"
                    ) == true
                        && relationship.attribute(
                            forName:
                                "TargetMode"
                        )?
                        .stringValue
                            != "External"
                }

            if styleRelationships.count == 1,
               let relationship =
                    styleRelationships.first,
               let target =
                    relationship.attribute(
                        forName:
                            "Target"
                    )?
                    .stringValue,
               let stylePath =
                    DOCXPackage.target(
                        target,
                        relativeTo:
                            mainPart
                    ),
               let styleData =
                    parts[
                        stylePath
                    ] {

                let stylesXML =
                    try DOCXPackage.xml(
                        styleData
                    )

                let definitions =
                    try stylesXML.nodes(
                        forXPath:
                            "/*[local-name()='styles']/*[local-name()='style']"
                    )
                    .compactMap {
                        $0 as? XMLElement
                    }

                for definition
                    in definitions {

                    guard
                        attribute(
                            definition,
                            "type"
                        )?
                        .lowercased()
                            == "character",
                        let styleID =
                            attribute(
                                definition,
                                "styleId"
                            ),
                        !styleID.isEmpty
                    else {
                        continue
                    }

                    let name =
                        definition.children?
                            .compactMap {
                                $0 as? XMLElement
                            }
                            .first {
                                $0.localName
                                    == "name"
                            }
                            .flatMap {
                                attribute(
                                    $0,
                                    "val"
                                )
                            }

                    let basedOn =
                        definition.children?
                            .compactMap {
                                $0 as? XMLElement
                            }
                            .first {
                                $0.localName
                                    == "basedOn"
                            }
                            .flatMap {
                                attribute(
                                    $0,
                                    "val"
                                )
                            }

                    let linkedStyleID =
                        definition.children?
                            .compactMap {
                                $0 as? XMLElement
                            }
                            .first {
                                $0.localName
                                    == "link"
                            }
                            .flatMap {
                                attribute(
                                    $0,
                                    "val"
                                )
                            }

                    characterStylesByID[
                        styleID
                    ] =
                        WordCharacterStyle(
                            styleID:
                                styleID,
                            name:
                                name,
                            basedOn:
                                basedOn,
                            linkedStyleID:
                                linkedStyleID,
                            dependencies:
                                try wordStyleDependencyGraph(
                                    parts:
                                        parts,
                                    mainPart:
                                        mainPart,
                                    rootStyleID:
                                        styleID
                                )
                        )
                }
            }
        }

        let runs =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']//*[local-name()='r']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedWordRunFlags] = []

        for run in runs {
            // Historical rPr snapshots are metadata, not visible runs.
            if hasAncestor(
                run,
                named:
                    "rPrChange"
            ) {
                continue
            }

            guard
                let properties =
                    child(
                        run,
                        named:
                            "rPr"
                    )
            else {
                continue
            }

            // Formatting revisions are normalized separately. Avoid
            // attaching a second interpretation to the same run here.
            if child(
                properties,
                named:
                    "rPrChange"
            ) != nil {
                continue
            }

            let smallCaps =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "smallCaps"
                    )
                )

            let hidden =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "vanish"
                    )
                )

            let noProof =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "noProof"
                    )
                )

            let rtl =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "rtl"
                    )
                )

            let complexScript =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "cs"
                    )
                )

            let complexScriptBold =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "bCs"
                    )
                )

            let complexScriptItalic =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "iCs"
                    )
                )

            let complexScriptSize:
                Int?

            if let sizeElement =
                child(
                    properties,
                    named:
                        "szCs"
                ),
               let raw =
                attribute(
                    sizeElement,
                    "val"
                ),
               let parsed =
                Int(
                    raw
                ) {

                complexScriptSize =
                    max(
                        1,
                        parsed
                    )
            } else {
                complexScriptSize = nil
            }

            let runFonts:
                WordRunFonts?

            if let fonts =
                child(
                    properties,
                    named:
                        "rFonts"
                ) {

                let parsed =
                    WordRunFonts(
                        ascii:
                            attribute(
                                fonts,
                                "ascii"
                            ),
                        hAnsi:
                            attribute(
                                fonts,
                                "hAnsi"
                            ),
                        eastAsia:
                            attribute(
                                fonts,
                                "eastAsia"
                            ),
                        complexScript:
                            attribute(
                                fonts,
                                "cs"
                            ),
                        asciiTheme:
                            attribute(
                                fonts,
                                "asciiTheme"
                            ),
                        hAnsiTheme:
                            attribute(
                                fonts,
                                "hAnsiTheme"
                            ),
                        eastAsiaTheme:
                            attribute(
                                fonts,
                                "eastAsiaTheme"
                            ),
                        complexScriptTheme:
                            attribute(
                                fonts,
                                "cstheme"
                            ),
                        hint:
                            attribute(
                                fonts,
                                "hint"
                            )
                    )

                // Plain ascii/hAnsi font names are already represented by
                // AppKit's native .font attribute. Preserve custom metadata
                // only when Word carries information AppKit cannot model.
                runFonts =
                    parsed.hasExtendedWordMetadata
                        ? parsed
                        : nil
            } else {
                runFonts = nil
            }

            let characterStyle:
                WordCharacterStyle?

            if let styleElement =
                child(
                    properties,
                    named:
                        "rStyle"
                ),
               let styleID =
                attribute(
                    styleElement,
                    "val"
                ),
               !styleID.isEmpty {

                characterStyle =
                    characterStylesByID[
                        styleID
                    ]
                    ?? WordCharacterStyle(
                        styleID:
                            styleID
                    )
            } else {
                characterStyle = nil
            }

            let runBorder:
                WordRunBorder?

            if let border =
                child(
                    properties,
                    named:
                        "bdr"
                ),
               let style =
                attribute(
                    border,
                    "val"
                ),
               !style.isEmpty {

                runBorder =
                    WordRunBorder(
                        style:
                            style,
                        size:
                            attribute(
                                border,
                                "sz"
                            )
                            .flatMap(
                                Int.init
                            ),
                        space:
                            attribute(
                                border,
                                "space"
                            )
                            .flatMap(
                                Int.init
                            ),
                        color:
                            attribute(
                                border,
                                "color"
                            ),
                        themeColor:
                            attribute(
                                border,
                                "themeColor"
                            ),
                        themeTint:
                            attribute(
                                border,
                                "themeTint"
                            ),
                        themeShade:
                            attribute(
                                border,
                                "themeShade"
                            )
                    )
            } else {
                runBorder = nil
            }

            let runShading:
                WordRunShading?

            if let shading =
                child(
                    properties,
                    named:
                        "shd"
                ) {

                runShading =
                    WordRunShading(
                        value:
                            attribute(
                                shading,
                                "val"
                            )
                            ?? "clear",
                        color:
                            attribute(
                                shading,
                                "color"
                            ),
                        fill:
                            attribute(
                                shading,
                                "fill"
                            ),
                        themeColor:
                            attribute(
                                shading,
                                "themeColor"
                            ),
                        themeTint:
                            attribute(
                                shading,
                                "themeTint"
                            ),
                        themeShade:
                            attribute(
                                shading,
                                "themeShade"
                            ),
                        themeFill:
                            attribute(
                                shading,
                                "themeFill"
                            ),
                        themeFillTint:
                            attribute(
                                shading,
                                "themeFillTint"
                            ),
                        themeFillShade:
                            attribute(
                                shading,
                                "themeFillShade"
                            )
                    )
            } else {
                runShading = nil
            }

            let highlight =
                child(
                    properties,
                    named:
                        "highlight"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
                .flatMap {
                    raw -> String? in

                    let trimmed =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    return trimmed.isEmpty
                        ? nil
                        : trimmed
                }

            let singleStrike = optionalEnabled(child(properties,named:"strike"))
            let doubleStrike =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "dstrike"
                    )
                )

            let allCaps =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "caps"
                    )
                )

            let characterScale:
                Int?

            if let scaleElement =
                child(
                    properties,
                    named:
                        "w"
                ),
               let raw =
                attribute(
                    scaleElement,
                    "val"
                ),
               let parsed =
                Int(
                    raw
                ) {

                characterScale =
                    max(
                        1,
                        min(
                            600,
                            parsed
                        )
                    )
            } else {
                characterScale = nil
            }

            let underlineVariant =
                child(
                    properties,
                    named:
                        "u"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
                .flatMap {
                    raw -> String? in

                    let trimmed =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    guard
                        !trimmed.isEmpty,
                        trimmed.lowercased()
                            != "none"
                    else {
                        return nil
                    }

                    return trimmed
                }

            let languageElement =
                child(
                    properties,
                    named:
                        "lang"
                )

            func normalizedAttribute(
                _ element: XMLElement?,
                _ name: String
            ) -> String? {
                guard
                    let raw =
                        element.flatMap({
                            attribute(
                                $0,
                                name
                            )
                        })
                else {
                    return nil
                }

                let trimmed =
                    raw.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                return trimmed.isEmpty
                    ? nil
                    : trimmed
            }

            let language =
                normalizedAttribute(
                    languageElement,
                    "val"
                )

            let wordLanguage: WordLanguage?

            if languageElement != nil {
                let parsed =
                    WordLanguage(
                        value:
                            language,
                        eastAsia:
                            normalizedAttribute(
                                languageElement,
                                "eastAsia"
                            ),
                        bidi:
                            normalizedAttribute(
                                languageElement,
                                "bidi"
                            )
                    )

                wordLanguage =
                    parsed.hasExtendedMetadata
                        ? parsed
                        : nil
            } else {
                wordLanguage = nil
            }

            let kernThreshold: Int?

            if let kernElement =
                child(
                    properties,
                    named:
                        "kern"
                ),
               let raw =
                attribute(
                    kernElement,
                    "val"
                ),
               let parsed =
                Int(
                    raw
                ) {

                kernThreshold =
                    max(
                        0,
                        parsed
                    )
            } else {
                kernThreshold = nil
            }

            let emphasis =
                child(
                    properties,
                    named:
                        "em"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
                .flatMap {
                    raw -> String? in

                    let trimmed =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    return trimmed.isEmpty
                        ? nil
                        : trimmed
                }

            let specVanish =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "specVanish"
                    )
                )

            let webHidden =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "webHidden"
                    )
                )

            let baselineOffset:
                Double?

            if let position =
                child(
                    properties,
                    named:
                        "position"
                ),
               let raw =
                attribute(
                    position,
                    "val"
                ),
               let halfPoints =
                Double(
                    raw
                ),
               halfPoints.isFinite {

                baselineOffset =
                    halfPoints / 2.0
            } else {
                baselineOffset = nil
            }

            let outline =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "outline"
                    )
                )

            let shadow =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "shadow"
                    )
                )

            let emboss =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "emboss"
                    )
                )

            let imprint =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "imprint"
                    )
                )

            let superscript:
                Int?

            if let vertical =
                child(
                    properties,
                    named:
                        "vertAlign"
                ),
               let raw =
                attribute(
                    vertical,
                    "val"
                )?
                .lowercased() {

                switch raw {
                case "superscript":
                    superscript = 1

                case "subscript":
                    superscript = -1

                case "baseline":
                    superscript = 0

                default:
                    superscript = nil
                }
            } else {
                superscript = nil
            }

            let kern:
                Double?

            if let spacing =
                child(
                    properties,
                    named:
                        "spacing"
                ),
               let raw =
                attribute(
                    spacing,
                    "val"
                ),
               let twentieths =
                Double(
                    raw
                ) {

                kern =
                    twentieths / 20.0
            } else {
                kern = nil
            }

            guard
                smallCaps != nil
                    || hidden != nil
                    || noProof != nil
                    || rtl != nil
                    || complexScript != nil
                    || complexScriptBold != nil
                    || complexScriptItalic != nil
                    || complexScriptSize != nil
                    || runFonts != nil
                    || characterStyle != nil
                    || runBorder != nil
                    || runShading != nil
                    || highlight != nil
                    || singleStrike != nil
                    || doubleStrike != nil
                    || allCaps != nil
                    || characterScale != nil
                    || underlineVariant != nil
                    || language != nil
                    || wordLanguage != nil
                    || kernThreshold != nil
                    || emphasis != nil
                    || specVanish != nil
                    || webHidden != nil
                    || baselineOffset != nil
                    || outline != nil
                    || shadow != nil
                    || emboss != nil
                    || imprint != nil
                    || superscript != nil
                    || kern != nil
            else {
                continue
            }

            guard
                let parent =
                    run.parent
                        as? XMLElement
            else {
                continue
            }

            let token =
                UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let start =
                "BOLDRUNFLAGSTART"
                + token

            let end =
                "BOLDRUNFLAGEND"
                + token

            let index =
                run.index

            parent.insertChild(
                revisionMarkerRun(
                    start
                ),
                at:
                    index
            )

            parent.insertChild(
                revisionMarkerRun(
                    end
                ),
                at:
                    index + 2
            )

            result.append(
                ImportedWordRunFlags(
                    startMarker:
                        start,
                    endMarker:
                        end,
                    smallCaps:
                        smallCaps,
                    hidden:
                        hidden,
                    noProof:
                        noProof,
                    rtl:
                        rtl,
                    complexScript:
                        complexScript,
                    complexScriptBold:
                        complexScriptBold,
                    complexScriptItalic:
                        complexScriptItalic,
                    complexScriptSize:
                        complexScriptSize,
                    runFonts:
                        runFonts,
                    characterStyle:
                        characterStyle,
                    runBorder:
                        runBorder,
                    runShading:
                        runShading,
                    highlight:
                        highlight,
                    singleStrike: singleStrike,
                    doubleStrike:
                        doubleStrike,
                    allCaps:
                        allCaps,
                    characterScale:
                        characterScale,
                    underlineVariant:
                        underlineVariant,
                    language:
                        language,
                    wordLanguage:
                        wordLanguage,
                    kernThreshold:
                        kernThreshold,
                    emphasis:
                        emphasis,
                    specVanish:
                        specVanish,
                    webHidden:
                        webHidden,
                    baselineOffset:
                        baselineOffset,
                    outline:
                        outline,
                    shadow:
                        shadow,
                    emboss:
                        emboss,
                    imprint:
                        imprint,
                    superscript:
                        superscript,
                    kern:
                        kern
                )
            )
        }

        return result
    }

    private static func restoreWordRunFlags(
        _ values: [ImportedWordRunFlags],
        into result:
            NSMutableAttributedString
    ) throws {
        // Work from the end of the imported string toward the start so
        // marker deletion for a later run cannot invalidate an earlier
        // run's positions.
        var located:
            [(
                ImportedWordRunFlags,
                NSRange,
                NSRange
            )] = []

        // AppKit may reorder runs, so index their unique markers in one scan
        // instead of searching the entire manuscript twice for every run.
        let source = result.string as NSString
        let expression = try NSRegularExpression(pattern: "BOLDRUNFLAG(?:START|END)[A-F0-9]{32}")
        var markers: [String: NSRange] = [:]
        expression.enumerateMatches(in: source as String, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let range = match?.range else { return }
            markers[source.substring(with: range)] = range
        }
        for value in values {
            guard let startRange = markers[value.startMarker] else {
                throw WriterError.message("A Word run-format start marker was lost during DOCX import.")
            }
            let afterStart = NSMaxRange(startRange)
            guard let endRange = markers[value.endMarker], endRange.location >= afterStart else {
                throw WriterError.message("A Word run-format end marker was lost during DOCX import.")
            }

            located.append(
                (
                    value,
                    startRange,
                    endRange
                )
            )
        }

        located.sort {
            $0.1.location
                > $1.1.location
        }

        for (
            value,
            originalStart,
            originalEnd
        ) in located {
            let contentRange =
                NSRange(
                    location:
                        NSMaxRange(
                            originalStart
                        ),
                    length:
                        originalEnd.location
                        - NSMaxRange(
                            originalStart
                        )
                )

            if contentRange.length > 0 {
                if let smallCaps =
                    value.smallCaps {

                    result.addAttribute(
                        .boldWriterSmallCaps,
                        value:
                            smallCaps,
                        range:
                            contentRange
                    )
                }

                if let hidden =
                    value.hidden {

                    result.addAttribute(
                        .boldWriterHiddenText,
                        value:
                            hidden,
                        range:
                            contentRange
                    )
                }

                if let noProof =
                    value.noProof {

                    result.addAttribute(
                        .boldWriterNoProof,
                        value:
                            noProof,
                        range:
                            contentRange
                    )
                }

                if let rtl =
                    value.rtl {

                    result.addAttribute(
                        .boldWriterRTL,
                        value:
                            rtl,
                        range:
                            contentRange
                    )
                }

                if let complexScript =
                    value.complexScript {

                    result.addAttribute(
                        .boldWriterComplexScript,
                        value:
                            complexScript,
                        range:
                            contentRange
                    )
                }

                if let complexScriptBold =
                    value.complexScriptBold {

                    result.addAttribute(
                        .boldWriterComplexScriptBold,
                        value:
                            complexScriptBold,
                        range:
                            contentRange
                    )
                }

                if let complexScriptItalic =
                    value.complexScriptItalic {

                    result.addAttribute(
                        .boldWriterComplexScriptItalic,
                        value:
                            complexScriptItalic,
                        range:
                            contentRange
                    )
                }

                if let complexScriptSize =
                    value.complexScriptSize {

                    result.addAttribute(
                        .boldWriterComplexScriptSize,
                        value:
                            complexScriptSize,
                        range:
                            contentRange
                    )
                }

                if let runFonts =
                    value.runFonts {

                    result.addAttribute(
                        .boldWriterRunFonts,
                        value:
                            runFonts.copy(),
                        range:
                            contentRange
                    )
                }

                if let characterStyle =
                    value.characterStyle {

                    result.addAttribute(
                        .boldWriterCharacterStyle,
                        value:
                            characterStyle.copy(),
                        range:
                            contentRange
                    )
                }

                if let runBorder =
                    value.runBorder {

                    result.addAttribute(
                        .boldWriterRunBorder,
                        value:
                            runBorder.copy(),
                        range:
                            contentRange
                    )
                }

                if let runShading =
                    value.runShading {

                    result.addAttribute(
                        .boldWriterRunShading,
                        value:
                            runShading.copy(),
                        range:
                            contentRange
                    )
                }

                if let highlight =
                    value.highlight {

                    result.addAttribute(
                        .boldWriterHighlight,
                        value:
                            highlight,
                        range:
                            contentRange
                    )

                    let normalized =
                        highlight.lowercased()

                    let visual:
                        NSColor?

                    switch normalized {
                    case "black":
                        visual = .black
                    case "blue":
                        visual = .blue
                    case "cyan":
                        visual = .cyan
                    case "green":
                        visual = .green
                    case "magenta":
                        visual = .magenta
                    case "red":
                        visual = .red
                    case "yellow":
                        visual = .yellow
                    case "white":
                        visual = .white
                    case "darkblue":
                        visual = NSColor(
                            calibratedRed:
                                0,
                            green:
                                0,
                            blue:
                                0.55,
                            alpha:
                                1
                        )
                    case "darkcyan":
                        visual = NSColor(
                            calibratedRed:
                                0,
                            green:
                                0.55,
                            blue:
                                0.55,
                            alpha:
                                1
                        )
                    case "darkgreen":
                        visual = NSColor(
                            calibratedRed:
                                0,
                            green:
                                0.45,
                            blue:
                                0,
                            alpha:
                                1
                        )
                    case "darkmagenta":
                        visual = NSColor(
                            calibratedRed:
                                0.55,
                            green:
                                0,
                            blue:
                                0.55,
                            alpha:
                                1
                        )
                    case "darkred":
                        visual = NSColor(
                            calibratedRed:
                                0.55,
                            green:
                                0,
                            blue:
                                0,
                            alpha:
                                1
                        )
                    case "darkyellow":
                        visual = NSColor(
                            calibratedRed:
                                0.55,
                            green:
                                0.55,
                            blue:
                                0,
                            alpha:
                                1
                        )
                    case "darkgray":
                        visual = .darkGray
                    case "lightgray":
                        visual = .lightGray
                    case "none":
                        visual = nil
                    default:
                        visual = nil
                    }

                    if let visual {
                        result.addAttribute(
                            .backgroundColor,
                            value:
                                visual,
                            range:
                                contentRange
                        )
                    }
                }

                if let singleStrike = value.singleStrike {
                    result.addAttribute(.strikethroughStyle,value:singleStrike ? NSUnderlineStyle.single.rawValue:0,range:contentRange)
                }
                if let doubleStrike =
                    value.doubleStrike {

                    result.addAttribute(
                        .boldWriterDoubleStrikethrough,
                        value:
                            doubleStrike,
                        range:
                            contentRange
                    )
                }

                if let allCaps =
                    value.allCaps {

                    result.addAttribute(
                        .boldWriterAllCaps,
                        value:
                            allCaps,
                        range:
                            contentRange
                    )
                }

                if let characterScale =
                    value.characterScale {

                    result.addAttribute(
                        .boldWriterCharacterScale,
                        value:
                            characterScale,
                        range:
                            contentRange
                    )
                }

                if let underlineVariant =
                    value.underlineVariant {

                    result.addAttribute(
                        .boldWriterUnderlineVariant,
                        value:
                            underlineVariant,
                        range:
                            contentRange
                    )

                    let nativeStyle:
                        NSUnderlineStyle

                    switch underlineVariant.lowercased() {
                    case "double", "wavedouble":
                        nativeStyle = .double

                    case "dotted", "dottedheavy":
                        nativeStyle = [
                            .single,
                            .patternDot
                        ]

                    case "dash",
                         "dashedheavy",
                         "dashlong",
                         "dashlongheavy":
                        nativeStyle = [
                            .single,
                            .patternDash
                        ]

                    case "dotdash",
                         "dotdashheavy":
                        nativeStyle = [
                            .single,
                            .patternDashDot
                        ]

                    case "dotdotdash",
                         "dotdotdashheavy":
                        nativeStyle = [
                            .single,
                            .patternDashDotDot
                        ]

                    default:
                        nativeStyle = .single
                    }

                    result.addAttribute(
                        .underlineStyle,
                        value:
                            nativeStyle.rawValue,
                        range:
                            contentRange
                    )
                }

                if let language =
                    value.language {

                    result.addAttribute(
                        .boldWriterLanguage,
                        value:
                            language,
                        range:
                            contentRange
                    )
                }

                if let wordLanguage =
                    value.wordLanguage {

                    result.addAttribute(
                        .boldWriterWordLanguage,
                        value:
                            wordLanguage.copy(),
                        range:
                            contentRange
                    )
                }

                if let kernThreshold =
                    value.kernThreshold {

                    result.addAttribute(
                        .boldWriterKernThreshold,
                        value:
                            kernThreshold,
                        range:
                            contentRange
                    )
                }

                if let emphasis =
                    value.emphasis {

                    result.addAttribute(
                        .boldWriterEmphasis,
                        value:
                            emphasis,
                        range:
                            contentRange
                    )
                }

                if let specVanish =
                    value.specVanish {

                    result.addAttribute(
                        .boldWriterSpecVanish,
                        value:
                            specVanish,
                        range:
                            contentRange
                    )
                }

                if let webHidden =
                    value.webHidden {

                    result.addAttribute(
                        .boldWriterWebHidden,
                        value:
                            webHidden,
                        range:
                            contentRange
                    )
                }

                if let baselineOffset =
                    value.baselineOffset {

                    result.addAttribute(
                        .baselineOffset,
                        value:
                            baselineOffset,
                        range:
                            contentRange
                    )
                }

                if let outline =
                    value.outline {

                    result.addAttribute(
                        .boldWriterOutlineText,
                        value:
                            outline,
                        range:
                            contentRange
                    )
                }

                if let shadow =
                    value.shadow {

                    result.addAttribute(
                        .boldWriterShadowText,
                        value:
                            shadow,
                        range:
                            contentRange
                    )
                }

                if let emboss =
                    value.emboss {

                    result.addAttribute(
                        .boldWriterEmbossText,
                        value:
                            emboss,
                        range:
                            contentRange
                    )
                }

                if let imprint =
                    value.imprint {

                    result.addAttribute(
                        .boldWriterImprintText,
                        value:
                            imprint,
                        range:
                            contentRange
                    )
                }

                if let superscript =
                    value.superscript {

                    result.addAttribute(
                        .superscript,
                        value:
                            superscript,
                        range:
                            contentRange
                    )
                }

                if let kern =
                    value.kern {

                    result.addAttribute(
                        .kern,
                        value:
                            kern,
                        range:
                            contentRange
                    )
                }
            }

            result.deleteCharacters(
                in:
                    originalEnd
            )

            result.deleteCharacters(
                in:
                    originalStart
            )
        }
    }

    private struct ImportedParagraphWordMetadata {
        let marker: String
        let bidi: Bool?
        let textDirection: String?
        let contextualSpacing: Bool?
        let suppressLineNumbers: Bool?
        let mirrorIndents: Bool?
    }

    private static func prepareParagraphWordMetadata(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphWordMetadata] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func child(
            _ parent: XMLElement,
            named name: String
        ) -> XMLElement? {
            parent.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func optionalEnabled(
            _ element: XMLElement?
        ) -> Bool? {
            guard
                let element
            else {
                return nil
            }

            guard
                let raw =
                    attribute(
                        element,
                        "val"
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()
            else {
                return true
            }

            return ![
                "0",
                "false",
                "off",
                "no"
            ]
            .contains(
                raw
            )
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphWordMetadata] = []

        for paragraph in paragraphs {
            guard
                let properties =
                    child(
                        paragraph,
                        named:
                            "pPr"
                    )
            else {
                continue
            }

            let bidi =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "bidi"
                    )
                )

            let contextualSpacing =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "contextualSpacing"
                    )
                )

            let suppressLineNumbers =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "suppressLineNumbers"
                    )
                )

            let mirrorIndents =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "mirrorIndents"
                    )
                )

            let textDirection =
                child(
                    properties,
                    named:
                        "textDirection"
                )
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
                .flatMap {
                    raw -> String? in

                    let trimmed =
                        raw.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    return trimmed.isEmpty
                        ? nil
                        : trimmed
                }

            guard
                bidi != nil
                    || textDirection != nil
                    || contextualSpacing != nil
                    || suppressLineNumbers != nil
                    || mirrorIndents != nil
            else {
                continue
            }

            let marker =
                "BOLDPARAWORD"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let insertionIndex =
                paragraph.children?
                    .first?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphWordMetadata(
                    marker:
                        marker,
                    bidi:
                        bidi,
                    textDirection:
                        textDirection,
                    contextualSpacing:
                        contextualSpacing,
                    suppressLineNumbers:
                        suppressLineNumbers,
                    mirrorIndents:
                        mirrorIndents
                )
            )
        }

        return result
    }

    private static func indexedImportMarkers(in result: NSAttributedString) throws -> [String: NSRange] {
        let source = result.string as NSString
        let expression = try NSRegularExpression(pattern: "BOLD(?:PARAWORD|PARAGRAPHBORDER|PARASHADING|PARATAB|PARASPACING|PARASTYLE)[A-F0-9]{32}")
        var markers: [String: NSRange] = [:]
        expression.enumerateMatches(in: source as String, range: NSRange(location: 0, length: source.length)) { match, _, _ in
            guard let range = match?.range else { return }
            markers[source.substring(with: range)] = range
        }
        return markers
    }

    private static func restoreParagraphWordMetadata(
        _ values: [ImportedParagraphWordMetadata],
        into result:
            NSMutableAttributedString
    ) throws {
        let markerIndex = try indexedImportMarkers(in: result)
        for value in values.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let source =
                result.string
                    as NSString

            let markerRange =
                markerIndex[value.marker] ?? NSRange(location: NSNotFound, length: 0)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph metadata marker was lost during DOCX import."
                )
            }

            let paragraphStart =
                source.paragraphRange(
                    for:
                        NSRange(
                            location:
                                markerRange.location,
                            length:
                                0
                        )
                )
                .location

            result.deleteCharacters(
                in:
                    markerRange
            )

            guard
                result.length > 0
            else {
                continue
            }

            let location =
                min(
                    paragraphStart,
                    result.length - 1
                )

            let paragraphRange =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                location,
                            length:
                                0
                        )
                )

            if let bidi =
                value.bidi {

                let paragraph = (result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
                    .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
                paragraph.baseWritingDirection = bidi ? .rightToLeft : .leftToRight
                result.addAttribute(.paragraphStyle, value: paragraph, range: paragraphRange)

                result.addAttribute(
                    .boldWriterParagraphBidi,
                    value:
                        bidi,
                    range:
                        paragraphRange
                )
            }

            if let textDirection =
                value.textDirection {

                result.addAttribute(
                    .boldWriterTextDirection,
                    value:
                        textDirection,
                    range:
                        paragraphRange
                )
            }

            if let contextualSpacing =
                value.contextualSpacing {

                result.addAttribute(
                    .boldWriterContextualSpacing,
                    value:
                        contextualSpacing,
                    range:
                        paragraphRange
                )
            }

            if let suppressLineNumbers =
                value.suppressLineNumbers {

                result.addAttribute(
                    .boldWriterSuppressLineNumbers,
                    value:
                        suppressLineNumbers,
                    range:
                        paragraphRange
                )
            }

            if let mirrorIndents =
                value.mirrorIndents {

                result.addAttribute(
                    .boldWriterMirrorIndents,
                    value:
                        mirrorIndents,
                    range:
                        paragraphRange
                )
            }
        }
    }

    private struct ImportedParagraphPagination {
        let marker: String
        let keepWithNext: Bool
        let keepLinesTogether: Bool
        let pageBreakBefore: Bool
        let widowControl: Bool?
    }

    private static func prepareParagraphPagination(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphPagination] {
        func rawAttribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func child(
            _ parent: XMLElement,
            named name: String
        ) -> XMLElement? {
            (parent.children ?? [])
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName == name
                }
        }

        func enabled(
            _ element: XMLElement?
        ) -> Bool {
            guard
                let element
            else {
                return false
            }

            guard
                let value =
                    rawAttribute(
                        element,
                        "val"
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()
            else {
                return true
            }

            return ![
                "0",
                "false",
                "off",
                "no"
            ]
            .contains(
                value
            )
        }

        func optionalEnabled(
            _ element: XMLElement?
        ) -> Bool? {
            guard
                let element
            else {
                return nil
            }

            guard
                let value =
                    rawAttribute(
                        element,
                        "val"
                    )?
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )
                    .lowercased()
            else {
                return true
            }

            return ![
                "0",
                "false",
                "off",
                "no"
            ]
            .contains(
                value
            )
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphPagination] = []

        for paragraph in paragraphs {
            guard
                let properties =
                    child(
                        paragraph,
                        named:
                            "pPr"
                    )
            else {
                continue
            }

            let keepWithNext =
                enabled(
                    child(
                        properties,
                        named:
                            "keepNext"
                    )
                )

            let keepLinesTogether =
                enabled(
                    child(
                        properties,
                        named:
                            "keepLines"
                    )
                )

            let pageBreakBefore =
                enabled(
                    child(
                        properties,
                        named:
                            "pageBreakBefore"
                    )
                )

            let widowControl =
                optionalEnabled(
                    child(
                        properties,
                        named:
                            "widowControl"
                    )
                )

            guard
                keepWithNext
                    || keepLinesTogether
                    || pageBreakBefore
                    || widowControl != nil
            else {
                continue
            }

            let marker =
                "BOLDPARAPAGINATION"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let insertionIndex =
                paragraph.children?
                    .first?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphPagination(
                    marker:
                        marker,
                    keepWithNext:
                        keepWithNext,
                    keepLinesTogether:
                        keepLinesTogether,
                    pageBreakBefore:
                        pageBreakBefore,
                    widowControl:
                        widowControl
                )
            )
        }

        return result
    }

    private static func restoreParagraphPagination(
        _ values: [ImportedParagraphPagination],
        into result:
            NSMutableAttributedString
    ) throws {
        for value in values {
            let markerRange =
                (
                    result.string
                        as NSString
                )
                .range(of: value.marker, options: .literal)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph-pagination marker was lost "
                    + "during DOCX import."
                )
            }

            let paragraphStart =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                markerRange.location,
                            length:
                                0
                        )
                )
                .location

            result.deleteCharacters(
                in:
                    markerRange
            )

            guard
                result.length > 0
            else {
                continue
            }

            let location =
                min(
                    paragraphStart,
                    result.length - 1
                )

            let paragraphRange =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                location,
                            length:
                                0
                        )
                )

            if value.keepWithNext {
                result.addAttribute(
                    .boldWriterKeepWithNext,
                    value:
                        true,
                    range:
                        paragraphRange
                )
            }

            if value.keepLinesTogether {
                result.addAttribute(
                    .boldWriterKeepLinesTogether,
                    value:
                        true,
                    range:
                        paragraphRange
                )
            }

            if value.pageBreakBefore {
                result.addAttribute(
                    .boldWriterPageBreakBefore,
                    value:
                        true,
                    range:
                        paragraphRange
                )
            }

            if let widowControl =
                value.widowControl {

                result.addAttribute(
                    .boldWriterWidowControl,
                    value:
                        widowControl,
                    range:
                        paragraphRange
                )
            }
        }
    }

    private struct ImportedParagraphBorders {
        let marker: String
        let borders: WordParagraphBorders
    }

    private static func prepareParagraphBorders(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphBorders] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func readBorder(
            from properties: XMLElement,
            named name: String
        ) throws -> WordParagraphBorder? {
            let nodes =
                try properties.nodes(
                    forXPath:
                        "./*[local-name()='"
                        + name
                        + "']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            guard
                nodes.count <= 1
            else {
                throw WriterError.message(
                    "A Word paragraph border is duplicated."
                )
            }

            guard
                let node =
                    nodes.first,
                let style =
                    attribute(
                        node,
                        "val"
                    ),
                !style.isEmpty
            else {
                return nil
            }

            return WordParagraphBorder(
                style:
                    style,
                size:
                    attribute(
                        node,
                        "sz"
                    )
                    .flatMap(
                        Int.init
                    ),
                space:
                    attribute(
                        node,
                        "space"
                    )
                    .flatMap(
                        Int.init
                    ),
                color:
                    attribute(
                        node,
                        "color"
                    )
            )
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphBorders] = []

        for paragraph in paragraphs {
            let groups =
                try paragraph.nodes(
                    forXPath:
                        "./*[local-name()='pPr']/*[local-name()='pBdr']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            guard
                groups.count <= 1
            else {
                throw WriterError.message(
                    "A Word paragraph contains duplicate paragraph-border groups."
                )
            }

            guard
                let properties =
                    groups.first
            else {
                continue
            }

            let borders =
                WordParagraphBorders(
                    top:
                        try readBorder(
                            from:
                                properties,
                            named:
                                "top"
                        ),
                    left:
                        try readBorder(
                            from:
                                properties,
                            named:
                                "left"
                        ),
                    bottom:
                        try readBorder(
                            from:
                                properties,
                            named:
                                "bottom"
                        ),
                    right:
                        try readBorder(
                            from:
                                properties,
                            named:
                                "right"
                        ),
                    between:
                        try readBorder(
                            from:
                                properties,
                            named:
                                "between"
                        )
                )

            guard
                !borders.isEmpty
            else {
                continue
            }

            let marker =
                "BOLDPARAGRAPHBORDER"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let insertionIndex =
                paragraph.children?
                    .first?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphBorders(
                    marker:
                        marker,
                    borders:
                        borders
                )
            )
        }

        return result
    }

    private static func restoreParagraphBorders(
        _ values: [ImportedParagraphBorders],
        into result:
            NSMutableAttributedString
    ) throws {
        let markerIndex = try indexedImportMarkers(in: result)
        for value in values.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let source =
                result.string
                    as NSString

            let markerRange =
                markerIndex[value.marker] ?? NSRange(location: NSNotFound, length: 0)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph-border marker was lost during DOCX import."
                )
            }

            let paragraphStart =
                source.paragraphRange(
                    for:
                        NSRange(
                            location:
                                markerRange.location,
                            length:
                                0
                        )
                )
                .location

            result.deleteCharacters(
                in:
                    markerRange
            )

            guard
                result.length > 0
            else {
                continue
            }

            let safeLocation =
                min(
                    paragraphStart,
                    result.length - 1
                )

            let paragraphRange =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                safeLocation,
                            length:
                                0
                        )
                )

            result.addAttribute(
                .boldWriterParagraphBorders,
                value:
                    value.borders.copy(),
                range:
                    paragraphRange
            )
        }
    }

    private struct ImportedParagraphShading {
        let marker: String
        let shading: WordParagraphShading
    }

    private static func prepareParagraphShading(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphShading] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func normalizedColor(
            _ raw: String?
        ) -> String? {
            guard
                let raw,
                !raw.isEmpty
            else {
                return nil
            }

            return raw.lowercased()
                == "auto"
                ? "auto"
                : raw.uppercased()
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphShading] = []

        for paragraph in paragraphs {
            let nodes =
                try paragraph.nodes(
                    forXPath:
                        "./*[local-name()='pPr']/*[local-name()='shd']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            guard nodes.count <= 1 else {
                throw WriterError.message(
                    "A Word paragraph contains duplicate shading properties."
                )
            }

            guard
                let node =
                    nodes.first
            else {
                continue
            }

            let value =
                attribute(
                    node,
                    "val"
                )
                ?? "clear"

            let shading =
                WordParagraphShading(
                    value:
                        value,
                    color:
                        normalizedColor(
                            attribute(
                                node,
                                "color"
                            )
                        ),
                    fill:
                        normalizedColor(
                            attribute(
                                node,
                                "fill"
                            )
                        )
                )

            let marker =
                "BOLDPARASHADING"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let insertionIndex =
                paragraph.children?
                    .first?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphShading(
                    marker:
                        marker,
                    shading:
                        shading
                )
            )
        }

        return result
    }

    private static func restoreParagraphShading(
        _ values: [ImportedParagraphShading],
        into result:
            NSMutableAttributedString
    ) throws {
        let markerIndex = try indexedImportMarkers(in: result)
        for value in values.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let source =
                result.string as NSString

            let markerRange =
                markerIndex[value.marker] ?? NSRange(location: NSNotFound, length: 0)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph-shading marker was lost during DOCX import."
                )
            }

            let paragraphStart =
                source.paragraphRange(
                    for:
                        NSRange(
                            location:
                                markerRange.location,
                            length:
                                0
                        )
                )
                .location

            result.deleteCharacters(
                in:
                    markerRange
            )

            guard result.length > 0 else {
                continue
            }

            let location =
                min(
                    paragraphStart,
                    result.length - 1
                )

            let paragraphRange =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                location,
                            length:
                                0
                        )
                )

            result.addAttribute(
                .boldWriterParagraphShading,
                value:
                    value.shading.copy(),
                range:
                    paragraphRange
            )
        }
    }

    private struct ImportedParagraphTabs {
        let marker: String
        let tabs: [NSTextTab]
    }

    private static func prepareParagraphTabs(in xml: XMLDocument) throws -> [ImportedParagraphTabs] {
        let paragraphs = DOCXPackage.bodyParagraphs(in:xml)
            .compactMap { $0 as? XMLElement }
        var result: [ImportedParagraphTabs] = []
        for paragraph in paragraphs {
            let nodes = try paragraph.nodes(forXPath: "./*[local-name()='pPr']/*[local-name()='tabs']/*[local-name()='tab']")
                .compactMap { $0 as? XMLElement }
            let tabs: [NSTextTab] = nodes.compactMap { node in
                func attribute(_ name: String) -> String? {
                    node.attributes?.first(where: {
                        $0.localName == name || $0.name == name || $0.name == "w:" + name
                    })?.stringValue
                }
                guard let rawPosition = attribute("pos"), let position = Double(rawPosition),
                      position.isFinite, position >= 0, position <= 200_000 else { return nil }
                let alignment: NSTextAlignment
                switch attribute("val") {
                case "left": alignment = .left
                case "right": alignment = .right
                case "center": alignment = .center
                default: return nil
                }
                return NSTextTab(textAlignment: alignment, location: CGFloat(position / 20), options: [:])
            }
            guard !tabs.isEmpty else { continue }
            let marker = "BOLDPARATAB" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let insertionIndex = paragraph.children?.first?.localName == "pPr" ? 1 : 0
            paragraph.insertChild(revisionMarkerRun(marker), at: insertionIndex)
            result.append(ImportedParagraphTabs(marker: marker, tabs: tabs))
        }
        return result
    }

    private static func restoreParagraphTabs(
        _ values: [ImportedParagraphTabs], into result: NSMutableAttributedString
    ) throws {
        let markerIndex = try indexedImportMarkers(in: result)
        for value in values.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let source = result.string as NSString
            let markerRange = markerIndex[value.marker] ?? NSRange(location: NSNotFound, length: 0)
            guard markerRange.location != NSNotFound else {
                throw WriterError.message("A Word paragraph tab-stop marker was lost during DOCX import.")
            }
            let paragraphStart = source.paragraphRange(for: NSRange(location: markerRange.location, length: 0)).location
            result.deleteCharacters(in: markerRange)
            guard result.length > 0 else { continue }
            let location = min(paragraphStart, result.length - 1)
            let paragraphRange = (result.string as NSString).paragraphRange(for: NSRange(location: location, length: 0))
            let style = (result.attribute(.paragraphStyle, at: location, effectiveRange: nil) as? NSParagraphStyle)?
                .mutableCopy() as? NSMutableParagraphStyle ?? NSMutableParagraphStyle()
            style.tabStops = value.tabs
            result.addAttribute(.paragraphStyle, value: style, range: paragraphRange)
        }
    }

    private struct ImportedParagraphLineSpacing {
        let marker: String
        let before: CGFloat?
        let after: CGFloat?
        let exact: CGFloat?
        let multiple: CGFloat?
    }

    private static func prepareParagraphLineSpacing(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphLineSpacing] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphLineSpacing] = []

        for paragraph in paragraphs {
            let spacingNodes =
                try paragraph.nodes(
                    forXPath:
                        "./*[local-name()='pPr']/*[local-name()='spacing']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            guard
                spacingNodes.count == 1,
                let spacing = spacingNodes.first
            else {
                continue
            }

            func points(
                _ name: String
            ) -> CGFloat? {
                guard
                    let raw = attribute(
                        spacing,
                        name
                    ),
                    let value = Double(raw),
                    value.isFinite
                else {
                    return nil
                }

                return CGFloat(
                    value / 20.0
                )
            }

            let before =
                points(
                    "before"
                )

            let after =
                points(
                    "after"
                )

            var exact:
                CGFloat?

            var multiple:
                CGFloat?

            if let rawLine =
                attribute(
                    spacing,
                    "line"
                ),
               let line =
                Double(rawLine),
               line.isFinite {

                let rule =
                    attribute(
                        spacing,
                        "lineRule"
                    )?
                    .lowercased()

                if rule == "exact" {
                    exact =
                        CGFloat(
                            line / 20.0
                        )
                } else if rule == "auto"
                            || rule == nil {
                    multiple =
                        CGFloat(
                            line / 240.0
                        )
                }
            }

            guard
                before != nil
                    || after != nil
                    || exact != nil
                    || multiple != nil
            else {
                continue
            }

            let marker =
                "BOLDPARASPACING"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let firstChild =
                paragraph.children?
                    .first

            let insertionIndex =
                firstChild?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphLineSpacing(
                    marker:
                        marker,
                    before:
                        before,
                    after:
                        after,
                    exact:
                        exact,
                    multiple:
                        multiple
                )
            )
        }

        return result
    }

    private static func restoreParagraphLineSpacing(
        _ values: [ImportedParagraphLineSpacing],
        into result:
            NSMutableAttributedString
    ) throws {
        let markerIndex = try indexedImportMarkers(in: result)
        for value in values.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let markerRange =
                markerIndex[value.marker] ?? NSRange(location: NSNotFound, length: 0)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph-spacing marker was lost "
                    + "during DOCX import."
                )
            }

            let paragraphStart =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                markerRange.location,
                            length:
                                0
                        )
                )
                .location

            result.deleteCharacters(
                in:
                    markerRange
            )

            guard
                result.length > 0
            else {
                continue
            }

            let adjustedStart =
                min(
                    paragraphStart,
                    result.length - 1
                )

            let paragraphRange =
                (
                    result.string
                        as NSString
                )
                .paragraphRange(
                    for:
                        NSRange(
                            location:
                                adjustedStart,
                            length:
                                0
                        )
                )

            let current =
                (
                    result.attribute(
                        .paragraphStyle,
                        at:
                            adjustedStart,
                        effectiveRange:
                            nil
                    )
                        as? NSParagraphStyle
                )?
                .mutableCopy()
                    as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            if let before =
                value.before {
                current.paragraphSpacingBefore =
                    before
            }

            if let after =
                value.after {
                current.paragraphSpacing =
                    after
            }

            if let exact =
                value.exact {
                current.lineHeightMultiple =
                    0

                current.minimumLineHeight =
                    exact

                current.maximumLineHeight =
                    exact
            } else if let multiple =
                value.multiple {
                current.minimumLineHeight =
                    0

                current.maximumLineHeight =
                    0

                current.lineHeightMultiple =
                    multiple
            }

            result.addAttribute(
                .paragraphStyle,
                value:
                    current,
                range:
                    paragraphRange
            )
        }
    }

    private static func prepareNamedParagraphStyles(
        in xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws -> [ImportedParagraphStyle] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName
                        == name
                        || $0.name
                            == name
                        || $0.name
                            == "w:"
                            + name
                        || $0.name
                            == "r:"
                            + name
                }?
                .stringValue
        }

        func childValue(
            _ definition: XMLElement,
            _ name: String
        ) -> String? {
            definition.children?
                .compactMap {
                    $0 as? XMLElement
                }
                .first {
                    $0.localName
                        == name
                }
                .flatMap {
                    attribute(
                        $0,
                        "val"
                    )
                }
        }

        func recognizedStyle(
            _ raw: String
        ) -> WriterStyle? {
            let normalized =
                raw
                .lowercased()
                .filter {
                    $0.isLetter
                        || $0.isNumber
                }

            switch normalized {
            case "normal":
                return .normal

            case "nospacing":
                return .noSpacing

            case "title":
                return .title

            case "subtitle":
                return .subtitle

            case "heading1":
                return .heading1

            case "heading2":
                return .heading2

            case "heading3":
                return .heading3

            case "heading4":
                return .heading4

            case "heading5":
                return .heading5

            case "heading6":
                return .heading6

            case "quote":
                return .quote

            case "intensequote":
                return .intenseQuote

            case "blockquote":
                return .blockQuote

            case "caption":
                return .caption

            default:
                return nil
            }
        }

        // Exact paragraph definitions are retained separately from
        // BOLD semantic WriterStyle classification.
        //
        // IMPORTANT:
        // basedOn and w:link never promote a custom Word style into
        // Heading/Title/etc. Only the style's own exact styleId or
        // exact w:name may identify a semantic BOLD style.

        var definitionsByID:
            [String: WordParagraphStyle] = [:]

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        if let relationshipData =
            parts[
                relationshipPath
            ] {

            let relationships =
                try DOCXPackage.xml(
                    relationshipData
                )

            let styleRelationships =
                DOCXPackage.descendants(in:relationships,named:"Relationship")
                .compactMap {
                    $0 as? XMLElement
                }
                .filter {
                    relationship in

                    relationship.attribute(
                        forName:
                            "Type"
                    )?
                    .stringValue?
                    .hasSuffix(
                        "/styles"
                    ) == true
                        && relationship.attribute(
                            forName:
                                "TargetMode"
                        )?
                        .stringValue
                            != "External"
                }

            if styleRelationships.count == 1,
               let relationship =
                styleRelationships.first,
               let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
               let stylePath =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
               let styleData =
                parts[
                    stylePath
                ] {

                let styleXML =
                    try DOCXPackage.xml(
                        styleData
                    )

                let definitions =
                    try styleXML.nodes(
                        forXPath:
                            "/*[local-name()='styles']/*[local-name()='style']"
                    )
                    .compactMap {
                        $0 as? XMLElement
                    }

                for definition in definitions {
                    let type =
                        attribute(
                            definition,
                            "type"
                        )?
                        .lowercased()

                    guard
                        type == nil
                            || type
                                == "paragraph",
                        let styleID =
                            attribute(
                                definition,
                                "styleId"
                            ),
                        !styleID.isEmpty
                    else {
                        continue
                    }

                    definitionsByID[
                        styleID
                    ] =
                        WordParagraphStyle(
                            styleID:
                                styleID,
                            name:
                                childValue(
                                    definition,
                                    "name"
                                ),
                            basedOn:
                                childValue(
                                    definition,
                                    "basedOn"
                                ),
                            linkedStyleID:
                                childValue(
                                    definition,
                                    "link"
                                ),
                            nextStyleID:
                                childValue(
                                    definition,
                                    "next"
                                ),
                            dependencies:
                                try wordStyleDependencyGraph(
                                    parts:
                                        parts,
                                    mainPart:
                                        mainPart,
                                    rootStyleID:
                                        styleID
                                )
                        )
                }
            }
        }

        let paragraphs =
            DOCXPackage.bodyParagraphs(in:xml)
            .compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphStyle] = []


        for paragraph in paragraphs {
            let styleNodes =
                try paragraph.nodes(
                    forXPath:
                        "./*[local-name()='pPr']/*[local-name()='pStyle']"
                )
                .compactMap {
                    $0 as? XMLElement
                }

            guard
                styleNodes.count == 1,
                let styleNode =
                    styleNodes.first,
                let styleID =
                    attribute(
                        styleNode,
                        "val"
                    ),
                !styleID.isEmpty
            else {
                continue
            }

            let definition =
                definitionsByID[
                    styleID
                ]

            let semantic =
                recognizedStyle(
                    styleID
                )
                ?? definition?
                    .name
                    .flatMap {
                        recognizedStyle(
                            $0
                        )
                    }

            let customWordStyle:
                WordParagraphStyle?

            if semantic == nil {
                customWordStyle =
                    definition
                    ?? WordParagraphStyle(
                        styleID:
                            styleID
                    )
            } else {
                customWordStyle =
                    nil
            }

            guard
                semantic != nil
                    || customWordStyle != nil
            else {
                continue
            }

            let marker =
                "BOLDPARASTYLE"
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )

            let firstChild =
                paragraph.children?
                    .first

            let insertionIndex =
                firstChild?
                    .localName
                    == "pPr"
                    ? 1
                    : 0

            paragraph.insertChild(
                revisionMarkerRun(
                    marker
                ),
                at:
                    insertionIndex
            )

            result.append(
                ImportedParagraphStyle(
                    marker:
                        marker,
                    semanticStyle:
                        semantic,
                    wordStyle:
                        customWordStyle
                )
            )
        }

        return result
    }

    private static func restoreNamedParagraphStyles(
        _ styles: [ImportedParagraphStyle],
        into result:
            NSMutableAttributedString
    ) throws {
        guard
            !styles.isEmpty
        else {
            return
        }

        let markerIndex = try indexedImportMarkers(in: result)
        for imported in styles.sorted(by: { (markerIndex[$0.marker]?.location ?? 0) > (markerIndex[$1.marker]?.location ?? 0) }) {
            let source =
                result.string
                    as NSString

            let markerRange =
                markerIndex[imported.marker] ?? NSRange(location: NSNotFound, length: 0)

            guard
                markerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A Word paragraph-style marker was lost "
                    + "during DOCX import. Import was stopped "
                    + "without changing the original file."
                )
            }

            let after =
                NSMaxRange(
                    markerRange
                )

            if after < source.length {
                let duplicate =
                    source.range(
                        of:
                            imported.marker,
                        options:
                            [],
                        range:
                            NSRange(
                                location:
                                    after,
                                length:
                                    source.length
                                    - after
                            )
                    )

                guard
                    duplicate.location
                        == NSNotFound
                else {
                    throw WriterError.message(
                        "A Word paragraph-style marker was "
                        + "duplicated during DOCX import."
                    )
                }
            }

            let paragraphLocation =
                markerRange.location

            result.deleteCharacters(
                in:
                    markerRange
            )

            let updated =
                result.string
                    as NSString

            guard
                updated.length > 0
            else {
                continue
            }

            let safeLocation =
                min(
                    paragraphLocation,
                    max(
                        0,
                        updated.length - 1
                    )
                )

            let paragraphRange =
                updated.paragraphRange(
                    for:
                        NSRange(
                            location:
                                safeLocation,
                            length:
                                0
                        )
                )

            guard
                paragraphRange.location
                    != NSNotFound,
                paragraphRange.length > 0,
                NSMaxRange(
                    paragraphRange
                )
                    <= result.length
            else {
                throw WriterError.message(
                    "A Word paragraph style could not be "
                    + "reattached to its imported paragraph."
                )
            }

            if let semantic =
                imported.semanticStyle {

                result.addAttribute(
                    .boldWriterStyle,
                    value:
                        semantic.rawValue,
                    range:
                        paragraphRange
                )
            }

            if let wordStyle =
                imported.wordStyle {

                result.addAttribute(
                    .boldWriterParagraphStyle,
                    value:
                        wordStyle,
                    range:
                        paragraphRange
                )
            }
        }
    }

    static func allBookmarkNamesForHyperlinkValidation(
        in xml: XMLDocument
    ) throws -> [String] {
        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName
                        == name
                        || $0.name
                            == name
                        || $0.name
                            == "w:"
                            + name
                }?
                .stringValue
        }

        return DOCXPackage.descendants(in:xml,named:"bookmarkStart")
        .compactMap {
            $0 as? XMLElement
        }
        .compactMap {
            attribute(
                $0,
                "name"
            )
        }
        .filter {
            !$0.isEmpty
        }
    }

    static func shouldRestoreWordBookmarkAsUserBookmark(
        _ name: String
    ) -> Bool {
        guard
            !name.hasPrefix(
                "_"
            ),
            let firstScalar =
                name.unicodeScalars.first
        else {
            return false
        }

        return CharacterSet
            .letters
            .contains(
                firstScalar
            )
    }

    private static func prepareHyperlinks(
        in xml: XMLDocument,
        bookmarkNames importedBookmarkNames: [String],
        parts: [String: Data],
        mainPart: String
    ) throws -> [ImportedHyperlink] {
        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "The DOCX contains a hyperlink that could not be "
                + "recovered safely. "
                + detail
            )
        }

        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName
                        == name
                        || $0.name
                            == name
                        || $0.name
                            == "w:"
                            + name
                        || $0.name
                            == "r:"
                            + name
                }?
                .stringValue
        }

        let hyperlinks =
            DOCXPackage.descendants(in:xml,named:"hyperlink")
            .compactMap {
                $0 as? XMLElement
            }

        guard
            !hyperlinks.isEmpty
        else {
            return []
        }

        let bookmarkNames = Set(importedBookmarkNames.map { DocumentBookmarks.normalizedName($0).lowercased() })

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        var externalTargets:
            [String: String] = [:]

        if let relationshipData =
            parts[
                relationshipPath
            ] {

            let relationships =
                try DOCXPackage.xml(
                    relationshipData
                )

            for case let relationship
                as XMLElement
                in DOCXPackage.descendants(in:relationships,named:"Relationship") {

                guard
                    relationship.attribute(
                        forName:
                            "Type"
                    )?
                    .stringValue?
                    .hasSuffix(
                        "/hyperlink"
                    ) == true
                else {
                    continue
                }

                guard
                    relationship.attribute(
                        forName:
                            "TargetMode"
                    )?
                    .stringValue
                        == "External",
                    let id =
                        relationship.attribute(
                            forName:
                                "Id"
                        )?
                        .stringValue,
                    !id.isEmpty,
                    let target =
                        relationship.attribute(
                            forName:
                                "Target"
                        )?
                        .stringValue,
                    !target.isEmpty
                else {
                    throw failure(
                        "A hyperlink relationship is not a valid "
                        + "external target."
                    )
                }

                guard
                    externalTargets[id]
                        == nil
                else {
                    throw failure(
                        "A hyperlink relationship identifier is duplicated."
                    )
                }

                externalTargets[id] =
                    target
            }
        }

        func marker(
            _ prefix: String
        ) -> String {
            prefix
            + UUID()
                .uuidString
                .replacingOccurrences(
                    of:
                        "-",
                    with:
                        ""
                )
        }

        var result:
            [ImportedHyperlink] = []

        for hyperlink in hyperlinks {
            let target:
                String

            if let anchor =
                attribute(
                    hyperlink,
                    "anchor"
                ),
               !anchor.isEmpty {

                guard bookmarkNames.contains(DocumentBookmarks.normalizedName(anchor).lowercased()) else {
                    throw failure("An internal hyperlink has a dangling bookmark or an external relationship.")
                }

                target =
                    "#"
                    + anchor

            } else if let relationshipID =
                attribute(
                    hyperlink,
                    "id"
                ),
                      !relationshipID.isEmpty {

                guard
                    let external =
                        externalTargets[
                            relationshipID
                        ]
                else {
                    throw failure(
                        "A hyperlink relationship target is missing."
                    )
                }

                guard let url = URL(string: external), let scheme = url.scheme?.lowercased(),
                      ["http", "https", "mailto"].contains(scheme),
                      (scheme == "mailto" ? !url.path.isEmpty : !(url.host ?? "").isEmpty) else {
                    throw failure("A hyperlink relationship has an unsafe or malformed target.")
                }

                target =
                    external

            } else {
                throw failure(
                    "A hyperlink has no internal anchor or "
                    + "external relationship."
                )
            }

            guard
                let parent =
                    hyperlink.parent
                        as? XMLElement
            else {
                throw failure(
                    "A hyperlink has no valid parent."
                )
            }

            let startMarker =
                marker(
                    "BOLDLINKSTART"
                )

            let endMarker =
                marker(
                    "BOLDLINKEND"
                )

            let insertionIndex =
                hyperlink.index

            let children =
                (hyperlink.children
                    ?? [])
                .map {
                    $0.copy()
                        as! XMLNode
                }

            parent.removeChild(
                at:
                    insertionIndex
            )

            var next =
                insertionIndex

            parent.insertChild(
                revisionMarkerRun(
                    startMarker
                ),
                at:
                    next
            )

            next += 1

            for child in children {
                parent.insertChild(
                    child,
                    at:
                        next
                )

                next += 1
            }

            parent.insertChild(
                revisionMarkerRun(
                    endMarker
                ),
                at:
                    next
            )

            result.append(
                ImportedHyperlink(
                    startMarker:
                        startMarker,
                    endMarker:
                        endMarker,
                    target:
                        target
                )
            )
        }

        return result
    }

    private static func restoreHyperlinks(
        _ hyperlinks: [ImportedHyperlink],
        bookmarkAliases: [String: String],
        into result:
            NSMutableAttributedString
    ) throws {
        guard
            !hyperlinks.isEmpty
        else {
            return
        }

        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "A Word hyperlink could not be restored safely. "
                + detail
            )
        }

        let source =
            result.string
                as NSString

        let markerNames =
            hyperlinks.flatMap {
                [
                    $0.startMarker,
                    $0.endMarker
                ]
            }

        var markerRanges:
            [String: NSRange] = [:]

        for marker in markerNames {
            let first =
                source.range(of: marker, options: .literal)

            guard
                first.location
                    != NSNotFound
            else {
                throw failure(
                    "A hyperlink boundary marker was lost during "
                    + "DOCX import."
                )
            }

            let after =
                NSMaxRange(
                    first
                )

            if after < source.length {
                let second =
                    source.range(
                        of:
                            marker,
                        options:
                            [],
                        range:
                            NSRange(
                                location:
                                    after,
                                length:
                                    source.length
                                    - after
                            )
                    )

                guard
                    second.location
                        == NSNotFound
                else {
                    throw failure(
                        "A hyperlink boundary marker was duplicated "
                        + "during DOCX import."
                    )
                }
            }

            markerRanges[
                marker
            ] =
                first
        }

        let allRanges =
            markerRanges.values
                .sorted {
                    $0.location
                        < $1.location
                }

        func adjustedLocation(
            _ location: Int
        ) -> Int {
            let removed =
                allRanges.reduce(
                    0
                ) {
                    partial,
                    range in

                    NSMaxRange(
                        range
                    )
                    <= location
                        ? partial
                            + range.length
                        : partial
                }

            return
                location
                - removed
        }

        struct RestoredLink {
            let range: NSRange
            let target: String
        }

        var restored:
            [RestoredLink] = []

        for hyperlink in hyperlinks {
            guard
                let start =
                    markerRanges[
                        hyperlink.startMarker
                    ],
                let end =
                    markerRanges[
                        hyperlink.endMarker
                    ],
                start.location
                    <= end.location
            else {
                throw failure(
                    "A hyperlink has invalid or reversed boundaries."
                )
            }

            let location =
                adjustedLocation(
                    start.location
                )

            let endLocation =
                adjustedLocation(
                    end.location
                )

            guard
                endLocation
                    >= location
            else {
                throw failure(
                    "A hyperlink range is reversed."
                )
            }

            restored.append(
                RestoredLink(
                    range:
                        NSRange(
                            location:
                                location,
                            length:
                                endLocation
                                - location
                        ),
                    target: hyperlink.target.hasPrefix("#")
                        ? "#" + (bookmarkAliases[String(hyperlink.target.dropFirst()).lowercased()] ?? String(hyperlink.target.dropFirst()))
                        : hyperlink.target
                )
            )
        }

        for range
            in allRanges.sorted(
                by: {
                    $0.location
                        > $1.location
                }
            ) {

            result.deleteCharacters(
                in:
                    range
            )
        }

        for link in restored {
            guard
                link.range.location >= 0,
                link.range.length >= 0,
                link.range.location
                    <= result.length,
                link.range.length
                    <= result.length
                        - link.range.location
            else {
                throw failure(
                    "A restored hyperlink lies outside the "
                    + "imported document."
                )
            }

            guard
                link.range.length > 0
            else {
                continue
            }

            result.addAttribute(
                .link,
                value:
                    link.target,
                range:
                    link.range
            )
        }
    }

    private static func prepareBookmarks(
        in xml: XMLDocument
    ) throws -> [ImportedBookmark] {
        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "The DOCX contains Word bookmarks that could not "
                + "be recovered safely. "
                + detail
            )
        }

        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName
                        == name
                        || $0.name
                            == name
                        || $0.name
                            == "w:"
                            + name
                }?
                .stringValue
        }

        let referencedNames = Set(DOCXPackage.descendants(in:xml,named:"hyperlink")
            .compactMap { $0 as? XMLElement }
            .compactMap { attribute($0,"anchor")?.lowercased() })

        let starts =
            DOCXPackage.descendants(in:xml,named:"bookmarkStart")
            .compactMap {
                $0 as? XMLElement
            }

        let ends =
            DOCXPackage.descendants(in:xml,named:"bookmarkEnd")
                .compactMap {
                    $0 as? XMLElement
                }

        guard !starts.isEmpty || ends.isEmpty else { throw failure("A bookmark end has no matching start.") }

        var seenIDs:
            Set<String> = []

        var result:
            [ImportedBookmark] = []
        var allStartIDs = Set<String>()
        var allEndIDs: [String] = []
        for end in ends {
            guard let id = attribute(end, "id"), !id.isEmpty else { throw failure("A bookmark end is missing its identifier.") }
            allEndIDs.append(id)
        }

        func marker(
            _ prefix: String
        ) -> String {
            prefix
            + UUID()
                .uuidString
                .replacingOccurrences(
                    of:
                        "-",
                    with:
                        ""
                )
        }

        func replace(
            _ node: XMLElement,
            with marker: String
        ) throws {
            guard
                let parent =
                    node.parent
                        as? XMLElement
            else {
                throw failure(
                    "A bookmark marker has no valid parent."
                )
            }

            parent.replaceChild(
                at:
                    node.index,
                with:
                    revisionMarkerRun(
                        marker
                    )
            )
        }

        for start in starts {
            guard
                let id =
                    attribute(
                        start,
                        "id"
                    ),
                !id.isEmpty,
                let name =
                    attribute(
                        start,
                        "name"
                    ),
                !name.isEmpty
            else {
                throw failure(
                    "A bookmark start marker is missing its "
                    + "identifier or name."
                )
            }

            guard
                seenIDs.insert(
                    id
                )
                .inserted
            else {
                throw failure(
                    "A bookmark identifier is duplicated."
                )
            }

            allStartIDs.insert(id)

            let matchingEnds =
                ends.filter {
                    attribute(
                        $0,
                        "id"
                    ) == id
                }

            guard
                matchingEnds.count == 1,
                let end =
                    matchingEnds.first
            else {
                throw failure(
                    "A user bookmark does not have exactly one "
                    + "matching end marker."
                )
            }

            // Generated bookmarks are still required when a hyperlink targets
            // them. Discarding those targets makes a subsequent DOCX export
            // contain dangling anchors (for example Google Docs headings).
            let referenced = referencedNames.contains(name.lowercased())
            if name.hasPrefix("_") && !referenced { continue }

            if let wordBookmarkName =
                attribute(
                    start,
                    "name"
                ),
               !shouldRestoreWordBookmarkAsUserBookmark(
                    wordBookmarkName
               ), !referenced {

                // Word system/generated bookmarks remain valid hyperlink
                // targets, but they are not native BOLD user bookmarks.
                // Their source ID/start/end structure has already been
                // validated before reaching this point.
                continue
            }

            let startMarker =
                marker(
                    "BOLDBOOKMARKSTART"
                )

            let endMarker =
                marker(
                    "BOLDBOOKMARKEND"
                )

            try replace(
                start,
                with:
                    startMarker
            )

            try replace(
                end,
                with:
                    endMarker
            )

            result.append(
                ImportedBookmark(
                    identity: UUID(),
                    startMarker:
                        startMarker,
                    endMarker:
                        endMarker,
                    name:
                        name
                )
            )
        }

        guard Set(allEndIDs).count == allEndIDs.count, Set(allEndIDs) == allStartIDs else {
            throw failure("Bookmark start/end identifiers are duplicated or unmatched.")
        }

        return result
    }

    private static func restoreBookmarks(
        _ bookmarks: [ImportedBookmark],
        additionalMarkers: [String] = [],
        into result:
            NSMutableAttributedString
    ) throws -> [DocumentBookmark] {
        guard
            !bookmarks.isEmpty
        else {
            return []
        }

        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "A Word bookmark could not be restored safely. "
                + detail
            )
        }

        let source =
            result.string
                as NSString

        let bookmarkMarkerNames =
            bookmarks.flatMap {
                [
                    $0.startMarker,
                    $0.endMarker
                ]
            }

        let markerNames =
            bookmarkMarkerNames
            + additionalMarkers

        var markerRanges:
            [String: NSRange] = [:]

        for marker in markerNames {
            let first =
                source.range(of: marker, options: .literal)

            guard
                first.location
                    != NSNotFound
            else {
                throw failure(
                    "A bookmark marker was lost during DOCX import."
                )
            }

            let after =
                NSMaxRange(
                    first
                )

            if after < source.length {
                let second =
                    source.range(
                        of:
                            marker,
                        options:
                            [],
                        range:
                            NSRange(
                                location:
                                    after,
                                length:
                                    source.length
                                    - after
                            )
                    )

                guard
                    second.location
                        == NSNotFound
                else {
                    throw failure(
                        "A bookmark marker was duplicated during "
                        + "DOCX import."
                    )
                }
            }

            markerRanges[
                marker
            ] =
                first
        }

        let allRanges =
            markerRanges.values
                .sorted {
                    $0.location
                        < $1.location
                }

        func adjustedLocation(
            _ location: Int
        ) -> Int {
            let removed =
                allRanges.reduce(
                    0
                ) {
                    partial,
                    range in

                    NSMaxRange(
                        range
                    )
                    <= location
                        ? partial
                            + range.length
                        : partial
                }

            return
                location
                - removed
        }

        var restored:
            [DocumentBookmark] = []

        for imported in bookmarks {
            guard
                let start =
                    markerRanges[
                        imported.startMarker
                    ],
                let end =
                    markerRanges[
                        imported.endMarker
                    ],
                start.location
                    <= end.location
            else {
                throw failure(
                    "A bookmark has invalid or reversed markers."
                )
            }

            restored.append(
                DocumentBookmark(
                    id: imported.identity,
                    name:
                        imported.name,
                    location:
                        adjustedLocation(
                            start.location
                        ),
                    length: adjustedLocation(end.location) - adjustedLocation(start.location)
                )
            )
        }

        let bookmarkRanges =
            bookmarkMarkerNames
                .compactMap {
                    markerRanges[
                        $0
                    ]
                }

        for range
            in bookmarkRanges.sorted(
                by: {
                    $0.location
                        > $1.location
                }
            ) {

            result.deleteCharacters(
                in:
                    range
            )
        }

        for bookmark in restored {
            guard
                bookmark.location >= 0,
                bookmark.location
                    <= result.length
            else {
                throw failure(
                    "A restored bookmark lies outside the "
                    + "imported document."
                )
            }
        }

        let normalized = DocumentBookmarks.normalized(restored.sorted {
            lhs,
            rhs in

            if lhs.location
                != rhs.location {

                return lhs.location
                    < rhs.location
            }

            return lhs.name
                .localizedStandardCompare(
                    rhs.name
                )
                == .orderedAscending
        })
        try DocumentBookmarks.validate(normalized, textLength: result.length)
        return normalized
    }

    private static func prepareComments(
        in xml: XMLDocument,
        parts: [String: Data],
        mainPart: String
    ) throws -> [ImportedComment] {
        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "The DOCX contains Word comments that could not be "
                + "recovered safely. "
                + detail
                + " Import was stopped without changing the "
                + "original file."
            )
        }

        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        let markerNodes =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='commentRangeStart' or local-name()='commentRangeEnd' or local-name()='commentReference']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        guard
            !markerNodes.isEmpty
        else {
            return []
        }

        var orderedIDs:
            [String] = []

        var seenIDs:
            Set<String> = []

        for node in markerNodes {
            guard
                let id =
                    attribute(
                        node,
                        "id"
                    ),
                !id.isEmpty
            else {
                throw failure(
                    "A comment marker has no identifier."
                )
            }

            if seenIDs.insert(id).inserted {
                orderedIDs.append(
                    id
                )
            }
        }

        let directory =
            (mainPart as NSString)
                .deletingLastPathComponent

        let relationshipPath =
            (directory.isEmpty
                ? ""
                : directory + "/")
            + "_rels/"
            + (mainPart as NSString)
                .lastPathComponent
            + ".rels"

        guard
            let relationshipData =
                parts[
                    relationshipPath
                ]
        else {
            throw failure(
                "The comments relationship is missing."
            )
        }

        let relationshipXML =
            try DOCXPackage.xml(
                relationshipData
            )

        let commentRelationships =
            DOCXPackage.descendants(in:relationshipXML,named:"Relationship")
            .compactMap {
                $0 as? XMLElement
            }
            .filter {
                relationship in

                relationship.attribute(
                    forName:
                        "Type"
                )?
                .stringValue?
                .hasSuffix(
                    "/comments"
                ) == true
            }

        guard
            commentRelationships.count == 1,
            let relationship =
                commentRelationships.first,
            relationship.attribute(
                forName:
                    "TargetMode"
            )?
            .stringValue != "External",
            let target =
                relationship.attribute(
                    forName:
                        "Target"
                )?
                .stringValue,
            let commentsPath =
                DOCXPackage.target(
                    target,
                    relativeTo:
                        mainPart
                ),
            let commentsData =
                parts[
                    commentsPath
                ]
        else {
            throw failure(
                "The comments part is missing, external, or ambiguous."
            )
        }

        let commentsXML =
            try DOCXPackage.xml(
                commentsData
            )

        let definitions =
            DOCXPackage.descendants(in:commentsXML,named:"comment")
            .compactMap {
                $0 as? XMLElement
            }

        struct Definition {
            let text: String
            let author: String
            let date: Date
        }

        var definitionsByID:
            [String: Definition] = [:]

        for definition in definitions {
            guard
                let id =
                    attribute(
                        definition,
                        "id"
                    ),
                !id.isEmpty
            else {
                continue
            }

            guard
                definitionsByID[id]
                    == nil
            else {
                throw failure(
                    "A comment identifier is duplicated."
                )
            }

            let paragraphs =
                try definition.nodes(
                    forXPath:
                        ".//*[local-name()='p']"
                )

            let body =
                try paragraphs.map {
                    paragraph -> String in

                    let nodes =
                        try paragraph.nodes(
                            forXPath:
                                ".//*[local-name()='t' or local-name()='tab' or local-name()='br' or local-name()='cr']"
                        )

                    return nodes.map {
                        node -> String in

                        switch node.localName {
                        case "tab":
                            return "\t"

                        case "br", "cr":
                            return "\n"

                        default:
                            return
                                node.stringValue
                                ?? ""
                        }
                    }
                    .joined()
                }
                .joined(
                    separator:
                        "\n"
                )

            definitionsByID[id] =
                Definition(
                    text:
                        body,
                    author:
                        attribute(
                            definition,
                            "author"
                        )
                        ?? "Unknown",
                    date:
                        revisionDate(
                            attribute(
                                definition,
                                "date"
                            )
                        )
                )
        }

        func nodes(
            named name: String,
            id: String
        ) -> [XMLElement] {
            markerNodes.filter {
                $0.localName
                    == name
                    && attribute(
                        $0,
                        "id"
                    ) == id
            }
        }

        func marker(
            _ prefix: String
        ) -> String {
            prefix
            + UUID()
                .uuidString
                .replacingOccurrences(
                    of:
                        "-",
                    with:
                        ""
                )
        }

        func replace(
            _ node: XMLElement,
            with marker: String
        ) throws {
            guard
                let parent =
                    node.parent
                        as? XMLElement
            else {
                throw failure(
                    "A comment marker has no valid parent."
                )
            }

            if node.localName
                == "commentReference",
               parent.localName
                == "r" {

                let text =
                    XMLElement(
                        name:
                            "w:t",
                        stringValue:
                            marker
                    )

                parent.replaceChild(
                    at:
                        node.index,
                    with:
                        text
                )

                return
            }

            parent.replaceChild(
                at:
                    node.index,
                with:
                    revisionMarkerRun(
                        marker
                    )
            )
        }

        var result:
            [ImportedComment] = []

        for id in orderedIDs {
            guard
                let definition =
                    definitionsByID[id]
            else {
                throw failure(
                    "A referenced comment body is missing."
                )
            }

            let starts =
                nodes(
                    named:
                        "commentRangeStart",
                    id:
                        id
                )

            let ends =
                nodes(
                    named:
                        "commentRangeEnd",
                    id:
                        id
                )

            let references =
                nodes(
                    named:
                        "commentReference",
                    id:
                        id
                )

            guard
                starts.count <= 1,
                ends.count <= 1,
                references.count <= 1
            else {
                throw failure(
                    "A comment has duplicate range markers."
                )
            }

            guard
                starts.isEmpty
                    == ends.isEmpty
            else {
                throw failure(
                    "A comment range is incomplete."
                )
            }

            guard
                !starts.isEmpty
                    || !references.isEmpty
            else {
                throw failure(
                    "A comment has no recoverable anchor."
                )
            }

            let startMarker =
                starts.isEmpty
                    ? nil
                    : marker(
                        "BOLDCOMMENTSTART"
                    )

            let endMarker =
                ends.isEmpty
                    ? nil
                    : marker(
                        "BOLDCOMMENTEND"
                    )

            let referenceMarker =
                references.isEmpty
                    ? nil
                    : marker(
                        "BOLDCOMMENTREF"
                    )

            if let startMarker,
               let start =
                    starts.first {

                try replace(
                    start,
                    with:
                        startMarker
                )
            }

            if let endMarker,
               let end =
                    ends.first {

                try replace(
                    end,
                    with:
                        endMarker
                )
            }

            if let referenceMarker,
               let reference =
                    references.first {

                try replace(
                    reference,
                    with:
                        referenceMarker
                )
            }

            result.append(
                ImportedComment(
                    startMarker:
                        startMarker,
                    endMarker:
                        endMarker,
                    referenceMarker:
                        referenceMarker,
                    text:
                        definition.text,
                    author:
                        definition.author,
                    date:
                        definition.date
                )
            )
        }

        return result
    }

    private static func restoreComments(
        _ comments: [ImportedComment],
        additionalMarkers: [String] = [],
        into result:
            NSMutableAttributedString
    ) throws -> [DocumentComment] {
        guard
            !comments.isEmpty
        else {
            return []
        }

        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "A Word comment could not be restored safely. "
                + detail
            )
        }

        let source =
            result.string
                as NSString

        let commentMarkerNames =
            comments.flatMap {
                comment -> [String] in

                [
                    comment.startMarker,
                    comment.endMarker,
                    comment.referenceMarker
                ]
                .compactMap {
                    $0
                }
            }

        let markerNames =
            commentMarkerNames
            + additionalMarkers

        var markerRanges:
            [String: NSRange] = [:]

        for marker in markerNames {
            let first =
                source.range(of: marker, options: .literal)

            guard
                first.location
                    != NSNotFound
            else {
                throw failure(
                    "A comment boundary marker was lost during DOCX import."
                )
            }

            let after =
                NSMaxRange(
                    first
                )

            if after < source.length {
                let second =
                    source.range(
                        of:
                            marker,
                        options:
                            [],
                        range:
                            NSRange(
                                location:
                                    after,
                                length:
                                    source.length
                                    - after
                            )
                    )

                guard
                    second.location
                        == NSNotFound
                else {
                    throw failure(
                        "A comment boundary marker was duplicated during DOCX import."
                    )
                }
            }

            markerRanges[
                marker
            ] =
                first
        }

        let allRanges =
            markerRanges.values
                .sorted {
                    lhs,
                    rhs in

                    lhs.location
                        < rhs.location
                }

        func adjustedLocation(
            _ location: Int
        ) -> Int {
            let removed =
                allRanges.reduce(
                    0
                ) {
                    partial,
                    range in

                    NSMaxRange(
                        range
                    )
                    <= location
                        ? partial
                            + range.length
                        : partial
                }

            return
                location
                - removed
        }

        var restored:
            [DocumentComment] = []

        for imported in comments {
            let location:
                Int

            let length:
                Int

            if let startMarker =
                imported.startMarker,
               let endMarker =
                imported.endMarker {

                guard
                    let start =
                        markerRanges[
                            startMarker
                        ],
                    let end =
                        markerRanges[
                            endMarker
                        ],
                    start.location
                        <= end.location
                else {
                    throw failure(
                        "A ranged comment has invalid boundaries."
                    )
                }

                let adjustedStart =
                    adjustedLocation(
                        start.location
                    )

                let adjustedEnd =
                    adjustedLocation(
                        end.location
                    )

                guard
                    adjustedEnd
                        >= adjustedStart
                else {
                    throw failure(
                        "A ranged comment has reversed boundaries."
                    )
                }

                location =
                    adjustedStart

                length =
                    adjustedEnd
                    - adjustedStart

            } else if let referenceMarker =
                imported.referenceMarker,
                      let reference =
                        markerRanges[
                            referenceMarker
                        ] {

                location =
                    adjustedLocation(
                        reference.location
                    )

                length =
                    0

            } else {
                throw failure(
                    "A comment has no usable anchor."
                )
            }

            var comment =
                DocumentComment(
                    text:
                        imported.text,
                    location:
                        location,
                    length:
                        length
                )

            comment.author =
                imported.author

            comment.createdAt =
                imported.date

            restored.append(
                comment
            )
        }

        let commentRanges =
            commentMarkerNames
                .compactMap {
                    markerRanges[
                        $0
                    ]
                }

        for range
            in commentRanges.sorted(
                by: {
                    $0.location
                        > $1.location
                }
            ) {

            result.deleteCharacters(
                in:
                    range
            )
        }

        for comment in restored {
            guard
                comment.location >= 0,
                comment.length >= 0,
                comment.location
                    <= result.length,
                comment.length
                    <= result.length
                        - comment.location
            else {
                throw failure(
                    "A restored comment lies outside the imported document."
                )
            }
        }

        return restored.sorted {
            lhs,
            rhs in

            if lhs.location
                != rhs.location {

                return lhs.location
                    < rhs.location
            }

            return lhs.length
                < rhs.length
        }
    }

    /// AppKit can discard a whitespace-only Word run when it
    /// sits between temporary revision-boundary marker runs.
    /// Protect those characters until the native import is complete.
    private static func prepareTrackedWhitespace(
        in xml: XMLDocument
    ) throws -> [ImportedTrackedWhitespace] {
        guard let root = xml.rootElement() else {
            return []
        }

        var result: [ImportedTrackedWhitespace] = []

        func visit(_ node: XMLNode) {
            if let element = node as? XMLElement,
               element.localName == "t" {

                // Reading the text-node children directly is deliberate.
                // FoundationXML's XPath/stringValue handling can discard
                // whitespace-only w:t content even when xml:space="preserve".
                let childText =
                    (element.children ?? [])
                        .compactMap { $0.stringValue }
                        .joined()

                let value =
                    childText.isEmpty
                        ? (element.stringValue ?? "")
                        : childText

                if !value.isEmpty
                    && value.unicodeScalars.allSatisfy({
                        CharacterSet.whitespacesAndNewlines
                            .contains($0)
                    }) {

                    let marker =
                        "BOLDTRACKSPACE"
                        + UUID().uuidString
                            .replacingOccurrences(
                                of: "-",
                                with: ""
                            )

                    element.stringValue = marker

                    result.append(
                        ImportedTrackedWhitespace(
                            marker: marker,
                            value: value
                        )
                    )
                }
            }

            for child in node.children ?? [] {
                visit(child)
            }
        }

        visit(root)
        return result
    }

    private static func restoreTrackedWhitespace(
        _ replacements: [ImportedTrackedWhitespace],
        into result: NSMutableAttributedString
    ) {
        for replacement in replacements {
            let range =
                (result.string as NSString)
                    .range(of: replacement.marker, options: .literal)

            guard range.location != NSNotFound else {
                continue
            }

            let attributes =
                range.location < result.length
                    ? result.attributes(
                        at: range.location,
                        effectiveRange: nil
                    )
                    : [:]

            result.replaceCharacters(
                in: range,
                with: NSAttributedString(
                    string: replacement.value,
                    attributes: attributes
                )
            )
        }
    }

    /// Prepare simple Word-native paragraph-format revisions.
    ///
    /// Word stores CURRENT paragraph properties directly in w:pPr
    /// and PREVIOUS paragraph properties inside:
    ///
    ///   w:pPrChange / w:pPr
    ///
    /// Unlike a run-format change, paragraph formatting cannot be
    /// represented by duplicating runs inside one Word paragraph:
    /// paragraph properties belong to the paragraph container.
    ///
    /// Therefore the import XML temporarily becomes:
    ///
    ///   previous paragraph
    ///   proposed paragraph
    ///
    /// Each copy receives a unique marker. AppKit imports both
    /// paragraph styles normally. After native import, BOLD removes
    /// those markers and turns the two parsed paragraphs into its
    /// ordinary linked deletion/insertion formatting pair.
    ///
    /// Initial scope deliberately excludes:
    /// - numbered/bulleted paragraphs (w:numPr)
    /// - text revisions nested in the paragraph
    /// - rPrChange in the same paragraph
    /// - drawings / footnotes
    ///
    /// Those combinations should not be guessed at or silently
    /// rewritten into structurally different Word content.
    private struct ImportedWordField {
        let startMarker: String
        let endMarker: String
        let field: WordField
    }

    private static func prepareWordFields(
        in xml: XMLDocument
    ) throws -> [ImportedWordField] {
        func failure(
            _ detail: String
        ) -> WriterError {
            .message(
                "A Word field could not be preserved safely: "
                + detail
                + " Import was stopped without changing the original file."
            )
        }

        func attribute(
            _ element: XMLElement,
            _ name: String
        ) -> String? {
            element.attributes?
                .first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?
                .stringValue
        }

        func marker(
            _ value: String
        ) -> XMLElement {
            revisionMarkerRun(
                value
            )
        }

        func markerValue(
            _ prefix: String
        ) -> String {
            prefix
                + UUID()
                    .uuidString
                    .replacingOccurrences(
                        of:
                            "-",
                        with:
                            ""
                    )
        }

        var result:
            [ImportedWordField] = []

        // ----------------------------------------------------
        // SIMPLE FIELDS
        // ----------------------------------------------------

        let simpleFields =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='body']//*[local-name()='fldSimple']"
            )
            .compactMap {
                $0 as? XMLElement
            }

        // Nested simple fields require a field tree rather than a
        // flat attributed-string range. Refuse rather than silently
        // changing their structure.
        for field in simpleFields {
            var ancestor =
                field.parent

            var nested =
                false

            while let current =
                ancestor {

                if current.localName
                    == "fldSimple" {

                    nested = true
                    break
                }

                ancestor =
                    current.parent
            }

            if nested {
                throw failure(
                    "nested w:fldSimple fields are not representable yet."
                )
            }
        }

        // Work from the deepest/rightmost nodes backward so sibling
        // indexes remain stable while wrappers are removed.
        for field in simpleFields.reversed() {
            guard
                let parent =
                    field.parent
                        as? XMLElement
            else {
                throw failure(
                    "a simple field has no XML parent."
                )
            }

            let instruction =
                attribute(
                    field,
                    "instr"
                )
                ?? ""

            let start =
                markerValue(
                    "BOLDFIELDSTART"
                )

            let end =
                markerValue(
                    "BOLDFIELDEND"
                )

            let children =
                (field.children ?? [])
                    .map {
                        $0.copy()
                            as! XMLNode
                    }

            guard
                !children.isEmpty
            else {
                throw failure(
                    "an empty simple field has no visible result text."
                )
            }

            let index =
                field.index

            parent.removeChild(
                at:
                    index
            )

            parent.insertChild(
                marker(
                    end
                ),
                at:
                    index
            )

            for child
                in children.reversed() {

                parent.insertChild(
                    child,
                    at:
                        index
                )
            }

            parent.insertChild(
                marker(
                    start
                ),
                at:
                    index
            )

            result.append(
                ImportedWordField(
                    startMarker:
                        start,
                    endMarker:
                        end,
                    field:
                        WordField(
                            kind:
                                .simple,
                            instruction:
                                instruction,
                            dirtyValue:
                                attribute(
                                    field,
                                    "dirty"
                                ),
                            lockedValue:
                                attribute(
                                    field,
                                    "fldLock"
                                )
                        )
                )
            )
        }

        // ----------------------------------------------------
        // COMPLEX FIELDS
        // ----------------------------------------------------

        // Complex fields (notably a TOC) can span multiple paragraphs.
        // Walk field tokens in document order rather than resetting state at
        // every paragraph. Leave result runs and paragraph structure intact.
        let tokens = try xml.nodes(forXPath:
            "//*[local-name()='body']//*[local-name()='fldChar' or local-name()='instrText']"
        ).compactMap { $0 as? XMLElement }
        var active = false
        var separated = false
        var instruction = ""
        var dirtyValue: String?
        var lockedValue: String?
        var startMarker = ""

        func replaceWithMarker(_ token: XMLElement, _ value: String) throws {
            guard let parent = token.parent as? XMLElement else {
                throw failure("a field token has no parent run.")
            }
            let index = token.index
            let text = XMLElement(name: "w:t", stringValue: value)
            token.detach()
            parent.insertChild(text, at: index)
        }

        for token in tokens {
            if token.localName == "instrText" {
                guard active, !separated else {
                    throw failure("field instructions appear outside a field instruction region.")
                }
                instruction += token.stringValue ?? ""
                token.detach()
                continue
            }
            switch attribute(token, "fldCharType")?.lowercased() {
            case "begin":
                guard !active else {
                    throw failure("nested complex fields are not representable yet.")
                }
                active = true
                separated = false
                instruction = ""
                dirtyValue = attribute(token, "dirty")
                lockedValue = attribute(token, "fldLock")
                token.detach()
            case "separate":
                guard active, !separated else {
                    throw failure("a complex field has an invalid separator.")
                }
                separated = true
                startMarker = markerValue("BOLDFIELDSTART")
                try replaceWithMarker(token, startMarker)
            case "end":
                guard active, separated else {
                    throw failure("a complex field is missing begin/separate/end structure.")
                }
                let endMarker = markerValue("BOLDFIELDEND")
                try replaceWithMarker(token, endMarker)
                result.append(ImportedWordField(
                    startMarker: startMarker, endMarker: endMarker,
                    field: WordField(kind: .complex, instruction: instruction,
                                     dirtyValue: dirtyValue, lockedValue: lockedValue)
                ))
                active = false
                separated = false
            default:
                throw failure("a complex field uses an unknown fldCharType.")
            }
        }
        guard !active else {
            throw failure("a complex field is not balanced.")
        }

        return result
    }

    private static func restoreWordFields(
        _ fields: [ImportedWordField],
        into result:
            NSMutableAttributedString
    ) throws {
        guard
            !fields.isEmpty
        else {
            return
        }

        for imported
            in fields {

            let source =
                result.string
                    as NSString

            let startRange =
                source.range(of: imported.startMarker, options: .literal)

            let endRange =
                source.range(of: imported.endMarker, options: .literal)

            guard
                startRange.location
                    != NSNotFound,
                endRange.location
                    != NSNotFound,
                endRange.location
                    >= NSMaxRange(
                        startRange
                    )
            else {
                throw WriterError.message(
                    "A Word field marker was lost during DOCX import."
                )
            }

            let resultLength =
                endRange.location
                - NSMaxRange(
                    startRange
                )

            guard
                resultLength > 0
            else {
                throw WriterError.message(
                    "A Word field has no editable visible result text."
                )
            }

            // Remove the trailing marker first so the leading marker's
            // location remains stable.
            result.deleteCharacters(
                in:
                    endRange
            )

            result.deleteCharacters(
                in:
                    startRange
            )

            let fieldRange =
                NSRange(
                    location:
                        startRange.location,
                    length:
                        resultLength
                )

            guard
                NSMaxRange(
                    fieldRange
                )
                    <= result.length
            else {
                throw WriterError.message(
                    "A Word field result range became invalid during import."
                )
            }

            result.addAttribute(
                .boldWriterField,
                value:
                    imported.field.copy(),
                range:
                    fieldRange
            )
        }
    }

    private static func prepareParagraphPropertyChanges(
        in xml: XMLDocument
    ) throws -> [ImportedParagraphPropertyChange] {

        let nodes =
            DOCXPackage.descendants(in:xml,named:"pPrChange")

        let changes =
            nodes.compactMap {
                $0 as? XMLElement
            }

        var result:
            [ImportedParagraphPropertyChange] = []

        var importedRevisionIDs:
            [String: UUID] = [:]

        for change in changes {
            guard
                let currentProperties =
                    change.parent
                        as? XMLElement,
                currentProperties.localName
                    == "pPr",
                let paragraph =
                    currentProperties.parent
                        as? XMLElement,
                paragraph.localName
                    == "p",
                let parent =
                    paragraph.parent
                        as? XMLElement,
                parent.localName
                    == "body"
            else {
                continue
            }

            // Do not combine paragraph-property normalization
            // with text/run revisions or structured inline content
            // in this first safe interoperability pass.
            let conflicting =
                try paragraph.nodes(
                    forXPath:
                        ".//*[local-name()='ins' or local-name()='del' or local-name()='rPrChange' or local-name()='drawing' or local-name()='pict' or local-name()='AlternateContent' or local-name()='footnoteReference' or local-name()='endnoteReference' or local-name()='commentRangeStart' or local-name()='commentRangeEnd' or local-name()='commentReference' or local-name()='bookmarkStart' or local-name()='bookmarkEnd' or local-name()='hyperlink']"
                )

            guard conflicting.isEmpty else {
                continue
            }

            var previousProperties:
                XMLElement?

            for child in change.children ?? [] {
                guard
                    let element =
                        child as? XMLElement
                else {
                    continue
                }

                if element.localName
                    == "pPr" {
                    previousProperties =
                        element

                    break
                }
            }

            guard
                let previousProperties
            else {
                continue
            }

            // List numbering is restored through a separate DOCX
            // numbering.xml pathway. Duplicating numPr here could
            // create false list instances, so defer it.
            let currentLists =
                try currentProperties.nodes(
                    forXPath:
                        "./*[local-name()='numPr']"
                )

            let previousLists =
                try previousProperties.nodes(
                    forXPath:
                        "./*[local-name()='numPr']"
                )

            guard
                currentLists.isEmpty,
                previousLists.isEmpty
            else {
                continue
            }

            func revisionAttribute(
                _ name: String
            ) -> String? {
                for attribute
                    in change.attributes ?? [] {

                    if attribute.localName
                        == name
                        || attribute.name
                            == name
                        || attribute.name
                            == "w:" + name {

                        return
                            attribute.stringValue
                    }
                }

                return nil
            }

            let rawID =
                revisionAttribute(
                    "id"
                )
                ?? UUID()
                    .uuidString

            let importedID:
                UUID

            if let existing =
                importedRevisionIDs[
                    rawID
                ] {

                importedID =
                    existing
            } else {
                let generated =
                    UUID()

                importedRevisionIDs[
                    rawID
                ] =
                    generated

                importedID =
                    generated
            }

            let author =
                revisionAttribute(
                    "author"
                )
                ?? "Unknown"

            let date =
                revisionDate(
                    revisionAttribute(
                        "date"
                    )
                )

            guard
                let previousParagraph =
                    paragraph.copy()
                        as? XMLElement,
                let proposedParagraph =
                    paragraph.copy()
                        as? XMLElement
            else {
                continue
            }

            // ------------------------------------------------
            // Previous paragraph:
            // replace current w:pPr with Word's saved old w:pPr.
            // ------------------------------------------------

            var previousCopyProperties:
                XMLElement?

            for child
                in previousParagraph.children ?? [] {

                guard
                    let element =
                        child as? XMLElement
                else {
                    continue
                }

                if element.localName
                    == "pPr" {
                    previousCopyProperties =
                        element

                    break
                }
            }

            guard
                let previousCopyProperties,
                let oldProperties =
                    previousProperties.copy()
                        as? XMLElement
            else {
                continue
            }

            previousParagraph.replaceChild(
                at:
                    previousCopyProperties.index,
                with:
                    oldProperties
            )

            // ------------------------------------------------
            // Proposed paragraph:
            // keep current formatting but strip pPrChange itself.
            // ------------------------------------------------

            var proposedProperties:
                XMLElement?

            for child
                in proposedParagraph.children ?? [] {

                guard
                    let element =
                        child as? XMLElement
                else {
                    continue
                }

                if element.localName
                    == "pPr" {
                    proposedProperties =
                        element

                    break
                }
            }

            guard
                let proposedProperties
            else {
                continue
            }

            var changeIndexes:
                [Int] = []

            for (
                index,
                child
            ) in
                (proposedProperties.children
                    ?? [])
                .enumerated() {

                if child.localName
                    == "pPrChange" {

                    changeIndexes.append(
                        index
                    )
                }
            }

            for index
                in changeIndexes.sorted(
                    by: >
                ) {

                proposedProperties
                    .removeChild(
                        at:
                            index
                    )
            }

            let token =
                UUID()
                    .uuidString
                    .replacingOccurrences(
                        of: "-",
                        with: ""
                    )

            let previousMarker =
                "BOLDPPRPREV"
                + token

            let proposedMarker =
                "BOLDPPRNEXT"
                + token

            func insertMarker(
                _ marker: String,
                into paragraph:
                    XMLElement
            ) {
                let markerRun =
                    revisionMarkerRun(
                        marker
                    )

                var insertionIndex =
                    0

                for child
                    in paragraph.children
                        ?? [] {

                    if child.localName
                        == "pPr" {

                        insertionIndex =
                            child.index + 1

                        break
                    }
                }

                paragraph.insertChild(
                    markerRun,
                    at:
                        insertionIndex
                )
            }

            insertMarker(
                previousMarker,
                into:
                    previousParagraph
            )

            insertMarker(
                proposedMarker,
                into:
                    proposedParagraph
            )

            let originalIndex =
                paragraph.index

            parent.removeChild(
                at:
                    originalIndex
            )

            parent.insertChild(
                previousParagraph,
                at:
                    originalIndex
            )

            parent.insertChild(
                proposedParagraph,
                at:
                    originalIndex + 1
            )

            result.append(
                ImportedParagraphPropertyChange(
                    previousMarker:
                        previousMarker,
                    proposedMarker:
                        proposedMarker,
                    id:
                        importedID,
                    author:
                        author,
                    date:
                        date
                )
            )
        }

        return result
    }

    /// Convert the two AppKit-parsed paragraphs created above
    /// into BOLD's normal adjacent formatting revision pair.
    private static func restoreParagraphPropertyChanges(
        _ changes: [ImportedParagraphPropertyChange],
        into result:
            NSMutableAttributedString
    ) throws {

        for change in changes {
            let source =
                result.string as NSString

            let previousMarkerRange =
                source.range(
                    of:
                        change.previousMarker
                )

            guard
                previousMarkerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A DOCX paragraph-format revision marker could not be recovered."
                )
            }

            let afterPrevious =
                NSMaxRange(
                    previousMarkerRange
                )

            let proposedMarkerRange =
                source.range(
                    of:
                        change.proposedMarker,
                    options:
                        [],
                    range:
                        NSRange(
                            location:
                                afterPrevious,
                            length:
                                source.length
                                - afterPrevious
                        )
                )

            guard
                proposedMarkerRange.location
                    != NSNotFound
            else {
                throw WriterError.message(
                    "A DOCX paragraph-format proposed marker could not be recovered."
                )
            }

            let previousParagraphRange =
                source.paragraphRange(
                    for:
                        previousMarkerRange
                )

            let proposedParagraphRange =
                source.paragraphRange(
                    for:
                        proposedMarkerRange
                )

            guard
                previousParagraphRange.location
                    < proposedParagraphRange.location,
                NSMaxRange(
                    previousParagraphRange
                )
                    == proposedParagraphRange.location
            else {
                throw WriterError.message(
                    "A DOCX paragraph-format revision boundary is invalid."
                )
            }

            let previous =
                NSMutableAttributedString(
                    attributedString:
                        result.attributedSubstring(
                            from:
                                previousParagraphRange
                        )
                )

            let proposed =
                NSMutableAttributedString(
                    attributedString:
                        result.attributedSubstring(
                            from:
                                proposedParagraphRange
                        )
                )

            func removeMarker(
                _ marker: String,
                from value:
                    NSMutableAttributedString
            ) throws {
                let range =
                    (
                        value.string
                            as NSString
                    )
                    .range(of: marker, options: .literal)

                guard
                    range.location
                        != NSNotFound
                else {
                    throw WriterError.message(
                        "A DOCX paragraph-format marker was lost during native import."
                    )
                }

                value.deleteCharacters(
                    in:
                        range
                )
            }

            try removeMarker(
                change.previousMarker,
                from:
                    previous
            )

            try removeMarker(
                change.proposedMarker,
                from:
                    proposed
            )

            // Word's required synthetic final paragraph break is
            // removed before this method runs. If the changed
            // paragraph was the document's final paragraph, only
            // the previous temporary copy may still carry "\n".
            // Normalize that one-character structural mismatch so
            // the two formatting halves remain semantically equal.
            if previous.string
                != proposed.string {

                if previous.string
                    == proposed.string
                        + "\n",
                   previous.length > 0 {

                    previous.deleteCharacters(
                        in:
                            NSRange(
                                location:
                                    previous.length - 1,
                                length:
                                    1
                            )
                    )
                } else if proposed.string
                    == previous.string
                        + "\n",
                          proposed.length > 0 {

                    proposed.deleteCharacters(
                        in:
                            NSRange(
                                location:
                                    proposed.length - 1,
                                length:
                                    1
                            )
                    )
                }
            }

            guard
                previous.string
                    == proposed.string,
                previous.length > 0,
                proposed.length
                    == previous.length
            else {
                throw WriterError.message(
                    "A DOCX paragraph-format revision could not be normalized safely."
                )
            }

            previous.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            change.id,
                        kind:
                            .deletion,
                        author:
                            change.author,
                        date:
                            change.date
                    ),
                range:
                    NSRange(
                        location: 0,
                        length:
                            previous.length
                    )
            )

            proposed.addAttribute(
                .boldWriterTrackChange,
                value:
                    TrackChanges.marker(
                        id:
                            change.id,
                        kind:
                            .insertion,
                        author:
                            change.author,
                        date:
                            change.date
                    ),
                range:
                    NSRange(
                        location: 0,
                        length:
                            proposed.length
                    )
            )

            let pair =
                NSMutableAttributedString()

            pair.append(
                previous
            )

            pair.append(
                proposed
            )

            let combinedRange =
                NSRange(
                    location:
                        previousParagraphRange
                            .location,
                    length:
                        NSMaxRange(
                            proposedParagraphRange
                        )
                        - previousParagraphRange
                            .location
                )

            result.replaceCharacters(
                in:
                    combinedRange,
                with:
                    pair
            )
        }
    }

    /// Convert Word-native run-formatting revisions into the
    /// paired deletion/insertion representation BOLD already uses
    /// for formatting review.
    ///
    /// Word stores the CURRENT formatting directly in w:rPr and
    /// nests the PREVIOUS formatting inside w:rPrChange/w:rPr.
    /// No text is inserted or deleted in Word's representation.
    ///
    /// BOLD represents the same semantic revision by duplicating
    /// the text temporarily:
    ///
    ///   previous formatting -> deletion
    ///   current formatting  -> insertion
    ///
    /// Both temporary wrappers keep Word's revision id, author,
    /// and date. prepareTrackedChanges() immediately consumes these
    /// wrappers and restores normal BOLD revision attributes.
    private static func prepareRunPropertyChanges(
        in xml: XMLDocument
    ) throws {
        let nodes =
            DOCXPackage.descendants(in:xml,named:"rPrChange")

        let changes =
            nodes.compactMap {
                node in

                node as? XMLElement
            }

        for change in changes {
            // Do not synthesize a second revision when this
            // formatting metadata already lives inside a normal
            // Word text insertion/deletion.
            var ancestor =
                change.parent

            var insideTextRevision =
                false

            while let current =
                ancestor {

                if current.localName
                    == "ins"
                    || current.localName
                        == "del" {

                    insideTextRevision =
                        true

                    break
                }

                ancestor =
                    current.parent
            }

            if insideTextRevision {
                continue
            }

            guard
                let currentProperties =
                    change.parent
                        as? XMLElement
            else {
                continue
            }

            guard
                currentProperties.localName
                    == "rPr"
            else {
                continue
            }

            guard
                let run =
                    currentProperties.parent
                        as? XMLElement
            else {
                continue
            }

            guard
                run.localName
                    == "r"
            else {
                continue
            }

            let commentReferences =
                try run.nodes(
                    forXPath:
                        ".//*[local-name()='commentReference']"
                )

            guard
                commentReferences.isEmpty
            else {
                continue
            }

            guard
                let parent =
                    run.parent
                        as? XMLElement
            else {
                continue
            }

            var previousProperties:
                XMLElement?

            if let children =
                change.children {

                for child in children {
                    guard
                        let element =
                            child as? XMLElement
                    else {
                        continue
                    }

                    if element.localName
                        == "rPr" {

                        previousProperties =
                            element

                        break
                    }
                }
            }

            guard
                let previousProperties
            else {
                continue
            }

            func revisionAttribute(
                _ name: String
            ) -> String? {
                guard
                    let attributes =
                        change.attributes
                else {
                    return nil
                }

                for attribute
                    in attributes {

                    if attribute.localName
                        == name
                        || attribute.name
                            == name
                        || attribute.name
                            == "w:" + name {

                        return
                            attribute.stringValue
                    }
                }

                return nil
            }

            let rawID =
                revisionAttribute(
                    "id"
                )
                ?? UUID()
                    .uuidString

            let author =
                revisionAttribute(
                    "author"
                )
                ?? "Unknown"

            let date =
                revisionAttribute(
                    "date"
                )

            guard
                let previousRun =
                    run.copy()
                        as? XMLElement
            else {
                continue
            }

            guard
                let proposedRun =
                    run.copy()
                        as? XMLElement
            else {
                continue
            }

            // ------------------------------------------------
            // PREVIOUS copy
            //
            // Replace the copied current rPr wholesale with the
            // previous rPr stored inside Word's rPrChange.
            // ------------------------------------------------

            var previousRunProperties:
                XMLElement?

            if let children =
                previousRun.children {

                for child in children {
                    guard
                        let element =
                            child as? XMLElement
                    else {
                        continue
                    }

                    if element.localName
                        == "rPr" {

                        previousRunProperties =
                            element

                        break
                    }
                }
            }

            guard
                let previousRunProperties
            else {
                continue
            }

            guard
                let oldProperties =
                    previousProperties
                        .copy()
                        as? XMLElement
            else {
                continue
            }

            previousRun.replaceChild(
                at:
                    previousRunProperties
                        .index,
                with:
                    oldProperties
            )

            // ------------------------------------------------
            // PROPOSED copy
            //
            // Keep Word's current properties, but remove the
            // historical rPrChange child itself.
            // ------------------------------------------------

            var proposedProperties:
                XMLElement?

            if let children =
                proposedRun.children {

                for child in children {
                    guard
                        let element =
                            child as? XMLElement
                    else {
                        continue
                    }

                    if element.localName
                        == "rPr" {

                        proposedProperties =
                            element

                        break
                    }
                }
            }

            guard
                let proposedProperties
            else {
                continue
            }

            var changeIndexes:
                [Int] = []

            if let children =
                proposedProperties.children {

                for (
                    index,
                    child
                ) in children.enumerated() {

                    if child.localName
                        == "rPrChange" {

                        changeIndexes.append(
                            index
                        )
                    }
                }
            }

            for index
                in changeIndexes
                    .sorted(
                        by: >
                    ) {

                proposedProperties
                    .removeChild(
                        at:
                            index
                    )
            }

            func makeWrapper(
                _ localName: String,
                run:
                    XMLElement
            ) -> XMLElement {

                let wrapper =
                    XMLElement(
                        name:
                            "w:"
                            + localName
                    )

                wrapper.addAttribute(
                    XMLNode.attribute(
                        withName:
                            "w:id",
                        stringValue:
                            rawID
                    ) as! XMLNode
                )

                wrapper.addAttribute(
                    XMLNode.attribute(
                        withName:
                            "w:author",
                        stringValue:
                            author
                    ) as! XMLNode
                )

                if let date {
                    wrapper.addAttribute(
                        XMLNode.attribute(
                            withName:
                                "w:date",
                            stringValue:
                                date
                        ) as! XMLNode
                    )
                }

                wrapper.addChild(
                    run
                )

                return wrapper
            }

            let deletion =
                makeWrapper(
                    "del",
                    run:
                        previousRun
                )

            let insertion =
                makeWrapper(
                    "ins",
                    run:
                        proposedRun
                )

            let insertionIndex =
                run.index

            parent.removeChild(
                at:
                    insertionIndex
            )

            parent.insertChild(
                deletion,
                at:
                    insertionIndex
            )

            parent.insertChild(
                insertion,
                at:
                    insertionIndex
                    + 1
            )
        }
    }

    /// Temporarily unwrap Word revision markup so AppKit imports
    /// the underlying rich text normally. Unique marker runs preserve
    /// the exact revision boundaries until BOLD restores its attributes.
    private static func prepareTrackedChanges(
        in xml: XMLDocument
    ) throws -> [ImportedTrackedChange] {
        let candidates =
            try xml.nodes(
                forXPath:
                    "//*[local-name()='ins' or local-name()='del']"
            )
            .compactMap { $0 as? XMLElement }

        let revisions = candidates.filter { element in
            var ancestor = element.parent

            while let current = ancestor {
                if current.localName == "ins"
                    || current.localName == "del" {
                    return false
                }

                ancestor = current.parent
            }

            return true
        }

        var result: [ImportedTrackedChange] = []

        var importedRevisionIDs:
            [String: UUID] = [:]

        for revision in revisions {
            guard let parent = revision.parent as? XMLElement else {
                continue
            }

            let kind: TrackChangeRecord.Kind =
                revision.localName == "del"
                    ? .deletion
                    : .insertion

            func attribute(_ name: String) -> String? {
                revision.attributes?.first {
                    $0.localName == name
                        || $0.name == name
                        || $0.name == "w:" + name
                }?.stringValue
            }

            let author =
                attribute("author") ?? "Unknown"

            let date =
                revisionDate(
                    attribute("date")
                )

            let importedID:
                UUID

            if let rawID =
                attribute(
                    "id"
                ) {
                if let existing =
                    importedRevisionIDs[
                        rawID
                    ] {
                    importedID =
                        existing
                } else {
                    let generated =
                        UUID()

                    importedRevisionIDs[
                        rawID
                    ] =
                        generated

                    importedID =
                        generated
                }
            } else {
                importedID =
                    UUID()
            }

            let token =
                UUID().uuidString
                    .replacingOccurrences(
                        of: "-",
                        with: ""
                    )

            let startMarker =
                "BOLDTRACKSTART" + token

            let endMarker =
                "BOLDTRACKEND" + token

            let copiedChildren =
                (revision.children ?? []).map {
                    $0.copy() as! XMLNode
                }

            if kind == .deletion {
                for child in copiedChildren {
                    convertDeletionText(in: child)
                }
            }

            let insertionIndex = revision.index

            parent.removeChild(
                at: insertionIndex
            )

            parent.insertChild(
                revisionMarkerRun(startMarker),
                at: insertionIndex
            )

            var next = insertionIndex + 1

            for child in copiedChildren {
                child.detach()

                parent.insertChild(
                    child,
                    at: next
                )

                next += 1
            }

            parent.insertChild(
                revisionMarkerRun(endMarker),
                at: next
            )

            result.append(
                ImportedTrackedChange(
                    startMarker: startMarker,
                    endMarker: endMarker,
                    id: importedID,
                    kind: kind,
                    author: author,
                    date: date
                )
            )
        }

        return result
    }

    private static func convertDeletionText(
        in node: XMLNode
    ) {
        if let element = node as? XMLElement,
           element.localName == "delText" {
            element.name =
                element.name?.contains(":") == true
                    ? "w:t"
                    : "t"
        }

        for child in node.children ?? [] {
            convertDeletionText(in: child)
        }
    }

    static func revisionMarkerRun(
        _ value: String
    ) -> XMLElement {
        let run = XMLElement(name: "w:r")

        let text =
            XMLElement(
                name: "w:t",
                stringValue: value
            )

        run.addChild(text)
        return run
    }

    private static func revisionDate(
        _ value: String?
    ) -> Date {
        guard let value else {
            return Date(
                timeIntervalSince1970: 0
            )
        }

        let formatter =
            ISO8601DateFormatter()

        if let date =
            formatter.date(from: value) {
            return date
        }

        formatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds
        ]

        return formatter.date(from: value)
            ?? Date(
                timeIntervalSince1970: 0
            )
    }

    private static func restoreTrackedChanges(
        _ changes: [ImportedTrackedChange],
        into result: NSMutableAttributedString
    ) throws {
        for change in changes {
            let source =
                result.string as NSString

            let start =
                source.range(
                    of: change.startMarker
                )

            guard start.location != NSNotFound else {
                throw WriterError.message(
                    "A DOCX tracked-change start marker could not be recovered."
                )
            }

            let afterStart =
                NSMaxRange(start)

            guard afterStart <= source.length else {
                throw WriterError.message(
                    "A DOCX tracked-change boundary is invalid."
                )
            }

            let end =
                source.range(
                    of: change.endMarker,
                    options: [],
                    range: NSRange(
                        location: afterStart,
                        length:
                            source.length
                            - afterStart
                    )
                )

            guard end.location != NSNotFound else {
                throw WriterError.message(
                    "A DOCX tracked-change end marker could not be recovered."
                )
            }

            let contentLength =
                end.location - afterStart

            // Remove the later marker first so positions stay stable.
            result.deleteCharacters(in: end)
            result.deleteCharacters(in: start)

            guard contentLength > 0 else {
                continue
            }

            let range =
                NSRange(
                    location: start.location,
                    length: contentLength
                )

            guard
                range.location <= result.length,
                range.length
                    <= result.length - range.location
            else {
                throw WriterError.message(
                    "A DOCX tracked-change range is invalid."
                )
            }

            result.addAttribute(
                .boldWriterTrackChange,
                value: TrackChanges.marker(
                    id: change.id,
                    kind: change.kind,
                    author: change.author,
                    date: change.date
                ),
                range: range
            )
        }
    }

    /// AppKit exposes Word's required final paragraph terminator
    /// as one real newline. BOLD's internal text model does not include
    /// that structural character, so remove exactly one trailing newline.
    /// If the source intentionally ended with a blank paragraph, another
    /// newline remains and the user's content is preserved.
    private static func removeSyntheticFinalParagraphBreak(
        from result: NSMutableAttributedString
    ) {
        guard result.length > 0 else { return }

        let string = result.string as NSString

        guard string.length > 0 else { return }

        let final =
            string.substring(
                with: NSRange(
                    location: string.length - 1,
                    length: 1
                )
            )

        guard final == "\n" else { return }

        result.deleteCharacters(
            in: NSRange(
                location: result.length - 1,
                length: 1
            )
        )
    }

    private static func nativeText(_ data: Data) throws -> NSAttributedString {
        try NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.officeOpenXML], documentAttributes: nil)
    }

    /// AppKit normally imports Word list formatting for us, but on some
    /// macOS versions it can turn a decimal Word list into a bullet list and
    /// discard its starting number. Word's numbering.xml is authoritative, so
    /// repair only the native NSTextList metadata after AppKit has imported the
    /// document text and character formatting.
    private static func restoreChecklistMetadata(
        parts: [String: Data],
        into result: NSMutableAttributedString
    ) throws {
        guard
            let data =
                parts[
                    "word/boldwriter-checklists.xml"
                ]
        else {
            return
        }

        let xml =
            try DOCXPackage.xml(
                data
            )

        guard
            xml.rootElement()?
                .localName
                == "checklists"
        else {
            return
        }

        let nodes =
            DOCXPackage.descendants(in:xml,named:"item")

        guard !nodes.isEmpty else {
            return
        }

        let source =
            result.string
                as NSString

        var ranges: [NSRange] = []
        var location = 0

        while location < source.length {
            let range =
                source.paragraphRange(
                    for:
                        NSRange(
                            location:
                                location,
                            length:
                                0
                        )
                )

            guard range.length > 0 else {
                break
            }

            ranges.append(
                range
            )

            let next =
                NSMaxRange(
                    range
                )

            guard next > location else {
                break
            }

            location =
                next
        }

        for case let element as XMLElement in nodes {
            guard
                let rawIndex =
                    element.attribute(
                        forName:
                            "paragraph"
                    )?
                    .stringValue,
                let index =
                    Int(
                        rawIndex
                    ),
                ranges.indices
                    .contains(
                        index
                    )
            else {
                continue
            }

            let checked =
                element.attribute(
                    forName:
                        "checked"
                )?
                .stringValue
                == "1"

            let range =
                ranges[
                    index
                ]

            guard
                range.length > 0,
                range.location < result.length
            else {
                continue
            }

            result.addAttribute(
                .boldWriterChecklist,
                value:
                    true,
                range:
                    range
            )

            result.addAttribute(
                .boldWriterChecklistChecked,
                value:
                    checked,
                range:
                    range
            )

            let existing =
                result.attribute(
                    .paragraphStyle,
                    at:
                        range.location,
                    effectiveRange:
                        nil
                ) as? NSParagraphStyle

            let paragraph =
                existing?
                    .mutableCopy()
                    as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            paragraph.textLists =
                [
                    NSTextList(
                        markerFormat:
                            checked
                                ? .check
                                : .box,
                        options:
                            0
                    )
                ]

            paragraph.headIndent =
                max(
                    paragraph.headIndent,
                    36
                )

            paragraph.firstLineHeadIndent =
                min(
                    paragraph.firstLineHeadIndent,
                    18
                )

            result.addAttribute(
                .paragraphStyle,
                value:
                    paragraph,
                range:
                    range
            )
        }
    }

    private static func restoreListMetadata(
        documentXML: XMLDocument,
        parts: [String: Data],
        mainPart: String,
        into result: NSMutableAttributedString
    ) throws {
        let directory = (mainPart as NSString).deletingLastPathComponent
        let relationshipPath =
            (directory.isEmpty ? "" : directory + "/")
            + "_rels/"
            + (mainPart as NSString).lastPathComponent
            + ".rels"

        var numberingPath =
            (directory.isEmpty ? "" : directory + "/")
            + "numbering.xml"

        if let relationshipData = parts[relationshipPath] {
            let relationships = try DOCXPackage.xml(relationshipData)

            if let relationship = try relationships
                .nodes(
                    forXPath:
                        "//*[local-name()='Relationship' and contains(@Type, '/numbering')]"
                )
                .compactMap({ $0 as? XMLElement })
                .first,
               relationship.attribute(forName: "TargetMode")?.stringValue != "External",
               let target = relationship.attribute(forName: "Target")?.stringValue,
               let resolved = DOCXPackage.target(target, relativeTo: mainPart) {
                numberingPath = resolved
            }
        }

        guard let numberingData = parts[numberingPath] else {
            return
        }

        let numberingXML = try DOCXPackage.xml(numberingData)

        func attribute(_ element: XMLElement, _ name: String) -> String? {
            element.attributes?.first {
                $0.localName == name || $0.name == name || $0.name == "w:" + name
            }?.stringValue
        }

        func childValue(
            _ element: XMLElement,
            childName: String,
            attributeName: String = "val"
        ) throws -> String? {
            guard let child = try element
                .nodes(forXPath: "./*[local-name()='\(childName)']")
                .first as? XMLElement else {
                return nil
            }

            return attribute(child, attributeName)
        }

        struct AbstractLevel {
            let format: String
            let start: Int
        }

        struct NumberInstance {
            let abstractID: Int
            let overrides: [Int: Int]
        }

        var abstractLevels: [Int: [Int: AbstractLevel]] = [:]

        for case let abstract as XMLElement in DOCXPackage.descendants(in:numberingXML,named:"abstractNum") {
            guard let rawID = attribute(abstract, "abstractNumId"),
                  let abstractID = Int(rawID) else {
                continue
            }

            var levels: [Int: AbstractLevel] = [:]

            for case let level as XMLElement in try abstract.nodes(
                forXPath: "./*[local-name()='lvl']"
            ) {
                let levelNumber = Int(attribute(level, "ilvl") ?? "0") ?? 0
                let format = try childValue(
                    level,
                    childName: "numFmt"
                ) ?? "bullet"

                let start = Int(
                    try childValue(
                        level,
                        childName: "start"
                    ) ?? "1"
                ) ?? 1

                levels[levelNumber] = AbstractLevel(
                    format: format,
                    start: max(1, start)
                )
            }

            abstractLevels[abstractID] = levels
        }

        var instances: [Int: NumberInstance] = [:]

        for case let number as XMLElement in DOCXPackage.descendants(in:numberingXML,named:"num") {
            guard let rawID = attribute(number, "numId"),
                  let numID = Int(rawID),
                  let rawAbstract = try childValue(
                    number,
                    childName: "abstractNumId"
                  ),
                  let abstractID = Int(rawAbstract) else {
                continue
            }

            var overrides: [Int: Int] = [:]

            for case let levelOverride as XMLElement in try number.nodes(
                forXPath: "./*[local-name()='lvlOverride']"
            ) {
                let level = Int(
                    attribute(levelOverride, "ilvl") ?? "0"
                ) ?? 0

                if let rawStart = try childValue(
                    levelOverride,
                    childName: "startOverride"
                ),
                   let start = Int(rawStart) {
                    overrides[level] = max(1, start)
                }
            }

            instances[numID] = NumberInstance(
                abstractID: abstractID,
                overrides: overrides
            )
        }

        struct ParagraphList {
            let text: String
            let numID: Int
            let level: Int
        }

        var listParagraphs: [ParagraphList] = []

        for case let paragraph as XMLElement in DOCXPackage.bodyParagraphs(in:documentXML) {
            guard let pPr = paragraph.children?.compactMap({ $0 as? XMLElement }).first(where: { $0.localName == "pPr" || $0.name == "w:pPr" || $0.name == "pPr" }),
                  let numPr = pPr.children?.compactMap({ $0 as? XMLElement }).first(where: { $0.localName == "numPr" || $0.name == "w:numPr" || $0.name == "numPr" }),
                  let rawNumID = try childValue(
                    numPr,
                    childName: "numId"
                  ),
                  let numID = Int(rawNumID) else {
                continue
            }

            let level = Int(
                try childValue(
                    numPr,
                    childName: "ilvl"
                ) ?? "0"
            ) ?? 0

            let textNodes = try paragraph.nodes(
                forXPath:
                    "./*[not(local-name()='pPr')]/descendant-or-self::*[local-name()='t' or local-name()='tab' or local-name()='br' or local-name()='cr']"
            )

            var paragraphText = ""

            for node in textNodes {
                switch node.localName {
                case "tab":
                    paragraphText += "\t"
                case "br", "cr":
                    paragraphText += "\n"
                default:
                    paragraphText += (node.stringValue ?? "").replacingOccurrences(
                        of: "BOLDPARATAB[A-F0-9]{32}", with: "", options: .regularExpression
                    )
                }
            }

            guard !paragraphText.isEmpty else {
                continue
            }

            listParagraphs.append(
                ParagraphList(
                    text: paragraphText,
                    numID: numID,
                    level: level
                )
            )
        }

        guard !listParagraphs.isEmpty else {
            return
        }

        let importedString = result.string as NSString
        var searchLocation = 0
        var nativeLists: [String: NSTextList] = [:]

        for item in listParagraphs {
            guard searchLocation <= importedString.length else {
                break
            }

            let searchRange = NSRange(
                location: searchLocation,
                length: importedString.length - searchLocation
            )

            let found = importedString.range(
                of: item.text,
                options: [],
                range: searchRange
            )

            guard found.location != NSNotFound else {
                continue
            }

            searchLocation = NSMaxRange(found)

            guard
                let instance =
                    instances[
                        item.numID
                    ],
                let levelInfo =
                    abstractLevels[
                        instance.abstractID
                    ]?[
                        item.level
                    ]
            else {
                continue
            }

            // BOLD currently models one semantic list level.
            // Do not flatten a Word sublevel into a fake
            // top-level list.
            guard
                item.level == 0
            else {
                continue
            }

            let marker:
                NSTextList.MarkerFormat

            switch levelInfo.format
                .lowercased() {

            case "bullet":
                marker =
                    .disc

            case "decimal":
                marker =
                    .decimal

            default:
                // Keep AppKit's visual/native interpretation
                // for richer Word formats such as lowerLetter,
                // upperRoman, lowerRoman, etc. Do not falsely
                // convert them to decimal BOLD semantics.
                continue
            }

            let key =
                "\(item.numID):0"

            let list:
                NSTextList

            if let existing =
                nativeLists[
                    key
                ] {

                list =
                    existing

            } else {
                let created =
                    NSTextList(
                        markerFormat:
                            marker,
                        options:
                            0
                    )

                created.startingItemNumber =
                    instance.overrides[0]
                    ?? levelInfo.start

                nativeLists[
                    key
                ] =
                    created

                list =
                    created
            }

            let paragraphRange = importedString.paragraphRange(for: found)

            guard paragraphRange.location < result.length else {
                continue
            }

            let existing =
                result.attribute(
                    .paragraphStyle,
                    at: paragraphRange.location,
                    effectiveRange: nil
                ) as? NSParagraphStyle

            let style =
                existing?.mutableCopy() as? NSMutableParagraphStyle
                ?? NSMutableParagraphStyle()

            style.textLists = [list]

            result.addAttribute(
                .paragraphStyle,
                value: style,
                range: paragraphRange
            )
        }
    }

    private static func wordPictureCrop(
        for reference: XMLElement
    ) throws -> WordPictureCrop? {
        var current: XMLNode? = reference
        var blipFill: XMLElement?

        while let node = current {
            if node.localName == "blipFill" {
                blipFill = node as? XMLElement
                break
            }

            current = node.parent
        }

        guard
            let blipFill,
            let sourceRectangle =
                try blipFill.nodes(
                    forXPath:
                        "./*[local-name()='srcRect']"
                )
                .first as? XMLElement
        else {
            return nil
        }

        func edge(
            _ name: String
        ) throws -> Int {
            guard
                let raw =
                    sourceRectangle
                        .attribute(forName: name)?
                        .stringValue
            else {
                return 0
            }

            guard
                let value = Int(raw),
                WordPictureCrop.validEdge(value)
            else {
                throw WriterError.message(
                    "A Word picture contains an invalid source-crop value. "
                    + "Import was stopped so its editable crop would not be silently changed."
                )
            }

            return value
        }

        let crop =
            WordPictureCrop(
                left: try edge("l"),
                top: try edge("t"),
                right: try edge("r"),
                bottom: try edge("b")
            )

        guard crop.hasValidGeometry else {
            throw WriterError.message(
                "A Word picture contains an invalid source-crop rectangle. "
                + "Import was stopped so its editable crop would not be silently changed."
            )
        }

        return crop.isEmpty ? nil : crop
    }

    private static func imageSize(in node: XMLNode) throws -> NSSize? {
        let root = node.copy() as! XMLElement
        let scoped = XMLDocument(rootElement: root)
        if let extent = try scoped.nodes(forXPath: ".//*[local-name()='extent' or local-name()='ext'][@cx and @cy]").first as? XMLElement,
           let width = Double(extent.attribute(forName: "cx")?.stringValue ?? ""),
           let height = Double(extent.attribute(forName: "cy")?.stringValue ?? "") {
            let size = NSSize(width: width / 12_700, height: height / 12_700)
            if DOCXImages.validSize(size) { return size }
        }
        if let shape = try scoped.nodes(forXPath: ".//*[local-name()='shape']").first as? XMLElement,
           let style = shape.attribute(forName: "style")?.stringValue {
            var dimensions: [String: Double] = [:]
            for property in style.split(separator: ";") {
                let pair = property.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                guard pair.count == 2, ["width", "height"].contains(pair[0]) else { continue }
                for (unit, scale) in [("pt", 1.0), ("in", 72.0), ("cm", 72 / 2.54), ("mm", 72 / 25.4), ("px", 0.75)] where pair[1].hasSuffix(unit) {
                    if let value = Double(pair[1].dropLast(unit.count)) { dimensions[pair[0]] = value * scale }
                }
            }
            if let width = dimensions["width"], let height = dimensions["height"] {
                let size = NSSize(width: width, height: height)
                if DOCXImages.validSize(size) { return size }
            }
        }
        return nil
    }
}
