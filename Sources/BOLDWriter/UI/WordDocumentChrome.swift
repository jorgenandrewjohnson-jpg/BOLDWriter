import AppKit
import PDFKit
import SwiftUI

// MARK: - Word-style application shell

enum DocumentEditingMode:
    String,
    CaseIterable,
    Identifiable
{
    case editing = "Editing"
    case suggesting = "Suggesting"
    case viewing = "Viewing"

    var id: String {
        rawValue
    }

    var isEditable: Bool {
        self != .viewing
    }
}

private enum WordRibbonTab:
    String,
    CaseIterable,
    Identifiable
{
    case home = "Home"
    case insert = "Insert"
    case draw = "Draw"
    case design = "Design"
    case layout = "Layout"
    case references = "References"
    case review = "Review"
    case view = "View"

    var id: String {
        rawValue
    }
}

struct WordTitleBar: View {
    @ObservedObject var document: BOLDWriterDocument

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "doc.richtext")
                    .font(.system(size: 15, weight: .semibold))

                Text("BOLD Writer")
                    .font(.system(size: 14, weight: .semibold))
            }

            TextField("Untitled", text: Binding(
                get: { document.metadata.title },
                set: { title in
                    var metadata = document.metadata
                    metadata.title = title
                    document.metadata = metadata
                }
            ))
            .textFieldStyle(.plain)
            .font(.system(size: 14, weight: .medium))
            .frame(maxWidth: 300)
            .accessibilityLabel("Document title")

            Spacer()

            Label("Local document", systemImage: "internaldrive")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            Color(
                nsColor:
                    .windowBackgroundColor
            )
        )
        .overlay(
            alignment:
                .bottom
        ) {
            Divider()
        }
    }
}

struct WordRibbon: View {
    @ObservedObject var editor: EditorController
    @State private var customStyleName = "Custom Style"

    @Binding var showLeftSidebar: Bool
    @Binding var showRightSidebar: Bool
    @Binding var printLayout: Bool

    var editingMode: DocumentEditingMode
    var onSetEditingMode: (DocumentEditingMode) -> Void
    var showNonPrintingCharacters: Bool
    var onToggleNonPrintingCharacters: () -> Void
    var showLineNumbers: Bool
    var onToggleLineNumbers: () -> Void
    var onExport: () -> Void
    var onInsertTOC: () -> Void
    var onInsertTOCMode: (PublishingTOCMode) -> Void
    var onBookCoverCreator: () -> Void
    var onBookHealthCheck: () -> Void
    var onPhysicalBookPreview: () -> Void
    var onShowEquationToolbar: () -> Void
    var onInsertFootnote: () -> Void
    var onEditFootnote: () -> Void
    var onInsertEndnote: () -> Void
    var onEditEndnote: () -> Void
    var onShowCitations: () -> Void
    var onInsertBibliography: () -> Void
    var onNewComment: () -> Void
    var onEditComment: () -> Void
    var onDeleteComment: () -> Void
    var onPreviousComment: () -> Void
    var onNextComment: () -> Void
    var onShowComments: () -> Void
    var onCheckSpelling: () -> Void
    var onShowSpellingPanel: () -> Void
    var onLink: () -> Void
    var onBookmark: () -> Void
    var onCrossReference: () -> Void
    var onUpdateFields: () -> Void
    var onInsertCaption: () -> Void

    @State private var selectedTab:
        WordRibbonTab = .home

    var body: some View {
        VStack(spacing: 0) {
            tabStrip

            Divider()

            ribbonContent
                .frame(height: 104)

            Divider()
        }
        .background(
            Color(
                nsColor:
                    .controlBackgroundColor
            )
        )
    }

