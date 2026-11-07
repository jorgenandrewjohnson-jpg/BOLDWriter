import AppKit
import ImageIO
import PDFKit
import SceneKit
import SwiftUI
import UniformTypeIdentifiers

struct PhysicalBookPreview: View {
    @ObservedObject var document: BOLDWriterDocument
    @Environment(\.undoManager) private var undoManager
    let isActive: Bool
    let requestedFocusComponent: BookSceneComponent?
    let focusRequestID: UUID?
    let onRenderedPageCountChange:
        (Int?) -> Void

    let onEditCover:
        (
            UUID,
            CoverPanelAnchor?
        ) -> Void

    let onEditManuscript:
        (
            Int,
            NSRange?
        ) -> Void

    let onOpenAutomationStudio: () -> Void


    init(
        document:
            BOLDWriterDocument,
        isActive:
            Bool = true,
        requestedFocusComponent:
            BookSceneComponent? = nil,
        focusRequestID:
            UUID? = nil,
        onRenderedPageCountChange:
            @escaping (
                Int?
            ) -> Void = { _ in },
        onEditCover:
            @escaping (
                UUID,
                CoverPanelAnchor?
            ) -> Void,
        onEditManuscript:
            @escaping (
                Int,
                NSRange?
            ) -> Void,
        onOpenAutomationStudio: @escaping () -> Void = {}
    ) {
        _document =
            ObservedObject(
                wrappedValue:
                    document
            )

        self.isActive =
            isActive

        self.requestedFocusComponent =
            requestedFocusComponent

        self.focusRequestID =
            focusRequestID


        self.onRenderedPageCountChange =
            onRenderedPageCountChange
        self.onEditCover =
            onEditCover

        self.onEditManuscript =
            onEditManuscript

        self.onOpenAutomationStudio = onOpenAutomationStudio
    }
    @State private var projectID: UUID?
    @State private var workingLayers = false
    // A temporary physical-preview choice, scoped to the active cover.
    // Preview-only state; never persisted to the cover project.
    @State private var inspection = BookInspectionState()
    @State private var compareSideBySide = false
    @State private var synchronizeCameras = true
    @State private var comparisonCamera: BookSavedCamera?
    @State private var comparisonHandle = BookStudioViewportHandle()
    @State private var comparisonCameraLink = BookInspectionCameraLink()
    @State private var dangerSeverity = "All"
    @State private var dangerComponent: BookSceneComponent?
    @State private var comparisonBinding: BookBinding?
    @State private var comparisonProjectID: UUID?

    @State private var studio = BookStudioPresentation.restingOpenPreviewDefault
    @State private var selectedComponent: BookSceneComponent?
    @State private var selectedCustomLightID: UUID?
    @State private var studioRestored = false
    @State private var pageEntry = BookStudioPageEntry()
    @FocusState private var pageEntryFocused: Bool
    @State private var renderSize: BookStudioRenderSize = .viewport
    @State private var exportJPEG = false
    @State private var transparentBackground = false
    @State private var customRenderWidth = 1600
    @State private var customRenderHeight = 2000
    @State private var viewportHandle = BookStudioViewportHandle()
    @State private var resetGeneration = 0
    @State private var pageTurnState = BookPageTurnState()
    @State private var pageTurnTexture: NSImage?
    @State private var pageTurnReverseTexture: NSImage?
    @State private var pageTurnGeneration = 0
    @State private var showMargins = false
    @State private var thumbMode: ThumbZoneMode = .off
    @State private var pageCount = 0
    @State private var paginatedPageSettings: [PageSettings] = []
    @State private var paginatedPageRanges: [NSRange] = []
    @State private var interiorImageIssuesByPage: [Int: [PhysicalBookInteriorImageResolutionIssue]] = [:]
    @State private var marginIssuesByPage: [Int: [String]] = [:]
    @State private var standardThumbIssuesByPage: [Int: String] = [:]
    @State private var compactThumbIssuesByPage: [Int: String] = [:]
    @State private var pageTextureCache = BookPageTextureCache()
    @State private var pageTextureDecorator = BookPageTextureDecorator()
    @State private var pendingPageTextures: Set<Int> = []
    @State private var previewPDF: PDFDocument?
    @State private var previewPDFURL: URL?
    @State private var isRendering = false
    @State private var renderError: String?
    @State private var renderRequestID = UUID()
    @State private var focusGeneration = 0
    @State private var zoomAction: CameraZoomAction = .fit
    @State private var zoomGeneration = 0
    @State private var cameraZoomScale = 1.0
    @State private var focusTarget: BookFocusTarget = .automatic
    @State private var animationPlaying = false
    @State private var animationRuntimeTime = 0.0
    @State private var animationPlaybackGeneration = 0
    @State private var animationExportFormat: BookStudioAnimationExportFormat = .pngSequence
    @State private var animationExporting = false
    @State private var animationExportProgress = 0.0
    @State private var animationExportCurrentFrame = 0
    @State private var animationExportGeneration = 0
    @State private var animationExportStatus: String?


    // BOLD_AUTO_PRINT_WRAP_BRIDGE_V1
    // Preserve the original cover and create a real editable print-wrap copy.
    private func restoreExistingArtworkFor3D() {
        let existing = document.metadata.coverProjects ?? []

        guard !existing.contains(where: {
            $0.type == .printFullWrap
        }) else {
            return
        }

        guard existing.count < CoverProjectOperations.maximumProjectCount else {
            return
        }

        let candidates = existing.filter {
            $0.type == .ebookFront
                && !$0.layers.isEmpty
        }

        let source = candidates.first {
            $0.id == document.metadata.activeCoverProjectID
        } ?? candidates.first

        guard let source,
              let recovered = CoverPrintWrapBridge.promote(source)
        else {
            return
        }

        var updated = existing
        updated.append(recovered)

        do {
            try CoverProject.validate(updated)
        } catch {
            NSLog(
                "BOLD Writer 3D cover recovery validation: %@",
                String(describing: error)
            )
            return
        }

        document.metadata.coverProjects = updated
        document.metadata.activeCoverProjectID = recovered.id
        projectID = recovered.id

        NSLog(
            "BOLD Writer: existing cover promoted to editable 3D print wrap."
        )
    }

    private var printProjects: [CoverProject] { (document.metadata.coverProjects ?? []).filter { $0.type == .printFullWrap } }
    private var binding: BookBinding {
        let comparison: BookBinding?
        if let activeID = project?.id, comparisonProjectID == activeID {
            comparison = comparisonBinding
        } else {
            comparison = nil
        }

        return BookBindingPreviewComparison.resolve(
            original: project?.productionBinding,
            comparison: comparison,
            fallback: studio.binding
        )
    }
    private var isOpen: Bool { studio.open }
    private var openAngle: Double { studio.openAngle }
    private var viewPreset: BookViewPreset { studio.cameraPreset }

    // Route explicit camera commands through one handler.
    // Re-selecting the active preset must reset manual orbit.
    // Ordinary page turns never call this method.
    private func chooseCameraPreset(
        _ selectedPreset: BookViewPreset
    ) {
        if BookStudioCameraPresetCommand.reselect(
            selectedPreset,
            presentation: &studio,
            resetGeneration: &resetGeneration
        ) {
            focusTarget = .automatic
            focusGeneration += 1
            cameraZoomScale = 1
        } else {
            studio.cameraPreset = selectedPreset
        }
    }


    private var animationDisplayTime:
        Double
    {
        animationPlaying
        ? animationRuntimeTime
        : BookStudioAnimationMath
            .normalizedTime(
                studio.animationPlayhead,
                duration:
                    studio.animationDuration
            )
    }

    private var animationPresentation:
        BookStudioPresentation
    {
        var result =
            studio

        let time =
            animationDisplayTime

        result.animationPlayhead =
            time

        result.modelTransform =
            BookStudioAnimationMath
            .turntableTransform(
                base:
                    studio.modelTransform,
                time:
                    time,
                duration:
                    studio.animationDuration,
                enabled:
                    studio.turntableEnabled,
                turns:
                    studio.turntableTurns,
                clockwise:
                    studio.turntableClockwise
            )

        if
            let camera =
                BookStudioAnimationMath
                .camera(
                    at:
                        time,
                    keyframes:
                        studio.cameraKeyframes,
                    duration:
                        studio.animationDuration
                )
        {
            result.savedCamera =
                camera
        }

        if animationPlaying {
            result.transformMode =
                .navigate
        }

        return result
    }

    private var animationScrubberBinding:
        Binding<Double>
    {
        Binding(
            get: {
                animationDisplayTime
            },
            set: {
                value in

                stopAnimationPlayback(
                    persist:
                        false
                )

                let next =
                    BookStudioAnimationMath
                    .normalizedTime(
                        value,
                        duration:
                            studio
                            .animationDuration
                    )

                animationRuntimeTime =
                    next

                studio.animationPlayhead =
                    next
            }
        )
    }

    private var animationDurationBinding:
        Binding<Double>
    {
        Binding(
            get: {
                studio.animationDuration
            },
            set: {
                value in

                let next =
                    min(
                        120,
                        max(
                            0.25,
                            value.isFinite
                            ? value
                            : 6
                        )
                    )

                studio.animationDuration =
                    next

                studio.animationPlayhead =
                    min(
                        next,
                        max(
                            0,
                            studio.animationPlayhead
                        )
                    )

                animationRuntimeTime =
                    min(
                        next,
                        max(
                            0,
                            animationRuntimeTime
                        )
                    )

                studio.cameraKeyframes =
                    studio.cameraKeyframes
                    .map {
                        $0.normalized(
                            duration:
                                next
                        )
                    }
                    .sorted {
                        if $0.time == $1.time {
                            return $0.id.uuidString
                                < $1.id.uuidString
                        }

                        return $0.time
                            < $1.time
                    }
            }
        )
    }
    private var project: CoverProject? { printProjects.first(where: { $0.id == projectID }) ?? printProjects.first(where: { $0.id == document.metadata.activeCoverProjectID }) ?? printProjects.first }

    private var productionBindingSelection:
        Binding<BookBinding>
    {
        Binding(
            get: { project?.productionBinding ?? studio.binding },
            set: {
                value in

                studio.binding =
                    value

                synchronizeProductionBinding(
                    value
                )
                  comparisonBinding = nil
                  comparisonProjectID = nil
            }
        )
    }
    static func focusTarget(
        for component:
            BookSceneComponent?
    ) -> BookFocusTarget? {
        switch component {
        case .front:
            return .front

        case .spine:
            return .spine

        case .back:
            return .back

        default:
            return nil
        }
    }

    private func applyRequestedSurfaceFocus() {
        guard
            focusRequestID != nil,
            let component =
                requestedFocusComponent,
            let target =
                Self.focusTarget(
                    for:
                        component
                )
        else {
            return
        }

        selectedComponent =
            component

        if component == .front
            || component == .spine
            || component == .back
        {
            studio.open =
                false
        }

        focusTarget =
            target

        cameraZoomScale =
            1

        focusGeneration +=
            1
    }


    private func viewportPresentation(secondary: Bool) -> BookStudioPresentation {
        var result = animationPresentation
        if secondary { result.savedCamera = comparisonCamera }
        return result
    }

    private func inspectionViewport(_ project: CoverProject, binding previewBinding: BookBinding, secondary: Bool) -> some View {
        BookPreviewSceneView(project: project, workingLayers: workingLayers, binding: previewBinding, isOpen: isOpen, openAngle: openAngle,
                                             pageCount: pageCount, spreadIndex: spreadIndex,
                                             turnTransition: pageTurnState.activeTransition, turnTexture: pageTurnTexture,
                                             turnReverseTexture: pageTurnReverseTexture,
                                             turnGeneration: pageTurnGeneration,
                                             leftPage: spread.leftPage, rightPage: spread.rightPage,
                                             leftTexture: spread.leftPage.flatMap { previewTexture(for: $0) }, rightTexture: spread.rightPage.flatMap { previewTexture(for: $0) },
                                             showMargins: showMargins, thumbMode: thumbMode,
                                             leftPageSettings: pageSettings(for: spread.leftPage ?? spread.rightPage ?? 1),
                                             rightPageSettings: pageSettings(for: spread.rightPage ?? spread.leftPage ?? 1),
                                             preset: viewPreset, revisionID: document.revisionID, resetGeneration: resetGeneration,
                                             focusGeneration: focusGeneration, focus: focusTarget, zoomAction: zoomAction, zoomGeneration: zoomGeneration, zoomDisplayScale: $cameraZoomScale,
                                             presentation: viewportPresentation(secondary: secondary), modelTransform: $studio.modelTransform,
                                             transformMode: $studio.transformMode, transformSpace: $studio.transformSpace,
                                             customLights: $studio.customLights, selectedCustomLightID: $selectedCustomLightID,
                                             savedCamera: secondary ? $comparisonCamera : $studio.savedCamera, selection: $selectedComponent, viewportHandle: secondary ? comparisonHandle : viewportHandle,
                                             inspection: inspection, cameraLink: compareSideBySide ? comparisonCameraLink : nil,
                                             isComparisonViewport: secondary)
            .frame(minWidth: compareSideBySide ? 200 : 360, minHeight: 360)
            .accessibilityLabel(secondary ? "Hardcover comparison viewport" : "3D book preview")
            .accessibilityIdentifier(secondary ? "bookstudio.comparison" : "bookstudio.viewport")
            .overlay(alignment: .topLeading) {
                if compareSideBySide {
                    Text(previewBinding == .softcover ? "Paperback" : "Hardcover")
                        .font(.caption.bold()).padding(8).background(.regularMaterial)
                        .allowsHitTesting(false)
                } else if studio.showMeasurements {
                    VStack(alignment: .leading) {
                        Text("Trim \(format(project.trimWidth, places: 2)) × \(format(project.trimHeight, places: 2)) in")
                        Text("Spine \(format(project.spineWidth, places: 3)) in · \(pageCount) pages")
                        Text(spreadLabel)
                    }.font(.caption.monospaced()).padding(8).background(.regularMaterial).allowsHitTesting(false)
                }
            }
    }

    private var productionTemplateSelection:
        Binding<BookProductionTemplate>
    {
        Binding(
            get: {
                guard
                    let project
                else {
                    return .custom
                }

                return BookProductionTemplate
                    .inferred(
                        from:
                            project
                    )
            },
            set: {
                template in

                applyProductionTemplate(
                    template
                )
            }
        )
    }

    private var spreadIndex: Int { pageTurnState.spreadIndex }
    private var pageTurnActive: Bool { pageTurnState.activeTransition != nil }
    private var spread: BookSpread { PhysicalBookGeometry.spread(at: spreadIndex, pageCount: pageCount) }
    private var allInteriorImageIssues:
        [PhysicalBookInteriorImageResolutionIssue] {

        interiorImageIssuesByPage
            .values
            .flatMap {
                $0
            }
            .sorted {
                if $0.pageNumber
                    != $1.pageNumber {

                    return $0.pageNumber
                        < $1.pageNumber
                }

                return $0.effectiveDPI
                    < $1.effectiveDPI
            }
    }

    private var interiorImageIssuePages:
        [Int] {

        Array(
            Set(
                allInteriorImageIssues
                    .map(
                        \.pageNumber
                    )
            )
        )
        .sorted()
    }

    private var currentInspectionPage:
        Int {

        spread.rightPage
        ?? spread.leftPage
        ?? 1
    }


    private var marginIssuePages:
        [Int] {

        marginIssuesByPage
            .keys
            .sorted()
    }

    private var activeThumbIssuesByPage:
        [Int: String] {

        guard thumbMode != .off else {
            return [:]
        }

        return thumbMode == .standard
            ? standardThumbIssuesByPage
            : compactThumbIssuesByPage
    }

    private var thumbIssuePages:
        [Int] {

        activeThumbIssuesByPage
            .keys
            .sorted()
    }


    // BOLD_LIGHT_WORKSPACE_V14
    var body: some View {
        boldLight3DStudioBody
            .preferredColorScheme(.light)
            .focusedSceneValue(\.studioWorkspaceMenus, isActive ? AnyView(nativeStudioMenuItems) : nil)
            .focusedSceneValue(\.studioUndoActions, isActive ? StudioUndoActions(manager: undoManager) : nil)
    }

    @ViewBuilder private var nativeStudioMenuItems: some View {
        Toggle("Open Book",isOn:$studio.open)
        Menu("Camera") {
            ForEach(BookViewPreset.allCases) { selectedPreset in
                Button {
                    chooseCameraPreset(selectedPreset)
                } label: {
                    if studio.cameraPreset == selectedPreset {
                        Label(
                            selectedPreset.rawValue,
                            systemImage: "checkmark"
                        )
                    } else {
                        Text(selectedPreset.rawValue)
                    }
                }
            }
        }
        Button("Previous Spread") { moveSpread(-1) }.disabled(!studio.open || spreadIndex <= 0)
        Button("Next Spread") { moveSpread(1) }.disabled(!studio.open || spreadIndex >= pageCount/2)
        Divider()
        Toggle("Show Cover Bleed / Wrap",isOn:Binding(get:{studio.showProductionMargins == true},set:{studio.showProductionMargins=$0}))
        Picker("Lighting",selection:$studio.lighting) { ForEach(BookLightingPreset.allCases) { Text($0.rawValue).tag($0) } }
        Button("Edit in Cover Creator") { if let id=projectID { onEditCover(id,nil) } }
    }

