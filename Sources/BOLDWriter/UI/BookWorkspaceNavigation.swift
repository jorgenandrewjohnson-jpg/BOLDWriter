import SwiftUI

enum BookStudioProductionEditRoute:
    Equatable
{
    case cover(
        CoverPanelAnchor?
    )
    case manuscript(
        Int
    )
}

enum BookStudioProductionRouting {
    static func studioComponent(
        for panel:
            CoverPanelAnchor?
    ) -> BookSceneComponent? {
        switch panel {
        case .front:
            return .front

        case .spine:
            return .spine

        case .back:
            return .back

        case .canvas,
             .none:
            return nil
        }
    }

    static func editRoute(
        for component:
            BookSceneComponent,
        spread:
            BookSpread
    ) -> BookStudioProductionEditRoute? {
        switch component {
        case .book:
            return .cover(
                nil
            )

        case .front:
            return .cover(
                .front
            )

        case .back:
            return .cover(
                .back
            )

        case .spine:
            return .cover(
                .spine
            )

        case .pages:
            return .manuscript(
                spread.rightPage
                ?? spread.leftPage
                ?? 1
            )

        case .leftPage:
            return .manuscript(
                spread.leftPage
                ?? spread.rightPage
                ?? 1
            )

        case .rightPage:
            return .manuscript(
                spread.rightPage
                ?? spread.leftPage
                ?? 1
            )

        case .environment,
             .lights,
             .camera:
            return nil
        }
    }
}

enum BookWorkspace: String, CaseIterable, Identifiable {
    case manuscript
    case coverCreator
    case bookStudio3D
    case automationStudio

    var id: String { rawValue }
}

/// One document and one active workspace in the existing document window.
/// Visited workspaces stay mounted so their transient editing/view state survives
/// navigation. The 3D viewport itself is suspended while Studio is inactive.
struct BookWorkspaceNavigation {
    let document: BOLDWriterDocument
    private(set) var active: BookWorkspace = .manuscript
    private(set) var hasVisitedCover = false
    private(set) var hasVisitedStudio = false
    private(set) var hasVisitedAutomation = false

    private(set) var coverFocusPanel:
        CoverPanelAnchor?

    private(set) var coverFocusRequestID:
        UUID?

    private(set) var manuscriptPageRequest:
        Int?

    private(set) var manuscriptRangeRequest:
        NSRange?

    private(set) var manuscriptRequestID:
        UUID?




    private(set) var studioFocusComponent:


        BookSceneComponent?



    private(set) var studioFocusRequestID:


        UUID?
    mutating func open(_ destination: BookWorkspace) {
        active = destination
        if destination == .coverCreator { hasVisitedCover = true }
        if destination == .bookStudio3D { hasVisitedStudio = true }
        if destination == .automationStudio { hasVisitedAutomation = true }
    }

    mutating func requestCoverEdit(
        projectID:
            UUID,
        panel:
            CoverPanelAnchor?
    ) {
        selectCoverProject(
            toEdit:
                projectID
        )

        coverFocusPanel =
            panel

        coverFocusRequestID =
            UUID()
    }

    mutating func requestManuscriptEdit(
        pageNumber:
            Int,
        range:
            NSRange?
    ) {
        manuscriptPageRequest =
            max(
                1,
                pageNumber
            )

        manuscriptRangeRequest =
            range

        manuscriptRequestID =
            UUID()
    }

    mutating func requestStudioFocus(
        panel:
            CoverPanelAnchor?
    ) {
        studioFocusComponent =
            BookStudioProductionRouting
                .studioComponent(
                    for:
                        panel
                )

        studioFocusRequestID =
            UUID()
    }

    func saveCoverProjects(_ projects: [CoverProject], activeID: UUID) {
        document.metadata.coverProjects = projects
        document.metadata.activeCoverProjectID = projects.contains { $0.id == activeID }
            ? activeID : projects.first?.id
    }