    private var tabStrip: some View {
        HStack(spacing: 4) {
            ForEach(
                WordRibbonTab.allCases
            ) {
                tab in

                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .font(
                            .system(
                                size:
                                    12,
                                weight:
                                    selectedTab == tab
                                    ? .semibold
                                    : .regular
                            )
                        )
                        .padding(
                            .horizontal,
                            12
                        )
                        .frame(
                            height:
                                30
                        )
                        .contentShape(
                            Rectangle()
                        )
                        .overlay(
                            alignment:
                                .bottom
                        ) {
                            if selectedTab == tab {
                                Rectangle()
                                    .frame(
                                        height:
                                            2
                                    )
                            }
                        }
                }
                .buttonStyle(.plain)
            }

            Button("Book Cover Creator", action: onBookCoverCreator)
                .font(.system(size: 12, weight: .semibold))
                .help("Edit the full wrap cover")
                .accessibilityIdentifier("ribbon.bookCoverCreator")
            Button("3D Book Preview", action: onPhysicalBookPreview)
                .font(.system(size: 12, weight: .semibold))
                .help("Inspect the physical book and print diagnostics")
                .accessibilityIdentifier("ribbon.physicalBookPreview")

            Spacer()

            Button {
                showLeftSidebar.toggle()
            } label: {
                Image(
                    systemName:
                        "sidebar.left"
                )
            }
            .buttonStyle(.borderless)
            .help(
                showLeftSidebar
                ? "Hide Navigation"
                : "Show Navigation"
            )

            Button {
                showRightSidebar.toggle()
            } label: {
                Image(
                    systemName:
                        "sidebar.right"
                )
            }
            .buttonStyle(.borderless)
            .help(
                showRightSidebar
                ? "Hide Inspector"
                : "Show Inspector"
            )

            Button(
                action:
                    onExport
            ) {
                Image(
                    systemName:
                        "square.and.arrow.up"
                )
            }
            .buttonStyle(.borderless)
            .help("Export")
        }
        .padding(
            .horizontal,
            10
        )
        .frame(height: 31)
    }

    @ViewBuilder
    private var ribbonContent: some View {
        switch selectedTab {
        case .home:
            homeRibbon

        case .insert:
            HStack(alignment: .top, spacing: 0) {
                WordRibbonGroup(title: "Links") {
                    WordRibbonSmallButton(title: "Link", systemImage: "link", action: onLink)
                    WordRibbonSmallButton(title: "Remove", systemImage: "link.badge.plus") { editor.removeHyperlink() }
                    WordRibbonSmallButton(title: "Bookmark", systemImage: "bookmark", action: onBookmark)
                    WordRibbonSmallButton(title: "Cross-ref", systemImage: "arrow.triangle.2.circlepath", action: onCrossReference)
                }
                WordRibbonGroup(title:"Publishing") {
                    WordRibbonSmallButton(title:"Book Cover",systemImage:"book.closed",action:onBookCoverCreator)
                    WordRibbonSmallButton(title:"Book Audit",systemImage:"checkmark.seal",action:onBookHealthCheck)
                }

                WordRibbonGroup(
                    title:
                        "Symbols"
                ) {
                    WordRibbonSmallButton(
                        title:
                            "Equation",
                        systemImage:
                            "function",
                        action:
                            onShowEquationToolbar
                    )
                }

                Spacer(
                    minLength:
                        0
                )
            }

        case .draw:
            placeholderRibbon(groups: [
                ("Drawing Tools", "Pens • Pencil • Highlighter"),
                ("Convert", "Ink tools")
            ])

        case .design:
            placeholderRibbon(groups: [
                ("Document Formatting", "Themes • Colors • Fonts"),
                ("Page Background", "Watermark • Borders")
            ])

        case .layout:
            placeholderRibbon(groups: [
                ("Page Setup", "Margins • Orientation • Size • Columns"),
                ("Paragraph", "Indent • Spacing"),
                ("Arrange", "Position • Wrap")
            ])

        case .references:
            referencesRibbon

        case .review:
            HStack(alignment: .top, spacing: 0) {
                WordRibbonGroup(title: "Comments") {
                    WordRibbonSmallButton(title: "New", systemImage: "plus.bubble", action: onNewComment)
                    WordRibbonSmallButton(title: "Edit", systemImage: "pencil", action: onEditComment)
                    WordRibbonSmallButton(title: "Delete", systemImage: "trash", action: onDeleteComment)
                    WordRibbonSmallButton(title: "Previous", systemImage: "chevron.up.bubble", action: onPreviousComment)
                    WordRibbonSmallButton(title: "Next", systemImage: "chevron.down.bubble", action: onNextComment)
                    WordRibbonSmallButton(title: "Show", systemImage: "sidebar.left", action: onShowComments)
                }
                WordRibbonGroup(title: "Proofing") {
                    WordRibbonSmallButton(
                        title: "Check Spelling",
                        systemImage: "checkmark.circle",
                        action: onCheckSpelling
                    )

                    WordRibbonSmallButton(
                        title: "Spelling & Grammar",
                        systemImage: "text.magnifyingglass",
                        action: onShowSpellingPanel
                    )
                }
                WordRibbonGroup(title: "Tracking") {
                    WordRibbonSmallButton(
                        title:
                            editingMode == .suggesting
                            ? "Track Changes On"
                            : "Track Changes",
                        systemImage:
                            editingMode == .suggesting
                            ? "checkmark.circle.fill"
                            : "circle"
                    ) {
                        onSetEditingMode(
                            editingMode == .suggesting
                            ? .editing
                            : .suggesting
                        )
                    }

                    Menu {
                        Button("Editing") {
                            onSetEditingMode(
                                .editing
                            )
                        }

                        Button("Suggesting") {
                            onSetEditingMode(
                                .suggesting
                            )
                        }

                        Button("Viewing") {
                            onSetEditingMode(
                                .viewing
                            )
                        }
                    } label: {
                        Label(
                            editingMode.rawValue,
                            systemImage:
                                "pencil.line"
                        )
                    }
                    .font(
                        .system(
                            size: 10
                        )
                    )
                    .frame(
                        maxWidth:
                            .infinity
                    )
                }

                WordRibbonGroup(title: "Changes") {
                    WordRibbonSmallButton(
                        title: "Previous",
                        systemImage: "chevron.up"
                    ) {
                        _ =
                            editor
                                .previousTrackedChange()
                    }

                    WordRibbonSmallButton(
                        title: "Next",
                        systemImage: "chevron.down"
                    ) {
                        _ =
                            editor
                                .nextTrackedChange()
                    }

                    WordRibbonSmallButton(
                        title: "Accept",
                        systemImage: "checkmark"
                    ) {
                        editor
                            .acceptTrackedChangeAtSelection()
                    }

                    WordRibbonSmallButton(
                        title: "Reject",
                        systemImage: "xmark"
                    ) {
                        editor
                            .rejectTrackedChangeAtSelection()
                    }

                    WordRibbonSmallButton(
                        title: "Accept All",
                        systemImage: "checkmark.circle"
                    ) {
                        editor
                            .acceptAllTrackedChanges()
                    }

                    WordRibbonSmallButton(
                        title: "Reject All",
                        systemImage: "xmark.circle"
                    ) {
                        editor
                            .rejectAllTrackedChanges()
                    }
                }
            }

        case .view:
            viewRibbon
        }
    }

    private var referencesRibbon: some View {
        HStack(
            alignment:
                .top,
            spacing:
                0
        ) {
            WordRibbonGroup(
                title:
                    "Table of Contents"
            ) {
                Menu {
                    Button("Print Book") { onInsertTOCMode(.printBook) }
                    Button("Kindle / eBook") { onInsertTOCMode(.kindle) }
                    Button("Digital / PDF") { onInsertTOCMode(.digitalPDF) }
                    Divider()
                    Button("Custom Table of Contents…",action:onInsertTOC)
                } label: { Label("Contents",systemImage:"list.number") }
                .font(.system(size:11))
                .frame(maxWidth:.infinity,minHeight:30)
                .accessibilityLabel("Table of Contents presets")
                WordRibbonSmallButton(title: "Update Table", systemImage: "arrow.clockwise", action: onUpdateFields)
                WordRibbonSmallButton(title: "Remove Table", systemImage: "trash") { editor.removeSelectedTableOfContents() }
            }
            .frame(
                width:
                    150
            )

            WordRibbonDivider()

            WordRibbonGroup(
                title:
                    "Footnotes"
            ) {
                HStack(
                    alignment:
                        .top,
                    spacing:
                        10
                ) {
                    VStack(
                        spacing:
                            3
                    ) {
                        WordRibbonSmallButton(
                            title:
                                "Insert Footnote",
                            systemImage:
                                "text.badge.plus"
                        ) {
                            onInsertFootnote()
                        }

                        WordRibbonSmallButton(
                            title:
                                "Edit Footnote",
                            systemImage:
                                "square.and.pencil"
                        ) {
                            onEditFootnote()
                        }
                    }

                    VStack(
                        spacing:
                            3
                    ) {
                        WordRibbonSmallButton(
                            title:
                                "Insert Endnote",
                            systemImage:
                                "doc.text"
                        ) {
                            onInsertEndnote()
                        }

                        WordRibbonSmallButton(
                            title:
                                "Edit Endnote",
                            systemImage:
                                "square.and.pencil"
                        ) {
                            onEditEndnote()
                        }
                    }
                }
            }
            .frame(
                width:
                    310
            )

            WordRibbonDivider()

            WordRibbonGroup(
                title:
                    "Citations"
            ) {
                VStack(
                    spacing:
                        3
                ) {
                    WordRibbonSmallButton(
                        title:
                            "Manage Sources",
                        systemImage:
                            "books.vertical",
                        action:
                            onShowCitations
                    )

                    WordRibbonSmallButton(
                        title:
                            "Bibliography",
                        systemImage:
                            "text.book.closed",
                        action:
                            onInsertBibliography
                    )
                }
            }
            .frame(
                width:
                    150
            )

            WordRibbonDivider()

            WordRibbonGroup(
                title:
                    "Captions"
            ) {
                WordRibbonSmallButton(title: "Insert Caption", systemImage: "text.below.photo", action: onInsertCaption)
                WordRibbonSmallButton(title: "Cross-reference", systemImage: "arrow.triangle.2.circlepath", action: onCrossReference)
                WordRibbonSmallButton(title: "Update Fields", systemImage: "arrow.clockwise", action: onUpdateFields)
            }
            .frame(
                width:
                    165
            )

            Spacer(
                minLength:
                    0
            )
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            7
        )
    }

    private var homeRibbon: some View {
        HStack(
            alignment:
                .top,
            spacing:
                0
        ) {
            clipboardGroup

            WordRibbonDivider()

            fontGroup

            WordRibbonDivider()

            paragraphGroup

            WordRibbonDivider()

            stylesGroup

            Spacer(
                minLength:
                    0
            )
        }
        .padding(
            .horizontal,
            8
        )
        .padding(
            .vertical,
            7
        )
    }

    private var clipboardGroup: some View {
        WordRibbonGroup(
            title:
                "Clipboard"
        ) {
            HStack(
                alignment:
                    .top,
                spacing:
                    4
            ) {
                Button {
                    _ =
                        NSApp.sendAction(
                            #selector(
                                NSText.paste(_:)
                            ),
                            to:
                                nil,
                            from:
                                nil
                        )
                } label: {
                    VStack(
                        spacing:
                            3
                    ) {
                        Image(
                            systemName:
                                "doc.on.clipboard"
                        )
                        .font(
                            .system(
                                size:
                                    22
                            )
                        )

                        Text("Paste")
                            .font(
                                .system(
                                    size:
                                        10
                                )
                            )
                    }
                    .frame(
                        width:
                            46,
                        height:
                            54
                    )
                }
                .buttonStyle(.borderless)

                VStack(
                    spacing:
                        2
                ) {
                    WordRibbonSmallButton(
                        title:
                            "Cut",
                        systemImage:
                            "scissors"
                    ) {
                        _ =
                            NSApp.sendAction(
                                #selector(
                                    NSText.cut(_:)
                                ),
                                to:
                                    nil,
                                from:
                                    nil
                            )
                    }

                    WordRibbonSmallButton(
                        title:
                            "Copy",
                        systemImage:
                            "doc.on.doc"
                    ) {
                        _ =
                            NSApp.sendAction(
                                #selector(
                                    NSText.copy(_:)
                                ),
                                to:
                                    nil,
                                from:
                                    nil
                            )
                    }
                }
            }
        }
        .frame(
            width:
                120
        )
    }

    private var fontGroup: some View {
        WordRibbonGroup(
            title:
                "Font"
        ) {
            VStack(
                alignment:
                    .leading,
                spacing:
                    5
            ) {
                HStack(
                    spacing:
                        4
                ) {
                    Picker(
                        "",
                        selection:
                            Binding(
                                get: {
                                    editor.fontFamily
                                },
                                set: {
                                    editor
                                        .setFontFamily(
                                            $0
                                        )
                                }
                            )
                    ) {
                        ForEach(
                            NSFontManager
                                .shared
                                .availableFontFamilies,
                            id:
                                \.self
                        ) {
                            family in

                            Text(family)
                                .tag(
                                    family
                                )
                        }
                    }
                    .labelsHidden()
                    .frame(
                        width:
                            150
                    )

                    TextField(
                        "",
                        value:
                            $editor.fontSize,
                        format:
                            .number
                    )
                    .textFieldStyle(
                        .roundedBorder
                    )
                    .frame(
                        width:
                            48
                    )
                    .onSubmit {
                        editor
                            .setFontSize(
                                editor
                                    .fontSize
                            )
                    }
                }

                HStack(
                    spacing:
                        2
                ) {
                    WordRibbonIconButton(
                        systemImage:
                            "bold",
                        help:
                            "Bold"
                    ) {
                        editor
                            .toggleTrait(
                                .boldFontMask
                            )
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "italic",
                        help:
                            "Italic"
                    ) {
                        editor
                            .toggleTrait(
                                .italicFontMask
                            )
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "underline",
                        help:
                            "Underline"
                    ) {
                        editor
                            .toggleUnderline()
                    }

                    Divider()
                        .frame(
                            height:
                                20
                        )

                    Button {
                        NSFontPanel
                            .shared
                            .orderFront(
                                nil
                            )
                    } label: {
                        Image(
                            systemName:
                                "character"
                        )
                        .frame(
                            width:
                                26,
                            height:
                                24
                        )
                    }
                    .buttonStyle(.borderless)
                    .help(
                        "More Font Options"
                    )

                    Button {
                        NSColorPanel
                            .shared
                            .orderFront(
                                nil
                            )
                    } label: {
                        Image(
                            systemName:
                                "paintpalette"
                        )
                        .frame(
                            width:
                                26,
                            height:
                                24
                        )
                    }
                    .buttonStyle(.borderless)
                    .help(
                        "Text Color"
                    )
                }
            }
        }
        .frame(
            width:
                230
        )
    }

    private var paragraphGroup: some View {
        WordRibbonGroup(
            title:
                "Paragraph"
        ) {
            VStack(
                alignment:
                    .leading,
                spacing:
                    5
            ) {
                HStack(
                    spacing:
                        2
                ) {
                    WordRibbonIconButton(
                        systemImage:
                            "list.bullet",
                        help:
                            "Bullets"
                    ) {
                        editor
                            .toggleBulletList()
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "list.number",
                        help:
                            "Numbering"
                    ) {
                        editor
                            .toggleNumberedList()
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "checklist",
                        help:
                            "Checklist"
                    ) {
                        editor
                            .toggleChecklist()
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "decrease.indent",
                        help:
                            "Decrease Indent"
                    ) {
                        editor
                            .decreaseIndent()
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "increase.indent",
                        help:
                            "Increase Indent"
                    ) {
                        editor
                            .increaseIndent()
                    }
                }

                HStack(
                    spacing:
                        2
                ) {
                    WordRibbonIconButton(
                        systemImage:
                            "text.alignleft",
                        help:
                            "Align Left"
                    ) {
                        editor
                            .setAlignment(
                                .left
                            )
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "text.aligncenter",
                        help:
                            "Center"
                    ) {
                        editor
                            .setAlignment(
                                .center
                            )
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "text.alignright",
                        help:
                            "Align Right"
                    ) {
                        editor
                            .setAlignment(
                                .right
                            )
                    }

                    WordRibbonIconButton(
                        systemImage:
                            "text.justify",
                        help:
                            "Justify"
                    ) {
                        editor
                            .setAlignment(
                                .justified
                            )
                    }
                }
            }
        }
        .frame(
            width:
                170
        )
    }

    private var stylesGroup: some View {
        WordRibbonGroup(
            title:
                "Styles"
        ) {
            HStack(
                spacing:
                    4
            ) {
                WordStyleTile(
                    title:
                        "Normal",
                    isSelected: editor.selectedStyle == .normal
                ) {
                    editor
                        .applyStyle(
                            .normal
                        )
                }

                WordStyleTile(
                    title:
                        "Title",
                    isSelected: editor.selectedStyle == .title
                ) {
                    editor
                        .applyStyle(
                            .title
                        )
                }

                WordStyleTile(
                    title:
                        "Heading 1",
                    isSelected: editor.selectedStyle == .heading1
                ) {
                    editor
                        .applyStyle(
                            .heading1
                        )
                }

                WordStyleTile(
                    title:
                        "Heading 2",
                    isSelected: editor.selectedStyle == .heading2
                ) {
                    editor
                        .applyStyle(
                            .heading2
                        )
                }

                WordStyleTile(title: "Heading 3", isSelected: editor.selectedStyle == .heading3) {
                    editor.applyStyle(.heading3)
                }

                Menu {
                    Button("Normal") { editor.applyStyle(.normal) }
                    Menu("Create Custom Style…") {
                        TextField("Style name", text: $customStyleName)
                        Button("Create and Apply") {
                            if let style = editor.createNamedStyle(name: customStyleName, basedOn: editor.selectedStyle) {
                                editor.applyNamedStyle(style)
                            }
                        }
                    }
                    Button("Clear Direct Formatting") { editor.clearDirectFormatting() }
                    Button("Update Custom Style to Match Selection") { _ = editor.updateNamedStyleFromSelection() }
                    Divider()
                    Button("Subtitle") { editor.applyStyle(.subtitle) }
                    Button("Heading 4") { editor.applyStyle(.heading4) }
                    Button("Heading 5") { editor.applyStyle(.heading5) }
                    Button("Heading 6") { editor.applyStyle(.heading6) }
                    Button("No Spacing") { editor.applyStyle(.noSpacing) }
                    Button("Quote") { editor.applyStyle(.quote) }
                    Button("Intense Quote") { editor.applyStyle(.intenseQuote) }
                } label: {
                    Image(systemName: "chevron.down")
                        .frame(width: 24, height: 48)
                }
                .menuStyle(.borderlessButton)
                .help("More Styles and Formatting")

            }
        }
        .frame(
            minWidth:
                360
        )
    }

    private var viewRibbon: some View {
        HStack(
            alignment:
                .top,
            spacing:
                0
        ) {
            WordRibbonGroup(
                title:
                    "Mode"
            ) {
                Menu(
                    editingMode.rawValue
                ) {
                    Button(
                        "Editing"
                    ) {
                        onSetEditingMode(
                            .editing
                        )
                    }

                    Button(
                        "Suggesting"
                    ) {
                        onSetEditingMode(
                            .suggesting
                        )
                    }

                    Button(
                        "Viewing"
                    ) {
                        onSetEditingMode(
                            .viewing
                        )
                    }
                }
                .menuStyle(
                    .borderlessButton
                )
                .frame(
                    width:
                        105
                )
            }

            WordRibbonDivider()

            WordRibbonGroup(
                title:
                    "Views"
            ) {
                HStack(
                    spacing:
                        8
                ) {
                    Button {
                        printLayout = true
                    } label: {
                        Label(
                            "Print Layout",
                            systemImage:
                                "doc"
                        )
                    }

                    Button {
                        printLayout = false
                    } label: {
                        Label(
                            "Continuous",
                            systemImage:
                                "text.alignleft"
                        )
                    }
                }
                .buttonStyle(
                    .borderless
                )
            }
            .frame(
                width:
                    240
            )

            WordRibbonDivider()

            WordRibbonGroup(
                title:
                    "Show"
            ) {
                HStack(
                    spacing:
                        12
                ) {
                    Toggle(
                        "Navigation",
                        isOn:
                            $showLeftSidebar
                    )

                    Toggle(
                        "Inspector",
                        isOn:
                            $showRightSidebar
                    )

                    Toggle(
                        "Formatting Marks",
                        isOn:
                            Binding(
                                get: {
                                    showNonPrintingCharacters
                                },
                                set: {
                                    _ in
                                    onToggleNonPrintingCharacters()
                                }
                            )
                    )

                    Toggle(
                        "Line Numbers",
                        isOn:
                            Binding(
                                get: {
                                    showLineNumbers
                                },
                                set: {
                                    _ in
                                    onToggleLineNumbers()
                                }
                            )
                    )
                }
                .toggleStyle(
                    .checkbox
                )
            }

            Spacer()
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            10
        )
    }

    private func placeholderRibbon(groups: [(String, String)]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                WordRibbonGroup(title: group.0) {
                    Text(group.1)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .frame(minWidth: 110, minHeight: 48)
                }
                WordRibbonDivider()
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
    }
}