    @ViewBuilder
    private var boldLight3DStudioBody: some View {
        VStack(spacing: 0) {
            if isActive {
            BookWorkspaceSwitcher(current: .bookStudio3D) { destination in
                switch destination {
                case .coverCreator:
                    onEditCover(
                        project?.id
                        ?? document.metadata.activeCoverProjectID
                        ?? UUID(),
                        nil
                    )
                case .bookStudio3D: break
                case .automationStudio: onOpenAutomationStudio()
                case .manuscript:
                    let page =
                        currentInspectionPage

                    onEditManuscript(
                        page,
                        pageRange(
                            for:
                                page
                        )
                    )
                }
            }
            ScrollView(.horizontal) { HStack {
                Picker("Print Full Wrap", selection: $projectID) {
                    ForEach(printProjects) { item in Text(item.name).tag(Optional(item.id)) }
                }.labelsHidden().frame(width: 165).accessibilityLabel("Print Full Wrap project")
                Picker("Cover preview mode", selection: $workingLayers) {
                    Text("Print Result").tag(false); Text("Working Layers").tag(true)
                }.labelsHidden().pickerStyle(.segmented).frame(width: 205).accessibilityLabel("Cover preview mode")
                Picker(
                    "Book state",
                    selection:
                        Binding(
                            get: {
                                studio.open
                            },
                            set: {
                                value in

                                studio.open =
                                    value

                                if value {
                                    studio.openAngle =
                                        max(
                                            studio.openAngle,
                                            160
                                        )

                                    studio.cameraPreset =
                                        .reading
                                } else if studio.cameraPreset == .reading {
                                    studio.cameraPreset =
                                        .front
                                }
                            }
                        )
                ) {
                    Text("Closed")
                        .tag(false)

                    Text("Open Book")
                        .tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 145)
                .accessibilityLabel("Book state")
                Menu("3D Compare") {
                    Toggle("Side-by-side comparison", isOn: $compareSideBySide)
                    Toggle("Synchronize cameras", isOn: $synchronizeCameras)
                    Divider()
                    Button("Match Original Cover") {
                        compareSideBySide = false
                        comparisonBinding = nil
                        comparisonProjectID = nil
                        studio.savedCamera = nil
                        resetGeneration += 1
                    }

                    Divider()

                    Button("Preview Paperback") {
                        comparisonBinding = .softcover
                        comparisonProjectID = project?.id
                        studio.savedCamera = nil
                        resetGeneration += 1
                    }

                    Button("Preview Hardcover") {
                        comparisonBinding = .hardcover
                        comparisonProjectID = project?.id
                        studio.savedCamera = nil
                        resetGeneration += 1
                    }
                }
                .accessibilityLabel("Compare physical binding without changing cover artwork")
                .onChange(of: synchronizeCameras) { _, enabled in
                    comparisonCameraLink.enabled = enabled
                    if enabled { comparisonCamera = studio.savedCamera }
                }
                .onChange(of: compareSideBySide) { _, _ in
                    comparisonCamera = studio.savedCamera
                    resetGeneration += 1
                }
                .onChange(of: project?.id) { _, _ in
                    compareSideBySide = false; comparisonCamera = nil
                    inspection = BookInspectionState()
                }
                Toggle("Print Danger", isOn: $inspection.danger).toggleStyle(.button)
                Toggle("X-Ray", isOn: $inspection.anatomy).toggleStyle(.button)
                    .onChange(of: inspection.anatomy) { _, _ in studio.exploded = false }

                if let sourceBinding = project?.productionBinding,
                   BookBindingPreviewComparison.isMismatch(
                       original: sourceBinding,
                       displayed: binding
                   ) {
                    Label("Template mismatch", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .help("Cover artwork remains " + sourceBinding.rawValue
                              + "; 3D book is " + binding.rawValue
                              + ". Select Match Original Cover to restore alignment.")
                }
                Picker("Binding", selection: productionBindingSelection) { ForEach(BookBinding.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().pickerStyle(.segmented).frame(width: 180).accessibilityLabel("Book binding")
                Menu("Book Views") {
                    Button("Readable Spread") {
                        studio = BookStudioQuickView.readableSpread.apply(to: studio)
                        focusTarget = .automatic
                        focusGeneration += 1
                        cameraZoomScale = 1
                        resetGeneration += 1
                    }
                    Button("Inspect Book Thickness") {
                        studio = BookStudioQuickView.inspectThickness.apply(to: studio)
                        focusTarget = .automatic
                        focusGeneration += 1
                        cameraZoomScale = 1
                        resetGeneration += 1
                    }
                }
                .accessibilityLabel("Quick physical book views")
                Menu("Pose") {
                    Button("Closed") {
                        studio.open = false
                        chooseCameraPreset(.front)
                    }
                    Button("Slightly Open") {
                        studio.open = true
                        studio.openAngle = 25
                        chooseCameraPreset(.reading)
                    }
                    Button("Reading") {
                        studio.open = true
                        studio.openAngle = 160
                        chooseCameraPreset(.reading)
                    }
                    Button("Flat / Open") {
                        studio.open = true
                        studio.openAngle = 180
                        chooseCameraPreset(.reading)
                    }
                }.accessibilityLabel("Book opening pose")
                if isOpen { Slider(value: $studio.openAngle, in: BookStudioPresentation.openingAngleRange, step: 1) { Text("Open angle") }.frame(width: 180).accessibilityLabel("Book open angle"); Text("\(Int(openAngle))°").font(.system(.caption, design: .monospaced)) }
                Spacer()
                // Explicit camera menu commands ensure that selecting
                // the currently active preset still resets the camera.
                Menu {
                    ForEach(BookViewPreset.allCases) { selectedPreset in
                        Button {
                            chooseCameraPreset(selectedPreset)
                        } label: {
                            if studio.cameraPreset == selectedPreset {
                                Label(
                                    selectedPreset.rawValue,
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(selectedPreset.rawValue)
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(studio.cameraPreset.rawValue)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.caption)
                    }
                }
                .accessibilityLabel("View Preset")
                .frame(width: 170)
                    .onChange(of: studio.cameraPreset) { _, _ in studio.savedCamera = nil; focusTarget = .automatic; focusGeneration += 1; cameraZoomScale = 1; resetGeneration += 1 }
                Button { studio.savedCamera = nil; focusTarget = .automatic; focusGeneration += 1; cameraZoomScale = 1; resetGeneration += 1 } label: { Image(systemName: "arrow.counterclockwise") }.keyboardShortcut("0", modifiers: []).accessibilityLabel("Reset book preview view").help("Reset the camera to the selected preset")
                Button("−") { zoomAction = .out; zoomGeneration += 1 }.accessibilityLabel("Zoom out of book preview")
                Button("+") { zoomAction = .in; zoomGeneration += 1 }.accessibilityLabel("Zoom in on book preview")
                Text("\(Int((cameraZoomScale * 100).rounded()))%")
                    .font(.system(.caption, design: .monospaced)).frame(width: 42)
                    .accessibilityLabel("Preview zoom \(Int((cameraZoomScale * 100).rounded())) percent")
                    .onChange(of: zoomGeneration) { _, _ in cameraZoomScale = zoomAction == .in ? min(4, cameraZoomScale * 1.25) : max(0.5, cameraZoomScale / 1.25) }
                Button("Fit") { studio.savedCamera = nil; zoomAction = .fit; cameraZoomScale = 1; resetGeneration += 1 }.accessibilityLabel("Fit book preview")
            }.padding(12) }
            Divider()
            if let project {
                HStack(spacing: 0) {
                    scenePanel(project).frame(width: 175)
                    Divider()
                    VStack(spacing: 0) {
                        HStack(spacing: 1) {
                            inspectionViewport(project, binding: compareSideBySide ? .softcover : binding, secondary: false)
                            if compareSideBySide {
                                Divider()
                                inspectionViewport(project, binding: .hardcover, secondary: true)
                            }
                        }
                        if isOpen {
                            HStack {
                                Button { jumpToSpread(0) } label: { Image(systemName: "backward.end.fill") }
                                    .accessibilityLabel("First spread")
                                    .disabled(pageTurnActive || spreadIndex == 0)
                                Button("Previous Spread") { moveSpread(-1) }.keyboardShortcut(.leftArrow, modifiers: []).disabled(pageTurnActive || spreadIndex == 0)
                                Text(spreadLabel).frame(minWidth: 150)
                                Button("Next Spread") { moveSpread(1) }.keyboardShortcut(.rightArrow, modifiers: []).disabled(pageTurnActive || spreadIndex >= pageCount / 2)
                                Button { jumpToSpread(pageCount / 2) } label: { Image(systemName: "forward.end.fill") }
                                    .accessibilityLabel("Last spread")
                                    .disabled(pageTurnActive || pageCount == 0 || spreadIndex >= pageCount / 2)
                                Spacer()
                                TextField("Page", text: $pageEntry.text).frame(width: 55).accessibilityLabel("Go to manuscript page").focused($pageEntryFocused).onSubmit { jumpToEnteredPage() }.disabled(pageTurnActive)
                                Button("Go") { jumpToEnteredPage() }.disabled(pageTurnActive || pageEntry.resolvedPage(pageCount:pageCount) == nil)
                            }.padding(10).background(.bar)
                        }
                        HStack(spacing: 8) {
                            Text("Focus")
                            ForEach(BookFocusTarget.allCases) { target in
                                Button(target.rawValue) {
                                    switch target {
                                    case .front, .spine, .back: studio.open = false
                                    case .spread, .text:
                                        studio.open = true
                                        studio.openAngle = 180
                                        studio.cameraPreset = .reading
                                    case .automatic: break
                                    }
                                    studio.savedCamera = nil; focusTarget = target; focusGeneration += 1; cameraZoomScale = 1
                                }
                                    .buttonStyle(.bordered).controlSize(.small)
                            }
                        }.padding(.horizontal, 10).padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
                    }
                    Divider()
                    inspector(project).frame(width: 300).padding(14)
                }
            } else {
                ContentUnavailableView(
                    "No Print Full Wrap Cover",
                    systemImage: "book.closed",
                    description: Text("A printed book needs front, spine, and back artwork. Open Cover Creator and choose New Print Wrap. Your manuscript remains in this document.")
                )
                Button("Open Cover Creator") {
                    onEditCover(
                        document.metadata.activeCoverProjectID
                        ?? UUID(),
                        nil
                    )
                }
                    .padding(.bottom, 20)
            }
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .onChange(of: focusRequestID) { _, requestID in

            guard requestID != nil else { return }

            applyRequestedSurfaceFocus()

        }

        .onAppear {
            restoreExistingArtworkFor3D()
            applyRequestedSurfaceFocus()
            studio = (document.metadata.bookStudioPresentation ?? BookStudioPresentation()).normalized(pageCount: Int.max)
            studioRestored = true
        }
        .onChange(of: studio) { _, value in
            guard studioRestored else { return }
            document.metadata.bookStudioPresentation = value
        }
        .onChange(of: spreadIndex) { _, _ in
            if !pageEntryFocused { pageEntry.synchronize(spreadIndex:spreadIndex,pageCount:pageCount) }
        }
        .onChange(of: pageCount) { _, _ in
            if !pageEntryFocused { pageEntry.synchronize(spreadIndex:spreadIndex,pageCount:pageCount) }
        }
        .task(id: "\(document.revisionID.uuidString)-\(isActive)") {
            guard isActive else { return }
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            refresh()
        }
        .onDisappear {
            // A document can keep its workspaces cached while another one is
            // active. Invalidate in-flight render completions and release the
            // PDF/page/SceneKit resources instead of relying on SwiftUI state
            // destruction to free Core Graphics and IOSurface allocations.
            renderRequestID = UUID()
            isRendering = false
            if let previewPDFURL { try? FileManager.default.removeItem(at: previewPDFURL) }
            previewPDFURL = nil
            previewPDF = nil
            pageTextureCache.reset()
            pageTextureDecorator.reset()
            pendingPageTextures.removeAll()
            pageTurnState.reset()
            pageTurnTexture = nil
            pageTurnReverseTexture = nil
            paginatedPageSettings = []
            paginatedPageRanges = []
            interiorImageIssuesByPage = [:]
            marginIssuesByPage = [:]
            standardThumbIssuesByPage = [:]
            compactThumbIssuesByPage = [:]
            viewportHandle.releasePreviewResources()
        }
    }

    private func pageRange(
        for pageNumber:
            Int
    ) -> NSRange? {
        guard
            pageNumber > 0,
            pageNumber <=
                paginatedPageRanges.count
        else {
            return nil
        }

        return paginatedPageRanges[
            pageNumber - 1
        ]
    }

    private var spreadLabel: String {
        guard pageCount > 0 else { return "Paginating…" }
        let left = spread.leftPage.map(String.init) ?? "Inside cover"
        let right = spread.rightPage.map(String.init) ?? "End"
        return "Spread \(spread.index + 1) · \(left) / \(right) of \(pageCount)"
    }


    private func selectSceneComponent(
        _ component: BookSceneComponent
    ) {
        selectedComponent =
            component

        selectedCustomLightID =
            nil

        if component == .front
            || component == .back
            || component == .spine
        {
            studio.open =
                false
        }

        if component == .leftPage
            || component == .rightPage
        {
            studio.open =
                true

            studio.openAngle =
                180
        }
    }

    private func moveSelectedCustomLight(
        by offset: Int
    ) {
        guard
            let selectedCustomLightID
        else {
            return
        }

        studio.customLights =
            BookStudioLightOrder
            .moved(
                studio.customLights,
                id:
                    selectedCustomLightID,
                offset:
                    offset
            )
    }

    private func canMoveSelectedCustomLight(
        by offset: Int
    ) -> Bool {
        guard
            let selectedCustomLightID
        else {
            return false
        }

        return BookStudioLightOrder
            .canMove(
                studio.customLights,
                id:
                    selectedCustomLightID,
                offset:
                    offset
            )
    }

    private func scenePanel(
        _ project: CoverProject
    ) -> some View {
        VStack(
            alignment: .leading,
            spacing: 8
        ) {
            HStack {
                Text("Scene")
                    .font(.headline)

                Spacer()

                Text(
                    "\(studio.customLights.count) custom"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(
                .horizontal,
                10
            )
            .padding(
                .top,
                12
            )

            ScrollView {
                VStack(
                    alignment: .leading,
                    spacing: 6
                ) {
                    DisclosureGroup(
                        isExpanded:
                            $studio
                            .outlinerBookExpanded
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            ForEach(
                                [
                                    BookSceneComponent.front,
                                    .back,
                                    .spine,
                                    .pages,
                                    .leftPage,
                                    .rightPage
                                ]
                            ) { component in
                                Button {
                                    selectSceneComponent(
                                        component
                                    )
                                } label: {
                                    HStack(
                                        spacing: 7
                                    ) {
                                        Image(
                                            systemName:
                                                sceneIcon(
                                                    component
                                                )
                                        )
                                        .frame(
                                            width: 18
                                        )

                                        Text(
                                            component.rawValue
                                        )

                                        Spacer()
                                    }
                                    .padding(
                                        .leading,
                                        18
                                    )
                                    .padding(
                                        .vertical,
                                        5
                                    )
                                    .contentShape(
                                        Rectangle()
                                    )
                                    .background(
                                        selectedComponent
                                            == component
                                        && selectedCustomLightID
                                            == nil
                                        ? Color.accentColor
                                            .opacity(
                                                0.17
                                            )
                                        : Color.clear,
                                        in:
                                            RoundedRectangle(
                                                cornerRadius: 6
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } label: {
                        HStack(
                            spacing: 5
                        ) {
                            Button {
                                selectSceneComponent(
                                    .book
                                )
                            } label: {
                                Label(
                                    "Book",
                                    systemImage:
                                        "book.closed"
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    alignment:
                                        .leading
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                studio
                                    .bookEditorVisible
                                    .toggle()
                            } label: {
                                Image(
                                    systemName:
                                        studio
                                        .bookEditorVisible
                                        ? "eye"
                                        : "eye.slash"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                studio
                                    .bookTransformLocked
                                    .toggle()
                            } label: {
                                Image(
                                    systemName:
                                        studio
                                        .bookTransformLocked
                                        ? "lock.fill"
                                        : "lock.open"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Divider()

                    DisclosureGroup(
                        isExpanded:
                            $studio
                            .outlinerEnvironmentExpanded
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Button {
                                selectSceneComponent(
                                    .environment
                                )
                            } label: {
                                HStack(
                                    spacing: 7
                                ) {
                                    Image(
                                        systemName:
                                            "sun.max"
                                    )
                                    .frame(
                                        width: 18
                                    )

                                    Text(
                                        "Environment"
                                    )

                                    Spacer()
                                }
                                .padding(
                                    .leading,
                                    18
                                )
                                .padding(
                                    .vertical,
                                    5
                                )
                                .contentShape(
                                    Rectangle()
                                )
                            }
                            .buttonStyle(.plain)

                            HStack(
                                spacing: 5
                            ) {
                                Button {
                                    selectSceneComponent(
                                        .environment
                                    )
                                } label: {
                                    HStack(
                                        spacing: 7
                                    ) {
                                        Image(
                                            systemName:
                                                "square.3.layers.3d.down.right"
                                        )
                                        .frame(
                                            width: 18
                                        )

                                        Text(
                                            "Ground"
                                        )

                                        Spacer()
                                    }
                                }
                                .buttonStyle(.plain)

                                Button {
                                    studio
                                        .groundEditorVisible
                                        .toggle()
                                } label: {
                                    Image(
                                        systemName:
                                            studio
                                            .groundEditorVisible
                                            ? "eye"
                                            : "eye.slash"
                                    )
                                }
                                .buttonStyle(.plain)

                                Button {
                                    studio
                                        .groundEditorLocked
                                        .toggle()
                                } label: {
                                    Image(
                                        systemName:
                                            studio
                                            .groundEditorLocked
                                            ? "lock.fill"
                                            : "lock.open"
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(
                                .leading,
                                18
                            )
                            .padding(
                                .vertical,
                                5
                            )
                        }
                    } label: {
                        Label(
                            "Environment",
                            systemImage:
                                "globe.americas"
                        )
                    }

                    Divider()

                    DisclosureGroup(
                        isExpanded:
                            $studio
                            .outlinerLightingExpanded
                    ) {
                        VStack(
                            alignment: .leading,
                            spacing: 2
                        ) {
                            Button {
                                selectedComponent =
                                    .lights

                                selectedCustomLightID =
                                    nil
                            } label: {
                                HStack(
                                    spacing: 7
                                ) {
                                    Image(
                                        systemName:
                                            "lightbulb"
                                    )
                                    .frame(
                                        width: 18
                                    )

                                    Text(
                                        "Built-in Lights"
                                    )

                                    Spacer()
                                }
                                .padding(
                                    .leading,
                                    18
                                )
                                .padding(
                                    .vertical,
                                    5
                                )
                            }
                            .buttonStyle(.plain)

                            HStack {
                                Text(
                                    "Custom Lights"
                                )
                                .font(.caption)
                                .foregroundStyle(
                                    .secondary
                                )

                                Spacer()

                                Menu {
                                    Button(
                                        "Point Light"
                                    ) {
                                        addCustomLight(
                                            .point
                                        )
                                    }

                                    Button(
                                        "Spot Light"
                                    ) {
                                        addCustomLight(
                                            .spot
                                        )
                                    }
                                } label: {
                                    Image(
                                        systemName:
                                            "plus"
                                    )
                                }
                                .menuStyle(
                                    .borderlessButton
                                )
                            }
                            .padding(
                                .leading,
                                18
                            )

                            ForEach(
                                studio.customLights
                            ) { light in
                                HStack(
                                    spacing: 5
                                ) {
                                    Button {
                                        selectedComponent =
                                            .lights

                                        selectedCustomLightID =
                                            light.id
                                    } label: {
                                        HStack(
                                            spacing: 7
                                        ) {
                                            Image(
                                                systemName:
                                                    light.type
                                                        == .point
                                                    ? "lightbulb.fill"
                                                    : "flashlight.on.fill"
                                            )
                                            .frame(
                                                width: 18
                                            )

                                            Text(
                                                light.name
                                            )
                                            .lineLimit(1)

                                            if !light.enabled {
                                                Image(
                                                    systemName:
                                                        "bolt.slash"
                                                )
                                                .font(
                                                    .caption2
                                                )
                                                .foregroundStyle(
                                                    .secondary
                                                )
                                            }

                                            Spacer()
                                        }
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        guard
                                            let index =
                                                studio
                                                .customLights
                                                .firstIndex(
                                                    where: {
                                                        $0.id
                                                        == light.id
                                                    }
                                                )
                                        else {
                                            return
                                        }

                                        studio
                                            .customLights[
                                                index
                                            ]
                                            .editorVisible
                                            .toggle()
                                    } label: {
                                        Image(
                                            systemName:
                                                light.editorVisible
                                                ? "eye"
                                                : "eye.slash"
                                        )
                                    }
                                    .buttonStyle(.plain)

                                    Button {
                                        guard
                                            let index =
                                                studio
                                                .customLights
                                                .firstIndex(
                                                    where: {
                                                        $0.id
                                                        == light.id
                                                    }
                                                )
                                        else {
                                            return
                                        }

                                        studio
                                            .customLights[
                                                index
                                            ]
                                            .locked
                                            .toggle()
                                    } label: {
                                        Image(
                                            systemName:
                                                light.locked
                                                ? "lock.fill"
                                                : "lock.open"
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                                .padding(
                                    .leading,
                                    18
                                )
                                .padding(
                                    .vertical,
                                    5
                                )
                                .background(
                                    selectedCustomLightID
                                        == light.id
                                    ? Color.accentColor
                                        .opacity(
                                            0.17
                                        )
                                    : Color.clear,
                                    in:
                                        RoundedRectangle(
                                            cornerRadius: 6
                                        )
                                )
                            }
                        }
                    } label: {
                        Label(
                            "Lighting",
                            systemImage:
                                "lightbulb.2"
                        )
                    }

                    Divider()

                    DisclosureGroup(
                        isExpanded:
                            $studio
                            .outlinerCameraExpanded
                    ) {
                        HStack(
                            spacing: 5
                        ) {
                            Button {
                                selectSceneComponent(
                                    .camera
                                )
                            } label: {
                                Label(
                                    "Camera",
                                    systemImage:
                                        "camera"
                                )
                                .frame(
                                    maxWidth:
                                        .infinity,
                                    alignment:
                                        .leading
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                studio
                                    .cameraEditorVisible
                                    .toggle()
                            } label: {
                                Image(
                                    systemName:
                                        studio
                                        .cameraEditorVisible
                                        ? "eye"
                                        : "eye.slash"
                                )
                            }
                            .buttonStyle(.plain)

                            Button {
                                studio
                                    .cameraEditorLocked
                                    .toggle()
                            } label: {
                                Image(
                                    systemName:
                                        studio
                                        .cameraEditorLocked
                                        ? "lock.fill"
                                        : "lock.open"
                                )
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(
                            .leading,
                            18
                        )
                        .padding(
                            .vertical,
                            5
                        )
                    } label: {
                        Label(
                            "Camera",
                            systemImage:
                                "video"
                        )
                    }
                }
                .padding(
                    .horizontal,
                    6
                )
            }

            if selectedCustomLightID != nil {
                HStack(
                    spacing: 6
                ) {
                    Button {
                        moveSelectedCustomLight(
                            by:
                                -1
                        )
                    } label: {
                        Image(
                            systemName:
                                "arrow.up"
                        )
                    }
                    .disabled(
                        !canMoveSelectedCustomLight(
                            by:
                                -1
                        )
                    )

                    Button {
                        moveSelectedCustomLight(
                            by:
                                1
                        )
                    } label: {
                        Image(
                            systemName:
                                "arrow.down"
                        )
                    }
                    .disabled(
                        !canMoveSelectedCustomLight(
                            by:
                                1
                        )
                    )

                    Button(
                        "Duplicate"
                    ) {
                        duplicateSelectedCustomLight()
                    }

                    Button(
                        "Delete"
                    ) {
                        deleteSelectedCustomLight()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .padding(
                    .horizontal,
                    8
                )
            } else if
                let actionTitle =
                    selectedProductionEditTitle
            {
                Button(
                    actionTitle
                ) {
                    editSelectedProductionComponent(
                        project
                    )
                }
                .buttonStyle(
                    .borderedProminent
                )
                .controlSize(.small)
                .padding(
                    .horizontal,
                    8
                )
                .accessibilityLabel(
                    actionTitle
                )
            }

            Text(
                "\(project.trimWidth, specifier: "%.2f") × \(project.trimHeight, specifier: "%.2f") in"
            )
            .font(
                .system(
                    .caption,
                    design:
                        .monospaced
                )
            )
            .foregroundStyle(
                .secondary
            )
            .padding(10)
        }
        .background(.bar)
    }

    private var selectedProductionEditTitle: String? {
        guard let selectedComponent else {
            return nil
        }

        switch selectedComponent {
        case .book, .front, .back, .spine:
            return "Edit in Cover Creator"

        case .pages, .leftPage, .rightPage:
            return "Edit Manuscript"

        case .environment, .lights, .camera:
            return nil
        }
    }

    private func editSelectedProductionComponent(
        _ project:
            CoverProject
    ) {
        guard
            let selectedComponent,
            let route =
                BookStudioProductionRouting
                    .editRoute(
                        for:
                            selectedComponent,
                        spread:
                            spread
                    )
        else {
            return
        }

        switch route {
        case .cover(
            let panel
        ):
            onEditCover(
                project.id,
                panel
            )

        case .manuscript(
            let pageNumber
        ):
            onEditManuscript(
                pageNumber,
                pageRange(
                    for:
                        pageNumber
                )
            )
        }
    }

    private func sceneIcon(_ component: BookSceneComponent) -> String {
        switch component {
        case .book: "book.closed"
        case .front, .back: "book"
        case .spine: "rectangle.portrait"
        case .pages, .leftPage, .rightPage: "doc.text"
        case .environment: "sun.max"
        case .lights: "lightbulb"
        case .camera: "camera"
        }
    }

    private func exportBookMockup() {
        let view = viewportHandle.view
        let customSize = BookStudioRenderDimensions(width: customRenderWidth, height: customRenderHeight)
        if renderSize == .custom && customSize == nil {
            renderError = "Custom render dimensions must be 256–6000 pixels per side and at most 24 megapixels."
            return
        }
        let pixels = renderSize.resolvedPixels(viewportSize: view?.bounds.size ?? .zero,
                                               backingScale: view?.window?.backingScaleFactor ?? 2,
                                               customSize: customSize)
        guard let image = viewportHandle.image(size: pixels,
                                               transparent: transparentBackground && !exportJPEG,
                                               highQualityCover: true),
              let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(
                using: exportJPEG ? .jpeg : .png,
                properties: exportJPEG ? [.compressionFactor: 0.92] : [:]
              ) else {
            renderError = "The 3D view could not be rendered as an image."
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [exportJPEG ? .jpeg : .png]
        panel.nameFieldStringValue = "BOLD Writer Book Mockup.\(exportJPEG ? "jpg" : "png")"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try data.write(to: url, options: .atomic)
            renderError = nil
        } catch {
            renderError = error.localizedDescription
        }
    }


    @ViewBuilder

    private var selectedCustomLightBinding:
        Binding<BookStudioLight>?
    {
        guard
            let selectedCustomLightID,
            let index =
                studio.customLights
                .firstIndex(
                    where: {
                        $0.id
                        == selectedCustomLightID
                    }
                )
        else {
            return nil
        }

        return Binding(
            get: {
                guard
                    index
                    < studio.customLights.count
                else {
                    return BookStudioLight
                        .point()
                }

                return studio
                    .customLights[
                        index
                    ]
            },
            set: {
                value in

                guard
                    index
                    < studio.customLights.count
                else {
                    return
                }

                studio.customLights[
                    index
                ] =
                    value.normalized
            }
        )
    }

    private func addCustomLight(
        _ type: BookStudioLightType
    ) {
        let baseName =
            type == .point
            ? "Point Light"
            : "Spot Light"

        let matchingCount =
            studio.customLights
            .filter {
                $0.type == type
            }
            .count

        let name =
            matchingCount == 0
            ? baseName
            : "\(baseName) \(matchingCount + 1)"

        let light =
            type == .point
            ? BookStudioLight.point(
                name: name
            )
            : BookStudioLight.spot(
                name: name
            )

        studio.customLights
            .append(
                light
            )

        selectedComponent =
            .lights

        selectedCustomLightID =
            light.id
    }

    private func duplicateSelectedCustomLight() {
        guard
            let selectedCustomLightID,
            let source =
                studio.customLights
                .first(
                    where: {
                        $0.id
                        == selectedCustomLightID
                    }
                )
        else {
            return
        }

        var duplicate =
            source

        duplicate.id =
            UUID()

        duplicate.name =
            source.name
            + " Copy"

        duplicate.transform.positionX +=
            0.35

        duplicate.transform.positionZ +=
            0.35

        duplicate =
            duplicate.normalized

        studio.customLights
            .append(
                duplicate
            )

        self.selectedCustomLightID =
            duplicate.id

        selectedComponent =
            .lights
    }

    private func deleteSelectedCustomLight() {
        guard
            let selectedCustomLightID
        else {
            return
        }

        studio.customLights
            .removeAll {
                $0.id
                == selectedCustomLightID
            }

        self.selectedCustomLightID =
            nil

        selectedComponent =
            .lights
    }

    @ViewBuilder
    private func customLightInspector(
        _ light: Binding<BookStudioLight>
    ) -> some View {
        GroupBox("Custom Light") {
            VStack(
                alignment: .leading,
                spacing: 9
            ) {
                Picker(
                    "Tool",
                    selection:
                        $studio.transformMode
                ) {
                    Text("Navigate")
                        .tag(
                            BookTransformMode.navigate
                        )

                    Text("Move")
                        .tag(
                            BookTransformMode.move
                        )

                    Text("Rotate")
                        .tag(
                            BookTransformMode.rotate
                        )
                }
                .pickerStyle(
                    .segmented
                )
                .accessibilityLabel(
                    "Custom light transform tool"
                )
                .disabled(
                    light.wrappedValue.locked
                )

                Picker(
                    "Space",
                    selection:
                        $studio.transformSpace
                ) {
                    ForEach(
                        BookTransformSpace.allCases
                    ) {
                        space in

                        Text(
                            space.displayName
                        )
                        .tag(space)
                    }
                }
                .pickerStyle(
                    .segmented
                )
                .disabled(
                    studio.transformMode
                        == .navigate
                )

                Text(
                    "G move · R rotate · V navigate · L local/world"
                )
                .font(
                    .caption2
                )
                .foregroundStyle(
                    .secondary
                )

                TextField(
                    "Name",
                    text:
                        light.name
                )
                .textFieldStyle(
                    .roundedBorder
                )

                Picker(
                    "Type",
                    selection:
                        light.type
                ) {
                    ForEach(
                        BookStudioLightType
                            .allCases
                    ) {
                        type in

                        Text(
                            type.rawValue
                        )
                        .tag(type)
                    }
                }
                .pickerStyle(
                    .segmented
                )

                Toggle(
                    "Enabled",
                    isOn:
                        light.enabled
                )

                Toggle(
                    "Editor Visible",
                    isOn:
                        light.editorVisible
                )

                Toggle(
                    "Lock Transform",
                    isOn:
                        light.locked
                )

                Toggle(
                    "Show Range / Cone Guide",
                    isOn:
                        $studio
                        .lightGuidesVisible
                )

                Text(
                    "Intensity \(Int(light.wrappedValue.intensity))"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

                Slider(
                    value:
                        light.intensity,
                    in:
                        0 ... 5_000,
                    step:
                        25
                )

                HStack {
                    Text("Color")
                        .font(
                            .caption
                        )

                    TextField(
                        "#FFFFFF",
                        text:
                            light.colorHex
                    )
                    .textFieldStyle(
                        .roundedBorder
                    )
                }

                Text(
                    "Range \(light.wrappedValue.range, specifier: "%.1f")"
                )
                .font(.caption)
                .foregroundStyle(
                    .secondary
                )

                Slider(
                    value:
                        light.range,
                    in:
                        0.1 ... 100,
                    step:
                        0.1
                )

                if light.wrappedValue.type
                    == .spot
                {
                    Text(
                        "Spot Inner \(Int(light.wrappedValue.spotInnerAngle))°"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    Slider(
                        value:
                            light
                            .spotInnerAngle,
                        in:
                            0 ... 179,
                        step:
                            1
                    )

                    Text(
                        "Spot Outer \(Int(light.wrappedValue.spotOuterAngle))°"
                    )
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                    Slider(
                        value:
                            light
                            .spotOuterAngle,
                        in:
                            1 ... 179,
                        step:
                            1
                    )
                }

                Toggle(
                    "Cast Shadows",
                    isOn:
                        light
                        .castsShadow
                )

                Divider()

                Text("Position")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                HStack(spacing: 6) {
                    transformField(
                        "X",
                        value:
                            light
                            .transform
                            .positionX
                    )

                    transformField(
                        "Y",
                        value:
                            light
                            .transform
                            .positionY
                    )

                    transformField(
                        "Z",
                        value:
                            light
                            .transform
                            .positionZ
                    )
                }

                Text("Rotation")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                HStack(spacing: 6) {
                    transformField(
                        "X°",
                        value:
                            light
                            .transform
                            .rotationX
                    )

                    transformField(
                        "Y°",
                        value:
                            light
                            .transform
                            .rotationY
                    )

                    transformField(
                        "Z°",
                        value:
                            light
                            .transform
                            .rotationZ
                    )
                }

                HStack {
                    Spacer()

                    Button(
                        "Reset Light Transform"
                    ) {
                        light.wrappedValue
                            .transform =
                            .identity
                    }
                    .controlSize(
                        .small
                    )
                    .disabled(
                        light.wrappedValue.locked
                    )
                }
            }
            .padding(
                .vertical,
                4
            )
        }
    }

    private var transformInspector: some View {
        GroupBox("Transform") {
            VStack(
                alignment: .leading,
                spacing: 8
            ) {
                Picker(
                    "Tool",
                    selection: $studio.transformMode
                ) {
                    ForEach(
                        BookTransformMode.allCases
                    ) { mode in
                        Text(
                            mode.displayName
                        )
                        .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel(
                    "3D transform tool"
                )

                Picker(
                    "Space",
                    selection: $studio.transformSpace
                ) {
                    ForEach(
                        BookTransformSpace.allCases
                    ) { space in
                        Text(
                            space.displayName
                        )
                        .tag(space)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(
                    studio.transformMode
                        == .navigate
                )
                .accessibilityLabel(
                    "3D transform coordinate space"
                )

                Toggle(
                    "Snap",
                    isOn:
                        $studio
                        .transformSnapEnabled
                )
                .accessibilityLabel(
                    "Snap 3D transforms"
                )

                if studio.transformSnapEnabled {
                    Text("Snap Steps")
                        .font(.caption)
                        .foregroundStyle(
                            .secondary
                        )

                    HStack(spacing: 6) {
                        transformField(
                            "Move",
                            value:
                                $studio
                                .moveSnapStep
                        )

                        transformField(
                            "°",
                            value:
                                $studio
                                .rotateSnapStep
                        )

                        transformField(
                            "Scale",
                            value:
                                $studio
                                .scaleSnapStep
                        )
                    }
                }

                Text("G move · R rotate · S scale · V navigate · L local/world · ⌘0 reset")
                    .font(.caption2)
                    .foregroundStyle(
                        .secondary
                    )
                    .fixedSize(
                        horizontal: false,
                        vertical: true
                    )

                Text("Position")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                HStack(spacing: 6) {
                    transformField(
                        "X",
                        value:
                            $studio
                            .modelTransform
                            .positionX
                    )

                    transformField(
                        "Y",
                        value:
                            $studio
                            .modelTransform
                            .positionY
                    )

                    transformField(
                        "Z",
                        value:
                            $studio
                            .modelTransform
                            .positionZ
                    )
                }

                Text("Rotation")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                HStack(spacing: 6) {
                    transformField(
                        "X°",
                        value:
                            $studio
                            .modelTransform
                            .rotationX
                    )

                    transformField(
                        "Y°",
                        value:
                            $studio
                            .modelTransform
                            .rotationY
                    )

                    transformField(
                        "Z°",
                        value:
                            $studio
                            .modelTransform
                            .rotationZ
                    )
                }

                Text("Scale")
                    .font(.caption)
                    .foregroundStyle(
                        .secondary
                    )

                HStack(spacing: 6) {
                    transformField(
                        "X",
                        value:
                            $studio
                            .modelTransform
                            .scaleX
                    )

                    transformField(
                        "Y",
                        value:
                            $studio
                            .modelTransform
                            .scaleY
                    )

                    transformField(
                        "Z",
                        value:
                            $studio
                            .modelTransform
                            .scaleZ
                    )
                }

                HStack {
                    Spacer()

                    Button(
                        "Reset Transform"
                    ) {
                        studio
                            .modelTransform =
                            .identity
                    }
                    .controlSize(.small)
                    .accessibilityLabel(
                        "Reset 3D book transform"
                    )
                }
            }
            .padding(
                .vertical,
                4
            )
        }
    }

    private func transformField(
        _ label: String,
        value: Binding<Double>
    ) -> some View {
        HStack(spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(
                    .secondary
                )

            TextField(
                label,
                value: value,
                format: .number
            )
            .textFieldStyle(
                .roundedBorder
            )
            .frame(
                minWidth: 54
            )
        }
    }


    private func defaultCameraSaved(
        _ project: CoverProject
    ) -> BookSavedCamera {
        BookPreviewCameraMath
            .state(
                project: project,
                open: isOpen,
                preset: viewPreset,
                focus: focusTarget
            )
            .saved
    }

    private func cameraValueBinding(
        _ keyPath: WritableKeyPath<BookSavedCamera, Double>,
        project: CoverProject
    ) -> Binding<Double> {
        Binding(
            get: {
                let camera =
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )

                return camera[
                    keyPath:
                        keyPath
                ]
            },
            set: {
                value in

                guard value.isFinite else {
                    return
                }

                var camera =
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )

                camera[
                    keyPath:
                        keyPath
                ] =
                    value

                if camera.isValid {
                    studio.savedCamera =
                        camera

                    focusTarget =
                        .automatic
                }
            }
        )
    }

    private func cameraDistanceBinding(
        _ project: CoverProject
    ) -> Binding<Double> {
        Binding(
            get: {
                (
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )
                )
                .distance
            },
            set: {
                value in

                guard value.isFinite else {
                    return
                }

                var camera =
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )

                camera.distance =
                    min(
                        30,
                        max(
                            0.35,
                            value
                        )
                    )

                studio.savedCamera =
                    camera

                focusTarget =
                    .automatic
            }
        )
    }

    private func cameraAngleBinding(
        _ keyPath: WritableKeyPath<BookSavedCamera, Double>,
        project: CoverProject,
        clampPitch: Bool = false
    ) -> Binding<Double> {
        Binding(
            get: {
                let camera =
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )

                return camera[
                    keyPath:
                        keyPath
                ]
                * 180
                / .pi
            },
            set: {
                degrees in

                guard degrees.isFinite else {
                    return
                }

                var camera =
                    studio.savedCamera
                    ?? defaultCameraSaved(
                        project
                    )

                var radians =
                    degrees
                    * .pi
                    / 180

                if clampPitch {
                    radians =
                        min(
                            1.52,
                            max(
                                -1.52,
                                radians
                            )
                        )
                }

                camera[
                    keyPath:
                        keyPath
                ] =
                    radians

                if camera.isValid {
                    studio.savedCamera =
                        camera

                    focusTarget =
                        .automatic
                }
            }
        )
    }


    private func toggleAnimationPlayback() {
        if animationPlaying {
            stopAnimationPlayback(
                persist:
                    true
            )

            return
        }

        animationRuntimeTime =
            BookStudioAnimationMath
            .normalizedTime(
                studio.animationPlayhead,
                duration:
                    studio.animationDuration
            )

        if animationRuntimeTime
            >= studio.animationDuration
        {
            animationRuntimeTime =
                0

            studio.animationPlayhead =
                0
        }

        animationPlaying =
            true

        animationPlaybackGeneration +=
            1

        let generation =
            animationPlaybackGeneration

        let startedAt =
            Date()

        let startTime =
            animationRuntimeTime

        Task { @MainActor in
            while
                animationPlaying
                && animationPlaybackGeneration
                    == generation
            {
                let elapsed =
                    Date()
                    .timeIntervalSince(
                        startedAt
                    )

                let duration =
                    max(
                        0.25,
                        studio.animationDuration
                    )

                let rawTime =
                    startTime
                    + elapsed

                if rawTime >= duration {
                    if studio.animationLoop {
                        animationRuntimeTime =
                            rawTime
                            .truncatingRemainder(
                                dividingBy:
                                    duration
                            )
                    } else {
                        animationRuntimeTime =
                            duration

                        studio.animationPlayhead =
                            duration

                        animationPlaying =
                            false

                        animationPlaybackGeneration +=
                            1

                        break
                    }
                } else {
                    animationRuntimeTime =
                        rawTime
                }

                try? await Task<Never, Never>
                    .sleep(
                        nanoseconds:
                            16_666_667
                    )
            }
        }
    }

    private func stopAnimationPlayback(
        persist: Bool
    ) {
        if
            persist,
            animationPlaying
        {
            studio.animationPlayhead =
                BookStudioAnimationMath
                .normalizedTime(
                    animationRuntimeTime,
                    duration:
                        studio.animationDuration
                )
        }

        animationPlaying =
            false

        animationPlaybackGeneration +=
            1
    }

    private func rewindAnimation() {
        stopAnimationPlayback(
            persist:
                false
        )

        animationRuntimeTime =
            0

        studio.animationPlayhead =
            0
    }

    private func currentAnimationCamera(
        _ project: CoverProject
    ) -> BookSavedCamera {
        BookStudioAnimationMath
            .camera(
                at:
                    animationDisplayTime,
                keyframes:
                    studio.cameraKeyframes,
                duration:
                    studio.animationDuration
            )
        ?? studio.savedCamera
        ?? defaultCameraSaved(
            project
        )
    }

    private func addCurrentCameraKeyframe(
        _ project: CoverProject
    ) {
        let time =
            BookStudioAnimationMath
            .normalizedTime(
                animationDisplayTime,
                duration:
                    studio.animationDuration
            )

        let camera =
            currentAnimationCamera(
                project
            )

        if
            let index =
                studio.cameraKeyframes
                .firstIndex(
                    where: {
                        abs(
                            $0.time
                            - time
                        )
                        < 0.000_1
                    }
                )
        {
            studio.cameraKeyframes[
                index
            ]
            .camera =
                camera
        } else {
            studio.cameraKeyframes
                .append(
                    BookStudioCameraKeyframe(
                        time:
                            time,
                        camera:
                            camera
                    )
                )
        }

        studio.cameraKeyframes =
            studio.cameraKeyframes
            .map {
                $0.normalized(
                    duration:
                        studio.animationDuration
                )
            }
            .sorted {
                if $0.time == $1.time {
                    return $0.id.uuidString
                        < $1.id.uuidString
                }

                return $0.time
                    < $1.time
            }
    }

    private func deleteCameraKeyframe(
        _ id: UUID
    ) {
        studio.cameraKeyframes
            .removeAll {
                $0.id == id
            }
    }

    private func moveCameraKeyframe(
        _ id: UUID,
        by offset: Int
    ) {
        studio.cameraKeyframes =
            BookStudioCameraKeyframeOrder
            .moved(
                studio.cameraKeyframes,
                id:
                    id,
                offset:
                    offset
            )
    }


    private func animationExportPixels() -> CGSize? {
        let view =
            viewportHandle.view

        let customSize =
            BookStudioRenderDimensions(
                width:
                    customRenderWidth,
                height:
                    customRenderHeight
            )

        if
            renderSize == .custom,
            customSize == nil
        {
            renderError =
                "Custom render dimensions must be 256–6000 pixels per side and at most 24 megapixels."

            return nil
        }

        return renderSize
            .resolvedPixels(
                viewportSize:
                    view?.bounds.size
                    ?? .zero,
                backingScale:
                    view?.window?
                    .backingScaleFactor
                    ?? 2,
                customSize:
                    customSize
            )
    }

    private func animationPNGData(
        _ image: NSImage
    ) -> Data? {
        guard
            let tiff =
                image.tiffRepresentation,
            let bitmap =
                NSBitmapImageRep(
                    data:
                        tiff
                )
        else {
            return nil
        }

        return bitmap
            .representation(
                using:
                    .png,
                properties:
                    [:]
            )
    }

    private func animationCGImage(
        _ image: NSImage
    ) -> CGImage? {
        if
            let image =
                image.cgImage(
                    forProposedRect:
                        nil,
                    context:
                        nil,
                    hints:
                        nil
                )
        {
            return image
        }

        guard
            let tiff =
                image.tiffRepresentation,
            let bitmap =
                NSBitmapImageRep(
                    data:
                        tiff
                )
        else {
            return nil
        }

        return bitmap.cgImage
    }

    private func animationExportError(
        _ message: String
    ) -> NSError {
        NSError(
            domain:
                "BOLDWriter.AnimationExport",
            code:
                1,
            userInfo:
                [
                    NSLocalizedDescriptionKey:
                        message
                ]
        )
    }

    private func uniqueAnimationFramesFolder(
        in parent: URL
    ) -> URL {
        let manager =
            FileManager.default

        let baseName =
            "BOLD Writer Animation Frames"

        var candidate =
            parent
            .appendingPathComponent(
                baseName,
                isDirectory:
                    true
            )

        var suffix =
            2

        while manager
            .fileExists(
                atPath:
                    candidate.path
            )
        {
            candidate =
                parent
                .appendingPathComponent(
                    "\(baseName) \(suffix)",
                    isDirectory:
                        true
                )

            suffix +=
                1
        }

        return candidate
    }

    private func cancelAnimationExport() {
        guard animationExporting else {
            return
        }

        animationExportGeneration +=
            1

        animationExporting =
            false

        animationExportStatus =
            "Animation export cancelled."
    }

    private func exportAnimation() {
        guard
            !animationExporting,
            let pixels =
                animationExportPixels()
        else {
            return
        }

        stopAnimationPlayback(
            persist:
                true
        )

        switch animationExportFormat {
        case .pngSequence:
            let panel =
                NSOpenPanel()

            panel.title =
                "Choose Destination for Animation Frames"

            panel.prompt =
                "Export Frames"

            panel.canChooseDirectories =
                true

            panel.canChooseFiles =
                false

            panel.canCreateDirectories =
                true

            panel.allowsMultipleSelection =
                false

            guard
                panel.runModal()
                    == .OK,
                let parent =
                    panel.url
            else {
                return
            }

            let destination =
                uniqueAnimationFramesFolder(
                    in:
                        parent
                )

            beginAnimationExport(
                format:
                    .pngSequence,
                destination:
                    destination,
                pixels:
                    pixels
            )

        case .gif:
            let panel =
                NSSavePanel()

            panel.allowedContentTypes =
                [
                    .gif
                ]

            panel.nameFieldStringValue =
                "BOLD Writer Animation.gif"

            guard
                panel.runModal()
                    == .OK,
                let destination =
                    panel.url
            else {
                return
            }

            beginAnimationExport(
                format:
                    .gif,
                destination:
                    destination,
                pixels:
                    pixels
            )
        }
    }

    private func beginAnimationExport(
        format: BookStudioAnimationExportFormat,
        destination: URL,
        pixels: CGSize
    ) {
        let presentation =
            studio

        let transparent =
            transparentBackground

        let plan =
            BookStudioAnimationExportPlan(
                duration:
                    presentation
                    .animationDuration,
                fps:
                    presentation
                    .animationFPS
            )

        animationExportGeneration +=
            1

        let generation =
            animationExportGeneration

        animationExporting =
            true

        animationExportProgress =
            0

        animationExportCurrentFrame =
            0

        animationExportStatus =
            "Preparing animation export…"

        renderError =
            nil

        Task { @MainActor in
            do {
                switch format {
                case .pngSequence:
                    try await exportAnimationPNGSequence(
                        presentation:
                            presentation,
                        plan:
                            plan,
                        destination:
                            destination,
                        pixels:
                            pixels,
                        transparent:
                            transparent,
                        generation:
                            generation
                    )

                case .gif:
                    try await exportAnimationGIF(
                        presentation:
                            presentation,
                        plan:
                            plan,
                        destination:
                            destination,
                        pixels:
                            pixels,
                        transparent:
                            transparent,
                        generation:
                            generation
                    )
                }

                guard
                    animationExportGeneration
                        == generation
                else {
                    return
                }

                animationExporting =
                    false

                animationExportProgress =
                    1

                animationExportStatus =
                    format == .pngSequence
                    ? "Exported \(plan.frameCount) PNG frames."
                    : "Exported animated GIF with \(plan.frameCount) frames."
            } catch {
                guard
                    animationExportGeneration
                        == generation
                else {
                    return
                }

                animationExporting =
                    false

                animationExportStatus =
                    "Animation export failed."

                renderError =
                    error.localizedDescription
            }
        }
    }

    @MainActor
    private func exportAnimationPNGSequence(
        presentation: BookStudioPresentation,
        plan: BookStudioAnimationExportPlan,
        destination: URL,
        pixels: CGSize,
        transparent: Bool,
        generation: Int
    ) async throws {
        let manager =
            FileManager.default

        let temporary =
            manager
            .temporaryDirectory
            .appendingPathComponent(
                "BOLDWriter-AnimationFrames-\(UUID().uuidString)",
                isDirectory:
                    true
            )

        try manager
            .createDirectory(
                at:
                    temporary,
                withIntermediateDirectories:
                    true
            )

        defer {
            try? manager
                .removeItem(
                    at:
                        temporary
                )
        }

        for frameIndex in 0 ..< plan.frameCount {
            guard
                animationExportGeneration
                    == generation,
                animationExporting
            else {
                return
            }

            guard
                let image =
                    viewportHandle
                    .animationFrame(
                        size:
                            pixels,
                        presentation:
                            presentation,
                        frameIndex:
                            frameIndex,
                        transparent:
                            transparent,
                        highQualityCover:
                            true
                    ),
                let data =
                    animationPNGData(
                        image
                    )
            else {
                throw animationExportError(
                    "Frame \(frameIndex + 1) could not be rendered as PNG."
                )
            }

            guard
                animationExportGeneration
                    == generation,
                animationExporting
            else {
                return
            }

            let frameURL =
                temporary
                .appendingPathComponent(
                    plan
                    .pngFileName(
                        forFrame:
                            frameIndex
                    )
                )

            try data
                .write(
                    to:
                        frameURL,
                    options:
                        .atomic
                )

            animationExportCurrentFrame =
                frameIndex + 1

            animationExportProgress =
                Double(
                    frameIndex + 1
                )
                / Double(
                    plan.frameCount
                )

            animationExportStatus =
                "Rendering PNG frame \(frameIndex + 1) of \(plan.frameCount)…"

            try? await Task<Never, Never>
                .sleep(
                    nanoseconds:
                        1
                )
        }

        guard
            animationExportGeneration
                == generation,
            animationExporting
        else {
            return
        }

        do {
            try manager
                .copyItem(
                    at:
                        temporary,
                    to:
                        destination
                )
        } catch {
            try? manager
                .removeItem(
                    at:
                        destination
                )

            throw error
        }
    }

    @MainActor
    private func exportAnimationGIF(
        presentation: BookStudioPresentation,
        plan: BookStudioAnimationExportPlan,
        destination: URL,
        pixels: CGSize,
        transparent: Bool,
        generation: Int
    ) async throws {
        let manager =
            FileManager.default

        let temporary =
            manager
            .temporaryDirectory
            .appendingPathComponent(
                "BOLDWriter-Animation-\(UUID().uuidString).gif"
            )

        defer {
            try? manager
                .removeItem(
                    at:
                        temporary
                )
        }

        guard
            let imageDestination =
                CGImageDestinationCreateWithURL(
                    temporary as CFURL,
                    UTType.gif.identifier
                        as CFString,
                    plan.frameCount,
                    nil
                )
        else {
            throw animationExportError(
                "The animated GIF encoder could not be created."
            )
        }

        if presentation.animationLoop {
            let gifProperties =
                [
                    kCGImagePropertyGIFLoopCount:
                        0
                ] as CFDictionary

            let destinationProperties =
                [
                    kCGImagePropertyGIFDictionary:
                        gifProperties
                ] as CFDictionary

            CGImageDestinationSetProperties(
                imageDestination,
                destinationProperties
            )
        }

        for frameIndex in 0 ..< plan.frameCount {
            guard
                animationExportGeneration
                    == generation,
                animationExporting
            else {
                return
            }

            guard
                let image =
                    viewportHandle
                    .animationFrame(
                        size:
                            pixels,
                        presentation:
                            presentation,
                        frameIndex:
                            frameIndex,
                        transparent:
                            transparent,
                        highQualityCover:
                            true
                    ),
                let cgImage =
                    animationCGImage(
                        image
                    )
            else {
                throw animationExportError(
                    "Frame \(frameIndex + 1) could not be rendered for the animated GIF."
                )
            }

            let gifFrameProperties =
                [
                    kCGImagePropertyGIFDelayTime:
                        plan.gifFrameDelay,
                    kCGImagePropertyGIFUnclampedDelayTime:
                        plan.gifFrameDelay
                ] as CFDictionary

            let frameProperties =
                [
                    kCGImagePropertyGIFDictionary:
                        gifFrameProperties
                ] as CFDictionary

            CGImageDestinationAddImage(
                imageDestination,
                cgImage,
                frameProperties
            )

            animationExportCurrentFrame =
                frameIndex + 1

            animationExportProgress =
                Double(
                    frameIndex + 1
                )
                / Double(
                    plan.frameCount
                )

            animationExportStatus =
                "Encoding GIF frame \(frameIndex + 1) of \(plan.frameCount)…"

            try? await Task<Never, Never>
                .sleep(
                    nanoseconds:
                        1
                )
        }

        guard
            animationExportGeneration
                == generation,
            animationExporting
        else {
            return
        }

        guard
            CGImageDestinationFinalize(
                imageDestination
            )
        else {
            throw animationExportError(
                "The animated GIF encoder could not finalize the file."
            )
        }

        let data =
            try Data(
                contentsOf:
                    temporary
            )

        try data
            .write(
                to:
                    destination,
                options:
                    .atomic
            )
    }

    @ViewBuilder
    private var animationExportControls:
        some View
    {
        Divider()

        Text(
            "Animation Export"
        )
        .font(
            .caption
        )
        .foregroundStyle(
            .secondary
        )

        Picker(
            "Format",
            selection:
                $animationExportFormat
        ) {
            ForEach(
                BookStudioAnimationExportFormat
                    .allCases
            ) {
                format in

                Text(
                    format.rawValue
                )
                .tag(format)
            }
        }

        Picker(
            "Size",
            selection:
                $renderSize
        ) {
            ForEach(
                BookStudioRenderSize
                    .allCases
            ) {
                size in

                Text(
                    size.rawValue
                )
                .tag(size)
            }
        }

        if renderSize == .custom {
            HStack {
                TextField(
                    "Width",
                    value:
                        $customRenderWidth,
                    format:
                        .number
                )
                .accessibilityLabel(
                    "Animation width in pixels"
                )

                Text("×")

                TextField(
                    "Height",
                    value:
                        $customRenderHeight,
                    format:
                        .number
                )
                .accessibilityLabel(
                    "Animation height in pixels"
                )
            }

            Text(
                "256–6000 px per side; maximum 24 megapixels"
            )
            .font(
                .caption2
            )
            .foregroundStyle(
                .secondary
            )
        }

        Toggle(
            "Transparent Background",
            isOn:
                $transparentBackground
        )

        if animationExporting {
            ProgressView(
                value:
                    animationExportProgress
            )

            Text(
                "Frame \(animationExportCurrentFrame) of \(BookStudioAnimationMath.frameCount(duration: studio.animationDuration, fps: studio.animationFPS))"
            )
            .font(
                .caption2
                    .monospacedDigit()
            )
            .foregroundStyle(
                .secondary
            )

            Button(
                "Cancel Export"
            ) {
                cancelAnimationExport()
            }
            .controlSize(
                .small
            )
        } else {
            Button(
                "Export Animation…"
            ) {
                exportAnimation()
            }
            .controlSize(
                .small
            )
        }

        if
            let animationExportStatus
        {
            Text(
                animationExportStatus
            )
            .font(
                .caption2
            )
            .foregroundStyle(
                .secondary
            )
        }
    }

    private func animationInspector(
        _ project: CoverProject
    ) -> some View {
        GroupBox(
            "Animation"
        ) {
            VStack(
                alignment:
                    .leading,
                spacing:
                    9
            ) {
                HStack {
                    Button(
                        animationPlaying
                        ? "Pause"
                        : "Play"
                    ) {
                        toggleAnimationPlayback()
                    }
                    .keyboardShortcut(
                        .space,
                        modifiers:
                            []
                    )

                    Button(
                        "Rewind"
                    ) {
                        rewindAnimation()
                    }

                    Spacer()

                    Text(
                        "\(animationDisplayTime, specifier: "%.2f") / \(studio.animationDuration, specifier: "%.2f") s"
                    )
                    .font(
                        .system(
                            .caption,
                            design:
                                .monospaced
                        )
                    )
                    .foregroundStyle(
                        .secondary
                    )
                }

                Slider(
                    value:
                        animationScrubberBinding,
                    in:
                        0
                        ... max(
                            0.25,
                            studio.animationDuration
                        )
                )
                .accessibilityLabel(
                    "Animation playhead"
                )

                Stepper(
                    "Duration \(studio.animationDuration, specifier: "%.2f") s",
                    value:
                        animationDurationBinding,
                    in:
                        0.25 ... 120,
                    step:
                        0.25
                )

                Stepper(
                    "FPS \(studio.animationFPS)",
                    value:
                        $studio.animationFPS,
                    in:
                        1 ... 60
                )

                Toggle(
                    "Loop",
                    isOn:
                        $studio.animationLoop
                )

                Divider()

                Toggle(
                    "Turntable",
                    isOn:
                        $studio.turntableEnabled
                )

                Stepper(
                    "Turns \(studio.turntableTurns, specifier: "%.2f")",
                    value:
                        $studio.turntableTurns,
                    in:
                        0.25 ... 8,
                    step:
                        0.25
                )
                .disabled(
                    !studio.turntableEnabled
                )

                Toggle(
                    "Clockwise",
                    isOn:
                        $studio.turntableClockwise
                )
                .disabled(
                    !studio.turntableEnabled
                )

                Text(
                    "\(BookStudioAnimationMath.frameCount(duration: studio.animationDuration, fps: studio.animationFPS)) deterministic frames"
                )
                .font(
                    .caption2
                )
                .foregroundStyle(
                    .secondary
                )

                animationExportControls

                Divider()

                HStack {
                    Text(
                        "Camera Keyframes"
                    )
                    .font(
                        .caption
                    )
                    .foregroundStyle(
                        .secondary
                    )

                    Spacer()

                    Button(
                        "Add Current"
                    ) {
                        addCurrentCameraKeyframe(
                            project
                        )
                    }
                    .controlSize(
                        .small
                    )
                }

                if
                    studio.cameraKeyframes
                    .isEmpty
                {
                    Text(
                        "No camera keyframes. The current camera remains unchanged across the timeline."
                    )
                    .font(
                        .caption2
                    )
                    .foregroundStyle(
                        .secondary
                    )
                } else {
                    ForEach(
                        studio.cameraKeyframes
                        .sorted {
                            if $0.time == $1.time {
                                return $0.id.uuidString
                                    < $1.id.uuidString
                            }

                            return $0.time
                                < $1.time
                        }
                    ) {
                        keyframe in

                        HStack(
                            spacing:
                                5
                        ) {
                            Image(
                                systemName:
                                    "diamond.fill"
                            )
                            .font(
                                .caption2
                            )

                            Text(
                                "\(keyframe.time, specifier: "%.2f") s"
                            )
                            .font(
                                .system(
                                    .caption,
                                    design:
                                        .monospaced
                                )
                            )

                            Spacer()

                            Button {
                                moveCameraKeyframe(
                                    keyframe.id,
                                    by:
                                        -1
                                )
                            } label: {
                                Image(
                                    systemName:
                                        "arrow.left"
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .disabled(
                                !BookStudioCameraKeyframeOrder
                                .canMove(
                                    studio.cameraKeyframes,
                                    id:
                                        keyframe.id,
                                    offset:
                                        -1
                                )
                            )

                            Button {
                                moveCameraKeyframe(
                                    keyframe.id,
                                    by:
                                        1
                                )
                            } label: {
                                Image(
                                    systemName:
                                        "arrow.right"
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                            .disabled(
                                !BookStudioCameraKeyframeOrder
                                .canMove(
                                    studio.cameraKeyframes,
                                    id:
                                        keyframe.id,
                                    offset:
                                        1
                                )
                            )

                            Button {
                                deleteCameraKeyframe(
                                    keyframe.id
                                )
                            } label: {
                                Image(
                                    systemName:
                                        "trash"
                                )
                            }
                            .buttonStyle(
                                .plain
                            )
                        }
                    }
                }
            }
            .padding(
                .vertical,
                4
            )
        }
    }

    private func inspector(_ project: CoverProject) -> some View {
        let dimensions = PhysicalBookGeometry(project: project)
        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                inspectionControls(project)
                BookStudioArtworkInspector(document: document, projectID: project.id, panel: selectedComponent == .front ? .front : selectedComponent == .back ? .back : selectedComponent == .spine ? .spine : nil) {
                    onEditCover(project.id, nil)
                }
                Toggle("Show Cover Bleed / Wrap", isOn: Binding(get:{ studio.showProductionMargins == true },set:{ studio.showProductionMargins = $0 }))
                    .help("Show production-margin guides around the finished cover. These margins are trimmed or folded during manufacture.")
                if
                    selectedCustomLightID == nil
                    && selectedComponent
                        != .camera
                {
                    transformInspector
                        .disabled(
                            studio
                                .bookTransformLocked
                        )
                }
                Text("3D Book Studio").font(.headline)
                Text(selectedComponent?.rawValue ?? "Book presentation")
                    .font(.caption).foregroundStyle(.secondary)


                Picker(
                    "Production profile",
                    selection:
                        productionTemplateSelection
                ) {
                    ForEach(
                        BookProductionTemplate
                            .allCases
                    ) {
                        template in

                        Text(
                            template.rawValue
                        )
                        .tag(
                            template
                        )
                    }
                }
                .disabled(
                    isRendering
                )

                Text(
                    "Shared with Manuscript and Cover Creator."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Picker("Presentation", selection: Binding(
                    get: { "Choose a scene" },
                    set: { name in
                        guard let preset = BookStudioPreset(rawValue: name) else { return }
                        studio = preset.apply(to: studio)

                        if preset == .reading,
                           pageCount > 0
                        {
                            let naturalSpread =
                                PhysicalBookGeometry
                                .naturalReadingSpread(
                                    pageCount:
                                        pageCount
                                )

                            studio.spreadIndex =
                                naturalSpread

                            pageTurnState.jump(
                                to:
                                    naturalSpread,
                                maximumSpread:
                                    pageCount / 2
                            )

                            renderCurrentSpread()
                        }
                        studio.savedCamera = nil
                        focusTarget = .automatic
                        focusGeneration += 1
                    }
                )) {
                    Text("Choose a scene").tag("Choose a scene")
                    ForEach(BookStudioPreset.allCases) { preset in Text(preset.rawValue).tag(preset.rawValue) }
                }
                switch selectedComponent {
                case .front, .back, .spine:
                    Picker("Cover finish", selection: $studio.finish) { ForEach(BookCoverFinish.allCases) { Text($0.rawValue).tag($0) } }
                    Text("Visualization only · print artwork stays unchanged.").font(.caption).foregroundStyle(.secondary)
                case .pages, .leftPage, .rightPage:
                    Picker("Paper", selection: $studio.paper) { ForEach(BookPaperTone.allCases) { Text($0.rawValue).tag($0) } }
                    metric("Current spread", "\(spreadIndex + 1)")
                case .camera:
                    Toggle(
                        "Show Camera Object",
                        isOn:
                            $studio
                            .cameraEditorVisible
                    )

                    Toggle(
                        "Lock Camera Controls",
                        isOn:
                            $studio
                            .cameraEditorLocked
                    )

                    Picker("Projection", selection: $studio.projection) { ForEach(BookCameraProjection.allCases) { Text($0.rawValue).tag($0) } }

                    Slider(value: $studio.cameraFieldOfView, in: 20...75, step: 1) { Text("Field of view") }
                        .accessibilityLabel("Camera field of view")

                    Text("\(Int(studio.cameraFieldOfView))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)

                    VStack(
                        alignment: .leading,
                        spacing: 8
                    ) {
                        Text("Orbit")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            transformField(
                                "Yaw°",
                                value:
                                    cameraAngleBinding(
                                        \.yaw,
                                        project:
                                            project
                                    )
                            )

                            transformField(
                                "Pitch°",
                                value:
                                    cameraAngleBinding(
                                        \.pitch,
                                        project:
                                            project,
                                        clampPitch:
                                            true
                                    )
                            )
                        }

                        Text(
                            "Distance \(cameraDistanceBinding(project).wrappedValue, specifier: "%.2f")"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)

                        Slider(
                            value:
                                cameraDistanceBinding(
                                    project
                                ),
                            in:
                                0.35 ... 30,
                            step:
                                0.05
                        )

                        Text("Target")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 6) {
                            transformField(
                                "X",
                                value:
                                    cameraValueBinding(
                                        \.targetX,
                                        project:
                                            project
                                    )
                            )

                            transformField(
                                "Y",
                                value:
                                    cameraValueBinding(
                                        \.targetY,
                                        project:
                                            project
                                    )
                            )

                            transformField(
                                "Z",
                                value:
                                    cameraValueBinding(
                                        \.targetZ,
                                        project:
                                            project
                                    )
                            )
                        }

                        Button(
                            "Make Current Camera Editable"
                        ) {
                            studio.savedCamera =
                                studio.savedCamera
                                ?? defaultCameraSaved(
                                    project
                                )
                        }
                        .controlSize(.small)
                    }
                    .disabled(
                        studio.cameraEditorLocked
                    )

                    Picker("Quality", selection: $studio.quality) { ForEach(BookRenderQuality.allCases) { Text($0.rawValue).tag($0) } }

                    Button("Reset Camera") {
                        studio.savedCamera = nil
                        focusTarget = .automatic
                        cameraZoomScale = 1
                        resetGeneration += 1
                    }
                case .environment:
                    Picker("Environment", selection: $studio.environment) { ForEach(BookEnvironmentPreset.allCases) { Text($0.rawValue).tag($0) } }
                    Slider(value: $studio.environmentIntensity, in: 0...2) { Text("Environment intensity") }
                    Toggle("Show Ground in Editor", isOn: $studio.groundEditorVisible)
                    Toggle("Lock Ground Editor Object", isOn: $studio.groundEditorLocked)
                    Picker("Ground", selection: $studio.ground) { ForEach(BookGroundPreset.allCases) { Text($0.rawValue).tag($0) } }
                        .disabled(studio.groundEditorLocked)
                case .lights:
                    if let selectedCustomLightBinding {
                        customLightInspector(
                            selectedCustomLightBinding
                        )
                    } else {
                        Picker("Lighting", selection: $studio.lighting) { ForEach(BookLightingPreset.allCases) { Text($0.rawValue).tag($0) } }
                        Slider(value: $studio.lightIntensity, in: 0...2) { Text("Light intensity") }
                        Toggle("Cast shadows", isOn: $studio.shadowsEnabled)
                    }
                case .book, .none:
                    Picker("Cover finish", selection: $studio.finish) { ForEach(BookCoverFinish.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Paper", selection: $studio.paper) { ForEach(BookPaperTone.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Environment", selection: $studio.environment) { ForEach(BookEnvironmentPreset.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Lighting", selection: $studio.lighting) { ForEach(BookLightingPreset.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Projection", selection: $studio.projection) { ForEach(BookCameraProjection.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("Quality", selection: $studio.quality) { ForEach(BookRenderQuality.allCases) { Text($0.rawValue).tag($0) } }
                    Slider(value: $studio.environmentIntensity, in: 0...2) { Text("Environment intensity") }
                    Slider(value: $studio.lightIntensity, in: 0...2) { Text("Light intensity") }
                    Toggle("Cast shadows", isOn: $studio.shadowsEnabled)
                }
                Divider()
                animationInspector(
                    project
                )
                Toggle("Measurements", isOn: $studio.showMeasurements)
                Divider()
                Text("Export Book Mockup").font(.headline)
                Picker("Size", selection: $renderSize) { ForEach(BookStudioRenderSize.allCases) { Text($0.rawValue).tag($0) } }
                if renderSize == .custom {
                    HStack {
                        TextField("Width", value: $customRenderWidth, format: .number).accessibilityLabel("Mockup width in pixels")
                        Text("×")
                        TextField("Height", value: $customRenderHeight, format: .number).accessibilityLabel("Mockup height in pixels")
                    }
                    Text("256–6000 px per side; maximum 24 megapixels")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Picker("Format", selection: $exportJPEG) { Text("PNG").tag(false); Text("JPEG").tag(true) }
                Toggle("Transparent PNG", isOn: $transparentBackground).disabled(exportJPEG)
                Button("Export Book Mockup…") { exportBookMockup() }
                Button("Reset 3D Presentation") {
                    stopAnimationPlayback(
                        persist:
                            false
                    )
                    animationRuntimeTime = 0
                    studio = BookStudioPresentation()
                    pageTurnState.reset()
                    selectedComponent = nil
                    cameraZoomScale = 1
                    resetGeneration += 1
                    renderCurrentSpread()
                }
                Divider()
                Text("Book Fit").font(.headline)
                preflightStatus(project)
                metric("Trim", "\(format(project.trimWidth, places: 3)) × \(format(project.trimHeight, places: 3)) in")
                metric("Manuscript", pageCount == 0 ? "Calculating…" : "\(pageCount) pages")
                metric("Spine", "\(format(project.spineWidth, places: 5)) in")
                metric("Modeled page block", "\(format(dimensions.pageBlockDepth(for: binding), places: 3)) in")
                if binding == .hardcover {
                    metric("Modeled board overhang", "\(format(dimensions.coverOverhang(for: binding), places: 3)) in")
                }
                metric("Full Cover", "\(format(project.canvasWidth, places: 5)) × \(format(project.canvasHeight, places: 3)) in")
                Divider(); Text("Manuscript Inspection").font(.headline)
                Toggle("Margins", isOn: $showMargins).accessibilityLabel("Show manuscript margins")
                Picker("Thumb Zones", selection: $thumbMode) { ForEach(ThumbZoneMode.allCases) { Text($0.rawValue).tag($0) } }.accessibilityLabel("Estimated thumb zones")
                Text("Thumb zones are estimated ergonomic areas in physical page coordinates.").font(.caption).foregroundStyle(.secondary)
                if let settings = try? PageGeometry(pageSettings(for: spread.rightPage ?? spread.leftPage ?? 1)) {
                    let page = spread.rightPage ?? spread.leftPage ?? 1
                    let inside = page.isMultiple(of: 2) ? settings.settings.rightMargin : settings.settings.leftMargin
                    let outside = page.isMultiple(of: 2) ? settings.settings.leftMargin : settings.settings.rightMargin
                    metric("Inside / outside", "\(format(inside / 72, places: 3)) / \(format(outside / 72, places: 3)) in")
                    metric("Top / bottom", "\(format(settings.settings.topMargin / 72, places: 3)) / \(format(settings.settings.bottomMargin / 72, places: 3)) in")
                }
                Divider(); Text("Diagnostics").font(.headline)
                diagnostics(project)
                if let renderError { Label(renderError, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).font(.caption) }
                if isRendering { ProgressView("Rendering manuscript pages…") }
            }
        }
    }

    @ViewBuilder
    private func preflightStatus(
        _ project: CoverProject
    ) -> some View {
        if isRendering
            || pageCount == 0 {

            HStack(
                spacing:
                    8
            ) {
                ProgressView()
                    .controlSize(
                        .small
                    )

                Text(
                    "Checking print readiness…"
                )
                .font(
                    .caption
                        .bold()
                )
            }
        } else {
            let summary =
                preflightSummary(
                    project
                )

            let errorWord =
                summary.errorCount == 1
                    ? "error"
                    : "errors"

            let warningWord =
                summary.warningCount == 1
                    ? "warning"
                    : "warnings"

            let countSummary =
                "\(summary.errorCount) \(errorWord) · \(summary.warningCount) \(warningWord)"

            let accessibilitySummary =
                "Print readiness \(summary.status.rawValue), \(summary.errorCount) \(errorWord), \(summary.warningCount) \(warningWord)"

            VStack(
                alignment:
                    .leading,
                spacing:
                    5
            ) {
                switch summary.status {
                case .ready:
                    Label(
                        summary.status.rawValue,
                        systemImage:
                            "checkmark.seal.fill"
                    )
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        .green
                    )

                case .review:
                    Label(
                        summary.status.rawValue,
                        systemImage:
                            "exclamationmark.triangle.fill"
                    )
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        .orange
                    )

                case .notReady:
                    Label(
                        summary.status.rawValue,
                        systemImage:
                            "xmark.octagon.fill"
                    )
                    .font(
                        .headline
                    )
                    .foregroundStyle(
                        .red
                    )
                }

                Text(
                    countSummary
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )
            }
            .accessibilityElement(
                children:
                    .combine
            )
            .accessibilityLabel(
                accessibilitySummary
            )
        }
    }

    private func manuscriptTrimMismatchPages(
        _ project: CoverProject
    ) -> [Int] {
        let pages =
            paginatedPageSettings.isEmpty
                ? [
                    document.metadata.page
                ]
                : paginatedPageSettings

        return PhysicalBookDiagnostics
            .trimMismatchPages(
                project:
                    project,
                pages:
                    pages
            )
    }

    private func preflightSummary(
        _ project: CoverProject
    ) -> PhysicalBookPreflightSummary {
        var errors =
            0

        var warnings =
            0

        if pageCount > 0,
           PhysicalBookDiagnostics
            .pageCountMessage(
                coverPages:
                    project.spinePageCount,
                manuscriptPages:
                    pageCount
            )
            != nil {

            warnings +=
                1
        }

        if pageCount > 0 {
            if let caliper =
                project.spineCaliperInches,
               let expected =
                PhysicalBookGeometry
                    .expectedSpine(
                        pageCount:
                            pageCount,
                        caliper:
                            caliper
                    ) {

                if abs(
                    expected
                    - project.spineWidth
                ) > 0.00001 {

                    warnings +=
                        1
                }
            } else {
                warnings +=
                    1
            }
        }

        warnings +=
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project:
                        project
                )
                .count

        warnings +=
            PhysicalBookDiagnostics
                .coverImageResolutionIssues(
                    project:
                        project
                )
                .count

        warnings +=
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project:
                        project
                )
                .count

        warnings +=
            manuscriptTrimMismatchPages(
                project
            )
            .count

        if project.bleed <= 0 {
            warnings +=
                1
        }

        warnings +=
            BookPreviewScene
                .coverTextures(
                    project:
                        project,
                    workingLayers:
                        false,
                    revisionID:
                        document.revisionID
                )
                .edgeWarnings
                .count

        let expectedCanvasWidth =
            project.backWidth
            + project.spineWidth
            + project.trimWidth
            + 2
                * project.bleed

        let expectedCanvasHeight =
            project.trimHeight
            + 2
                * project.bleed

        if abs(
            project.canvasWidth
            - expectedCanvasWidth
        ) > 0.01
            || abs(
                project.canvasHeight
                - expectedCanvasHeight
            ) > 0.01 {

            errors +=
                1
        }

        let hiddenGroups =
            Set(
                project.layers
                    .filter {
                        $0.kind == .group
                            && !$0.visible
                    }
                    .map(
                        \.id
                    )
            )

        let outside =
            project.layers.filter {
                $0.visible
                    && $0.opacity > 0
                    && $0.kind != .group
                    && !(
                        $0.groupID
                            .map(
                                hiddenGroups.contains
                            )
                        ?? false
                    )
                    && (
                        $0.frame.x < -0.001
                        || $0.frame.y < -0.001
                        || $0.frame.x
                            + $0.frame.width
                            > 1.001
                        || $0.frame.y
                            + $0.frame.height
                            > 1.001
                    )
            }

        if !outside.isEmpty {
            warnings +=
                1
        }

        let geometry =
            PhysicalBookGeometry(
                project:
                    project
            )

        let trimRegions =
            [
                geometry.panelMapping.back,
                geometry.panelMapping.spine,
                geometry.panelMapping.front
            ]

        let misplacedText =
            project.layers.filter {
                layer in

                layer.visible
                    && layer.kind == .text
                    && !layer.text
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .isEmpty
                    && layer.opacity > 0
                    && !(
                        layer.groupID
                            .map(
                                hiddenGroups.contains
                            )
                        ?? false
                    )
                    && !trimRegions
                        .contains {
                            rectsOverlap(
                                layer.frame,
                                $0
                            )
                        }
            }

        if !misplacedText.isEmpty {
            warnings +=
                1
        }

        if isRegionEmpty(
            project,
            geometry.panelMapping.back
        ) {
            warnings +=
                1
        }

        if isRegionEmpty(
            project,
            geometry.panelMapping.spine
        ) {
            warnings +=
                1
        }

        if isRegionEmpty(
            project,
            geometry.panelMapping.front
        ) {
            warnings +=
                1
        }

        warnings +=
            allInteriorImageIssues
                .count

        warnings +=
            marginIssuesByPage
                .values
                .reduce(
                    0
                ) {
                    partial,
                    messages in

                    partial
                    + messages.count
                }

        if thumbMode != .off {
            warnings +=
                activeThumbIssuesByPage
                    .count
        }

        if pageCount > 1,
           PhysicalBookDiagnostics
            .hasUnmirroredMargins(
                pages:
                    paginatedPageSettings
            ) {

            warnings +=
                1
        }

        return PhysicalBookDiagnostics
            .preflightSummary(
                errorCount:
                    errors,
                warningCount:
                    warnings
            )
    }

    @ViewBuilder private func inspectionControls(_ project: CoverProject) -> some View {
        if inspection.anatomy || inspection.danger {
            Divider()
            Text("Advanced Inspection").font(.headline)
        }
        if inspection.anatomy {
            Text("Explode assembly · \(Int(inspection.explosion * 100))%")
            Slider(value: $inspection.explosion, in: 0...1).accessibilityLabel("Explode book anatomy")
            Text("X-Ray transparency")
            Slider(value: $inspection.transparency, in: 0...0.85).accessibilityLabel("Book anatomy transparency")
            ForEach([BookSceneComponent.front, .back, .spine, .pages, .leftPage, .rightPage]) { component in
                HStack {
                    Toggle(component.rawValue, isOn: Binding(get: { !inspection.hidden.contains(component) }, set: {
                        if $0 { inspection.hidden.remove(component) } else { inspection.hidden.insert(component) }
                    }))
                    Button(inspection.isolated == component ? "Show all" : "Isolate") {
                        selectedComponent = component
                        inspection.isolated = inspection.isolated == component ? nil : component
                    }.controlSize(.small)
                }
            }
            if let selectedComponent,
               let scene = viewportHandle.view?.scene,
               let node = BookStudioSceneStyling.highlightedNode(in: scene, component: selectedComponent) {
                let bounds = node.boundingBox
                Text(String(format: "Modeled bounds %.3f × %.3f × %.3f in", Double(bounds.max.x - bounds.min.x) / 0.7, Double(bounds.max.y - bounds.min.y) / 0.7, Double(bounds.max.z - bounds.min.z) / 0.7))
                    .font(.caption.monospaced())
            }
            Button("Reassemble Book") {
                inspection.explosion = 0; inspection.transparency = 0
                inspection.hidden = []; inspection.isolated = nil
                studio.exploded = false
            }
        }
        if inspection.danger {
            Picker("Severity", selection: $dangerSeverity) {
                Text("All").tag("All")
                ForEach(BookPrintDangerSeverity.allCases, id: \.rawValue) { Text($0.rawValue).tag($0.rawValue) }
            }
            Picker("Region", selection: $dangerComponent) {
                Text("All").tag(nil as BookSceneComponent?)
                ForEach([BookSceneComponent.front, .spine, .back]) { Text($0.rawValue).tag(Optional($0)) }
            }
            let bindings: [BookBinding] = compareSideBySide ? [.softcover, .hardcover] : [binding]
            ForEach(bindings, id: \.rawValue) { previewBinding in
                let issues = BookPrintDanger.inspect(project: project, binding: previewBinding, pageCount: pageCount, edgeIssues: BookPreviewScene.coverTextures(project: project, workingLayers: workingLayers, revisionID: document.revisionID).edgeIssues)
                Text(previewBinding.rawValue).font(.caption.bold())
                if issues.isEmpty { Text("No issues detected by the supported checks.").font(.caption) }
                ForEach(issues.filter { (dangerSeverity == "All" || $0.severity.rawValue == dangerSeverity) && (dangerComponent == nil || $0.component == dangerComponent) }) { issue in
                    Button {
                        selectedComponent = issue.component
                        focusTarget = Self.focusTarget(for: issue.component) ?? .automatic
                        focusGeneration += 1
                        studio.savedCamera = nil; comparisonCamera = nil
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(issue.severity.rawValue + " · " + issue.component.rawValue, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color(nsColor: issue.severity.color))
                            Text(issue.message)
                            Text(issue.correction).foregroundStyle(.secondary)
                        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.plain)
                }
            }
            Text("Wire overlays identify affected components. Review exact safe edges and bleed findings in Diagnostics below. These checks are not manufacturer certification.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private func diagnostics(_ project: CoverProject) -> some View {
        let geometry = PhysicalBookGeometry(project: project)
        finding("OK", "Print Full Wrap project selected")
        if pageCount > 0, let message = PhysicalBookDiagnostics.pageCountMessage(coverPages: project.spinePageCount, manuscriptPages: pageCount) {
            finding("Warning", message)
        } else if pageCount > 0 { finding("OK", "Cover and manuscript page counts match") }
        if pageCount > 0 {
            if let caliper = project.spineCaliperInches, let expected = PhysicalBookGeometry.expectedSpine(pageCount: pageCount, caliper: caliper) {
                if abs(expected - project.spineWidth) > 0.00001 { finding("Warning", "Expected spine for the current manuscript: \(format(expected, places: 5)) in; cover spine: \(format(project.spineWidth, places: 5)) in. Cover has not been changed.") }
                else { finding("OK", "Expected spine matches cover spine for the selected caliper") }
            } else { finding("Warning", "Expected spine cannot be calculated because this project does not store its print caliper") }
        }
        let spineTextIssues =
            PhysicalBookDiagnostics
                .spineTextIssues(
                    project: project
                )

        ForEach(
            Array(
                spineTextIssues
                    .enumerated()
            ),
            id: \.offset
        ) { _, issue in
            finding(
                "Warning",
                issue.message
            )
        }

        let imageResolutionIssues =
            PhysicalBookDiagnostics
                .coverImageResolutionIssues(
                    project: project
                )

        ForEach(
            Array(
                imageResolutionIssues
                    .enumerated()
            ),
            id: \.offset
        ) { _, issue in
            finding(
                "Warning",
                issue.message
            )
        }

        let coverSafeIssues =
            PhysicalBookDiagnostics
                .coverContentSafeIssues(
                    project: project
                )

        ForEach(
            Array(
                coverSafeIssues
                    .enumerated()
            ),
            id: \.offset
        ) { _, issue in
            finding(
                "Warning",
                issue.message
            )
        }

        Button("Edit Cover") {
            onEditCover(
                project.id,
                nil
            )
        }
        .accessibilityLabel(
            "Edit this Print Full Wrap cover"
        )
        let affectedTrimPages =
            manuscriptTrimMismatchPages(
                project
            )

        if !affectedTrimPages.isEmpty {
            finding(
                "Warning",
                String(
                    affectedTrimPages.count
                )
                + " manuscript page"
                + (
                    affectedTrimPages.count
                        == 1
                    ? ""
                    : "s"
                )
                + " use a trim size that differs from the cover."
            )

            if let nextPage =
                PhysicalBookDiagnostics
                    .nextIssuePage(
                        after:
                            currentInspectionPage,
                        issuePages:
                            affectedTrimPages
                    ) {

                Button(
                    "Go to trim issue on page \(nextPage)"
                ) {
                    goToManuscriptIssue(
                        nextPage
                    )
                }
                .accessibilityLabel(
                    "Go to manuscript trim-size issue on page \(nextPage)"
                )
            }

            Button(
                "Open Page Setup"
            ) {
                onEditManuscript(
                    currentInspectionPage,
                    pageRange(
                        for:
                            currentInspectionPage
                    )
                )
            }
        } else if pageCount > 0
                    && !isRendering {

            finding(
                "OK",
                "Every manuscript page matches the cover trim size"
            )
        }
        let productionRepairTemplate =
            PhysicalBookDiagnostics
                .productionProfileRepairTemplate(
                    project:
                        project
                )

        let productionPageSettings =
            paginatedPageSettings.isEmpty
            ? [
                document.metadata.page
            ]
            : paginatedPageSettings

        if let productionRepairTemplate,
           PhysicalBookDiagnostics
            .productionProfileNeedsRepair(
                project:
                    project,
                manuscriptPages:
                    pageCount,
                pageSettings:
                    productionPageSettings
            )
        {
            finding(
                "Warning",
                "The shared production profile is out of sync with the manuscript or physical cover."
            )

            Button(
                "Repair Production Profile"
            ) {
                applyProductionTemplate(
                    productionRepairTemplate
                )
            }
            .buttonStyle(
                .borderedProminent
            )
            .disabled(
                isRendering
                || pageCount == 0
            )
            .accessibilityLabel(
                "Repair manuscript, cover, spine, paper, and binding from \(productionRepairTemplate.rawValue)"
            )

            Text(
                "Reapplies \(productionRepairTemplate.rawValue) using the current rendered manuscript page count while preserving physically anchored cover artwork."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        if project.bleed <= 0 { finding("Warning", "No bleed is configured") }
        ForEach(BookPreviewScene.coverTextures(project: project, workingLayers: false, revisionID: document.revisionID).edgeWarnings, id: \.self) { warning in
            finding("Warning", warning)
        }
        if abs(project.canvasWidth - (project.backWidth + project.spineWidth + project.trimWidth + 2 * project.bleed)) > 0.01 || abs(project.canvasHeight - (project.trimHeight + 2 * project.bleed)) > 0.01 { finding("Error", "Full-wrap canvas does not match panel geometry") }
        let hiddenGroups = Set(project.layers.filter { $0.kind == .group && !$0.visible }.map(\.id))
        let visibleTemplates = project.layers.filter { $0.visible && $0.isReferenceLayer && !($0.groupID.map(hiddenGroups.contains) ?? false) }
        if !visibleTemplates.isEmpty { finding(workingLayers ? "Warning" : "OK", "\(visibleTemplates.count) visible template layer(s) \(workingLayers ? "shown in Working Layers" : "excluded from Print Result")") }
        let outside = project.layers.filter { $0.visible && $0.opacity > 0 && $0.kind != .group && !($0.groupID.map(hiddenGroups.contains) ?? false) && ($0.frame.x < -0.001 || $0.frame.y < -0.001 || $0.frame.x + $0.frame.width > 1.001 || $0.frame.y + $0.frame.height > 1.001) }
        if !outside.isEmpty { finding("Warning", "\(outside.count) visible layer(s) extend beyond the cover canvas") }
        let trimRegions = [geometry.panelMapping.back, geometry.panelMapping.spine, geometry.panelMapping.front]
        let misplacedText = project.layers.filter { layer in
            layer.visible && layer.kind == .text && !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            layer.opacity > 0 && !(layer.groupID.map(hiddenGroups.contains) ?? false) &&
            !trimRegions.contains(where: { rectsOverlap(layer.frame, $0) })
        }
        if !misplacedText.isEmpty { finding("Warning", "\(misplacedText.count) visible text layer(s) sit outside the back, spine, and front trim regions") }
        if isRegionEmpty(project, geometry.panelMapping.back) { finding("Warning", "Back cover region has no visible production artwork") }
        if isRegionEmpty(project, geometry.panelMapping.spine) { finding("Warning", "Spine region has no visible production artwork") }
        if isRegionEmpty(project, geometry.panelMapping.front) { finding("Warning", "Front cover region has no visible production artwork") }
        if thumbMode != .off {
            let allThumbIssues =
                activeThumbIssuesByPage

            let affectedThumbPages =
                thumbIssuePages

            if !affectedThumbPages.isEmpty {
                finding(
                    "Warning",
                    String(
                        affectedThumbPages.count
                    )
                    + " manuscript page"
                    + (
                        affectedThumbPages.count
                            == 1
                        ? ""
                        : "s"
                    )
                    + " enter the estimated "
                    + (
                        thumbMode == .standard
                            ? "standard"
                            : "compact"
                    )
                    + " thumb zones."
                )

                if let nextPage =
                    PhysicalBookDiagnostics
                        .nextIssuePage(
                            after:
                                currentInspectionPage,
                            issuePages:
                                affectedThumbPages
                        ) {

                    Button(
                        "Go to thumb issue on page \(nextPage)"
                    ) {
                        goToManuscriptIssue(
                            nextPage
                        )
                    }
                    .accessibilityLabel(
                        "Go to manuscript thumb-zone issue on page \(nextPage)"
                    )
                }
            } else if pageCount > 0
                        && !isRendering {

                finding(
                    "OK",
                    "No text glyph bounds enter the estimated thumb zones anywhere in the manuscript"
                )
            }

            let warnings =
                [
                    spread.leftPage,
                    spread.rightPage
                ]
                .compactMap {
                    $0
                }
                .compactMap {
                    allThumbIssues[
                        $0
                    ]
                }

            if warnings.isEmpty {
                finding(
                    "OK",
                    "No text glyph bounds enter the estimated thumb zones on this spread"
                )
            } else {
                ForEach(
                    warnings,
                    id:
                        \.self
                ) {
                    finding(
                        "Warning",
                        $0
                    )
                }
            }
        }
        let allImageIssues =
            self.allInteriorImageIssues

        if !allImageIssues.isEmpty {
            let affectedPages =
                interiorImageIssuePages

            finding(
                "Warning",
                String(
                    allImageIssues.count
                )
                + " manuscript image"
                + (
                    allImageIssues.count
                        == 1
                    ? ""
                    : "s"
                )
                + " below the 300-DPI print target across "
                + String(
                    affectedPages.count
                )
                + " page"
                + (
                    affectedPages.count
                        == 1
                    ? ""
                    : "s"
                )
                + "."
            )

            if let nextPage =
                PhysicalBookDiagnostics
                    .nextIssuePage(
                        after:
                            currentInspectionPage,
                        issuePages:
                            affectedPages
                    ) {

                Button(
                    "Go to image issue on page \(nextPage)"
                ) {
                    goToManuscriptIssue(
                        nextPage
                    )
                }
                .accessibilityLabel(
                    "Go to manuscript image resolution issue on page \(nextPage)"
                )
            }
        } else if pageCount > 0
                    && !isRendering {

            finding(
                "OK",
                "No low-resolution manuscript images detected"
            )
        }

        let visibleInteriorImageIssues =
            [
                spread.leftPage,
                spread.rightPage
            ]
            .compactMap { $0 }
            .flatMap {
                interiorImageIssuesByPage[
                    $0
                ]
                ?? []
            }

        ForEach(
            Array(
                visibleInteriorImageIssues
                    .enumerated()
            ),
            id: \.offset
        ) { _, issue in
            finding(
                "Warning",
                issue.message
            )
        }

        let affectedMarginPages =
            marginIssuePages

        if !affectedMarginPages.isEmpty {
            finding(
                "Warning",
                String(
                    affectedMarginPages.count
                )
                + " manuscript page"
                + (
                    affectedMarginPages.count
                        == 1
                    ? ""
                    : "s"
                )
                + " have margin or gutter clearance warnings."
            )

            if let nextPage =
                PhysicalBookDiagnostics
                    .nextIssuePage(
                        after:
                            currentInspectionPage,
                        issuePages:
                            affectedMarginPages
                    ) {

                Button(
                    "Go to margin issue on page \(nextPage)"
                ) {
                    goToManuscriptIssue(
                        nextPage
                    )
                }
                .accessibilityLabel(
                    "Go to manuscript margin or gutter issue on page \(nextPage)"
                )
            }
        } else if pageCount > 0
                    && !isRendering {

            finding(
                "OK",
                "No manuscript margin or gutter clearance warnings detected"
            )
        }

        let marginFindings =
            [
                spread.leftPage,
                spread.rightPage
            ]
            .compactMap {
                $0
            }
            .flatMap {
                marginIssuesByPage[
                    $0
                ]
                ?? []
            }

        if !marginFindings.isEmpty {
            ForEach(
                marginFindings,
                id:
                    \.self
            ) {
                finding(
                    "Warning",
                    $0
                )
            }
        }
        if pageCount > 1, PhysicalBookDiagnostics.hasUnmirroredMargins(pages: paginatedPageSettings) {
            finding("Warning", "The exported manuscript repeats unequal left/right margins on facing pages. Even-page inside and outside margins do not mirror.")
        }
        Button("Edit Manuscript") { onEditManuscript(
                    currentInspectionPage,
                    pageRange(
                        for:
                            currentInspectionPage
                    )
                ) }.accessibilityLabel("Return to manuscript")
    }

    private func finding(_ level: String, _ message: String) -> some View {
        HStack(alignment: .top, spacing: 6) { Image(systemName: level == "Error" ? "xmark.octagon.fill" : level == "Warning" ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"); VStack(alignment: .leading) { Text(level).font(.caption.bold()); Text(message).font(.caption) } }.foregroundStyle(level == "Error" ? .red : level == "Warning" ? .orange : .secondary)
    }

    private func metric(_ name: String, _ value: String) -> some View { HStack(alignment: .firstTextBaseline) { Text(name).foregroundStyle(.secondary); Spacer(minLength: 8); Text(value).multilineTextAlignment(.trailing).font(.system(.body, design: .monospaced)) } }
    private func format(_ value: Double, places: Int) -> String { String(format: "%.*f", places, value) }
    private func isRegionEmpty(_ project: CoverProject, _ region: CoverRect) -> Bool {
        let hiddenGroups = Set(project.layers.filter { $0.kind == .group && !$0.visible }.map(\.id))
        return !project.layers.contains(where: { layer in
            guard layer.visible, layer.opacity > 0, !layer.isReferenceLayer, layer.kind != .group,
                  !(layer.groupID.map(hiddenGroups.contains) ?? false), rectsOverlap(layer.frame, region) else { return false }
            switch layer.kind {
            case .image, .paint, .smartObject: return layer.imageData != nil
            case .text: return !layer.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .shape, .gradient: return (layer.fillOpacity ?? 1) > 0
            case .path: return layer.pathPoints?.isEmpty == false
            case .adjustment, .template, .group: return false
            }
        })
    }
    private func rectsOverlap(_ a: CoverRect, _ b: CoverRect) -> Bool { a.x < b.x + b.width && a.x + a.width > b.x && a.y < b.y + b.height && a.y + a.height > b.y }
    private func pageSettings(for page: Int) -> PageSettings { paginatedPageSettings.indices.contains(page - 1) ? paginatedPageSettings[page - 1] : document.metadata.page }
    private func goToManuscriptIssue(
        _ page: Int
    ) {
        guard
            pageCount > 0,
            page >= 1,
            page <= pageCount
        else {
            return
        }

        let target =
            PhysicalBookGeometry
                .spread(
                    forPage:
                        page,
                    pageCount:
                        pageCount
                )

        studio.open =
            true

        studio.openAngle =
            180

        focusTarget =
            .spread

        cameraZoomScale =
            1

        focusGeneration +=
            1

        pageTurnState.jump(
            to:
                target.index,
            maximumSpread:
                max(
                    0,
                    pageCount / 2
                )
        )
        studio.spreadIndex = pageTurnState.spreadIndex

        if let previewPDF {
            renderPages(
                previewPDF,
                spread:
                    target
            )
        }
    }

    private func jumpToPage(_ page: Int) {
        jumpToSpread(PhysicalBookGeometry.spread(forPage: page, pageCount: pageCount).index)
    }

    private func jumpToEnteredPage() {
        guard let page = pageEntry.resolvedPage(pageCount:pageCount) else { return }
        pageEntry.text = String(page)
        // Submitting ends the typing session. Otherwise navigation buttons can
        // leave this field focused and suppress every subsequent spread update.
        pageEntryFocused = false
        jumpToPage(page)
    }

    private func jumpToSpread(_ index: Int) {
        guard !pageTurnActive, pageCount > 0 else { return }
        pageEntryFocused = false
        pageTurnState.jump(to: index, maximumSpread: pageCount / 2)
        studio.spreadIndex = pageTurnState.spreadIndex
        renderCurrentSpread()
    }

    private func moveSpread(_ delta: Int) {
        guard !pageTurnActive, pageCount > 0,
              let transition = pageTurnState.begin(to: spreadIndex + delta, maximumSpread: max(0, pageCount / 2)) else { return }
        pageEntryFocused = false
        studio.spreadIndex = pageTurnState.spreadIndex
        // A bound leaf can turn freely once the covers are flat. Open the shell
        // before animating navigation from a partly closed inspection pose.
        if openAngle < 179 { studio.openAngle = 180 }
        let faces = PhysicalBookGeometry.pageTurnFaces(direction: transition.direction, fromSpread: transition.fromSpread,
                                                       toSpread: transition.toSpread, pageCount: pageCount)

        // Render both physical sides of the turning leaf before SceneKit starts
        // the animation so the page can never begin with an unresolved texture.
        pageTurnTexture = faces.front.flatMap { pageImage($0) }
        pageTurnReverseTexture = faces.reverse.flatMap { pageImage($0) }

        // Also warm the destination spread before the navigation state flips.
        // Without this, SwiftUI could briefly rebuild the landed spread before
        // its manuscript textures had entered either visible-page cache.
        let destinationSpread = PhysicalBookGeometry.spread(
            at: transition.toSpread,
            pageCount: pageCount
        )

        for pageNumber in [destinationSpread.leftPage, destinationSpread.rightPage].compactMap({ $0 }) {
            _ = pageImage(pageNumber)
        }

        pageTurnGeneration += 1
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            pageTurnState.finish()
            pageTurnTexture = nil
            pageTurnReverseTexture = nil
            if let previewPDF { renderPages(previewPDF, spread: PhysicalBookGeometry.spread(at: spreadIndex, pageCount: pageCount)) }
        }
    }

    private func previewTexture(
        for number: Int
    ) -> NSImage? {
        guard let image = pageTextureCache.image(for: number) else { return nil }
        return pageTextureDecorator.texture(for: number, source: image,
                                            hasIssue: !(interiorImageIssuesByPage[number] ?? []).isEmpty)
    }

    private func pageImage(_ number: Int) -> NSImage? {
        if let image = pageTextureCache.image(for: number) {
            return pageTextureDecorator.texture(for: number, source: image,
                                                hasIssue: !(interiorImageIssuesByPage[number] ?? []).isEmpty)
        }

        guard
            let page =
                previewPDF?
                    .page(
                        at:
                            number - 1
                    ),
            let image =
                Self.renderManuscriptPage(
                    page,
                    maximumPixelSize:
                        900
                )
        else {
            return nil
        }

        pageTextureCache.store(image, for: number, maximumPixels: 900)
        schedulePageTexture(number, maximumPixels: 2400)
        return pageTextureDecorator.texture(for: number, source: image,
                                            hasIssue: !(interiorImageIssuesByPage[number] ?? []).isEmpty)
    }

    static func manuscriptGeometryDiagnostics(
        pdf: PDFDocument,
        pageSettings: [PageSettings],
        spineWidth: Double
    ) -> (
        marginWarningsByPage:
            [Int: [String]],
        standardThumbWarningsByPage:
            [Int: String],
        compactThumbWarningsByPage:
            [Int: String]
    ) {
        var marginWarningsByPage:
            [Int: [String]] = [:]

        var standardThumbWarningsByPage:
            [Int: String] = [:]

        var compactThumbWarningsByPage:
            [Int: String] = [:]

        guard pdf.pageCount > 0 else {
            return (
                marginWarningsByPage,
                standardThumbWarningsByPage,
                compactThumbWarningsByPage
            )
        }

        for pageNumber
            in 1...pdf.pageCount {

            guard
                let (
                    pdfPage,
                    ink
                ) =
                    selectedTextBounds(
                        pageNumber:
                            pageNumber,
                        pdf:
                            pdf
                    )
            else {
                continue
            }

            let page =
                pdfPage.bounds(
                    for:
                        .mediaBox
                )

            let content =
                CoverRect(
                    x:
                        (
                            ink.minX
                            - page.minX
                        )
                        / 72,
                    y:
                        (
                            ink.minY
                            - page.minY
                        )
                        / 72,
                    width:
                        ink.width
                        / 72,
                    height:
                        ink.height
                        / 72
                )

            if pageSettings.indices
                .contains(
                    pageNumber - 1
                ) {

                let settings =
                    pageSettings[
                        pageNumber - 1
                    ]

                let intrusion =
                    PhysicalBookGeometry
                        .marginIntrusions(
                            content:
                                content,
                            pageWidth:
                                page.width
                                / 72,
                            pageHeight:
                                page.height
                                / 72,
                            left:
                                settings.leftMargin
                                / 72,
                            right:
                                settings.rightMargin
                                / 72,
                            top:
                                settings.topMargin
                                / 72,
                            bottom:
                                settings.bottomMargin
                                / 72
                        )

                let leftName =
                    pageNumber
                        .isMultiple(
                            of:
                                2
                        )
                        ? "outside"
                        : "inside"

                let rightName =
                    pageNumber
                        .isMultiple(
                            of:
                                2
                        )
                        ? "inside"
                        : "outside"

                var messages:
                    [String] = []

                if intrusion.left > 0 {
                    messages.append(
                        "Page "
                        + String(
                            pageNumber
                        )
                        + " text enters the "
                        + leftName
                        + " margin by "
                        + formattedInches(
                            intrusion.left
                        )
                        + " in."
                    )
                }

                if intrusion.right > 0 {
                    messages.append(
                        "Page "
                        + String(
                            pageNumber
                        )
                        + " text enters the "
                        + rightName
                        + " margin by "
                        + formattedInches(
                            intrusion.right
                        )
                        + " in."
                    )
                }

                if intrusion.top > 0 {
                    messages.append(
                        "Page "
                        + String(
                            pageNumber
                        )
                        + " text enters the top margin by "
                        + formattedInches(
                            intrusion.top
                        )
                        + " in."
                    )
                }

                if intrusion.bottom > 0 {
                    messages.append(
                        "Page "
                        + String(
                            pageNumber
                        )
                        + " text enters the bottom margin by "
                        + formattedInches(
                            intrusion.bottom
                        )
                        + " in."
                    )
                }

                let insideClearance =
                    pageNumber
                        .isMultiple(
                            of:
                                2
                        )
                        ? (
                            page.width
                            / 72
                            - content.x
                            - content.width
                        )
                        : content.x

                let minimumInside =
                    CGFloat(
                        0.375
                        + min(
                            0.35,
                            spineWidth
                            * 0.2
                        )
                    )

                if insideClearance
                    < minimumInside {

                    messages.append(
                        "Page "
                        + String(
                            pageNumber
                        )
                        + " ink is "
                        + formattedInches(
                            insideClearance
                        )
                        + " in from the gutter; allow about "
                        + formattedInches(
                            minimumInside
                        )
                        + " in for this spine."
                    )
                }

                if !messages.isEmpty {
                    marginWarningsByPage[
                        pageNumber
                    ] =
                        messages
                }
            }

            if let warning =
                thumbWarning(
                    pageNumber:
                        pageNumber,
                    page:
                        page,
                    content:
                        content,
                    reach:
                        0.65
                ) {

                standardThumbWarningsByPage[
                    pageNumber
                ] =
                    warning
            }

            if let warning =
                thumbWarning(
                    pageNumber:
                        pageNumber,
                    page:
                        page,
                    content:
                        content,
                    reach:
                        0.40
                ) {

                compactThumbWarningsByPage[
                    pageNumber
                ] =
                    warning
            }
        }

        return (
            marginWarningsByPage,
            standardThumbWarningsByPage,
            compactThumbWarningsByPage
        )
    }

    private static func thumbWarning(
        pageNumber: Int,
        page: CGRect,
        content: CoverRect,
        reach: CGFloat
    ) -> String? {
        let side:
            ThumbSide =
                pageNumber
                    .isMultiple(
                        of:
                            2
                    )
                    ? .left
                    : .right

        let zone =
            PhysicalBookGeometry
                .thumbZone(
                    pageWidth:
                        page.width
                        / 72,
                    pageHeight:
                        page.height
                        / 72,
                    depth:
                        reach,
                    side:
                        side,
                    mode:
                        .standard
                )

        guard
            PhysicalBookGeometry
                .intersects(
                    content,
                    zone:
                        zone
                )
                > 0
        else {
            return nil
        }

        let pageWidth =
            page.width
            / 72

        let intrusion =
            side == .left
                ? reach
                    - content.x
                : content.x
                    + content.width
                    - (
                        pageWidth
                        - reach
                    )

        return "Page "
            + String(
                pageNumber
            )
            + " text enters estimated "
            + (
                side == .left
                    ? "left"
                    : "right"
            )
            + "-thumb zone by "
            + formattedInches(
                max(
                    0,
                    intrusion
                )
            )
            + " in."
    }

    private static func selectedTextBounds(
        pageNumber: Int,
        pdf: PDFDocument
    ) -> (
        PDFPage,
        CGRect
    )? {
        guard
            let page =
                pdf.page(
                    at:
                        pageNumber - 1
                ),
            page.numberOfCharacters > 0,
            let selection =
                page.selection(
                    for:
                        NSRange(
                            location:
                                0,
                            length:
                                page.numberOfCharacters
                        )
                )
        else {
            return nil
        }

        let bounds =
            selection.bounds(
                for:
                    page
            )

        return bounds.isNull
                || bounds.isEmpty
            ? nil
            : (
                page,
                bounds
            )
    }

    private static func formattedInches(
        _ value: CGFloat
    ) -> String {
        String(
            format:
                "%.2f",
            Double(
                value
            )
        )
    }

    private func applyProductionTemplate(
        _ template:
            BookProductionTemplate
    ) {
        BookWorkspaceNavigation(
            document:
                document
        )
        .applyProductionTemplate(
            template,
            pageCount:
                pageCount > 0
                ? pageCount
                : nil
        )

        if let activeID =
            document.metadata
                .activeCoverProjectID
        {
            projectID =
                activeID
        }

        applyProductionSettingsToStudio()

        guard
            template != .custom
        else {
            return
        }

        refresh()
    }

    private func synchronizeProductionBinding(
        _ binding: BookBinding
    ) {
        guard
            let current =
                project
        else {
            return
        }

        var projects =
            document.metadata.coverProjects
            ?? []

        guard
            let index =
                projects.firstIndex(
                    where: {
                        $0.id
                            == current.id
                    }
                )
        else {
            return
        }

        guard
            projects[index]
                .productionBinding
                != binding
        else {
            return
        }

        projects[index]
            .productionBinding =
            binding

        document.metadata.coverProjects =
            projects

        document.metadata.activeCoverProjectID =
            current.id
    }

    private func applyProductionSettingsToStudio() {
        guard
            let current =
                project
        else {
            return
        }

        if let productionBinding =
            current.productionBinding
        {
            studio.binding =
                productionBinding
        }

        let paperPreset =
            current.paperStockPreset
            ?? PrintPaperStockPreset
                .inferred(
                    caliper:
                        current
                            .spineCaliperInches
                )

        if let tone =
            paperPreset.bookPaperTone
        {
            studio.paper =
                tone
        }
    }

    private func synchronizeCoverGeometryFromManuscript(
        pageCount: Int
    ) {
        guard
            pageCount > 0,
            let current = project,
            let synchronized =
                PhysicalBookGeometry.synchronizedPrintCover(
                    current,
                    manuscriptPageCount: pageCount
                )
        else {
            return
        }

        var projects =
            document.metadata.coverProjects
            ?? []

        guard
            let index =
                projects.firstIndex(
                    where: {
                        $0.id == current.id
                    }
                )
        else {
            return
        }

        projects[index] =
            synchronized

        document.metadata.coverProjects =
            projects

        document.metadata.activeCoverProjectID =
            synchronized.id
    }

    private func refresh() {
        applyProductionSettingsToStudio()
        if projectID == nil { projectID = project?.id }
        guard project != nil else {
            pageCount = 0
            onRenderedPageCountChange(nil)
            paginatedPageRanges = []
            previewPDF = nil
            interiorImageIssuesByPage = [:]
            marginIssuesByPage = [:]
            standardThumbIssuesByPage = [:]
            compactThumbIssuesByPage = [:]
            return
        }
        if let previewPDFURL { try? FileManager.default.removeItem(at: previewPDFURL) }; previewPDFURL = nil; previewPDF = nil
        renderError = nil
        pageTextureCache.reset()
        pageTextureDecorator.reset()
        pendingPageTextures.removeAll()
        pageCount = 0
        paginatedPageSettings = []
        paginatedPageRanges = []
        interiorImageIssuesByPage = [:]
        marginIssuesByPage = [:]
        standardThumbIssuesByPage = [:]
        compactThumbIssuesByPage = [:]
        pageTurnState.reset()
        pageTurnTexture = nil
        pageTurnReverseTexture = nil
        let snapshot = NSAttributedString(attributedString: document.text)
        let settings = document.metadata.page, sections = document.metadata.sections
        let floatingImages = document.metadata.floatingImages ?? []
        let diagnosticSpineWidth =
            Double(
                project?.spineWidth
                ?? 0
            )
        isRendering = true
        let requestID = UUID(); renderRequestID = requestID
        Task { @MainActor in
            do {
                let numberedSnapshot = NSMutableAttributedString(attributedString: snapshot)
                try Footnotes.renumber(numberedSnapshot)
                let printableSnapshot = try Endnotes.printable(numberedSnapshot)

                let production = try BookHealthReport.productionPDF(
                    from: snapshot,
                    settings: settings,
                    sections: sections ?? [],
                    floatingImages: floatingImages
                )
                let data = production.data
                let pageSettings = production.pageSettings
                let pageRanges = production.pageRanges

                let renderedPageSettings =
                    pageSettings

                let renderedInteriorIssues =
                    PhysicalBookDiagnostics
                        .interiorImageResolutionIssues(
                            text:
                                printableSnapshot,
                            pageRanges:
                                pageRanges
                        )
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("BOLDWriter-Preview-\(requestID.uuidString).pdf")
                try data.write(to: url, options: .atomic)
                guard renderRequestID == requestID else { try? FileManager.default.removeItem(at: url); return }
                guard let pdf = PDFDocument(url: url) else { try? FileManager.default.removeItem(at: url); renderError = "The manuscript preview could not be opened."; isRendering = false; return }

                let manuscriptGeometry =
                    Self.manuscriptGeometryDiagnostics(
                        pdf:
                            pdf,
                        pageSettings:
                            renderedPageSettings,
                        spineWidth:
                            diagnosticSpineWidth
                    )
                if let previewPDFURL { try? FileManager.default.removeItem(at: previewPDFURL) }
                previewPDFURL = url
                previewPDF = pdf
                pageCount = pdf.pageCount
                if studio.open,
                   studio.cameraPreset == .reading,
                   studio.spreadIndex == 0,
                   pageCount > 2
                {
                    let initialRestingSpread =
                        PhysicalBookGeometry
                        .naturalReadingSpread(
                            pageCount:
                                pageCount
                        )

                    studio.spreadIndex =
                        initialRestingSpread

                    pageTurnState.jump(
                        to:
                            initialRestingSpread,
                        maximumSpread:
                            pageCount / 2
                    )
                }
                onRenderedPageCountChange(
                    pdf.pageCount
                )
                synchronizeCoverGeometryFromManuscript(
                    pageCount: pdf.pageCount
                )
                pageTurnState.jump(to: studio.spreadIndex, maximumSpread: pdf.pageCount / 2)
                studio.spreadIndex = pageTurnState.spreadIndex
                paginatedPageSettings =
                    renderedPageSettings

                paginatedPageRanges =
                    pageRanges
                interiorImageIssuesByPage =
                    Dictionary(
                        grouping:
                            renderedInteriorIssues,
                        by:
                            \.pageNumber
                    )
                marginIssuesByPage =
                    manuscriptGeometry
                        .marginWarningsByPage
                standardThumbIssuesByPage =
                    manuscriptGeometry
                        .standardThumbWarningsByPage
                compactThumbIssuesByPage =
                    manuscriptGeometry
                        .compactThumbWarningsByPage
                isRendering = false
                renderPages(pdf, spread: PhysicalBookGeometry.spread(at: spreadIndex, pageCount: pdf.pageCount))
            } catch { if renderRequestID == requestID { renderError = error.localizedDescription; isRendering = false } }
        }
    }

    private func renderCurrentSpread() {
        guard pageCount > 0, let previewPDF else { return }
        renderPages(previewPDF, spread: PhysicalBookGeometry.spread(at: spreadIndex, pageCount: previewPDF.pageCount))
    }

    private func renderPages(_ pdf: PDFDocument, spread: BookSpread) {
        let plan = BookPageTextureCache.pagePlan(for: spread, pageCount: pdf.pageCount)
        for number in plan.visible {
            pageTextureCache.markUsed(number)
            if pageTextureCache.image(for: number) == nil,
               let page = pdf.page(at: number - 1),
               let image = Self.renderManuscriptPage(page, maximumPixelSize: 900) {
                pageTextureCache.store(image, for: number, maximumPixels: 900)
            }
            schedulePageTexture(number, maximumPixels: 2400)
        }
        for number in plan.adjacent where pageTextureCache.needsImage(for: number, maximumPixels: 900) {
            schedulePageTexture(number, maximumPixels: 900)
        }
    }

    private func schedulePageTexture(_ number: Int, maximumPixels: Int) {
        guard pageTextureCache.needsImage(for: number, maximumPixels: maximumPixels),
              !pendingPageTextures.contains(number), let url = previewPDFURL else { return }
        let sourceID = pageTextureCache.sourceID
        pendingPageTextures.insert(number)
        // Each worker opens its own PDFDocument. PDFPage instances never cross queues.
        DispatchQueue.global(qos: .userInitiated).async {
            let image = PDFDocument(url: url)?.page(at: number - 1)
                .flatMap { Self.renderManuscriptPage($0, maximumPixelSize: CGFloat(maximumPixels)) }
            DispatchQueue.main.async {
                guard pageTextureCache.sourceID == sourceID else { return }
                pendingPageTextures.remove(number)
                let currentPlan = BookPageTextureCache.pagePlan(for: spread, pageCount: pageCount)
                guard currentPlan.visible.contains(number) || currentPlan.adjacent.contains(number) else { return }
                if let image { pageTextureCache.store(image, for: number, maximumPixels: maximumPixels) }
                if maximumPixels < 2400 &&
                    [spread.leftPage, spread.rightPage].compactMap({ $0 }).contains(number) {
                    schedulePageTexture(number, maximumPixels: 2400)
                }
            }
        }
    }

    static func interiorResolutionTexture(
        _ image: NSImage,
        hasIssue: Bool
    ) -> NSImage {
        guard
            hasIssue,
            image.size.width > 0,
            image.size.height > 0
        else {
            return image
        }

        let marked =
            NSImage(
                size:
                    image.size
            )

        marked.lockFocus()

        image.draw(
            in:
                NSRect(
                    origin:
                        .zero,
                    size:
                        image.size
                ),
            from:
                .zero,
            operation:
                .sourceOver,
            fraction:
                1
        )

        let badgeHeight =
            max(
                CGFloat(4),
                image.size.height
                    * 0.018
            )

        let badgeWidth =
            max(
                CGFloat(16),
                min(
                    image.size.width
                        * 0.32,
                    image.size.width
                        - 4
                )
            )

        let badge =
            NSRect(
                x:
                    max(
                        2,
                        image.size.width
                            - badgeWidth
                            - 2
                    ),
                y:
                    max(
                        2,
                        image.size.height
                            - badgeHeight
                            - 2
                    ),
                width:
                    badgeWidth,
                height:
                    badgeHeight
            )

        NSColor.systemRed
            .withAlphaComponent(
                0.82
            )
            .setFill()

        NSBezierPath(
            roundedRect:
                badge,
            xRadius:
                badgeHeight
                    * 0.22,
            yRadius:
                badgeHeight
                    * 0.22
        )
        .fill()

        marked.unlockFocus()

        return marked
    }

    static func renderManuscriptPage(_ page: PDFPage, maximumPixelSize: CGFloat = 1200) -> NSImage? {
        let bounds = page.bounds(for: .mediaBox).integral
        guard !bounds.isNull, !bounds.isEmpty, bounds.width.isFinite, bounds.height.isFinite,
              maximumPixelSize > 0 else { return nil }
        let scale = min(4.0, maximumPixelSize / max(bounds.width, bounds.height))
        let size = NSSize(width: ceil(bounds.width * scale), height: ceil(bounds.height * scale))
        guard let source = page.thumbnail(of: size, for: .mediaBox).cgImage(forProposedRect: nil, context: nil, hints: nil),
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: source.width, height: source.height,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(source, in: CGRect(x: 0, y: 0, width: source.width, height: source.height))
        guard let normalized = context.makeImage() else { return nil }
        // Preserve the raster's pixel size as the SceneKit texture size.
        let image = NSImage(cgImage: normalized, size: NSSize(width: source.width, height: source.height))
        return image
    }
}


// A deliberate second selection of the active preset is a camera command,
// even though the selected enum value itself has not changed. Ordinary page
// turns and unrelated SwiftUI updates must not invoke this operation.
@MainActor
enum BookStudioCameraPresetCommand {
    @discardableResult
    static func reselect(
        _ preset: BookViewPreset,
        presentation: inout BookStudioPresentation,
        resetGeneration: inout Int
    ) -> Bool {
        guard presentation.cameraPreset == preset else {
            return false
        }
        presentation.savedCamera = nil
        resetGeneration += 1
        return true
    }
}