    func applyProductionTemplateToManuscript(
        _ template:
            BookProductionTemplate
    ) {
        guard
            template != .custom
        else {
            return
        }

        var metadata =
            document.metadata

        template.apply(
            to:
                &metadata.page
        )

        if var sections =
            metadata.sections,
           !sections.isEmpty
        {
            for index in
                sections.indices
            {
                template.apply(
                    to:
                        &sections[index].page
                )
            }

            metadata.sections =
                DocumentSection
                    .normalized(
                        sections,
                        textLength:
                            document.text.length,
                        fallbackPage:
                            metadata.page
                    )

            if let first =
                metadata.sections?.first
            {
                metadata.page =
                    first.page
            }
        }

        document.metadata =
            metadata
    }

    func applyProductionTemplate(
        _ template:
            BookProductionTemplate,
        pageCount:
            Int? = nil
    ) {
        var projects =
            document.metadata.coverProjects
            ?? []

        let activeID =
            document.metadata.activeCoverProjectID

        let index =
            activeID
                .flatMap {
                    id in

                    projects.firstIndex {
                        $0.id == id
                            && $0.type
                                == .printFullWrap
                    }
                }
            ?? projects.firstIndex {
                $0.type
                    == .printFullWrap
            }

        if template == .custom {
            guard
                let index
            else {
                return
            }

            projects[index]
                .productionTemplate =
                .custom

            document.metadata.coverProjects =
                projects

            document.metadata.activeCoverProjectID =
                projects[index].id

            return
        }

        applyProductionTemplateToManuscript(
            template
        )

        guard
            let index
        else {
            return
        }

        let current =
            projects[index]

        let fallbackCaliper =
            current.spineCaliperInches
            ?? template
                .paperStockPreset?
                .caliperInches
            ?? PrintCoverSpecification
                .kdpBlackAndWhiteWhitePaperCaliper

        let inferredPageCount =
            CoverCalculator
                .inferredPageCount(
                    spineWidth:
                        current.spineWidth,
                    caliperInches:
                        fallbackCaliper
                )

        let effectivePageCount =
            max(
                1,
                pageCount
                ?? current.spinePageCount
                ?? inferredPageCount
            )

        if let updated =
            PhysicalBookGeometry
                .applyingProductionTemplate(
                    template,
                    to:
                        current,
                    pageCount:
                        effectivePageCount
                )
        {
            projects[index] =
                updated
        }

        document.metadata.coverProjects =
            projects

        document.metadata.activeCoverProjectID =
            projects[index].id
    }

    func selectCoverProject(toEdit requestedID: UUID) {
        let projects = document.metadata.coverProjects ?? []
        document.metadata.activeCoverProjectID =
            projects.first(where: { $0.id == requestedID })?.id
            ?? projects.first(where: { $0.type == .printFullWrap })?.id
            ?? projects.first?.id
    }
}

struct BookWorkspaceSwitcher: View {
    let current: BookWorkspace
    let onSelect: (BookWorkspace) -> Void

    var body: some View {
        HStack(spacing: 7) {
            workspaceButton("Manuscript", symbol: "doc.text", destination: .manuscript)
            workspaceButton("Cover Creator", symbol: "paintpalette", destination: .coverCreator)
            workspaceButton("3D Studio", symbol: "book.closed", destination: .bookStudio3D)
            workspaceButton("Automation Studio", symbol: "curlybraces", destination: .automationStudio)
            Spacer(minLength: 0)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Book workspaces")
    }

    private func workspaceButton(
        _ title: String,
        symbol: String,
        destination: BookWorkspace
    ) -> some View {
        Group {
            if current == destination {
                Button { } label: {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button { onSelect(destination) } label: {
                    Label(title, systemImage: symbol)
                        .font(.system(size: 12))
                }
                .buttonStyle(.bordered)
            }
        }
        .accessibilityLabel(title)
        .accessibilityAddTraits(current == destination ? .isSelected : [])
    }
}