struct WordEquationToolbar: View {
    @ObservedObject var editor: EditorController
    var onClose: () -> Void

    private let operators = [
        "±",
        "×",
        "÷",
        "≠",
        "≤",
        "≥",
        "≈",
        "∞",
    ]

    private let greek = [
        "π",
        "θ",
        "α",
        "β",
        "γ",
        "δ",
        "Δ",
        "λ",
        "μ",
        "σ",
        "φ",
        "Ω",
    ]

    private let calculus = [
        "√",
        "∑",
        "∏",
        "∫",
        "∂",
        "∇",
        "∞",
    ]

    private let sets = [
        "∈",
        "∉",
        "⊂",
        "⊆",
        "∪",
        "∩",
        "∅",
        "ℝ",
    ]

    private let arrows = [
        "→",
        "←",
        "↔",
        "⇒",
        "⇔",
    ]

    var body: some View {
        HStack(
            spacing:
                8
        ) {
            Image(
                systemName:
                    "function"
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                "Equation"
            )
            .font(
                .system(
                    size:
                        11,
                    weight:
                        .semibold
                )
            )

            Divider()
                .frame(
                    height:
                        22
                )

            symbolMenu(
                "Operators",
                symbols:
                    operators
            )

            symbolMenu(
                "Greek",
                symbols:
                    greek
            )

            symbolMenu(
                "Calculus",
                symbols:
                    calculus
            )

            symbolMenu(
                "Sets",
                symbols:
                    sets
            )

            symbolMenu(
                "Arrows",
                symbols:
                    arrows
            )

            Menu(
                "Templates"
            ) {
                Button(
                    "Squared  x²"
                ) {
                    editor.insertEquationText(
                        "x²"
                    )
                }

                Button(
                    "Subscript  xₙ"
                ) {
                    editor.insertEquationText(
                        "xₙ"
                    )
                }

                Button(
                    "Square Root  √()"
                ) {
                    editor.insertEquationText(
                        "√()"
                    )
                }

                Button(
                    "Summation  ∑()"
                ) {
                    editor.insertEquationText(
                        "∑()"
                    )
                }

                Button(
                    "Integral  ∫()"
                ) {
                    editor.insertEquationText(
                        "∫()"
                    )
                }

                Button(
                    "Fraction  ()/()"
                ) {
                    editor.insertEquationText(
                        "()/()"
                    )
                }
            }
            .font(
                .system(
                    size:
                        11
                )
            )

            Spacer(
                minLength:
                    0
            )

            Button {
                onClose()
            } label: {
                Image(
                    systemName:
                        "xmark"
                )
            }
            .buttonStyle(
                .borderless
            )
            .help(
                "Hide Equation Toolbar"
            )
        }
        .padding(
            .horizontal,
            10
        )
        .frame(
            height:
                36
        )
        .background(
            Color(
                nsColor:
                    .controlBackgroundColor
            )
        )
        .overlay(
            alignment:
                .bottom
        ) {
            Divider()
        }
    }

