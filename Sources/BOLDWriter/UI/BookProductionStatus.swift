import Foundation
import SwiftUI

enum BookProductionReadinessIssue:
    String,
    Equatable,
    Identifiable
{
    case ready
    case missingPrintCover
    case needsManuscriptPagination
    case productionProfileMismatch
    case trimMismatch
    case pageCountMismatch
    case spineMismatch
    case manualCustom

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .ready:
            return "Ready"

        case .missingPrintCover:
            return "Needs Print Cover"

        case .needsManuscriptPagination:
            return "Needs Pagination"

        case .productionProfileMismatch:
            return "Profile Mismatch"

        case .trimMismatch:
            return "Trim Mismatch"

        case .pageCountMismatch:
            return "Page-Count Mismatch"

        case .spineMismatch:
            return "Spine Mismatch"

        case .manualCustom:
            return "Manual / Custom"
        }
    }

    var symbolName: String {
        switch self {
        case .ready:
            return "checkmark.circle.fill"

        case .manualCustom:
            return "slider.horizontal.3"

        case .needsManuscriptPagination:
            return "doc.text.magnifyingglass"

        case .missingPrintCover:
            return "rectangle.portrait.on.rectangle.portrait"

        case .productionProfileMismatch,
             .trimMismatch,
             .pageCountMismatch,
             .spineMismatch:
            return "exclamationmark.triangle.fill"
        }
    }

    var isActionable: Bool {
        self != .ready
    }
}

struct BookProductionStatusSnapshot:
    Equatable
{
    let projectID: UUID?
    let profile: BookProductionTemplate?
    let trimWidth: Double?
    let trimHeight: Double?
    let renderedPageCount: Int?
    let storedPageCount: Int?
    let spineWidth: Double?
    let paperStock: PrintPaperStockPreset?
    let binding: BookBinding?
    let issue: BookProductionReadinessIssue

    static func activePrintProject(
        projects: [CoverProject],
        activeProjectID: UUID?
    ) -> CoverProject? {
        if let activeProjectID,
           let active =
            projects.first(
                where: {
                    $0.id == activeProjectID
                        && $0.type == .printFullWrap
                }
            )
        {
            return active
        }

        return projects.first {
            $0.type == .printFullWrap
        }
    }

    static func make(
        projects: [CoverProject],
        activeProjectID: UUID?,
        renderedPageCount: Int?,
        manuscriptPageSettings: [PageSettings]
    ) -> Self {
        make(
            project:
                activePrintProject(
                    projects:
                        projects,
                    activeProjectID:
                        activeProjectID
                ),
            renderedPageCount:
                renderedPageCount,
            manuscriptPageSettings:
                manuscriptPageSettings
        )
    }

    static func make(
        project: CoverProject?,
        renderedPageCount: Int?,
        manuscriptPageSettings: [PageSettings]
    ) -> Self {
        guard let project else {
            return Self(
                projectID:
                    nil,
                profile:
                    nil,
                trimWidth:
                    nil,
                trimHeight:
                    nil,
                renderedPageCount:
                    renderedPageCount,
                storedPageCount:
                    nil,
                spineWidth:
                    nil,
                paperStock:
                    nil,
                binding:
                    nil,
                issue:
                    .missingPrintCover
            )
        }

        let profile =
            project.productionTemplate
            ?? BookProductionTemplate
                .inferred(
                    from:
                        project
                )

        let paper =
            project.paperStockPreset
            ?? PrintPaperStockPreset
                .inferred(
                    caliper:
                        project.spineCaliperInches
                )

        let binding =
            project.productionBinding
            ?? .softcover

        let normalizedRenderedPageCount =
            renderedPageCount.flatMap {
                $0 > 0
                    ? $0
                    : nil
            }

        let issue:
            BookProductionReadinessIssue

        if project.productionTemplate == .custom
            || profile == .custom
        {
            issue =
                .manualCustom
        } else if normalizedRenderedPageCount == nil {
            issue =
                .needsManuscriptPagination
        } else if !PhysicalBookDiagnostics
            .trimMismatchPages(
                project:
                    project,
                pages:
                    manuscriptPageSettings
            )
            .isEmpty
        {
            issue =
                .trimMismatch
        } else if PhysicalBookDiagnostics
            .pageCountMessage(
                coverPages:
                    project.spinePageCount,
                manuscriptPages:
                    normalizedRenderedPageCount
                    ?? 0
            )
            != nil
        {
            issue =
                .pageCountMismatch
        } else if PhysicalBookDiagnostics
            .expectedSpineMismatch(
                project:
                    project,
                manuscriptPages:
                    normalizedRenderedPageCount
                    ?? 0
            )
            != nil
        {
            issue =
                .spineMismatch
        } else if let repairTemplate =
            PhysicalBookDiagnostics
                .productionProfileRepairTemplate(
                    project:
                        project
                ),
           !repairTemplate.matches(
                project
           )
        {
            issue =
                .productionProfileMismatch
        } else {
            issue =
                .ready
        }

        return Self(
            projectID:
                project.id,
            profile:
                profile,
            trimWidth:
                project.trimWidth,
            trimHeight:
                project.trimHeight,
            renderedPageCount:
                normalizedRenderedPageCount,
            storedPageCount:
                project.spinePageCount,
            spineWidth:
                project.spineWidth,
            paperStock:
                paper,
            binding:
                binding,
            issue:
                issue
        )
    }

    var profileText: String {
        profile?.rawValue
        ?? "No print profile"
    }

    var trimText: String {
        guard
            let trimWidth,
            let trimHeight
        else {
            return "—"
        }

        return String(
            format:
                "%.2f × %.2f in",
            trimWidth,
            trimHeight
        )
    }

    var pageCountText: String {
        if let renderedPageCount {
            return "\(renderedPageCount)"
        }

        if let storedPageCount {
            return "\(storedPageCount) stored"
        }

        return "—"
    }

    var spineText: String {
        guard let spineWidth else {
            return "—"
        }

        return String(
            format:
                "%.3f in",
            spineWidth
        )
    }

    var paperText: String {
        paperStock?.rawValue
        ?? "—"
    }

    var bindingText: String {
        binding?.rawValue
        ?? "—"
    }
}