    @ViewBuilder
    private func symbolMenu(
        _ title: String,
        symbols: [String]
    ) -> some View {
        Menu(
            title
        ) {
            ForEach(
                symbols,
                id:
                    \.self
            ) {
                symbol in

                Button(
                    symbol
                ) {
                    editor.insertEquationText(
                        symbol
                    )
                }
            }
        }
        .font(
            .system(
                size:
                    11
            )
        )
    }
}

private struct WordRibbonGroup<
    Content:
        View
>: View {
    var title: String

    @ViewBuilder var content:
        () -> Content

    var body: some View {
        VStack(
            spacing:
                3
        ) {
            content()

            Spacer(
                minLength:
                    0
            )

            Text(title)
                .font(
                    .system(
                        size:
                            9
                    )
                )
                .foregroundStyle(
                    .secondary
                )
                .lineLimit(1)
        }
        .padding(
            .horizontal,
            6
        )
        .frame(
            height:
                88
        )
    }
}

private struct WordRibbonDivider: View {
    var body: some View {
        Divider()
            .frame(
                height:
                    78
            )
            .padding(
                .horizontal,
                3
            )
    }
}

private struct WordRibbonSmallButton: View {
    var title: String
    var systemImage: String
    var action: () -> Void

    var body: some View {
        Button(
            action:
                action
        ) {
            Label(
                title,
                systemImage:
                    systemImage
            )
            .font(
                .system(
                    size:
                        10
                )
            )
            .frame(
                width:
                    62,
                alignment:
                    .leading
            )
        }
        .buttonStyle(.borderless)
    }
}

private struct WordRibbonIconButton: View {
    var systemImage: String
    var help: String
    var action: () -> Void

    var body: some View {
        Button(
            action:
                action
        ) {
            Image(
                systemName:
                    systemImage
            )
            .font(
                .system(
                    size:
                        13
                )
            )
            .frame(
                width:
                    27,
                height:
                    24
            )
            .contentShape(
                Rectangle()
            )
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct WordStyleTile: View {
    var title: String
    var isSelected = false
    var action: () -> Void

    var body: some View {
        Button(
            action:
                action
        ) {
            VStack(
                spacing:
                    1
            ) {
                Text("AaBbCc")
                    .font(
                        title.contains(
                            "Heading"
                        )
                        ? .system(
                            size:
                                14,
                            weight:
                                .semibold
                        )
                        : .system(
                            size:
                                13
                        )
                    )

                Text(title)
                    .font(
                        .system(
                            size:
                                9
                        )
                    )
                    .lineLimit(1)
            }
            .frame(
                width:
                    72,
                height:
                    48
            )
            .background(
                RoundedRectangle(
                    cornerRadius:
                        3
                )
                .fill(
                    Color(
                        nsColor:
                            .textBackgroundColor
                    )
                )
            )
            .overlay(
                RoundedRectangle(
                    cornerRadius:
                        3
                )
                .stroke(
                    isSelected ? Color.accentColor : Color.secondary.opacity(0.22),
                    lineWidth:
                        isSelected ? 2 : 1
                )
            )
        }
        .buttonStyle(.plain)
    }
}

struct WordStatusBar: View {
    @Binding var showLeftSidebar: Bool
    @Binding var printLayout: Bool
    var statistics: DocumentStatistics
    var onShowWordCount: () -> Void
    @Binding var zoom: Double

    var body: some View {
        HStack(
            spacing:
                12
        ) {
            Button {
                onShowWordCount()
            } label: {
                Text(
                    "\(statistics.words.formatted()) words"
                )
                .font(
                    .system(
                        size:
                            10
                    )
                )
            }
            .buttonStyle(.borderless)
            .help("Word Count")

            Divider()
                .frame(
                    height:
                        14
                )

            Button {
                showLeftSidebar.toggle()
            } label: {
                Label(
                    "Navigation",
                    systemImage:
                        "sidebar.left"
                )
                .font(
                    .system(
                        size:
                            10
                    )
                )
            }
            .buttonStyle(.borderless)

            Spacer()

            Button {
                printLayout = false
            } label: {
                Image(
                    systemName:
                        "text.alignleft"
                )
            }
            .buttonStyle(.borderless)
            .help("Continuous View")

            Button {
                printLayout = true
            } label: {
                Image(
                    systemName:
                        "doc"
                )
            }
            .buttonStyle(.borderless)
            .help("Print Layout")

            Divider()
                .frame(
                    height:
                        14
                )

            Button {
                zoom =
                    max(
                        0.65,
                        zoom - 0.1
                    )
            } label: {
                Image(
                    systemName:
                        "minus"
                )
            }
            .buttonStyle(.borderless)

            Slider(
                value:
                    $zoom,
                in:
                0.65...1.8
            )
            .frame(
                width:
                    120
            )

            Button {
                zoom =
                    min(
                        1.8,
                        zoom + 0.1
                    )
            } label: {
                Image(
                    systemName:
                        "plus"
                )
            }
            .buttonStyle(.borderless)

            Text(
                "\(Int(zoom * 100))%"
            )
            .font(
                .system(
                    size:
                        10,
                    design:
                        .monospaced
                )
            )
            .frame(
                width:
                    42,
                alignment:
                    .trailing
            )
        }
        .padding(
            .horizontal,
            10
        )
        .frame(
            height:
                25
        )
        .background(
            Color(
                nsColor:
                    .controlBackgroundColor
            )
        )
        .overlay(
            alignment:
                .top
        ) {
            Divider()
        }
    }
}