struct BookProductionStatusStrip:
    View
{
    let snapshot: BookProductionStatusSnapshot
    let workspace: BookWorkspace
    let onIssue: (BookProductionReadinessIssue) -> Void

    var body: some View {
        HStack(
            spacing:
                10
        ) {
            Label(
                "Production",
                systemImage:
                    "book.closed"
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
                        16
                )

            metric(
                "Profile",
                snapshot.profileText
            )

            metric(
                "Trim",
                snapshot.trimText
            )

            metric(
                "Pages",
                snapshot.pageCountText
            )

            metric(
                "Spine",
                snapshot.spineText
            )

            metric(
                "Paper",
                snapshot.paperText
            )

            metric(
                "Binding",
                snapshot.bindingText
            )

            Spacer(
                minLength:
                    8
            )

            Text(
                workspace.rawValue
            )
            .font(
                .caption2
            )
            .foregroundStyle(
                .secondary
            )

            if snapshot.issue.isActionable {
                Button {
                    onIssue(
                        snapshot.issue
                    )
                } label: {
                    Label(
                        snapshot.issue.title,
                        systemImage:
                            snapshot.issue
                                .symbolName
                    )
                }
                .buttonStyle(
                    .bordered
                )
                .controlSize(
                    .small
                )
                .accessibilityLabel(
                    "Production status: "
                    + snapshot.issue.title
                )
            } else {
                Label(
                    snapshot.issue.title,
                    systemImage:
                        snapshot.issue
                            .symbolName
                )
                .font(
                    .caption
                        .bold()
                )
                .foregroundStyle(
                    .secondary
                )
                .accessibilityLabel(
                    "Production status: Ready"
                )
            }
        }
        .padding(
            .horizontal,
            10
        )
        .padding(
            .vertical,
            5
        )
        .background(
            .bar
        )
        .overlay(
            alignment:
                .top
        ) {
            Divider()
        }
        .accessibilityElement(
            children:
                .contain
        )
        .accessibilityLabel(
            "Book production status"
        )
    }

    private func metric(
        _ label:
            String,
        _ value:
            String
    ) -> some View {
        HStack(
            spacing:
                3
        ) {
            Text(
                label + ":"
            )
            .foregroundStyle(
                .secondary
            )

            Text(
                value
            )
            .lineLimit(
                1
            )
        }
        .font(
            .caption2
        )
    }
}
