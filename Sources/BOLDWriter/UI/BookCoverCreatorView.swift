import AppKit
import SwiftUI
import UniformTypeIdentifiers

enum CoverEditorTool: String, CaseIterable, Identifiable {
    case move, rectangle, ellipse, lasso, wand, crop, eyedropper, heal, blur, sharpen, brush, pencil, clone, eraser, gradient, dodge, burn, type, pen, path, shape, hand, zoom, rotateView
    var id:String{rawValue}
    var title:String{switch self{case .rectangle:"Rectangle Select";case .lasso:"Lasso";case .wand:"Magic Wand";case .heal:"Spot Healing";case .blur:"Blur";case .sharpen:"Sharpen";case .clone:"Clone Stamp";case .type:"Type";case .rotateView:"Rotate View";default:rawValue.capitalized}}
    var symbol:String{switch self{case .move:"arrow.up.left.and.arrow.down.right";case .rectangle:"rectangle.dashed";case .ellipse:"oval";case .lasso:"scribble.variable";case .wand:"wand.and.stars";case .crop:"crop.rotate";case .eyedropper:"eyedropper";case .heal:"bandage";case .blur:"drop";case .sharpen:"triangle";case .brush:"paintbrush.pointed";case .pencil:"pencil";case .clone:"circle.lefthalf.filled";case .eraser:"eraser";case .gradient:"circle.lefthalf.filled";case .dodge:"sun.max";case .burn:"sun.max.fill";case .type:"textformat";case .pen:"pencil.tip.crop.circle";case .path:"point.topleft.down.curvedto.point.bottomright.up";case .shape:"square.on.circle";case .hand:"hand.draw";case .zoom:"magnifyingglass";case .rotateView:"rotate.right"}}
    var isImplemented:Bool{[.move,.rectangle,.ellipse,.lasso,.wand,.crop,.eyedropper,.heal,.blur,.sharpen,.brush,.pencil,.clone,.eraser,.gradient,.dodge,.burn,.type,.pen,.path,.shape,.hand,.zoom,.rotateView].contains(self)}
}

private enum CoverMaskPreviewMode: String, CaseIterable, Identifiable {
    case artwork = "Artwork"
    case grayscale = "Grayscale"
    case overlay = "Overlay"
    var id: String { rawValue }
}

struct BookCoverCreatorView: View {
    private let sourceProjects: [CoverProject]
    private let productionPreflight: (CoverProject) throws -> PhysicalBookPublishingPreflight
    private let convertPaperback: (CoverProject, PrintPaperStockPreset) throws -> CoverProject
    private let convertHardcover: (CoverProject, PrintPaperStockPreset) throws -> CoverProject
    let activeProjectID: UUID?
    let isActive: Bool
    let focusPanel:
        CoverPanelAnchor?
    let focusRequestID:
        UUID?
    @State private var projects: [CoverProject]
    @State private var projectIndex = 0
    @State private var showingHome: Bool
    @State private var hasOpenedProject: Bool
    @State private var selectedID: UUID?
    @State private var selectedIDs: Set<UUID> = []
    @State private var undoStack: [CoverProject] = []
    @State private var redoStack: [CoverProject] = []
    @State private var showDropChoice = false
    @State private var droppedURL: URL?
    @State private var showPhysicalProofSheet = false
    @State private var showExport = false
    @State private var exportFormat = "png"
    @State private var proofExport = false
    @State private var zoom = 0.7
    @State private var panOffset = CGSize.zero
    @State private var viewRotation = 0.0
    @State private var quickMask = false
    @State private var cropPreview: CoverRect?
    @State private var activeStrokeTranslation = CGSize.zero
    @State private var proportionalScale = true
    @State private var pageCount = 240
    @State private var caliper = PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper
    @State private var manualSpine = 0.54
    @State private var useCaliper = true
    @State private var errorMessage: String?
    @State private var adjustmentExpanded = true
    @State private var selectiveColorTarget = "reds"
    @State private var workspace = CoverWorkspaceState()
    @State private var rightDockTab: CoverDockTab = .layers
    @State private var activeTool: CoverEditorTool = .move
    @State private var brushDiameter = 24.0
    @State private var brushHardness = 0.8
    @State private var brushFlow = 1.0
    @State private var brushStrength = 0.5
    @State private var fitScaleEstimate = 72.0
    @State private var panLastTranslation = CGSize.zero
    @State private var selectionTolerance = 0.12
    @State private var canvasRenderCache = CoverCanvasRenderCache()
    @State private var foregroundHex = "#202020"
    @State private var backgroundColorHex = "#FFFFFF"
    @State private var copiedLayer: CoverLayer?
    @State private var cloneSource: CGPoint?
    @State private var canvasDragPoints: [CGPoint] = []
    @State private var selectionMode: CoverSelectionMode = .replace
    @State private var constructionPoints: [CGPoint] = []
    @State private var selectedPathContourIndex: Int?
    @State private var selectedPathPointIndex: Int?
    @State private var selectedPathAnchors: Set<CoverVectorAnchorIndex> = []
    @State private var showPathGeometryTransform = false
    @State private var pathGeometryScaleX = 1.0
    @State private var pathGeometryScaleY = 1.0
    @State private var pathGeometryRotation = 0.0
    @State private var selectionDragStart: CGPoint?
    @State private var selectionDragPreview: Data?
    @State private var selectionTransformSnapshot: Data?
    @State private var magneticRadius = 10.0
    @State private var magneticContrast = 0.55
    @State private var magneticFrequency = 12.0
    @State private var showSaveSelection = false
    @State private var savedSelectionName = "Selection"
    @State private var lassoMode = 0
    @State private var selectionRadiusPrompt: SelectionRadiusOperation?
    @State private var showCanvasResize = false
    @State private var canvasResizeWidth = 6.0
    @State private var canvasResizeHeight = 9.0
    @State private var selectionRadius = 3.0
    private enum SelectionRadiusOperation { case feather, expand, contract, border }
    @State private var wandContiguous = true
    @State private var wandAntialias = true
    @State private var selectionFeather = 0.0
    @State private var autoSelect = true
    @State private var showTransformControls = true
    @State private var transformSnapshot: CoverProject?
    @State private var selectedMaskLayerID: UUID?
    private var maskSelected: Bool {
        get { selectedID != nil && selectedMaskLayerID == selectedID }
        nonmutating set { selectedMaskLayerID = newValue ? selectedID : nil }
    }
    @State private var selectionTranslationX = 0.0
    @State private var selectionTranslationY = 0.0
    @State private var selectionScale = 1.0
    @State private var selectionAngle = 0.0
    @State private var brushOpacity = 1.0
    @State private var shapeToolKind: CoverShapeKind = .rectangle
    @State private var gradientRadial = false
    @State private var gradientMaskOpacity = 1.0
    @State private var gradientMaskReversed = false
    @State private var maskPreviewMode: CoverMaskPreviewMode = .artwork
    @State private var showNewGuide = false
    @State private var newGuideAxis = "Vertical"
    @State private var newGuidePosition = 1.0
    @State private var alignmentReference = "Canvas"
    @State private var inspectedPhysicalPanel: CoverPanelAnchor = .canvas
    @State private var perspectiveEditing = false
    @State private var perspectiveDragStart: [CoverPathPoint]?
    @State private var alignmentIndicators:[CGPoint]=[]
    @State private var warpEditing=false
    @State private var warpPreset:CoverWarpPreset = .arch
    @State private var transformPivot="Center"
    @State private var zoomScrubStart:(CGPoint,Double)?
    @State private var pinchStartZoom:Double?
    @State private var rotateViewStart:Double?
    @State private var cropAspect="Free"
    @State private var cropWidth=1.0
    @State private var cropHeight=1.0
    @State private var cropStraighten=0.0
    @State private var guidePreview:(String,Double)?
    @State private var guideDragActive=false
    @State private var cropInteractionStart:CoverRect?
    @FocusState private var canvasFocused:Bool
    @State private var previousTool:CoverEditorTool?
    @State private var keyMonitor:Any?
    @State private var nudgeGeneration=0
    @State private var nudgeUndoOpen=false
    @State private var canvasViewportSize=CGSize.zero
    var onSave: ([CoverProject], UUID) -> Void
    var onApplyProductionTemplate: (BookProductionTemplate) -> Void
    var onOpenManuscript: () -> Void
    var onOpenBookStudio: () -> Void

    var onOpenBookStudioPanel:
        (CoverPanelAnchor?) -> Void
    init(
        projects: [CoverProject],
        activeProjectID: UUID? = nil,
        isActive: Bool = true,
        focusPanel: CoverPanelAnchor? = nil,
        focusRequestID: UUID? = nil,
        onSave: @escaping ([CoverProject], UUID) -> Void,
        productionPreflight: @escaping (CoverProject) throws -> PhysicalBookPublishingPreflight,
        convertPaperback: @escaping (CoverProject, PrintPaperStockPreset) throws -> CoverProject,
        convertHardcover: @escaping (CoverProject, PrintPaperStockPreset) throws -> CoverProject = { _, _ in
            throw WriterError.message("KDP hardcover conversion is unavailable in this cover workspace.")
        },
        onApplyProductionTemplate: @escaping (BookProductionTemplate) -> Void = { _ in },
        onOpenManuscript: @escaping () -> Void,
        onOpenBookStudio: @escaping () -> Void,
        onOpenBookStudioPanel: @escaping (CoverPanelAnchor?) -> Void = { _ in }
    ) {
        self.sourceProjects = projects
        self.productionPreflight = productionPreflight
        self.convertPaperback = convertPaperback
        self.convertHardcover = convertHardcover
        self.activeProjectID = activeProjectID
        self.isActive = isActive
        self.focusPanel = focusPanel
        self.focusRequestID = focusRequestID
        let restored = projects.isEmpty ? [CoverProject()] : projects
        let activeIndex=activeProjectID.flatMap{id in restored.firstIndex{$0.id == id}} ?? 0
        _projects=State(initialValue:restored)
        _projectIndex=State(initialValue:activeIndex)
        _showingHome=State(initialValue:projects.isEmpty)
        _hasOpenedProject=State(initialValue:!projects.isEmpty)
        let active=restored[activeIndex]
        _pageCount=State(initialValue:active.spinePageCount ?? (active.type == .printFullWrap ? CoverCalculator.inferredPageCount(spineWidth:active.spineWidth,caliperInches:active.spineCaliperInches ?? PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper):240))
        _caliper=State(initialValue:restored[activeIndex].spineCaliperInches ?? PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper)
        self.onSave=onSave
        self.onApplyProductionTemplate=onApplyProductionTemplate
        self.onOpenManuscript=onOpenManuscript
        self.onOpenBookStudio=onOpenBookStudio
        self.onOpenBookStudioPanel = onOpenBookStudioPanel
    }
    static func centeredPanelPan(
        for panel:
            CoverPanelAnchor,
        in project:
            CoverProject,
        scale:
            Double
    ) -> CGSize? {
        guard
            panel != .canvas,
            project.canvasWidth > 0,
            project.canvasHeight > 0,
            scale > 0
        else {
            return nil
        }

        let geometry =
            CoverWrapGeometry(
                project:
                    project
            )

        let region =
            CoverCalculator
                .panelRegion(
                    panel,
                    geometry:
                        geometry
                )

        let centerX =
            region.x
            + region.width / 2

        let centerY =
            region.y
            + region.height / 2

        return CGSize(
            width:
                (
                    0.5
                    - centerX
                )
                * project.canvasWidth
                * scale,
            height:
                (
                    0.5
                    - centerY
                )
                * project.canvasHeight
                * scale
        )
    }

    static func preferredLayerID(
        for panel:
            CoverPanelAnchor,
        in project:
            CoverProject
    ) -> UUID? {
        if let explicit =
            project.layers
                .reversed()
                .first(
                    where: {
                        $0.panelAnchor
                            == panel
                    }
                )
        {
            return explicit.id
        }

        return project.layers
            .reversed()
            .first(
                where: {
                    $0.panelAnchor
                        == nil
                    && CoverCalculator
                        .inferredPanelAnchor(
                            for:
                                $0.frame,
                            in:
                                project
                        )
                        == panel
                }
            )?
            .id
    }

    private func centerPhysicalPanel(
        _ panel:
            CoverPanelAnchor
    ) {
        let scale =
            max(
                0.0001,
                fitScaleEstimate
                * zoom
            )

        guard
            let target =
                Self.centeredPanelPan(
                    for:
                        panel,
                    in:
                        project,
                    scale:
                        scale
                )
        else {
            return
        }

        panOffset =
            target
    }

    private func focusPhysicalPanel(
        _ panel:
            CoverPanelAnchor?
    ) {
        guard
            let panel,
            panel != .canvas
        else {
            return
        }

        synchronizeFromSourceProjects()

        if let activeProjectID,
           let index =
            projects.firstIndex(
                where: {
                    $0.id
                        == activeProjectID
                }
            )
        {
            projectIndex =
                index
        }

        guard
            project.type
                == .printFullWrap
        else {
            return
        }

        showingHome =
            false

        hasOpenedProject =
            true

        workspace.rightDock =
            true

        workspace.layers =
            true

        rightDockTab =
            .layers

        activeTool =
            .move

        if let id =
            Self.preferredLayerID(
                for:
                    panel,
                in:
                    project
            )
        {
            selectedID =
                id

            selectedIDs =
                [
                    id
                ]
        } else {
            selectedID =
                nil

            selectedIDs =
                []
        }

        canvasFocused =
            true

        DispatchQueue.main.async {
            centerPhysicalPanel(
                panel
            )
        }
}

    private var project: CoverProject { projects[min(projectIndex,projects.count-1)] }
    private var activeSelection: Data? {
        get { project.editorActiveSelectionMask }
        nonmutating set {
            guard projects.indices.contains(projectIndex) else { return }
            projects[projectIndex].editorActiveSelectionMask = newValue
            if newValue == nil {
                projects[projectIndex].editorActiveSelectionLayerID = nil
            }
        }
    }
    private var selectionLayerID: UUID? {
        get { project.editorActiveSelectionLayerID }
        nonmutating set {
            guard projects.indices.contains(projectIndex) else { return }
            projects[projectIndex].editorActiveSelectionLayerID = newValue
        }
    }
    private var dismissedSelection: (Data, UUID)? {
        get {
            guard let mask = project.editorDismissedSelectionMask,
                  let layerID = project.editorDismissedSelectionLayerID
            else { return nil }
            return (mask, layerID)
        }
        nonmutating set {
            guard projects.indices.contains(projectIndex) else { return }
            projects[projectIndex].editorDismissedSelectionMask = newValue?.0
            projects[projectIndex].editorDismissedSelectionLayerID = newValue?.1
        }
    }
    private var selectedIndex: Int? { project.layers.firstIndex(where:{$0.id == selectedID}) }
    private var selectedLayer: CoverLayer? { selectedIndex.map{project.layers[$0]} }
    private var selectionPixelSize: CGSize { guard let data=selectedLayer?.imageData,let rep=NSBitmapImageRep(data:data) else{return .zero};return CGSize(width:rep.pixelsWide,height:rep.pixelsHigh) }
    private var selectedBounds:CGRect?{let ids=selectedIDs.isEmpty ? Set([selectedID].compactMap{$0}):selectedIDs;let frames=project.layers.filter{ids.contains($0.id)}.map{CGRect(x:$0.frame.x,y:$0.frame.y,width:$0.frame.width,height:$0.frame.height)};guard let first=frames.first else{return nil};return frames.dropFirst().reduce(first){$0.union($1)}}
    private var booleanSelectedPathIDs:Set<UUID>{
        let candidates =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        return Set(
            project.layers
                .filter {
                    let contours =
                        CoverEditorEngine
                            .vectorContours(
                                for:$0
                            )

                    return
                        candidates.contains($0.id)
                        && $0.kind == .path
                        && !$0.locked
                        && $0.positionLocked != true
                        && !contours.isEmpty
                        && CoverEditorEngine
                            .vectorContourClosures(
                                for:$0,
                                contourCount:contours.count
                            )
                            .contains(true)
                        && abs($0.skewX ?? 0)<0.0000001
                        && abs($0.skewY ?? 0)<0.0000001
                }
                .map(\.id)
        )
    }

    private var compoundSelectedPathIDs:Set<UUID>{
        let candidates =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        return Set(
            project.layers
                .filter {
                    let contours =
                        CoverEditorEngine
                            .vectorContours(
                                for:$0
                            )

                    return
                        candidates.contains($0.id)
                        && $0.kind == .path
                        && !contours.isEmpty
                        && abs($0.skewX ?? 0)
                            < 0.0000001
                        && abs($0.skewY ?? 0)
                            < 0.0000001
                }
                .map(\.id)
        )
    }

    private var canSeparateSelectedCompoundPath:Bool {
        guard let layer =
            selectedLayer,
              layer.kind == .path
        else {
            return false
        }

        return CoverEditorEngine
            .vectorContours(
                for:layer
            )
            .count >= 2
    }

    private func supportsPathSelectionTarget(
        _ layer: CoverLayer
    ) -> Bool {
        layer.imageData != nil
        && layer.frame.width > 0.0000001
        && layer.frame.height > 0.0000001
        && abs(layer.rotation)
            < 0.0000001
        && layer.flipHorizontal == false
        && layer.flipVertical == false
        && abs(layer.skewX ?? 0)
            < 0.0000001
        && abs(layer.skewY ?? 0)
            < 0.0000001
    }

    private var pathSelectionTargetLayer:
        CoverLayer?
    {
        if let explicit =
            project.layers
                .reversed()
                .first(
                    where: {
                        $0.id != selectedID
                        && selectedIDs.contains(
                            $0.id
                        )
                        && supportsPathSelectionTarget(
                            $0
                        )
                    }
                )
        {
            return explicit
        }

        return project.layers
            .reversed()
            .first(
                where: {
                    $0.id != selectedID
                    && supportsPathSelectionTarget(
                        $0
                    )
                }
            )
    }

    private var canMakeSelectionFromSelectedPath:
        Bool
    {
        guard let layer =
            selectedLayer,
              layer.kind == .path,
              abs(layer.skewX ?? 0)
                < 0.0000001,
              abs(layer.skewY ?? 0)
                < 0.0000001,
              pathSelectionTargetLayer != nil
        else {
            return false
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        layer
                )

        guard !contours.isEmpty else {
            return false
        }

        let closures =
            CoverEditorEngine
                .vectorContourClosures(
                    for:
                        layer,
                    contourCount:
                        contours.count
                )

        return contours.indices.contains {
            index in

            closures[index]
            && contours[index].count >= 3
        }
    }

    private var selectionToPathHostInfo:
        (
            layer: CoverLayer,
            width: Int,
            height: Int
        )?
    {
        guard let id =
            selectionLayerID,
              let layer =
                project.layers.first(
                    where: {
                        $0.id == id
                    }
                ),
              let imageData =
                layer.imageData,
              let representation =
                NSBitmapImageRep(
                    data:
                        imageData
                ),
              representation.pixelsWide > 0,
              representation.pixelsHigh > 0
        else {
            return nil
        }

        return (
            layer,
            representation.pixelsWide,
            representation.pixelsHigh
        )
    }

    private var canConvertSelectionToPath:
        Bool
    {
        guard let selection =
            activeSelection,
              let host =
                selectionToPathHostInfo,
              selection.count
                == host.width
                * host.height
        else {
            return false
        }

        return selection.contains(
            where: {
                $0 >= 128
            }
        )
    }




    private var explicitTransformableSelectedIDs:Set<UUID>{
        let ids =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        return CoverEditorEngine.transformableLayerIDs(
            project.layers,
            ids:ids
        )
    }

    private var transformableSelectedIDs:Set<UUID>{
        let explicit =
            explicitTransformableSelectedIDs

        guard !maskSelected else {
            return explicit
        }

        let linked =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                project.layers,
                ids:explicit
            )

        return CoverEditorEngine.transformableLayerIDs(
            project.layers,
            ids:linked
        )
    }

    private var transformableSelectedBounds:CGRect?{
        CoverEditorEngine.transformBounds(
            project.layers,
            ids:transformableSelectedIDs,
            canvasSize:CGSize(width:project.canvasWidth,height:project.canvasHeight)
        )
    }

    private var linkEligibleSelectedIDs:Set<UUID>{
        let ids =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        return CoverEditorEngine.linkableLayerIDs(
            project.layers,
            ids:ids
        )
    }

    private var canLinkSelectedLayers:Bool{
        linkEligibleSelectedIDs.count >= 2
    }

    private var canUnlinkSelectedLayers:Bool{
        let ids =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        return project.layers.contains {
            ids.contains($0.id)
            && $0.linkSetID != nil
        }
    }

    private var canSelectLinkedLayers:Bool{
        guard let selectedID,
              let layer =
                project.layers.first(where:{
                    $0.id == selectedID
                })
        else {
            return false
        }

        return layer.linkSetID != nil
    }
    private var activePhysicalPanelForStudio:
        CoverPanelAnchor?
    {
        if let selectedLayer {
            if let explicit =
                selectedLayer.panelAnchor
            {
                return explicit == .canvas
                    ? nil
                    : explicit
            }

            return CoverCalculator
                .inferredPanelAnchor(
                    for:
                        selectedLayer.frame,
                    in:
                        project
                )
        }

        if let focusPanel,
           focusPanel != .canvas
        {
            return focusPanel
        }

        return nil
    }


    private var projectUnitInches:Double{switch project.unit ?? "in"{case "mm":1/25.4;case "px":1/max(1,project.dpi);default:1}}

    // BOLD_LIGHT_WORKSPACE_V14
    var body: some View {
        boldLightCoverCreatorBody
            .preferredColorScheme(.light)
            .focusedSceneValue(\.coverWorkspaceMenus, nativeCoverMenus)
            .onChange(of:project) { _, _ in if isActive { saveProjects() } }

    }

    private var nativeCoverMenus: CoverWorkspaceMenus? {
        guard isActive else { return nil }
        return CoverWorkspaceMenus(file:AnyView(fileMenuItems), edit:AnyView(editMenuItems), image:AnyView(imageMenuItems),
            layer:AnyView(layerMenuItems), selection:AnyView(selectMenuItems), filter:AnyView(filterMenuItems),
            view:AnyView(viewMenuItems), window:AnyView(windowMenuItems),
            open:{ presentImport(template:false,asProject:true) }, save:saveProjects,
            undo:undo, redo:redo, canUndo:!undoStack.isEmpty, canRedo:!redoStack.isEmpty)
    }

    @ViewBuilder
    private var boldLightCoverCreatorBody: some View {
        VStack(spacing:0) {
            if isActive {
            BookWorkspaceSwitcher(current: .coverCreator) { destination in
                guard destination != .coverCreator else { return }
                saveProjects()
                if destination == .bookStudio3D {
                    onOpenBookStudioPanel(
                        activePhysicalPanelForStudio
                    )
                    onOpenBookStudio()
                }
                else { onOpenManuscript() }
            }
            menuBar
            Divider()
            if showingHome {
                coverHome
            } else {
                toolOptionsBar
                if project.type == .printFullWrap { physicalPanelBar }
                Divider()
                HStack(spacing:0) {
                    if workspace.toolbar { toolRail.zIndex(1); Divider() }
                    canvasWorkspace
                    if workspace.rightDock { Divider(); rightDock.frame(width:310) }
                }
                Divider()
                editorStatusBar
            }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .font(.system(size:12))
        .controlSize(.small)
        .preferredColorScheme(.light)
        .frame(minWidth:780,minHeight:560)
        .onAppear{
            if isActive {
                synchronizeFromSourceProjects()
                focusPhysicalPanel(
                    focusPanel
                )
                installCanvasKeyMonitor()
            }
        }
        .onChange(of:isActive){_,active in
            if active {
                synchronizeFromSourceProjects()
                focusPhysicalPanel(
                    focusPanel
                )
                installCanvasKeyMonitor()
            }
            else {
                canvasFocused=false
                if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor=nil }
                saveProjects()
            }
        }
        .onChange(of:sourceProjects){_,incoming in
            // A document can replace another while Cover Creator stays mounted and
            // active. Always accept the newly opened document's authoritative cover
            // projects; filtering on isActive leaves the prior document's geometry in
            // @State when both documents reuse the same active project ID.
            synchronizeFromSourceProjects(incoming)
        }
        .onChange(of:activeProjectID){_,id in
            if let id,let index=projects.firstIndex(where:{$0.id == id}) {
                if index != projectIndex { projectIndex=index }
                synchronizeProductionControls(for: projects[index])
            }
        }
        .onChange(of:focusRequestID){_,requestID in
            guard
                isActive,
                requestID != nil
            else {
                return
            }

            focusPhysicalPanel(
                focusPanel
            )
        }
        .onDisappear{if let keyMonitor{NSEvent.removeMonitor(keyMonitor);self.keyMonitor=nil};saveProjects()}
        .onChange(of:project.layers.map(\.id)){previous,current in
            if let selectedID,!previous.contains(selectedID),current.contains(selectedID){selectedIDs=[selectedID]}
        }
        .onChange(of:projectIndex){_,_ in selectedID=nil;selectedIDs=[];selectedMaskLayerID=nil;undoStack=[];redoStack=[];synchronizeProductionControls(for: project)}
        .onChange(of:selectedIDs){_,ids in if ids.isEmpty{selectedID=nil}else if selectedID.map({!ids.contains($0)}) ?? true{selectedID=ids.first}}
        .onChange(of:selectedID){_,_ in selectedPathAnchors.removeAll()}
        .onChange(of:activeTool){_,tool in if tool != .path { selectedPathAnchors.removeAll() }}
        .onDrop(of:[UTType.fileURL],isTargeted:nil) { providers in
            handleArtworkDrop(providers)
        }

        .sheet(isPresented:$showCanvasResize) {
            VStack(alignment:.leading,spacing:12) {
                Text("Canvas Size").font(.headline)
                Text("Resize around the center while preserving artwork size in inches.")
                LabeledContent("Width (inches)"){TextField("Width",value:$canvasResizeWidth,format:.number)}
                LabeledContent("Height (inches)"){TextField("Height",value:$canvasResizeHeight,format:.number)}
                HStack {
                    Button("Cancel"){showCanvasResize=false};Spacer()
                    Button("Apply"){
                        if applyCoverOperation("canvas-resize",arguments:["width":String(canvasResizeWidth),"height":String(canvasResizeHeight)]) != nil { showCanvasResize=false }
                    }
                }
            }.padding(20).frame(width:360)
        }
        .sheet(isPresented:Binding(get:{selectionRadiusPrompt != nil},set:{if !$0{selectionRadiusPrompt=nil}})) {
            VStack(alignment:.leading,spacing:12) {
                Text("Selection Edge").font(.headline)
                HStack { Text("Radius (px)");TextField("Radius",value:$selectionRadius,format:.number).frame(width:70);Text("\(Int(selectionRadius.rounded())) px").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                Slider(value:$selectionRadius,in:0...1000,step:1).accessibilityLabel("Selection edge radius in pixels")
                Text("Feather softens the edge. Expand and Contract move the existing irregular boundary by this radius.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                HStack { Button("Cancel"){selectionRadiusPrompt=nil};Spacer();Button("Apply"){if let operation=selectionRadiusPrompt{selectionRadius=max(0,min(1000,selectionRadius));applySelectionRadius(operation)};selectionRadiusPrompt=nil}.keyboardShortcut(.defaultAction) }
            }.padding(20).frame(width:280)
        }
        .sheet(isPresented:Binding(get:{selectionTransformSnapshot != nil},set:{if !$0{cancelSelectionTransform()}})) {
            VStack(alignment:.leading,spacing:10) {
                Text("Transform Selection").font(.headline)
                LabeledContent("X (pixels)"){TextField("X",value:$selectionTranslationX,format:.number)}
                LabeledContent("Y (pixels)"){TextField("Y",value:$selectionTranslationY,format:.number)}
                LabeledContent("Scale"){TextField("Scale",value:$selectionScale,format:.number)}
                LabeledContent("Rotation (degrees)"){TextField("Rotation",value:$selectionAngle,format:.number)}
                HStack {
                    Button("Cancel",action:cancelSelectionTransform)
                    Spacer()
                    Button("Apply"){applySelectionTransform(dx:selectionTranslationX,dy:selectionTranslationY,scale:CGSize(width:max(0.01,selectionScale),height:max(0.01,selectionScale)),rotation:selectionAngle)}
                }
            }.padding(20).frame(width:320)
        }
        .sheet(
            isPresented:
                $showPathGeometryTransform
        ) {
            VStack(
                alignment:
                    .leading,
                spacing:
                    12
            ) {
                Text(
                    "Transform Selected Path Geometry"
                )
                .font(
                    .headline
                )

                LabeledContent(
                    "Scale X"
                ) {
                    TextField(
                        "Scale X",
                        value:
                            $pathGeometryScaleX,
                        format:
                            .number
                    )
                }

                LabeledContent(
                    "Scale Y"
                ) {
                    TextField(
                        "Scale Y",
                        value:
                            $pathGeometryScaleY,
                        format:
                            .number
                    )
                }

                LabeledContent(
                    "Rotation (degrees)"
                ) {
                    TextField(
                        "Rotation",
                        value:
                            $pathGeometryRotation,
                        format:
                            .number
                    )
                }

                Text(
                    "Transforms selected anchors only. Bézier handles move with their anchors."
                )
                .font(
                    .caption
                )
                .foregroundStyle(
                    .secondary
                )

                HStack {
                    Button(
                        "Cancel"
                    ) {
                        showPathGeometryTransform =
                            false
                    }

                    Spacer()

                    Button(
                        "Apply"
                    ) {
                        applySelectedPathGeometryTransform(
                            scaleX:
                                pathGeometryScaleX,
                            scaleY:
                                pathGeometryScaleY,
                            rotation:
                                pathGeometryRotation
                        )

                        showPathGeometryTransform =
                            false
                    }
                    .keyboardShortcut(
                        .defaultAction
                    )
                }
            }
            .padding(
                20
            )
            .frame(
                width:
                    340
            )
        }
        .sheet(isPresented:$showNewGuide){VStack(alignment:.leading,spacing:12){Text("New Guide").font(.title2.bold());Picker("Orientation",selection:$newGuideAxis){Text("Vertical").tag("Vertical");Text("Horizontal").tag("Horizontal")};TextField("Position (\(project.unit ?? "in"))",value:$newGuidePosition,format:.number);HStack{Button("Cancel"){showNewGuide=false};Spacer();Button("Add Guide"){addGuide(axis:newGuideAxis,position:newGuidePosition)}.keyboardShortcut(.defaultAction)}}.padding(20).frame(width:320)}
        .sheet(isPresented:$showSaveSelection){VStack(alignment:.leading,spacing:12){Text("Save Selection").font(.title2.bold());TextField("Name",text:$savedSelectionName);HStack{Button("Cancel"){showSaveSelection=false};Spacer();Button("Save"){saveSelection(named:savedSelectionName);showSaveSelection=false}.keyboardShortcut(.defaultAction)}}.padding(20).frame(width:340)}
        .alert("Cover Creator",isPresented:Binding(get:{errorMessage != nil},set:{if !$0 {errorMessage=nil}})) { Button("OK",role:.cancel){errorMessage=nil} } message:{Text(errorMessage ?? "")}
        .sheet(isPresented: $showPhysicalProofSheet) {
            BOLDPrintCoverProofSheet(coverProject: project)
        }
        .confirmationDialog("Export Cover",isPresented:$showExport,titleVisibility:.visible) {
            ForEach(project.type == .ebookFront ? ["png","png-transparent","jpeg","svg","psd"] : ["pdf","png","png-transparent","jpeg","svg","psd"],id:\.self) { format in Button(format == "pdf" ? "Print PDF…" : format == "psd" ? "Photoshop PSD…" : format == "svg" ? "SVG Vector…" : format == "png-transparent" ? "PNG (Transparent)…" : format.uppercased()) { export(format:format,proof:false) } }
            Button("Export Proof (guides and template)") { export(format:project.type == .printFullWrap ? "pdf" : "png",proof:true) }
            if project.type == .printFullWrap {
                Button("Create Physical Wrap Guide PDF…") { showPhysicalProofSheet = true }
            }
            Button("Cancel",role:.cancel) { }
        }
        .confirmationDialog("Add Dropped File",isPresented:$showDropChoice,titleVisibility:.visible){Button("Add as Artwork"){if let droppedURL{importArtwork(droppedURL,template:false)}};Button("Use as Template"){if let droppedURL{importArtwork(droppedURL,template:true)}};Button("Cancel",role:.cancel){droppedURL=nil}} message:{Text("Templates are reference overlays fitted into this cover without resizing it.")}
    }

}

// MARK: - Workspace menus and panels

private extension BookCoverCreatorView {
    private var coverHome: some View {
        CoverEditorHome(projects:hasOpenedProject ? projects : [],activeProjectID:hasOpenedProject ? project.id : nil,
                        canCreate:CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject),
                        openProject:{index in
                            guard projects.indices.contains(index) else { return }
                            let selectedID = projects[index].id
                            synchronizeFromSourceProjects(sourceProjects)
                            guard let refreshedIndex = projects.firstIndex(where: { $0.id == selectedID }) else { return }
                            projectIndex=refreshedIndex
                            synchronizeProductionControls(for: projects[refreshedIndex])
                            showingHome=false
                            hasOpenedProject=true
                        },
                        newEbook:{createProject(.ebookFront)},newPrint:{createProject(.printFullWrap)},
                        openImage:{presentImport(template:false,asProject:true)},openTemplate:{presentImport(template:true)})
    }

    private func createProject(_ type:CoverProjectType) {
        guard CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject) else {
            errorMessage="A manuscript can contain up to eight cover projects."
            return
        }
        var newProject=CoverProject(type:type)
        if type == .printFullWrap {
            newProject=CoverProject(type:.printFullWrap,width:12.79,height:9.25)
            newProject.bleed=0.125
            newProject.spineWidth=0.54
            newProject.backWidth=6
            newProject.trimWidth=6
            newProject.trimHeight=9
        }
        if hasOpenedProject { projects.append(newProject);projectIndex=projects.count-1 }
        else { projects[0]=newProject;projectIndex=0 }
        hasOpenedProject=true
        showingHome=false
        selectedID=nil
        selectedIDs=[]
        undoStack=[]
        redoStack=[]
        fitCover()
    }

    private func synchronizeFromSourceProjects(
        _ incoming: [CoverProject]? = nil
    ) {
        let source =
            incoming
            ?? sourceProjects

        guard source != projects else {
            return
        }

        let currentID: UUID? =
            projects.indices.contains(projectIndex)
            ? projects[projectIndex].id
            : nil

        if source.isEmpty {
            projects = [CoverProject()]
            projectIndex = 0
            showingHome = true
            hasOpenedProject = false
            selectedID = nil
            selectedIDs = []
            selectedMaskLayerID = nil
            undoStack = []
            redoStack = []
            return
        }

        let requestedID =
            activeProjectID
            ?? currentID

        projects =
            source

        projectIndex =
            requestedID.flatMap {
                id in
                source.firstIndex {
                    $0.id == id
                }
            }
            ?? 0

        showingHome = false
        hasOpenedProject = true
        selectedID = nil
        selectedIDs = []
        selectedMaskLayerID = nil
        undoStack = []
        redoStack = []

        let refreshed =
            projects[projectIndex]

        synchronizeProductionControls(for: refreshed)
    }

    /// Production controls belong to the selected cover project. Reset all derived values
    /// together whenever selection changes so a prior project's page count cannot leak.
    private func synchronizeProductionControls(for selected: CoverProject) {
        let selectedCaliper = selected.spineCaliperInches
            ?? PrintCoverSpecification.kdpBlackAndWhiteWhitePaperCaliper
        caliper = selectedCaliper
        pageCount = selected.spinePageCount
            ?? (selected.type == .printFullWrap
                ? CoverCalculator.inferredPageCount(
                    spineWidth: selected.spineWidth,
                    caliperInches: selectedCaliper
                )
                : 240)
        manualSpine = selected.spineWidth
        useCaliper = selected.spineCaliperInches != nil
    }

    private func saveProjects() {
        onSave(hasOpenedProject ? projects : [],project.id)
    }

    private func createPaperback(_ paper: PrintPaperStockPreset) {
        guard CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject) else {
            errorMessage = "A manuscript can contain up to eight cover projects. Save or remove a cover project before creating another."
            return
        }
        do {
            let converted = try convertPaperback(project, paper)
            projects.append(converted)
            projectIndex = projects.count - 1
            hasOpenedProject = true
            showingHome = false
            selectedID = nil
            selectedIDs = []
            saveProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func createHardcover(_ paper: PrintPaperStockPreset) {
        guard CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject) else {
            errorMessage = "A manuscript can contain up to eight cover projects. Save or remove a cover project before creating another."
            return
        }
        do {
            let converted = try convertHardcover(project, paper)
            projects.append(converted)
            projectIndex = projects.count - 1
            hasOpenedProject = true
            showingHome = false
            selectedID = nil
            selectedIDs = []
            saveProjects()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var commands: CoverCommandAvailability {
        CoverCommandAvailability(hasLayer:selectedLayer != nil,hasImage:selectedLayer?.imageData != nil,
                                 hasSelection:activeSelection != nil,hasDismissedSelection:dismissedSelection != nil)
    }

    @ViewBuilder private var fileMenuItems: some View {
                        Button("Home") { synchronizeFromSourceProjects(sourceProjects); showingHome=true }
                        Button("New eBook") { createProject(.ebookFront) }.disabled(!CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject))
                        Button("New Print Wrap") { createProject(.printFullWrap) }.disabled(!CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject))
                        Button("Open…"){presentImport(template:false,asProject:true)}
                        Button("Open & Place…"){presentImport(template:false)}
                        Button("Place Embedded…",action:presentPlaceEmbedded)
                        Button("Place Linked…",action:presentPlaceLinked)
                        Button("Import Cover Template…"){presentImport(template:true)}
                        Divider()
                        Button("Save"){saveProjects()}
                        Button("Save as PSD…"){export(format:"psd",proof:false)}
                        Menu("Export As") {
                            Button("PNG…"){export(format:"png",proof:false)}
                            Button("JPEG…"){export(format:"jpeg",proof:false)}
                            Button("SVG…"){export(format:"svg",proof:false)}
                            Button("PDF…"){export(format:"pdf",proof:false)}
                        }
                        Button("Export Cover…"){showExport=true}
                        if project.type == .printFullWrap { Button("Export Print PDF…"){export(format:"pdf",proof:false)} }
                        Button("Save and Close"){saveProjects();onOpenManuscript()}

    }
    @ViewBuilder private var editMenuItems: some View {
                        Button("Undo",action:undo).keyboardShortcut("z",modifiers:.command).disabled(undoStack.isEmpty)
                        Button("Redo",action:redo).keyboardShortcut("z",modifiers:[.command,.shift]).disabled(redoStack.isEmpty)
                        Divider()
                        Button("Copy Layer",action:copySelectedLayer).keyboardShortcut("c").disabled(!commands.hasLayer)
                        Button("Cut",action:cutSelectedLayer).keyboardShortcut("x").disabled(!commands.hasLayer)
                        Button("Copy Merged",action:copyMerged)
                        Button("Paste",action:pasteClipboard).keyboardShortcut("v")
                        Button("Fill Selection with Foreground",action:fillSelection).disabled(!commands.hasSelection)
                        transformMenu

    }
    @ViewBuilder private var imageMenuItems: some View {
                        Button("Document Properties"){selectedID=nil;selectedIDs=[];maskSelected=false;workspace.properties=true;workspace.rightDock=true}
                        Button("Canvas Size…") { canvasResizeWidth=project.canvasWidth;canvasResizeHeight=project.canvasHeight;showCanvasResize=true }
                        Menu("Adjustments") { adjustmentCommands }
                        transformMenu

    }
    @ViewBuilder private var layerMenuItems: some View {
                        Menu("New") { addCommands;Button("Paint Layer",action:addPaintLayer) }
                        Button("Duplicate"){if let selectedID{duplicate(selectedID)}}.disabled(!commands.hasLayer)
                        Button("Group",action:groupSelectedLayers).disabled(selectedIDs.count<2)
                        Button("Ungroup"){
                            if let id=selectedID, let ids=applyCoverOperation("ungroup",arguments:["layerID":id.uuidString]) { selectedIDs=Set(ids);selectedID=ids.first }
                        }.disabled(selectedLayer?.kind != .group)
                Button("Link Layers",action:linkSelectedLayers).disabled(!canLinkSelectedLayers)
                Button("Unlink Layers",action:unlinkSelectedLayers).disabled(!canUnlinkSelectedLayers)
                Button("Select Linked Layers",action:selectLinkedLayers).disabled(!canSelectLinkedLayers)
                        Button("Move Backward"){moveLayer(-1)}.disabled(!commands.hasLayer)
                        Button("Move Forward"){moveLayer(1)}.disabled(!commands.hasLayer)
                        Menu("New Adjustment Layer") { adjustmentCommands }
                        Menu("Smart Object") {
                            Button("Place Embedded…",action:presentPlaceEmbedded)
                            Button("Place Linked…",action:presentPlaceLinked)
                            if let layer=selectedLayer, layer.kind == .smartObject {
                                Button("Replace Contents…"){presentReplaceSmartObjectContents(layer.id)}.disabled(layer.locked)
                                Button("Rasterize"){rasterizeSmartObject(layer.id)}.disabled(layer.locked)
                            }
                        }
                        Button("Layer Style…"){workspace.properties=true;workspace.rightDock=true}.disabled(!commands.hasLayer)
                        Button("Mask from Selection",action:applySelectionAsMask).disabled(!commands.canMask)
                        if let i=selectedIndex {
                            Button("Toggle Clipping Mask"){toggleClip(at:i)}
                            if selectedLayer?.maskData != nil {
                                Button("Invert Mask"){invertMask(at:i)}
                                Button("Apply Mask"){applyMask(at:i)}
                            }
                        }
                        Button("Delete",role:.destructive){if let selectedID{delete(selectedID)}}.disabled(!commands.hasLayer)

    }
    @ViewBuilder private var selectMenuItems: some View { selectionCommands
    }
    @ViewBuilder private var filterMenuItems: some View {
                        ForEach([CoverAdjustmentKind.gaussianBlur,.sharpen,.invert]) { kind in
                            Button(kind.workspaceTitle){addAdjustment(kind)}
                        }

    }
    @ViewBuilder private var viewMenuItems: some View { viewCommands
    }
    @ViewBuilder private var windowMenuItems: some View {
                        Toggle("Toolbar",isOn:$workspace.toolbar)
                        Toggle("History and Swatches",isOn:$workspace.historyAndSwatches)
                        Toggle("Layers",isOn:$workspace.layers)
                        Toggle("Paths",isOn:$workspace.paths)
                        Toggle("Properties",isOn:$workspace.properties)
                        Toggle("Character",isOn:$workspace.character)
                        Toggle("Paragraph",isOn:$workspace.paragraph)
                        Toggle("Adjustments",isOn:$workspace.adjustments)
                        Toggle("Channels",isOn:$workspace.channels)
                        Divider()
                        Button("Show All Cover Panels") {
                            workspace.showAllDockPanels()
                        }
                        Toggle("Right Dock",isOn:$workspace.rightDock)

    }

    private var menuBar: some View {
        HStack(spacing:4) {
            ScrollView(.horizontal) {
                HStack(spacing:2) {
                    Menu("File") { fileMenuItems }
                    Menu("Edit") { editMenuItems }
                    Menu("Image") { imageMenuItems }
                    Menu("Layer") { layerMenuItems }
                    Menu("Select") { selectMenuItems }
                    Menu("Filter") { filterMenuItems }
                    Menu("View") { viewMenuItems }
                    Menu("Window") { windowMenuItems }
                    Menu("More") {
                        Picker("Project",selection:$projectIndex) { ForEach(projects.indices,id:\.self){Text(projects[$0].name).tag($0)} }
                    }
                }.menuStyle(.borderlessButton).fixedSize()
            }.scrollIndicators(.hidden)
            if !showingHome {
                Text(project.name).lineLimit(1).foregroundStyle(.secondary).frame(maxWidth:160)
                Button { workspace.rightDock.toggle() } label:{Image(systemName:"sidebar.right")}
                    .help("Toggle Right Dock").accessibilityLabel("Toggle Right Dock")
            }
            Button("Done"){saveProjects();onOpenManuscript()}
        }.padding(.horizontal,8).frame(height:32).background(Color(nsColor: .windowBackgroundColor))
    }

    private var transformMenu: some View {
        Menu("Transform") {
            Button("Free Transform"){selectTool(.move);beginTransform()}.keyboardShortcut("t",modifiers:.command)
            Button("Perspective"){selectTool(.move);beginPerspective()}.disabled(!commands.hasImage)
            Button("Warp…"){selectTool(.move);beginTransform();warpEditing=true;if let i=selectedIndex{mutatePreviewLayer(at:i){$0.warpPreset=warpPreset;$0.warpAmount=$0.warpAmount ?? 0.25}}}
            Divider()
            Button("Rotate 90° CW"){rotateSelection(90)}
            Button("Rotate 90° CCW"){rotateSelection(-90)}
            Button("Rotate 180°"){rotateSelection(180)}
            Button("Flip Horizontal"){flipSelection(horizontal:true)}
            Button("Flip Vertical"){flipSelection(horizontal:false)}
        }.disabled(!commands.hasLayer)
    }

    private var toolRail: some View {
        CoverEditorToolbar(activeTool:activeTool,lassoMode:$lassoMode,selectTool:selectTool)
    }

    private var canvasWorkspace: some View {
        VStack(spacing:0) {
            if workspace.rulers { horizontalRuler.frame(height:20) }
            HStack(spacing:0) {
                if workspace.rulers { verticalRuler.frame(width:28) }
                canvas
                    // Bound both drawing and gestures to the viewport, below the rulers.
                    .contentShape(Rectangle())
                    .clipped()
            }
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
            .background(Color(red:37.0/255,green:37.0/255,blue:37.0/255))
    }

    private var physicalPanelBar: some View {
        HStack(spacing:12) {
            Text("Cover panels").foregroundStyle(.secondary)
            ForEach([CoverPanelAnchor.canvas,.back,.spine,.front],id:\.self) { panel in
                Button(panel == .canvas ? "Full Wrap" : panel.rawValue.capitalized) {
                    inspectedPhysicalPanel = panel
                    if panel == .canvas { fitCover() }
                    else {
                        centerPhysicalPanel(panel)
                        if let id = Self.preferredLayerID(for:panel,in:project) { selectedID = id; selectedIDs = [id] }
                    }
                }
                .buttonStyle(.bordered)
                .tint(inspectedPhysicalPanel == panel ? Color.accentColor:Color.gray)
                .accessibilityIdentifier("cover.panel."+panel.rawValue)
            }
            autoFitPanelMenu
            Text(String(format:"Spine %.3f in",project.spineWidth)).monospacedDigit()
            Menu("Convert to Paperback") {
                Button("KDP B&W · White Paper") { createPaperback(.kdpWhite) }
                Button("KDP B&W · Cream Paper") { createPaperback(.kdpCream) }
            }
            .disabled(project.type != .printFullWrap || !CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject))
            Menu("Convert to Hardcover") {
                Button("KDP Case Laminate · B&W White · 391 pages") { createHardcover(.kdpWhite) }
            }
            .disabled(project.type != .printFullWrap || !CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject))
            Spacer(minLength:0)
        }
        .padding(.horizontal,10).padding(.vertical,4)
        .accessibilityElement(children:.contain)
        .accessibilityLabel("Measured back, spine and front cover panels")
    }

    private var editorStatusBar: some View {
        HStack(spacing:12) {
            Text(project.type.displayName)
            Text("\(Int(project.rasterPixelSize.width)) × \(Int(project.rasterPixelSize.height)) px")
                .monospacedDigit()
            Text("\(Int(project.dpi)) DPI")
                .monospacedDigit()
            Spacer(minLength:8)
            if let selectedLayer { Text(selectedLayer.name).lineLimit(1) }
            Text("\(project.layers.count) layers")
            Button("\(Int(zoom * 100))%") { fitCover() }
                .buttonStyle(.plain)
                .help("Fit cover in window")
                .accessibilityLabel("Zoom \(Int(zoom * 100)) percent. Fit cover in window")
        }
        .font(.system(size:10))
        .foregroundStyle(.secondary)
        .padding(.horizontal,10)
        .frame(height:25)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var rightDock: some View {
        VStack(spacing:0) {
            coverDockTabs
            Divider()

            CoverDockPanel(
                title:rightDockTab.title,
                hide:{
                    workspace.setDockTabVisible(rightDockTab,false)
                }
            ) {
                activeRightDockPanel
            }
            .frame(maxHeight:.infinity)
        }
        .background(Color(nsColor:.windowBackgroundColor))
    }

    private var coverDockTabs: some View {
        LazyVGrid(
            columns:[
                GridItem(.flexible(),spacing:2),
                GridItem(.flexible(),spacing:2),
                GridItem(.flexible(),spacing:2)
            ],
            spacing:2
        ) {
            ForEach(workspace.availableDockTabs) { tab in
                let enabled=workspace.isDockTabVisible(tab)

                Button {
                    workspace.revealDockTab(tab)
                    rightDockTab=tab
                } label: {
                    HStack(spacing:4) {
                        Image(systemName:tab.symbol)
                            .font(.system(size:10))

                        Text(tab.compactTitle)
                            .font(
                                .system(
                                    size:10,
                                    weight:rightDockTab == tab
                                        ? .semibold
                                        : .regular
                                )
                            )
                            .lineLimit(1)
                    }
                    .foregroundStyle(
                        enabled || rightDockTab == tab
                            ? Color.primary
                            : Color.secondary
                    )
                    .frame(maxWidth:.infinity,minHeight:22)
                    .padding(.horizontal,3)
                    .background(
                        rightDockTab == tab
                            ? Color.accentColor.opacity(0.48)
                            : enabled
                                ? Color.white.opacity(0.055)
                                : Color.white.opacity(0.02)
                    )
                    .clipShape(RoundedRectangle(cornerRadius:3))
                }
                .buttonStyle(.plain)
                .help(
                    enabled
                        ? tab.title
                        : "Show \(tab.title)"
                )
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(
                    rightDockTab == tab
                        ? .isSelected
                        : []
                )
            }
        }
        .padding(5)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var activeRightDockPanel: some View {
        switch rightDockTab {
        case .history:
            historyPanel

        case .swatches:
            swatchesPanel

        case .layers:
            layersPanel

        case .paths:
            ScrollView {
                pathsPanel
            }

        case .properties:
            ScrollView {
                propertiesPanel
                    .padding(10)
            }

        case .character:
            ScrollView {
                characterPanel
                    .padding(10)
            }

        case .paragraph:
            ScrollView {
                paragraphPanel
                    .padding(10)
            }

        case .adjustments:
            ScrollView {
                adjustmentsPanel
                    .padding(10)
            }

        case .channels:
            ScrollView {
                channelsPanel
                    .padding(8)
            }
        }
    }

    private var historyPanel: some View {
        VStack(spacing:0) {
            HStack {
                Button("Undo",action:undo).disabled(undoStack.isEmpty)
                Button("Redo",action:redo).disabled(redoStack.isEmpty)
                Spacer()
                Text("\(undoStack.count) edits").foregroundStyle(.secondary)
            }.padding(.horizontal,10).padding(.vertical,5)
            ScrollView {
                VStack(spacing:1) {
                    ForEach(undoStack.indices,id:\.self) { index in
                        Button { jumpToHistory(index) } label: {
                            HStack { Image(systemName:"clock.arrow.circlepath");Text(index == 0 ? "Open" : "Edit \(index)");Spacer() }
                                .padding(.horizontal,9).frame(height:23)
                        }.buttonStyle(.plain)
                    }
                    HStack { Image(systemName:"checkmark.circle.fill");Text("Current");Spacer() }
                        .padding(.horizontal,9).frame(height:23)
                        .background(Color.accentColor.opacity(0.28))
                    ForEach(redoStack.indices.reversed(),id:\.self) { index in
                        Button { jumpToHistory(undoStack.count + redoStack.count - index) } label: {
                            HStack { Image(systemName:"arrow.uturn.forward");Text("Redo \(redoStack.count-index)");Spacer() }
                                .padding(.horizontal,9).frame(height:23)
                        }.buttonStyle(.plain)
                    }
                }.frame(maxWidth:.infinity)
            }.scrollIndicators(.visible)
        }
    }

    private var swatchesPanel: some View {
        let colors=["#000000","#FFFFFF","#D5D5D5","#474747","#3482F6","#E44D4D",
                    "#F28C28","#F5C542","#57B86B","#13A5A8","#715ACB","#D45FAD",
                    "#533E2D","#C8A77A","#224466","#7C9F72"]
        return VStack(alignment:.leading,spacing:9) {
            Text("Foreground  \(foregroundHex.uppercased())").font(.caption)
            LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:6),count:8),spacing:7) {
                ForEach(colors,id:\.self) { hex in
                    Button { foregroundHex=hex } label: {
                        RoundedRectangle(cornerRadius:2).fill(Color(nsColor:NSColor(hex:hex)))
                            .frame(height:25)
                            .overlay(RoundedRectangle(cornerRadius:2).stroke(.white.opacity(0.55),lineWidth:0.7))
                    }.buttonStyle(.plain).help(hex).accessibilityLabel("Set foreground color to \(hex)")
                }
            }
            TextField("Custom hex color",text:$foregroundHex).textFieldStyle(.roundedBorder)
        }.padding(10).frame(maxHeight:.infinity,alignment:.top)
    }

    private var pathsPanel: some View {
        VStack(spacing:0) {
            if CoverPathPanelModel.layers(in:project).isEmpty {
                VStack(spacing:7) {
                    Image(
                        systemName:
                            "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    .font(.system(size:22))
                    .foregroundStyle(.secondary)

                    Text("No paths")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button("Create Path") {
                        createPathFromPanel()
                    }
                    .buttonStyle(.borderless)
                }
                .frame(
                    maxWidth:.infinity,
                    minHeight:72
                )
            } else {
                ScrollView {
                    LazyVStack(spacing:2) {
                        ForEach(
                            CoverPathPanelModel.layers(in:project),
                            id:\.id
                        ) { layer in
                            pathPanelRow(layer)
                        }
                    }
                    .padding(6)
                }
                .scrollIndicators(.visible)
            }

            Divider()

            HStack(spacing:8) {
                Button {
                    createPathFromPanel()
                } label: {
                    Label(
                        "New Path",
                        systemImage:"plus.square"
                    )
                }
                .help("New Path")

                Spacer()

                Button {
                    if let id=selectedID,
                       project.layers.contains(
                        where:{
                            $0.id == id &&
                            $0.kind == .path
                        }
                       ) {
                        deletePathFromPanel(id)
                    }
                } label: {
                    Label(
                        "Delete Path",
                        systemImage:"trash"
                    )
                }
                .help("Delete Path")
                .disabled(
                    selectedLayer?.kind != .path
                )
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(8)
        }
    }

    private func pathPanelRow(
        _ layer:CoverLayer
    ) -> some View {
        HStack(spacing:6) {
            Button {
                selectPathFromPanel(
                    layer.id
                )
            } label: {
                HStack(spacing:7) {
                    Image(
                        systemName:
                            "point.topleft.down.curvedto.point.bottomright.up"
                    )
                    .frame(width:18)

                    VStack(
                        alignment:.leading,
                        spacing:1
                    ) {
                        Text(layer.name)
                            .lineLimit(1)

                        Text(
                            "\(CoverPathPanelModel.anchorCount(for:layer)) anchors • \(CoverPathPanelModel.status(for:layer))"
                        )
                        .font(.system(size:9))
                        .foregroundStyle(.secondary)
                    }

                    Spacer(minLength:0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Select \(layer.name)")

            Button {
                togglePathClosedFromPanel(
                    layer.id
                )
            } label: {
                Image(
                    systemName:
                        CoverPathPanelModel.isClosed(layer)
                        ? "rectangle.compress.vertical"
                        : "rectangle.expand.vertical"
                )
            }
            .buttonStyle(.borderless)
            .help(
                CoverPathPanelModel.isClosed(layer)
                ? "Open Path"
                : "Close Path"
            )
            .disabled(
                layer.locked ||
                CoverPathPanelModel.anchorCount(for:layer) < 2
            )

            Button {
                deletePathFromPanel(
                    layer.id
                )
            } label: {
                Image(systemName:"trash")
            }
            .buttonStyle(.borderless)
            .help("Delete \(layer.name)")
        }
        .padding(.horizontal,7)
        .padding(.vertical,5)
        .background(
            selectedID == layer.id
            ? Color.accentColor.opacity(0.24)
            : Color.clear
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius:4
            )
        )
    }

    private var layersPanel: some View {
        VStack(spacing:0) {
            List(selection:$selectedIDs) {
                ForEach(project.layers.reversed()) { layer in
                    layerRow(layer).tag(layer.id).contextMenu {
                        Button("Duplicate"){
                            duplicate(layer.id)
                        }

                        if layer.kind == .shape {
                            Button(
                                "Convert to Path"
                            ) {
                                convertShapeToPath(
                                    layer.id
                                )
                            }
                            .disabled(
                                layer.locked
                            )
                        }

                        if layer.kind == .smartObject {
                            if layer.smartObject?.storageMode == .linked {
                                Button(
                                    "Relink…"
                                ) {
                                    presentRelinkSmartObject(
                                        layer.id
                                    )
                                }
                                .disabled(
                                    layer.locked
                                )

                                Button(
                                    "Update Modified Content"
                                ) {
                                    updateLinkedSmartObjectContents(
                                        layer.id
                                    )
                                }
                                .disabled(
                                    layer.locked
                                    || !linkedSmartObjectCanUpdate(
                                        layer
                                    )
                                )

                                Button(
                                    "Convert to Embedded"
                                ) {
                                    convertLinkedSmartObjectToEmbedded(
                                        layer.id
                                    )
                                }
                                .disabled(
                                    layer.locked
                                )
                            } else {
                                Button(
                                    "Replace Contents…"
                                ) {
                                    presentReplaceSmartObjectContents(
                                        layer.id
                                    )
                                }
                                .disabled(
                                    layer.locked
                                )
                            }

                            Button(
                                "Rasterize Smart Object"
                            ) {
                                rasterizeSmartObject(
                                    layer.id
                                )
                            }
                            .disabled(
                                layer.locked
                            )
                        }

                        Button(
                            "Delete",
                            role:.destructive
                        ){
                            delete(layer.id)
                        }
                    }
                }
            }.listStyle(.plain)
            Divider()
            HStack(spacing:8) {
                Button(action:addPaintLayer){Label("New Paint Layer",systemImage:"plus.square")}.help("New Paint Layer")
                Button(
                    action:
                        presentPlaceEmbedded
                ) {
                    Label(
                        "Place Embedded",
                        systemImage:
                            "doc.badge.plus"
                    )
                }
                .help(
                    "Place Embedded Smart Object"
                )

                Button(action:presentPlaceLinked){Label("Place Linked",systemImage:"link.badge.plus")}.help("Place Linked Smart Object")
                Button(action:groupSelectedLayers){Label("Group",systemImage:"folder.badge.plus")}.help("Group Selected Layers").disabled(selectedIDs.count<2)
            Button(action:linkSelectedLayers){Label("Link",systemImage:"link")}.help("Link Selected Layers").disabled(!canLinkSelectedLayers)
            Button(action:unlinkSelectedLayers){Label("Unlink",systemImage:"link.badge.minus")}.help("Unlink Selected Layers").disabled(!canUnlinkSelectedLayers)
                Button {if let selectedID{duplicate(selectedID)}} label:{Label("Duplicate",systemImage:"square.on.square")}.help("Duplicate Layer").disabled(!commands.hasLayer)
                Button(action:applySelectionAsMask){Label("Mask from Selection",systemImage:"rectangle.inset.filled")}.help("Mask from Selection").disabled(!commands.canMask)
                Menu { Button("Move Backward"){moveLayer(-1)};Button("Move Forward"){moveLayer(1)} } label:{Label("Layer Actions",systemImage:"ellipsis")}.disabled(!commands.hasLayer)
                Spacer()
                Button {if let selectedID{delete(selectedID)}} label:{Label("Delete",systemImage:"trash")}.help("Delete Layer").disabled(!commands.hasLayer)
            }.labelStyle(.iconOnly).buttonStyle(.borderless).padding(8)
        }
    }

    private func linkedSmartObjectStatus(
        _ layer: CoverLayer
    ) -> CoverLinkedSmartObjectStatus {
        CoverEditorEngine
            .linkedSmartObjectStatus(
                in:
                    layer
            )
        ?? .unavailable
    }

    private func linkedSmartObjectCanUpdate(
        _ layer: CoverLayer
    ) -> Bool {
        switch linkedSmartObjectStatus(
            layer
        ) {
        case .modified,
             .staleBookmarkResolved:
            return true

        case .current,
             .unavailable:
            return false
        }
    }

    @ViewBuilder
    private func linkedSmartObjectIndicator(
        _ layer: CoverLayer
    ) -> some View {
        if layer.smartObject?
            .storageMode
            == .linked
        {
            switch linkedSmartObjectStatus(
                layer
            ) {
            case .current:
                Image(
                    systemName:
                        "link"
                )
                .foregroundStyle(
                    .secondary
                )
                .help(
                    "Linked Smart Object — source current"
                )

            case .modified:
                Image(
                    systemName:
                        "arrow.triangle.2.circlepath"
                )
                .foregroundStyle(
                    Color.orange
                )
                .help(
                    "Linked Smart Object — source modified"
                )

            case .unavailable:
                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .foregroundStyle(
                    Color.orange
                )
                .help(
                    "Linked Smart Object — source unavailable; cached artwork is preserved"
                )

            case .staleBookmarkResolved:
                Image(
                    systemName:
                        "link.badge.plus"
                )
                .foregroundStyle(
                    Color.orange
                )
                .help(
                    "Linked Smart Object — bookmark changed; update content to refresh the saved link"
                )
            }
        }
    }

    private func layerRow(_ layer:CoverLayer) -> some View {
        HStack(spacing:5) {
            Button {if let i=project.layers.firstIndex(where:{$0.id==layer.id}){mutateLayer(at:i){$0.visible.toggle()}}} label:{Image(systemName:layer.visible ? "eye":"eye.slash")}
                .help("Toggle Visibility").accessibilityLabel("Toggle Visibility for \(layer.name)")
            if layer.groupID != nil { Image(systemName:"arrow.turn.down.right").foregroundStyle(.secondary) }
            if layer.linkSetID != nil { Image(systemName:"link").foregroundStyle(.secondary).help("Linked Layer") }
            linkedSmartObjectIndicator(layer)
            Button {selectedID=layer.id;selectedIDs=[layer.id];maskSelected=false;if layer.kind == .text {workspace.character=true;workspace.paragraph=true;workspace.rightDock=true}} label:{layerThumbnailForLayer(layer)}
                .help("Select Layer").accessibilityLabel("Select \(layer.name)")
            Text(layer.name).lineLimit(1)
            Spacer(minLength:0)
            if let mask=layer.maskData {
                Button {selectedID=layer.id;selectedIDs=[layer.id];maskSelected=true;workspace.properties=true} label:{layerThumbnail(mask,symbol:"rectangle.inset.filled").overlay(RoundedRectangle(cornerRadius:2).stroke(maskSelected && selectedID==layer.id ? Color.accentColor:.clear,lineWidth:2))}
                    .help("Select Mask").accessibilityLabel("Select Mask for \(layer.name)")
            }
            Button {if let i=project.layers.firstIndex(where:{$0.id==layer.id}){updateProject{$0.layers[i].locked.toggle()}}} label:{Image(systemName:layer.locked ? "lock.fill":"lock.open").foregroundStyle(layer.locked ? .primary:.secondary)}
                .help("Toggle Lock").accessibilityLabel("Toggle Lock for \(layer.name)")
        }.buttonStyle(.borderless).padding(.vertical,2)
    }

    private func layerThumbnail(_ data:Data?,symbol:String) -> some View {
        Group {
            if let data,let image=NSImage(data:data){Image(nsImage:image).resizable().scaledToFit()}
            else {Image(systemName:symbol)}
        }.frame(width:26,height:26).background(Color.white.opacity(0.08)).cornerRadius(2)
    }

    private func layerThumbnailForLayer(
        _ layer: CoverLayer
    ) -> some View {
        layerThumbnail(
            layer.imageData,
            symbol:
                layer.kind == .group
                ? "folder"
                : layer.kind == .text
                ? "textformat"
                : "square.fill"
        )
        .overlay(
            alignment:
                .bottomTrailing
        ) {
            if layer.kind == .smartObject {
                Image(
                    systemName:
                        "doc.on.doc.fill"
                )
                .font(
                    .system(
                        size:
                            8,
                        weight:
                            .bold
                    )
                )
                .padding(
                    1
                )
                .background(
                    Color.black
                        .opacity(
                            0.65
                        )
                )
                .clipShape(
                    RoundedRectangle(
                        cornerRadius:
                            2
                    )
                )
                .help(
                    "Smart Object"
                )
            }
        }
    }


    private var adjustmentCommands: some View {
        ForEach(CoverAdjustmentKind.allCases){kind in Button(kind.workspaceTitle){addAdjustment(kind)}}
    }

    private var channelsPanel: some View {
        VStack(
            alignment:.leading,
            spacing:8
        ) {
            HStack {
                Text(
                    selectedLayer?.imageData != nil
                    ? "Selected raster source"
                    : "Document composite"
                )
                .font(
                    .caption
                        .weight(
                            .semibold
                        )
                )

                Spacer()

                Text("Read only")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            ForEach(
                CoverChannelPreviewKind.allCases
            ) { channel in
                HStack(
                    spacing:9
                ) {
                    Group {
                        if let preview =
                            channelPreviewImage(
                                channel
                            ) {
                            Image(
                                nsImage:preview
                            )
                            .resizable()
                            .scaledToFill()
                        } else {
                            Image(
                                systemName:
                                    "photo"
                            )
                            .foregroundStyle(
                                .secondary
                            )
                        }
                    }
                    .frame(
                        width:72,
                        height:44
                    )
                    .clipped()
                    .background(
                        Color.black
                    )
                    .overlay(
                        RoundedRectangle(
                            cornerRadius:3
                        )
                        .stroke(
                            Color.white
                                .opacity(0.15),
                            lineWidth:1
                        )
                    )

                    VStack(
                        alignment:.leading,
                        spacing:2
                    ) {
                        Text(
                            channel.rawValue
                        )
                        .fontWeight(
                            channel == .composite
                            ? .semibold
                            : .regular
                        )

                        Text(
                            channel == .alpha
                            ? "Transparency"
                            : channel == .composite
                            ? "RGB composite"
                            : "\(channel.rawValue) intensity"
                        )
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .accessibilityElement(
                    children:.combine
                )
                .accessibilityLabel(
                    "\(channel.rawValue) channel preview"
                )
            }

            Divider()

            Text(
                "RGB and Alpha are inspection previews only. Channel visibility and production rendering are unchanged."
            )
            .font(.caption2)
            .foregroundStyle(.secondary)
            .fixedSize(
                horizontal:false,
                vertical:true
            )
        }
    }

    private func channelPreviewImage(
        _ channel:CoverChannelPreviewKind
    ) -> NSImage? {
        let sourceData: Data?

        if let data =
            selectedLayer?.imageData {
            sourceData = data
        } else {
            let longestSide =
                max(
                    1,
                    max(
                        project.canvasWidth,
                        project.canvasHeight
                    )
                )

            let previewScale =
                max(
                    8,
                    min(
                        28,
                        220 / longestSide
                    )
                )

            if let rendered =
                try? CoverArtwork.render(
                    project,
                    includeGuides:false,
                    includeTemplate:true,
                    scale:previewScale
                ) {
                sourceData =
                    rendered.tiffRepresentation
            } else {
                sourceData = nil
            }
        }

        guard let sourceData,
              let previewData =
                try? CoverEditorEngine.channelPreview(
                    imageData:sourceData,
                    channel:channel
                )
        else {
            return nil
        }

        return NSImage(
            data:previewData
        )
    }

    private var adjustmentsPanel: some View {
        VStack(alignment:.leading,spacing:8) {
            DisclosureGroup("Add Adjustment") { adjustmentCommands.buttonStyle(.borderless) }
            if let i=selectedIndex,let kind=selectedLayer?.adjustment {
                DisclosureGroup(kind.workspaceTitle,isExpanded:$adjustmentExpanded) {
                    ForEach(CoverAdjustmentControl.controls(for:kind)) { control in
                        CoverAdjustmentControlRow(
                            control:control,
                            value:adjustmentValueBinding(at:i,control:control)
                        )
                    }
                    if kind == .gradientMap {
                        HStack {
                            Text("Shadows")
                                .frame(width:75,alignment:.leading)
                            TextField(
                                "#000000",
                                text:layerBinding(i,\.fillHex)
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Highlights")
                                .frame(width:75,alignment:.leading)
                            TextField(
                                "#FFFFFF",
                                text:
                                    typographyOptionalBinding(
                                        i,
                                        \.gradientEndHex,
                                        default:"#FFFFFF"
                                    )
                            )
                            .textFieldStyle(.roundedBorder)
                        }
                        HStack(spacing:6) {
                            RoundedRectangle(cornerRadius:3)
                                .fill(Color(nsColor:NSColor(hex:project.layers[i].fillHex)))
                                .frame(height:18)
                            Image(systemName:"arrow.right")
                                .foregroundStyle(.secondary)
                            RoundedRectangle(cornerRadius:3)
                                .fill(Color(nsColor:NSColor(hex:project.layers[i].gradientEndHex ?? "#FFFFFF")))
                                .frame(height:18)
                        }
                        .accessibilityLabel("Gradient Map preview")
                    }
                    if kind == .channelMixer {
                        Toggle(
                            "Preserve Luminosity",
                            isOn:
                                Binding(
                                    get:{
                                        (
                                            project.layers[i]
                                                .adjustmentValues?[
                                                    "preserveLuminosity"
                                                ]
                                            ?? 1
                                        ) >= 0.5
                                    },
                                    set:{ enabled in
                                        mutateLayer(
                                            at:i
                                        ) { layer in
                                            var values =
                                                layer.adjustmentValues
                                                ?? [:]

                                            values[
                                                "preserveLuminosity"
                                            ] =
                                                enabled
                                                ? 1
                                                : 0

                                            layer.adjustmentValues =
                                                values
                                        }
                                    }
                                )
                        )
                    }

                    if kind == .selectiveColor {
                        Picker(
                            "Colors",
                            selection:$selectiveColorTarget
                        ) {
                            ForEach(
                                CoverSelectiveColor.targets,
                                id:\.self
                            ) { target in
                                Text(
                                    CoverSelectiveColor.title(
                                        for:target
                                    )
                                )
                                .tag(target)
                            }
                        }

                        ForEach(
                            CoverSelectiveColor.controls(
                                for:selectiveColorTarget
                            )
                        ) { control in
                            CoverAdjustmentControlRow(
                                control:control,
                                value:adjustmentValueBinding(at:i,control:control),
                                accessibilityTitle:"\(CoverSelectiveColor.title(for:selectiveColorTarget)) \(control.title)"
                            )
                        }

                        Toggle(
                            "Relative",
                            isOn:
                                Binding(
                                    get:{
                                        (
                                            project.layers[i]
                                                .adjustmentValues?[
                                                    "selectiveRelative"
                                                ]
                                            ?? 1
                                        ) >= 0.5
                                    },
                                    set:{ enabled in
                                        mutateLayer(
                                            at:i
                                        ) { layer in
                                            var values =
                                                layer.adjustmentValues
                                                ?? [:]

                                            values[
                                                "selectiveRelative"
                                            ] =
                                                enabled
                                                ? 1
                                                : 0

                                            layer.adjustmentValues =
                                                values
                                        }
                                    }
                                )
                        )
                    }

                    if kind == .monochrome {
                        Toggle(
                            "Tint",
                            isOn:
                                Binding(
                                    get:{
                                        (
                                            project.layers[i]
                                                .adjustmentValues?[
                                                    "blackWhiteTint"
                                                ]
                                            ?? 0
                                        ) >= 0.5
                                    },
                                    set:{ enabled in
                                        mutateLayer(
                                            at:i
                                        ) { layer in
                                            var values =
                                                layer.adjustmentValues
                                                ?? [:]

                                            values[
                                                "blackWhiteTint"
                                            ] =
                                                enabled
                                                ? 1
                                                : 0

                                            layer.adjustmentValues =
                                                values
                                        }
                                    }
                                )
                        )

                        if (
                            project.layers[i]
                                .adjustmentValues?[
                                    "blackWhiteTint"
                                ]
                            ?? 0
                        ) >= 0.5 {
                            HStack {
                                Text("Tint Color")
                                    .frame(
                                        width:75,
                                        alignment:.leading
                                    )

                                TextField(
                                    "#C7A46A",
                                    text:
                                        layerBinding(
                                            i,
                                            \.fillHex
                                        )
                                )
                                .textFieldStyle(
                                    .roundedBorder
                                )

                                RoundedRectangle(
                                    cornerRadius:3
                                )
                                .fill(
                                    Color(
                                        nsColor:
                                            NSColor(
                                                hex:
                                                    project.layers[i]
                                                        .fillHex
                                            )
                                    )
                                )
                                .frame(
                                    width:28,
                                    height:18
                                )
                            }
                        }
                    }

                    Toggle("Enabled",isOn:layerBinding(i,\.visible))
                }
            }
        }.frame(maxWidth:.infinity,alignment:.leading)
    }

    private var toolOptionsBar: some View {
        ScrollView(.horizontal) { HStack(spacing:8) {
            Text(quickMask ? "Quick Mask · \(activeTool.title)" : activeTool.title).fontWeight(.semibold)
                if activeTool.options == .selection { Picker("Selection mode",selection:$selectionMode){ForEach(CoverSelectionMode.allCases){Text($0.rawValue.capitalized).tag($0)}}.frame(width:135) }
                if [.rectangle,.ellipse,.lasso].contains(activeTool) { Slider(value:$selectionFeather,in:0...20).frame(width:80);Text("Feather \(Int(selectionFeather)) px").font(.caption);Toggle("Anti-alias",isOn:$wandAntialias).toggleStyle(.checkbox) }
                if activeTool == .lasso { Menu("Lasso Mode"){Button("Freehand Lasso"){lassoMode=0};Button("Polygonal Lasso"){lassoMode=1};Button("Magnetic Lasso"){lassoMode=2}} }
                if activeTool == .lasso && lassoMode == 2 { Slider(value:$magneticRadius,in:1...64).frame(width:80);Text("Width \(Int(magneticRadius))");Slider(value:$magneticContrast,in:0...1).frame(width:80);Text("Contrast");Slider(value:$magneticFrequency,in:1...100).frame(width:80);Text("Frequency") }
                if activeTool == .lasso && lassoMode == 1 { Button("Close Polygon (Enter)"){finishPolygonSelection()}.disabled(constructionPoints.count<3);Button("Cancel Polygon (Esc)"){constructionPoints=[]} }
                if (activeTool == .pen || activeTool == .path),let i=selectedIndex,project.layers[i].kind == .path {
                    Button(activePathContourIsClosed ? "Open Contour":"Close Contour"){
                        setActivePathContourClosed(
                            !activePathContourIsClosed
                        )
                    }
                    .disabled(!canToggleActivePathContour)

                    if activeTool == .path {
                        Button("Delete Anchor"){
                            deleteSelectedPathPoint()
                        }
                        .disabled(selectedPathPointIndex == nil && selectedPathAnchors.isEmpty)

                        Menu("Anchor Type") {
                            Button("Corner") {
                                setSelectedPathAnchorType(
                                    .corner
                                )
                            }

                            Button("Smooth") {
                                setSelectedPathAnchorType(
                                    .smooth
                                )
                            }

                            Button("Symmetric") {
                                setSelectedPathAnchorType(
                                    .symmetric
                                )
                            }
                        }
                        .disabled(selectedPathPointIndex == nil && selectedPathAnchors.isEmpty)

                        Button("Break Handles") {
                            setSelectedPathAnchorType(
                                .corner
                            )
                        }
                        .disabled(selectedPathPointIndex == nil && selectedPathAnchors.isEmpty)

                        Button("Reconnect Smooth") {
                            setSelectedPathAnchorType(
                                .smooth
                            )
                        }
                        .disabled(selectedPathPointIndex == nil && selectedPathAnchors.isEmpty)


                        Button(
                            "Select Contour"
                        ) {
                            selectActivePathContourAnchors()
                        }
                        .disabled(
                            !canSelectActivePathContourAnchors
                        )

                        Menu(
                            "Transform Selected"
                        ) {
                            Button(
                                "Transform…"
                            ) {
                                beginSelectedPathGeometryTransform()
                            }

                            Divider()

                            Button(
                                "Rotate 90° Clockwise"
                            ) {
                                rotateSelectedPathGeometry(
                                    90
                                )
                            }

                            Button(
                                "Rotate 90° Counterclockwise"
                            ) {
                                rotateSelectedPathGeometry(
                                    -90
                                )
                            }

                            Divider()

                            Button(
                                "Flip Horizontal"
                            ) {
                                flipSelectedPathGeometry(
                                    horizontal:
                                        true
                                )
                            }

                            Button(
                                "Flip Vertical"
                            ) {
                                flipSelectedPathGeometry(
                                    horizontal:
                                        false
                                )
                            }
                        }
                        .disabled(
                            !canTransformSelectedPathGeometry
                        )

                        Button("Join Endpoints") {
                            joinSelectedPathEndpoints()
                        }
                        .disabled(!canJoinSelectedPathEndpoints)

                        Button("Split Path") {
                            splitSelectedPath()
                        }
                        .disabled(!canSplitSelectedPath)

                        Button("Cut Path") {
                            cutSelectedPath()
                        }
                        .disabled(!canCutSelectedPath)

                        Button("Duplicate Contour") {
                            duplicateActivePathContour()
                        }
                        .disabled(!canMutateActivePathContour)

                        Button("Reverse Contour") {
                            reverseActivePathContour()
                        }
                        .disabled(!canMutateActivePathContour)

                        Button("Bring Contour Forward") {
                            orderActivePathContour(
                                .forward
                            )
                        }
                        .disabled(
                            !canOrderActivePathContour(
                                .forward
                            )
                        )

                        Button("Send Contour Backward") {
                            orderActivePathContour(
                                .backward
                            )
                        }
                        .disabled(
                            !canOrderActivePathContour(
                                .backward
                            )
                        )

                        Button("Bring Contour to Front") {
                            orderActivePathContour(
                                .front
                            )
                        }
                        .disabled(
                            !canOrderActivePathContour(
                                .front
                            )
                        )

                        Button("Send Contour to Back") {
                            orderActivePathContour(
                                .back
                            )
                        }
                        .disabled(
                            !canOrderActivePathContour(
                                .back
                            )
                        )

                        let contourCount =
                            CoverEditorEngine
                                .vectorContours(
                                    for: project.layers[i]
                                )
                                .count

                        if contourCount > 1 {
                            Button("Previous Contour") {
                                selectAdjacentPathContour(
                                    delta: -1
                                )
                            }

                            Text(
                                "Contour \((selectedPathContourIndex ?? 0) + 1)/\(contourCount)"
                            )
                            .font(.caption)
                            .monospacedDigit()

                            Button("Next Contour") {
                                selectAdjacentPathContour(
                                    delta: 1
                                )
                            }
                        }


                        Button("Combine Paths") {
                            combineSelectedPathLayers()
                        }
                        .disabled(
                            compoundSelectedPathIDs.count < 2
                        )

                        Button("Separate Compound Path") {
                            separateSelectedCompoundPath()
                        }
                        .disabled(
                            !canSeparateSelectedCompoundPath
                        )

                        Button("Make Selection") {
                            makeSelectionFromSelectedPath()
                        }
                        .disabled(
                            !canMakeSelectionFromSelectedPath
                        )

                        Menu("Boolean") {
                            Button("Union"){
                                performPathBoolean(.union)
                            }

                            Button("Subtract"){
                                performPathBoolean(.subtract)
                            }

                            Button("Intersect"){
                                performPathBoolean(.intersect)
                            }

                            Button("Exclude"){
                                performPathBoolean(.exclude)
                            }
                        }
                        .disabled(
                            booleanSelectedPathIDs.count < 2
                        )
                    }
                }
                if activeTool == .wand { Slider(value:$selectionTolerance,in:0...1).frame(width:80);Text("Tolerance").font(.caption);Toggle("Contiguous",isOn:$wandContiguous).toggleStyle(.checkbox);Toggle("Anti-alias",isOn:$wandAntialias).toggleStyle(.checkbox) }
                if activeTool == .move {
                    Toggle("Auto Select",isOn:$autoSelect).toggleStyle(.checkbox)
                    Toggle("Show Transform Controls",isOn:$showTransformControls).toggleStyle(.checkbox)
                    Picker("Align To",selection:$alignmentReference){ForEach(["Selection Bounds","Canvas","Front Cover","Back Cover","Spine"],id:\.self){Text($0).tag($0)}}.frame(width:140)
                    Button("Align Left"){alignSelection(.left)}.disabled(!canAlignSelection);Button("Center H"){alignSelection(.centerX)}.disabled(!canAlignSelection);Button("Align Right"){alignSelection(.right)}.disabled(!canAlignSelection)
                    Button("Align Top"){alignSelection(.top)}.disabled(!canAlignSelection);Button("Center V"){alignSelection(.centerY)}.disabled(!canAlignSelection);Button("Align Bottom"){alignSelection(.bottom)}.disabled(!canAlignSelection)
                    autoFitPanelMenu
                    Button("Distribute H"){distributeSelection(.horizontal)}.disabled(transformableSelectedIDs.count<3)
                    Button("Distribute V"){distributeSelection(.vertical)}.disabled(transformableSelectedIDs.count<3)
                }
                if activeTool == .hand { Button("Reset Pan"){panOffset = .zero} }
                if activeTool == .zoom {
                    TextField("Zoom %",value:Binding(get:{zoom*100},set:{zoom=min(8,max(0.1,$0/100))}),format:.number).frame(width:64)
                    Button("Fit Cover"){fitCover()};Button("Fit Selection"){fitSelected()};Button("100%"){zoom=min(8,max(0.1,1/max(0.001,fitScaleEstimate/72)))};Button("Zoom In"){zoom=min(8,zoom*1.2)};Button("Zoom Out"){zoom=max(0.1,zoom/1.2)}
                }
                if activeTool == .rotateView { TextField("Angle",value:$viewRotation,format:.number).frame(width:72);Button("Reset View"){viewRotation=0} }
                if (activeTool.options == .paint && activeTool != .blur && activeTool != .sharpen) || activeTool.options == .color { Text("FG").font(.caption.bold());TextField("#RRGGBB",text:$foregroundHex).frame(width:82).textFieldStyle(.roundedBorder)
                Button("Swap FG/BG"){let old=foregroundHex;foregroundHex=backgroundColorHex;backgroundColorHex=old}.help("Swap foreground and background colors") }
                if activeTool == .shape { Picker("Shape",selection:$shapeToolKind){ForEach(CoverShapeKind.allCases){Text($0.rawValue.capitalized).tag($0)}}.frame(width:120) }
                if activeTool == .gradient {
                    Toggle("Radial",isOn:$gradientRadial).toggleStyle(.checkbox)
                    if maskSelected {
                        Toggle("Reverse",isOn:$gradientMaskReversed).toggleStyle(.checkbox)
                        Slider(value:$gradientMaskOpacity,in:0...1).frame(width:80)
                        Text("Opacity \(Int(gradientMaskOpacity*100))%")
                            .font(.caption.monospacedDigit())
                        Text(gradientRadial ? "Drag center to radius" : "Drag black to white")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if activeTool.options == .paint { Slider(value:$brushDiameter,in:2...180).frame(width:80);Text("\(Int(brushDiameter)) px").font(.caption.monospacedDigit()) }
                if activeTool == .brush || activeTool == .pencil || activeTool == .eraser || activeTool == .clone || activeTool == .blur || activeTool == .sharpen {
                    if activeTool == .brush || activeTool == .pencil || activeTool == .eraser || activeTool == .clone {
                        Slider(value:$brushOpacity,in:0...1).frame(width:80)
                        Text("Opacity \(Int(brushOpacity*100))%").font(.caption)
                    }
                    if activeTool != .pencil {
                        Slider(value:$brushHardness,in:0...1).frame(width:80)
                        Text("Hard \(Int(brushHardness*100))%").font(.caption)
                    }
                    Slider(value:$brushFlow,in:0.01...1).frame(width:80)
                    Text("Flow \(Int(brushFlow*100))%").font(.caption)
                    if activeTool == .blur || activeTool == .sharpen {
                        Slider(value:$brushStrength,in:0...1).frame(width:80)
                        Text("Strength \(Int(brushStrength*100))%").font(.caption)
                    }
                }
                if activeTool == .crop {
                    Picker("Aspect",selection:$cropAspect){Text("Free").tag("Free");Text("Original").tag("Original");Text("Custom").tag("Custom")}.frame(width:100)
                    if cropAspect == "Custom" {TextField("W",value:$cropWidth,format:.number).frame(width:45);Text(":");TextField("H",value:$cropHeight,format:.number).frame(width:45)}
                    TextField("Straighten°",value:$cropStraighten,format:.number).frame(width:70)
                    Button("Apply"){commitCrop()}.disabled(cropPreview == nil);Button("Cancel"){cancelCrop()}
                }
                if activeTool == .move, transformSnapshot != nil, let i=selectedIndex {
                    TextField("X",value:transformReferenceBinding(i,horizontal:true),format:.number).frame(width:55)
                    TextField("Y",value:transformReferenceBinding(i,horizontal:false),format:.number).frame(width:55)
                    TextField("W",value:transformDimensionBinding(i,width:true),format:.number).frame(width:55)
                    Toggle("Link W/H",isOn:$proportionalScale).toggleStyle(.checkbox)
                    TextField("H",value:transformDimensionBinding(i,width:false),format:.number).frame(width:55)
                    TextField("Angle",value:rotationBinding(i),format:.number).frame(width:62)
                    TextField("Skew X",value:optionalTransformBinding(i,\.skewX),format:.number).frame(width:60)
                    TextField("Skew Y",value:optionalTransformBinding(i,\.skewY),format:.number).frame(width:60)
                    Picker("Pivot",selection:$transformPivot){ForEach(["Top Left","Top Center","Top Right","Center Left","Center","Center Right","Bottom Left","Bottom Center","Bottom Right"],id:\.self){Text($0).tag($0)}}.frame(width:120)
                    Toggle("Warp",isOn:warpToggleBinding(i)).toggleStyle(.checkbox)
                    if warpEditing { Picker("Preset",selection:warpPresetBinding(i)){ForEach(CoverWarpPreset.allCases){Text($0.rawValue.capitalized).tag($0)}}.frame(width:90);Slider(value:warpAmountBinding(i),in:-1...1).frame(width:85);Text("Amount") }
                }

                if transformSnapshot != nil { Button("Apply Transform"){commitTransform()};Button("Cancel Transform"){cancelTransform()} }

        }.fixedSize(horizontal:true,vertical:false).padding(.horizontal,10).frame(height:40) }.scrollIndicators(.visible)
    }

    @ViewBuilder
    private var characterPanel: some View {
        if
            let index = selectedIndex,
            project.layers[index].kind == .text
        {
            VStack(
                alignment: .leading,
                spacing: 9
            ) {
                Picker(
                    "Font",
                    selection:
                        layerBinding(
                            index,
                            \.fontName
                        )
                ) {
                    ForEach(
                        CoverTypography.fontFamilies,
                        id: \.self
                    ) { family in
                        Text(family)
                            .tag(family)
                    }
                }

                HStack {
                    LabeledContent("Size") {
                        TextField(
                            "Size",
                            value:
                                layerBinding(
                                    index,
                                    \.fontSize
                                ),
                            format: .number
                        )
                        .frame(width: 72)
                    }

                    LabeledContent("Leading") {
                        TextField(
                            "Leading",
                            value:
                                typographyOptionalBinding(
                                    index,
                                    \.leading,
                                    default:
                                        max(
                                            1,
                                            project
                                                .layers[index]
                                                .fontSize
                                                * 1.2
                                        )
                                ),
                            format: .number
                        )
                        .frame(width: 72)
                    }
                }

                TextField(
                    "Color (#RRGGBB)",
                    text:
                        layerBinding(
                            index,
                            \.colorHex
                        )
                )

                HStack(spacing: 12) {
                    Toggle(
                        "Bold",
                        isOn:
                            layerBinding(
                                index,
                                \.bold
                            )
                    )

                    Toggle(
                        "Italic",
                        isOn:
                            layerBinding(
                                index,
                                \.italic
                            )
                    )
                }

                HStack(spacing: 12) {
                    Toggle(
                        "Underline",
                        isOn:
                            typographyOptionalBinding(
                                index,
                                \.underline,
                                default: false
                            )
                    )

                    Toggle(
                        "Strike",
                        isOn:
                            typographyOptionalBinding(
                                index,
                                \.strikethrough,
                                default: false
                            )
                    )
                }

                LabeledContent("Tracking") {
                    TextField(
                        "Tracking",
                        value:
                            layerBinding(
                                index,
                                \.letterSpacing
                            ),
                        format: .number
                    )
                    .frame(width: 86)
                }

                LabeledContent("Horizontal scale") {
                    HStack(spacing: 4) {
                        TextField(
                            "Horizontal scale",
                            value:
                                typographyOptionalBinding(
                                    index,
                                    \.horizontalScale,
                                    default: 1
                                ),
                            format: .number
                        )
                        .frame(width: 70)

                        Text("×")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Vertical scale") {
                    HStack(spacing: 4) {
                        TextField(
                            "Vertical scale",
                            value:
                                typographyOptionalBinding(
                                    index,
                                    \.verticalScale,
                                    default: 1
                                ),
                            format: .number
                        )
                        .frame(width: 70)

                        Text("×")
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Baseline shift") {
                    TextField(
                        "Baseline shift",
                        value:
                            typographyOptionalBinding(
                                index,
                                \.baselineShift,
                                default: 0
                            ),
                        format: .number
                    )
                    .frame(width: 86)
                }

                Button("Reset Character") {
                    mutateLayer(
                        at: index
                    ) { layer in
                        layer.fontName = "Georgia"
                        layer.fontSize = 36
                        layer.bold = false
                        layer.italic = false
                        layer.colorHex = "#202020"
                        layer.letterSpacing = 0
                        layer.leading = nil
                        layer.horizontalScale = nil
                        layer.verticalScale = nil
                        layer.baselineShift = nil
                        layer.underline = nil
                        layer.strikethrough = nil
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        } else {
            typographyEmptyPanel(
                title: "Character",
                symbol: "textformat",
                message:
                    "Select a text layer to edit character formatting."
            )
        }
    }

    @ViewBuilder
    private var paragraphPanel: some View {
        if
            let index = selectedIndex,
            project.layers[index].kind == .text
        {
            VStack(
                alignment: .leading,
                spacing: 10
            ) {
                Picker(
                    "Alignment",
                    selection:
                        layerBinding(
                            index,
                            \.alignment
                        )
                ) {
                    Text("Left")
                        .tag("left")

                    Text("Center")
                        .tag("center")

                    Text("Right")
                        .tag("right")

                    Text("Justify")
                        .tag("justified")
                }
                .pickerStyle(.segmented)

                LabeledContent("Line spacing") {
                    TextField(
                        "Line spacing",
                        value:
                            layerBinding(
                                index,
                                \.lineSpacing
                            ),
                        format: .number
                    )
                    .frame(width: 86)
                }

                LabeledContent("First-line indent") {
                    TextField(
                        "First-line indent",
                        value:
                            typographyOptionalBinding(
                                index,
                                \.paragraphIndent,
                                default: 0
                            ),
                        format: .number
                    )
                    .frame(width: 86)
                }

                LabeledContent("Space after") {
                    TextField(
                        "Space after",
                        value:
                            typographyOptionalBinding(
                                index,
                                \.paragraphSpacing,
                                default: 0
                            ),
                        format: .number
                    )
                    .frame(width: 86)
                }

                Button("Reset Paragraph") {
                    mutateLayer(
                        at: index
                    ) { layer in
                        layer.alignment = "center"
                        layer.lineSpacing = 1
                        layer.paragraphIndent = nil
                        layer.paragraphSpacing = nil
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: .leading
            )
        } else {
            typographyEmptyPanel(
                title: "Paragraph",
                symbol: "text.alignleft",
                message:
                    "Select a text layer to edit paragraph formatting."
            )
        }
    }

    private func typographyEmptyPanel(
        title: String,
        symbol: String,
        message: String
    ) -> some View {
        VStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 22))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.caption.bold())

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: 80
        )
    }

    private func vectorStrokeWidthBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return 0
                }

                return project.layers[index].strokeWidth
            },
            set: {
                value in

                guard value.isFinite else {
                    return
                }

                mutateLayer(
                    at:index
                ) {
                    $0.strokeWidth =
                        min(
                            1_000_000,
                            max(
                                0,
                                value
                            )
                        )
                }
            }
        )
    }

    private func vectorStrokeCapBinding(
        _ index: Int
    ) -> Binding<CoverStrokeCap> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return .butt
                }

                return project.layers[index].strokeCap
                    ?? .butt
            },
            set: {
                value in

                mutateLayer(
                    at:index
                ) {
                    $0.strokeCap =
                        value
                }
            }
        )
    }

    private func vectorStrokeJoinBinding(
        _ index: Int
    ) -> Binding<CoverStrokeJoin> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return .miter
                }

                return project.layers[index].strokeJoin
                    ?? .miter
            },
            set: {
                value in

                mutateLayer(
                    at:index
                ) {
                    $0.strokeJoin =
                        value
                }
            }
        )
    }

    private func vectorStrokeMiterBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return CoverStrokeValidation.defaultMiterLimit
                }

                return project.layers[index].strokeMiterLimit
                    ?? CoverStrokeValidation.defaultMiterLimit
            },
            set: {
                value in

                guard value.isFinite else {
                    return
                }

                mutateLayer(
                    at:index
                ) {
                    $0.strokeMiterLimit =
                        min(
                            CoverStrokeValidation.maximumMiterLimit,
                            max(
                                1,
                                value
                            )
                        )
                }
            }
        )
    }

    private func vectorStrokeDashPatternBinding(
        _ index: Int
    ) -> Binding<String> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return ""
                }

                return (
                    project.layers[index].strokeDashPattern
                    ?? []
                )
                .map {
                    String(
                        format:
                            "%g",
                        $0
                    )
                }
                .joined(
                    separator:
                        ", "
                )
            },
            set: {
                text in

                let trimmed =
                    text.trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                if trimmed.isEmpty {
                    mutateLayer(
                        at:index
                    ) {
                        $0.strokeDashPattern =
                            nil
                    }

                    return
                }

                let pieces =
                    trimmed.split(
                        separator:
                            ",",
                        omittingEmptySubsequences:
                            false
                    )

                guard !pieces.isEmpty,
                      pieces.count
                        <= CoverStrokeValidation.maximumDashCount
                else {
                    return
                }

                var pattern:
                    [Double] = []

                for piece in pieces {
                    let string =
                        piece.trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                    guard let value =
                        Double(
                            string
                        ),
                          value.isFinite,
                          value > 0,
                          value
                            <= CoverStrokeValidation.maximumDashValue
                    else {
                        return
                    }

                    pattern.append(
                        value
                    )
                }

                mutateLayer(
                    at:index
                ) {
                    $0.strokeDashPattern =
                        pattern
                }
            }
        )
    }

    private func vectorStrokeDashPhaseBinding(
        _ index: Int
    ) -> Binding<Double> {
        Binding(
            get: {
                guard project.layers.indices.contains(index)
                else {
                    return 0
                }

                return project.layers[index].strokeDashPhase
                    ?? 0
            },
            set: {
                value in

                guard value.isFinite else {
                    return
                }

                mutateLayer(
                    at:index
                ) {
                    $0.strokeDashPhase =
                        min(
                            CoverStrokeValidation.maximumDashValue,
                            max(
                                -CoverStrokeValidation.maximumDashValue,
                                value
                            )
                        )
                }
            }
        )
    }

    private var propertiesPanel: some View {
        VStack(alignment:.leading,spacing:8) {
            if let i=selectedIndex, workspace.propertiesTarget(layer:selectedLayer,maskSelected:maskSelected) == .mask {
                if project.layers[i].maskData != nil {
                    HStack { Text("Raster Mask").fontWeight(.semibold);Spacer();Button("Select Image"){maskPreviewMode = .artwork;maskSelected=false} }
                    Text("Paint with FG: white reveals, black conceals, gray is partial. Eraser reveals.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack {
                        Button("Edit Mask") { maskPreviewMode = .artwork; maskSelected = true }
                        Picker("Mask View", selection: $maskPreviewMode) {
                            ForEach(CoverMaskPreviewMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 230)
                    }
                    Toggle("Mask Enabled",isOn:Binding(get:{project.layers[i].maskEnabled ?? true},set:{v in mutateLayer(at:i){$0.maskEnabled=v}}))
                    Button("Mask Link: \((project.layers[i].maskLinked ?? true) ? "On":"Off")"){mutateLayer(at:i){$0.maskLinked = !($0.maskLinked ?? true)}}
                    HStack { Button("Invert Mask"){invertMask(at:i)};Button("Apply Mask"){applyMask(at:i)} }
                    Slider(value:Binding(get:{project.layers[i].maskDensity ?? 1},set:{v in mutateLayer(at:i){$0.maskDensity=v}}),in:0...1){Text("Density")}
                }
            } else if let i=selectedIndex {
                Divider(); TextField("Layer name",text:layerBinding(i,\.name)).font(.headline)
                Toggle("Visible",isOn:layerBinding(i,\.visible)); Toggle("Locked",isOn:layerBinding(i,\.locked))
                Toggle("Lock position",isOn:Binding(get:{project.layers[i].positionLocked ?? false},set:{v in mutateLayer(at:i){$0.positionLocked=v}}))
                if project.type == .printFullWrap,
                   ![
                        CoverLayerKind.template,
                        .group,
                        .adjustment
                   ].contains(
                        project.layers[i].kind
                   )
                {
                    Divider()

                    Picker(
                        "Physical anchor",
                        selection:
                            Binding(
                                get: {
                                    project.layers[i]
                                        .panelAnchor
                                    ?? CoverCalculator
                                        .inferredPanelAnchor(
                                            for:
                                                project.layers[i]
                                                    .frame,
                                            in:
                                                project
                                        )
                                    ?? .canvas
                                },
                                set: {
                                    anchor in

                                    mutateLayer(
                                        at:
                                            i
                                    ) {
                                        layer in

                                        layer.panelAnchor =
                                            anchor
                                    }
                                }
                            )
                    ) {
                        ForEach(
                            CoverPanelAnchor
                                .allCases
                        ) {
                            anchor in

                            Text(
                                anchor.title
                            )
                            .tag(
                                anchor
                            )
                        }
                    }

                    Text(
                        "Canvas keeps this layer in full-wrap coordinates. Back, Spine, and Front preserve the layer’s local position inside that physical panel when book geometry changes."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Text(
                        "Changing the anchor does not move the layer now."
                    )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                Slider(value:layerBinding(i,\.opacity),in:0...1) { Text("Opacity") }; Text("Opacity \(Int(project.layers[i].opacity*100))%").font(.caption)
                Button(project.layers[i].clippedToLayerID == nil ? "Create Clipping Mask":"Release Clipping Mask") { toggleClip(at:i) }
                if project.layers[i].kind == .template { Text("Imported guide layer").font(.caption).foregroundStyle(.secondary) }
                if project.layers[i].kind == .text {
                    TextField("Text",text:layerBinding(i,\.text),axis:.vertical).lineLimit(2...5)
                    TextField("Font",text:layerBinding(i,\.fontName)); TextField("Size",value:layerBinding(i,\.fontSize),format:.number)
                    TextField("Color (#RRGGBB)",text:layerBinding(i,\.colorHex)); Toggle("Bold",isOn:layerBinding(i,\.bold)); Toggle("Italic",isOn:layerBinding(i,\.italic))
                    Button("Rotate spine text 90°") { mutateLayer(at:i){$0.rotation += 90} }
                    HStack { Button("Align left"){mutateLayer(at:i){$0.alignment="left"}};Button("Center"){mutateLayer(at:i){$0.alignment="center"}};Button("Align right"){mutateLayer(at:i){$0.alignment="right"}} }
                    Slider(value:layerBinding(i,\.letterSpacing),in:-3...12);Text("Letter spacing").font(.caption)
                }
                Picker("Blend",selection:Binding(get:{project.layers[i].blendMode ?? .normal},set:{value in mutateLayer(at:i){$0.blendMode=value}})){ForEach(CoverBlendMode.allCases){Text($0.title).tag($0)}}
                Slider(value:Binding(get:{project.layers[i].fillOpacity ?? 1},set:{value in mutateLayer(at:i){$0.fillOpacity=value}}),in:0...1){Text("Fill")}
                if [
                    CoverLayerKind.shape,
                    .path
                ].contains(
                    project.layers[i].kind
                ) {
                    if project.layers[i].kind == .shape {
                        Picker(
                            "Shape",
                            selection:
                                layerBinding(
                                    i,
                                    \.shape
                                )
                        ) {
                            ForEach(
                                CoverShapeKind.allCases,
                                id: \.self
                            ) {
                                Text(
                                    $0.rawValue.capitalized
                                )
                                .tag($0)
                            }
                        }
                    }

                    TextField(
                        "Fill",
                        text:
                            layerBinding(
                                i,
                                \.fillHex
                            )
                    )

                    if project.layers[i].kind == .path {
                        Picker(
                            "Fill Rule",
                            selection:
                                Binding(
                                    get: {
                                        CoverEditorEngine
                                            .vectorFillRule(
                                                for:
                                                    project.layers[i]
                                            )
                                    },
                                    set: {
                                        value in

                                        mutateLayer(
                                            at:i
                                        ) {
                                            $0.fillRule =
                                                value
                                        }
                                    }
                                )
                        ) {
                            ForEach(
                                CoverFillRule.allCases
                            ) {
                                value in

                                Text(
                                    value.title
                                )
                                .tag(
                                    value
                                )
                            }
                        }
                        .help(
                            "Even-Odd ignores contour direction. Non-Zero uses contour winding direction."
                        )
                    }

                    TextField(
                        "Stroke",
                        text:
                            layerBinding(
                                i,
                                \.strokeHex
                            )
                    )

                    TextField(
                        "Stroke Width",
                        value:
                            vectorStrokeWidthBinding(
                                i
                            ),
                        format:
                            .number
                    )

                    Picker(
                        "Cap",
                        selection:
                            vectorStrokeCapBinding(
                                i
                            )
                    ) {
                        ForEach(
                            CoverStrokeCap.allCases
                        ) {
                            value in

                            Text(
                                value.title
                            )
                            .tag(value)
                        }
                    }

                    Picker(
                        "Join",
                        selection:
                            vectorStrokeJoinBinding(
                                i
                            )
                    ) {
                        ForEach(
                            CoverStrokeJoin.allCases
                        ) {
                            value in

                            Text(
                                value.title
                            )
                            .tag(value)
                        }
                    }

                    if (
                        project.layers[i]
                            .strokeJoin
                        ?? .miter
                    ) == .miter {
                        TextField(
                            "Miter Limit",
                            value:
                                vectorStrokeMiterBinding(
                                    i
                                ),
                            format:
                                .number
                        )
                    }

                    TextField(
                        "Dash Pattern",
                        text:
                            vectorStrokeDashPatternBinding(
                                i
                            )
                    )
                    .help(
                        "Comma-separated dash and gap lengths, for example 8, 4."
                    )

                    TextField(
                        "Dash Phase",
                        value:
                            vectorStrokeDashPhaseBinding(
                                i
                            ),
                        format:
                            .number
                    )

                    Menu(
                        "Dash Presets"
                    ) {
                        Button(
                            "Solid"
                        ) {
                            mutateLayer(
                                at:i
                            ) {
                                $0.strokeDashPattern =
                                    nil
                                $0.strokeDashPhase =
                                    0
                            }
                        }

                        Button(
                            "Dashed"
                        ) {
                            mutateLayer(
                                at:i
                            ) {
                                $0.strokeDashPattern = [
                                    8,
                                    4
                                ]
                            }
                        }

                        Button(
                            "Dotted"
                        ) {
                            mutateLayer(
                                at:i
                            ) {
                                $0.strokeDashPattern = [
                                    2,
                                    3
                                ]
                            }
                        }

                        Button(
                            "Dash Dot"
                        ) {
                            mutateLayer(
                                at:i
                            ) {
                                $0.strokeDashPattern = [
                                    8,
                                    4,
                                    2,
                                    4
                                ]
                            }
                        }
                    }

                    if project.layers[i].kind == .shape {
                        Button(
                            "Convert to Path",
                            systemImage:
                                "point.topleft.down.curvedto.point.bottomright.up"
                        ) {
                            convertShapeToPath(
                                project.layers[i].id
                            )
                        }
                        .disabled(
                            project.layers[i].locked
                        )
                        .help(
                            "Convert this shape to editable vector path anchors."
                        )
                    }
                }
                if project.layers[i].kind == .gradient {
                    gradientEditorControls(i)
                }
                if ![CoverLayerKind.group,.adjustment,.template].contains(project.layers[i].kind) {
                    DisclosureGroup("Layer Effects") {
                        layerEffectsPanel(i)
                    }
                }
                if project.layers[i].kind == .image, let bytes=project.layers[i].imageData, let nsImage=NSImage(data:bytes), !nsImage.representations.isEmpty {
                    Button("Replace Image…") { presentReplaceImage(project.layers[i].id) }
                        .disabled(project.layers[i].locked || project.layers[i].pixelsLocked == true)
                        .help("Replace source pixels while keeping this layer's crop, mask, transform, effects, and position.")
                    if project.type == .printFullWrap {
                        let geo=CoverWrapGeometry(project:project)
                        Text("Print Region Placement").font(.caption.bold())
                        HStack { Button("Fit Full Wrap"){placeImage(at:i,region:CoverRect(),fill:false)};Button("Fill Full Wrap"){placeImage(at:i,region:CoverRect(),fill:true)} }
                        HStack { Button("Fit Back Cover"){placeImage(at:i,region:geo.back,fill:false)};Button("Fill Back Cover"){placeImage(at:i,region:geo.back,fill:true)} }
                        HStack { Button("Fit Spine"){placeImage(at:i,region:geo.spine,fill:false)};Button("Fill Spine"){placeImage(at:i,region:geo.spine,fill:true)} }
                        HStack { Button("Fit Front Cover"){placeImage(at:i,region:geo.front,fill:false)};Button("Fill Front Cover"){placeImage(at:i,region:geo.front,fill:true)} }
                    }
                    Picker("Crop",selection:layerBinding(i,\.cropMode)){Text("Fit").tag(CoverCropMode.fit);Text("Fill").tag(CoverCropMode.fill);Text("Free Crop").tag(CoverCropMode.free)}
                    if let effectiveDPI =
                        CoverEditorEngine
                            .effectiveDPI(
                                project.layers[i],
                                project:
                                    project
                            ) {

                        let quality =
                            CoverCalculator
                                .resolutionQuality(
                                    effectiveDPI:
                                        effectiveDPI,
                                    targetDPI:
                                        project.dpi
                                )

                        let status =
                            CoverCalculator
                                .resolutionStatus(
                                    effectiveDPI:
                                        effectiveDPI,
                                    targetDPI:
                                        project.dpi
                                )

                        Text(
                            "\(Int(effectiveDPI.rounded())) effective DPI · \(status)"
                        )
                        .font(
                            .caption
                        )
                        .foregroundStyle(
                            coverResolutionColor(
                                quality
                            )
                        )
                    }
                    HStack { Button("Flip H"){mutateLayer(at:i){CoverEditorEngine.flip(&$0,horizontal:true)}};Button("Flip V"){mutateLayer(at:i){CoverEditorEngine.flip(&$0,horizontal:false)}};Button("Rotate"){mutateLayer(at:i){CoverEditorEngine.rotate(&$0,degrees:90)}} }
                    Slider(value:layerBinding(i,\.cropOffsetX),in:0...0.8);Text("Crop horizontal position").font(.caption)
                    Slider(value:layerBinding(i,\.cropOffsetY),in:0...0.8);Text("Crop vertical position").font(.caption)
                }
                HStack { Button("Center H") { mutateLayer(at:i){$0.frame.x=(1-$0.frame.width)/2} }; Button("Center V") { mutateLayer(at:i){$0.frame.y=(1-$0.frame.height)/2} } }
                if project.layers[i].kind == .image { Toggle("Scale proportionally",isOn:$proportionalScale) }
                HStack { Text("Width");Slider(value:frameDimensionBinding(i,width:true),in:0.02...1);Text("\(project.layers[i].frame.width, specifier:"%.2f")") }
                HStack { Text("Height");Slider(value:frameDimensionBinding(i,width:false),in:0.02...1);Text("\(project.layers[i].frame.height, specifier:"%.2f")") }
                HStack { Button("Left") { mutateLayer(at:i){$0.frame.x=0} }; Button("Right") { mutateLayer(at:i){$0.frame.x=1-$0.frame.width} }; Button("Top") { mutateLayer(at:i){$0.frame.y=0} }; Button("Bottom") { mutateLayer(at:i){$0.frame.y=1-$0.frame.height} } }
            } else { documentProperties }
        }.textFieldStyle(.roundedBorder)
    }

    private func coverResolutionColor(
        _ quality: CoverResolutionQuality
    ) -> Color {
        switch quality {
        case .good:
            return .secondary

        case .marginal:
            return .orange

        case .low:
            return .red
        }
    }

    private var documentProperties: some View {
        VStack(alignment:.leading,spacing:8) {
            Text(project.type == .ebookFront ? "eBook Front" : "Print Full Wrap").foregroundStyle(.secondary)
            if project.type == .printFullWrap && project.layers.contains(where:{$0.isReferenceLayer}) && project.spineWidth == 0 {
                Text("Set trim, bleed, and spine from the printer's template before final export. The reference layer appears only in proof exports.")
                    .font(.caption).foregroundStyle(.orange)
            }
            Text("Safe area: 5% inset (guides)").foregroundStyle(.secondary)

            if project.type == .printFullWrap {
                Picker(
                    "Production profile",
                    selection:
                        Binding(
                            get: {
                                BookProductionTemplate
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

                Text(
                    "One profile synchronizes manuscript trim, cover geometry, paper stock, binding, and the 3D book. Custom keeps manual production settings."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            LabeledContent("Trim width (in)") { TextField("Trim width (in)",value:binding(\.trimWidth),format:.number).frame(width:90) }
            LabeledContent("Trim height (in)") { TextField("Trim height (in)",value:binding(\.trimHeight),format:.number).frame(width:90) }
            LabeledContent("Bleed (in)") { TextField("Bleed (in)",value:binding(\.bleed),format:.number).frame(width:90) }
            if project.type == .printFullWrap {
                LabeledContent("Back width (in)") { TextField("Back width (in)",value:binding(\.backWidth),format:.number).frame(width:90) }
                Picker(
                    "Binding",
                    selection:
                        Binding(
                            get: {
                                project.productionBinding
                                ?? .softcover
                            },
                            set: {
                                value in
                                updateProject {
                                    $0.productionBinding =
                                        value
                                }
                            }
                        )
                ) {
                    ForEach(
                        BookBinding.allCases
                    ) {
                        binding in
                        Text(
                            binding.rawValue
                        )
                        .tag(
                            binding
                        )
                    }
                }
                .pickerStyle(.segmented)

                Picker(
                    "Paper stock",
                    selection:
                        Binding(
                            get: {
                                project.paperStockPreset
                                ?? PrintPaperStockPreset
                                    .inferred(
                                        caliper:
                                            project
                                                .spineCaliperInches
                                            ?? caliper
                                    )
                            },
                            set: {
                                preset in
                                applyPaperStockPreset(
                                    preset
                                )
                            }
                        )
                ) {
                    ForEach(
                        PrintPaperStockPreset
                            .allCases
                    ) {
                        preset in
                        Text(
                            preset.rawValue
                        )
                        .tag(
                            preset
                        )
                    }
                }

                Toggle(
                    "Calculate spine from pages × caliper",
                    isOn:
                        $useCaliper
                )

                if useCaliper {
                    LabeledContent(
                        "Pages"
                    ) {
                        TextField(
                            "Page count",
                            value:
                                $pageCount,
                            format:
                                .number
                        )
                        .frame(
                            width:
                                90
                        )
                    }

                    LabeledContent(
                        "Caliper (in)"
                    ) {
                        TextField(
                            "Caliper",
                            value:
                                $caliper,
                            format:
                                .number
                        )
                        .frame(
                            width:
                                90
                        )
                    }
                } else {
                    LabeledContent(
                        "Spine (in)"
                    ) {
                        TextField(
                            "Spine width",
                            value:
                                $manualSpine,
                            format:
                                .number
                        )
                        .frame(
                            width:
                                90
                        )
                    }
                }

                Button(
                    "Recalculate Wrap"
                ) {
                    recalculate()
                }
                Text("Barcode stays reserved; no ISBN is generated.").font(.caption2).foregroundStyle(.secondary)
            }
            Text("\(project.canvasWidth, specifier:"%.3f") × \(project.canvasHeight, specifier:"%.3f") in\n\(project.canvasWidth*25.4, specifier:"%.1f") × \(project.canvasHeight*25.4, specifier:"%.1f") mm\n\(Int(project.rasterPixelSize.width)) × \(Int(project.rasterPixelSize.height)) px @ \(Int(project.dpi)) DPI").font(.caption).foregroundStyle(.secondary)
            LabeledContent("DPI") { TextField("DPI",value:binding(\.dpi),format:.number).frame(width:90) }
            DisclosureGroup("Grid") {
                LabeledContent("Spacing (in)") {
                    TextField("Grid spacing",value:Binding(get:{project.gridSpacingInches ?? 0.25},set:{v in updateProject{$0.gridSpacingInches=max(0.01,v)}}),format:.number)
                }
            }
        }
    }

    private var addCommands: some View {
        Group {
            Button("Import Image…",systemImage:"photo") { presentImport(template:false) }
            Button("Import Cover Template…",systemImage:"doc.viewfinder") { presentImport(template:true) }
            Button("Add Title Text",systemImage:"textformat") { addText("Title",frame:CoverRect(x:0.08,y:0.35,width:0.84,height:0.2),size:38) }
            Button("Add Text",systemImage:"text.alignleft") { addText("Text",frame:CoverRect(x:0.12,y:0.72,width:0.76,height:0.16),size:18) }
            Menu("Add Shape") { ForEach(CoverShapeKind.allCases,id:\.self) { shape in Button(shape.rawValue.capitalized) { addShape(shape) } } }
            Button("Add Gradient Layer",systemImage:"circle.lefthalf.filled"){addGradientLayer()}
            if project.type == .printFullWrap {
                Button("Back-Cover Description") { addText("Back-Cover Description",frame:CoverRect(x:project.bleed+0.25,y:0.18,width:max(0.1,project.backWidth-0.5),height:0.52),size:12) }
                Button("Author Bio") { addText("Author Bio",frame:CoverRect(x:project.bleed+0.25,y:0.72,width:max(0.1,project.backWidth-0.5),height:0.16),size:10) }
                Button("Reserve Barcode Area") { var l=CoverLayer(kind:.shape,name:"Reserved Barcode",frame:CoverRect(x:project.bleed+project.backWidth-1.8,y:0.72,width:1.5,height:0.85));l.fillHex="#FFFFFF";l.strokeHex="#BBBBBB";updateProject{$0.layers.append(l)} }
                if projects.contains(where:{$0.type == .ebookFront}) { Button("Copy eBook Art to Front") { copyEbookArt() } }
            }
        }
    }

    private var selectionCommands: some View {
        Group {
            Button("Select All",action:selectAll).disabled(!commands.hasImage && !project.layers.contains(where:{$0.imageData != nil}))
            Button("Deselect",action:deselect).disabled(!commands.hasSelection)
            Button("Reselect",action:reselect).disabled(!commands.canReselect)
            Button("Inverse",action:invertSelection).disabled(!commands.hasSelection)

            Button(
                "Convert Selection to Path",
                action:
                    convertSelectionToEditablePath
            )
            .disabled(
                !canConvertSelectionToPath
            )
            Menu("Modify") {
                Button("Feather…"){selectionRadiusPrompt = .feather}
                Button("Expand…"){selectionRadiusPrompt = .expand}
                Button("Contract…"){selectionRadiusPrompt = .contract}
                Button("Smooth",action:smoothSelection)
                Button("Border…"){selectionRadiusPrompt = .border}
            }.disabled(!commands.hasSelection)
            Button("Select Subject"){selectSubject(removeBackground:false)}.disabled(!commands.hasImage)
            Button("Remove Background"){selectSubject(removeBackground:true)}.disabled(!commands.hasImage)
            Toggle("Quick Mask",isOn:$quickMask).disabled(!commands.hasImage)
            Divider()
            Button("Save Selection…"){savedSelectionName="Selection \((project.savedSelections?.count ?? 0)+1)";showSaveSelection=true}.disabled(!commands.hasSelection)
            Button("Transform Selection…") {
                selectionTranslationX=0;selectionTranslationY=0;selectionScale=1;selectionAngle=0
                beginSelectionTransform()
            }.disabled(!commands.hasSelection)
            Menu("Load Selection") {
                ForEach(project.savedSelections ?? []){saved in Button(saved.name){pushUndo();activeSelection=saved.mask;selectionLayerID=selectedLayer?.id}}
            }.disabled(!commands.hasImage || (project.savedSelections ?? []).isEmpty)
            Button("Delete Saved Selection",action:deleteSavedSelection).disabled((project.savedSelections ?? []).isEmpty)
        }
    }
    private var viewCommands: some View {
        Group {
            Button("Fit Cover",action:fitCover)
            Button("Fit Selection",action:fitSelected).disabled(!commands.hasLayer)
            Button("100%"){zoom=min(8,max(0.1,72/max(1,fitScaleEstimate)))}
            Button("Zoom In"){zoom=min(8,zoom*1.2)}
            Button("Zoom Out"){zoom=max(0.1,zoom/1.2)}
            Button("Rotate View Left"){viewRotation -= 5}
            Button("Rotate View Right"){viewRotation += 5}
            Button("Reset View"){fitCover();viewRotation=0}
            Divider()
            Toggle("Rulers",isOn:$workspace.rulers)
            Toggle("Show guides",isOn:binding(\.guidesVisible))
            Toggle("Show grid",isOn:binding(\.gridVisible))
            Picker("Ruler units",selection:Binding(get:{project.unit ?? "in"},set:{value in updateProject{$0.unit=value}})){Text("Inches").tag("in");Text("Millimeters").tag("mm");Text("Pixels").tag("px")}
            Toggle("Snap",isOn:Binding(get:{project.snapEnabled ?? true},set:{v in updateProject{$0.snapEnabled=v}}))
            Menu("Snap To") { Toggle("Guides",isOn:projectBoolBinding(\.snapGuides));Toggle("Grid",isOn:projectBoolBinding(\.snapGrid));Toggle("Canvas Edges",isOn:projectBoolBinding(\.snapCanvasEdges));Toggle("Canvas Center",isOn:projectBoolBinding(\.snapCanvasCenter));Toggle("Front Cover Edges",isOn:projectBoolBinding(\.snapFrontCover));Toggle("Front Cover Center",isOn:projectBoolBinding(\.snapFrontCoverCenter));Toggle("Back Cover Edges",isOn:projectBoolBinding(\.snapBackCover));Toggle("Back Cover Center",isOn:projectBoolBinding(\.snapBackCoverCenter));Toggle("Spine Edges",isOn:projectBoolBinding(\.snapSpine));Toggle("Spine Center",isOn:projectBoolBinding(\.snapSpineCenter));Toggle("Trim",isOn:projectBoolBinding(\.snapTrim));Toggle("Bleed",isOn:projectBoolBinding(\.snapBleed));Toggle("Safe Zone",isOn:projectBoolBinding(\.snapSafeZone));Toggle("Other Layer Edges",isOn:projectBoolBinding(\.snapLayerEdges));Toggle("Other Layer Centers",isOn:projectBoolBinding(\.snapLayerCenters)) }
            Toggle("Lock guides",isOn:Binding(get:{project.guidesLocked ?? false},set:{v in updateProject{$0.guidesLocked=v}}))
            Toggle("Pixel grid",isOn:Binding(get:{project.pixelGridVisible ?? false},set:{v in updateProject{$0.pixelGridVisible=v}}))
            Menu("Grid Spacing") { ForEach([0.125,0.25,0.5,1.0],id:\.self){spacing in Button("\(spacing) in"){updateProject{$0.gridSpacingInches=spacing}}} }
            Button("New Guide…"){newGuidePosition=0;showNewGuide=true}
            Button("Clear Guides"){_ = applyCoverOperation("guide-clear",arguments:[:])}
        }
    }

}

// MARK: - Canvas rendering and gestures

private extension BookCoverCreatorView {
    private var canvas: some View {
        GeometryReader { geo in
            let fitScale=min((geo.size.width-60)/project.canvasWidth,(geo.size.height-60)/project.canvasHeight)
            let displayScale=fitScale*zoom
            let canvasSize=CGSize(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale)
            let contentWidth=max(geo.size.width,canvasSize.width+60),contentHeight=max(geo.size.height,canvasSize.height+60)
            // The editor shows visible reference layers; production export excludes them.
            // Hiding every template here made successful PDF imports look blank.
            let image=canvasRenderCache.image(project: project, scale: displayScale)
            ScrollView([.horizontal,.vertical]){ZStack {
                if let image { Image(nsImage:image).resizable().interpolation(.high).frame(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale).shadow(radius:8) }
                if maskSelected, maskPreviewMode != .artwork,
                   let layer = selectedLayer,
                   let data = layer.imageData,
                   let representation = NSBitmapImageRep(data: data),
                   let maskData = layer.maskData,
                   let mask = CoverEditorEngine.decodedMask(maskData, width: representation.pixelsWide, height: representation.pixelsHigh),
                   let previewData = CoverEditorEngine.maskInspectionPreview(mask, width: representation.pixelsWide, height: representation.pixelsHigh, overlay: maskPreviewMode == .overlay),
                   let preview = NSImage(data: previewData) {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: layer.frame.width * canvasSize.width, height: layer.frame.height * canvasSize.height)
                        .position(
                            x: contentWidth / 2 + (layer.frame.x + layer.frame.width / 2 - 0.5) * canvasSize.width,
                            y: contentHeight / 2 + (layer.frame.y + layer.frame.height / 2 - 0.5) * canvasSize.height
                        )
                        .allowsHitTesting(false)
                        .accessibilityLabel(maskPreviewMode == .grayscale ? "Grayscale raster mask preview" : "Raster mask concealment overlay")
                }
                if project.type == .printFullWrap, project.spineWidth > 0 {
                    let region = CoverWrapGeometry(project:project).spineTrim
                    Rectangle()
                        .stroke(Color.orange,style:StrokeStyle(lineWidth:inspectedPhysicalPanel == .spine ? 2:1,dash:[5,3]))
                        .frame(width:region.width*canvasSize.width,height:region.height*canvasSize.height)
                        .position(x:contentWidth/2+(region.x+region.width/2-0.5)*canvasSize.width,
                                  y:contentHeight/2+(region.y+region.height/2-0.5)*canvasSize.height)
                        .allowsHitTesting(false)
                        .accessibilityLabel(String(format:"Spine panel, %.3f inches wide",project.spineWidth))
                }
                if activeTool == .path,
                   let layer = selectedLayer,
                   layer.kind == .path
                {
                    let contours =
                        CoverEditorEngine
                            .vectorContours(
                                for: layer
                            )

                    ForEach(
                        Array(contours.enumerated()),
                        id: \.offset
                    ) {
                        contourIndex,
                        contour in

                        ForEach(
                            Array(contour.enumerated()),
                            id: \.offset
                        ) {
                            pointIndex,
                            point in

                            let x =
                                contentWidth / 2
                                + (
                                    layer.frame.x
                                    + point.x
                                    * layer.frame.width
                                    - 0.5
                                )
                                * project.canvasWidth
                                * displayScale

                            let y =
                                contentHeight / 2
                                + (
                                    layer.frame.y
                                    + point.y
                                    * layer.frame.height
                                    - 0.5
                                )
                                * project.canvasHeight
                                * displayScale

                            let anchorSelection =
                                CoverVectorAnchorIndex(
                                    contourIndex: contourIndex,
                                    pointIndex: pointIndex
                                )

                            let selected =
                                selectedPathAnchors.contains(
                                    anchorSelection
                                )
                                || (
                                    selectedPathAnchors.isEmpty
                                    && (
                                        selectedPathContourIndex
                                        ?? 0
                                    ) == contourIndex
                                    && selectedPathPointIndex
                                        == pointIndex
                                )

                            Circle()
                                .fill(
                                    selected
                                    ? Color.yellow
                                    : (
                                        contourIndex
                                        == (
                                            selectedPathContourIndex
                                            ?? 0
                                        )
                                        ? Color.white
                                        : Color.cyan
                                    )
                                )
                                .overlay(
                                    Circle()
                                        .stroke(
                                            Color.black,
                                            lineWidth: 1
                                        )
                                )
                                .frame(
                                    width: 11,
                                    height: 11
                                )
                                .position(
                                    x: x,
                                    y: y
                                )
                                .allowsHitTesting(false)
                        }
                    }
                }
                if !constructionPoints.isEmpty { Canvas{context,size in var path=Path();path.move(to:CGPoint(x:constructionPoints[0].x/selectionPixelSize.width*size.width,y:constructionPoints[0].y/selectionPixelSize.height*size.height));for p in constructionPoints.dropFirst(){path.addLine(to:CGPoint(x:p.x/selectionPixelSize.width*size.width,y:p.y/selectionPixelSize.height*size.height))};context.stroke(path,with:.color(.yellow),lineWidth:1.5);for p in constructionPoints{let center=CGPoint(x:p.x/selectionPixelSize.width*size.width,y:p.y/selectionPixelSize.height*size.height);context.fill(Path(ellipseIn:CGRect(x:center.x-3,y:center.y-3,width:6,height:6)),with:.color(.white))}}.frame(width:(selectedLayer?.frame.width ?? 1)*project.canvasWidth*displayScale,height:(selectedLayer?.frame.height ?? 1)*project.canvasHeight*displayScale).position(x:contentWidth/2+((selectedLayer?.frame.x ?? 0)+(selectedLayer?.frame.width ?? 1)/2-0.5)*project.canvasWidth*displayScale,y:contentHeight/2+((selectedLayer?.frame.y ?? 0)+(selectedLayer?.frame.height ?? 1)/2-0.5)*project.canvasHeight*displayScale).allowsHitTesting(false) }
                if CoverEditorEngine.maskInspectionSelectionTintEnabled(
                    maskSelected: maskSelected,
                    inspectionModeActive: maskPreviewMode != .artwork
                ), let mask=selectionDragPreview ?? activeSelection,
                   let layerID=selectionLayerID,
                   let layer=project.layers.first(where:{$0.id==layerID}),
                   let bytes=layer.imageData,
                   let source=NSImage(data:bytes),
                   let rep=source.representations.first,
                   let previewData=CoverEditorEngine.selectionPreview(mask,width:rep.pixelsWide,height:rep.pixelsHigh),
                   let preview=NSImage(data:previewData) {
                    Image(nsImage:preview)
                        .resizable()
                        .frame(width:layer.frame.width*project.canvasWidth*displayScale,height:layer.frame.height*project.canvasHeight*displayScale)
                        .position(x:contentWidth/2+(layer.frame.x+layer.frame.width/2-0.5)*project.canvasWidth*displayScale,y:contentHeight/2+(layer.frame.y+layer.frame.height/2-0.5)*project.canvasHeight*displayScale)
                        .allowsHitTesting(false)
                }
                if activeTool == .gradient, maskSelected, canvasDragPoints.count > 1,
                   let first = canvasDragPoints.first, let last = canvasDragPoints.last {
                    Canvas { context, _ in
                        let origin = CGPoint(x: (contentWidth - canvasSize.width) / 2, y: (contentHeight - canvasSize.height) / 2)
                        let start = CGPoint(x: origin.x + first.x, y: origin.y + first.y)
                        let end = CGPoint(x: origin.x + last.x, y: origin.y + last.y)
                        var line = Path()
                        line.move(to: start)
                        line.addLine(to: end)
                        context.stroke(line, with: .color(.white), lineWidth: 3)
                        context.stroke(line, with: .color(.black.opacity(0.75)), lineWidth: 1)
                        for point in [start, end] {
                            let marker = CGRect(x: point.x - 5, y: point.y - 5, width: 10, height: 10)
                            context.fill(Path(ellipseIn: marker), with: .color(.white))
                            context.stroke(Path(ellipseIn: marker), with: .color(.black), lineWidth: 1)
                        }
                    }
                    .frame(width: contentWidth, height: contentHeight)
                    .allowsHitTesting(false)
                }
                if let crop=cropPreview,let layer=selectedLayer {
                    let cw=crop.width*layer.frame.width*project.canvasWidth*displayScale,ch=crop.height*layer.frame.height*project.canvasHeight*displayScale
                    let cx=contentWidth/2+(layer.frame.x+(crop.x+crop.width/2)*layer.frame.width-0.5)*project.canvasWidth*displayScale,cy=contentHeight/2+(layer.frame.y+(crop.y+crop.height/2)*layer.frame.height-0.5)*project.canvasHeight*displayScale
                    Canvas{context,size in var mask=Path();mask.addRect(CGRect(origin:.zero,size:size));mask.addRect(CGRect(x:cx-cw/2,y:cy-ch/2,width:cw,height:ch));context.fill(mask,with:.color(.black.opacity(0.42)),style:FillStyle(eoFill:true))}.frame(width:contentWidth,height:contentHeight).allowsHitTesting(false)
                    Rectangle().stroke(.yellow,style:StrokeStyle(lineWidth:1.5,dash:[5,3])).frame(width:cw,height:ch).position(x:cx,y:cy).contentShape(Rectangle()).gesture(DragGesture().onChanged{value in if cropInteractionStart == nil{cropInteractionStart=crop};guard let start=cropInteractionStart else{return};let dx=Double(value.translation.width)/(max(1,layer.frame.width*project.canvasWidth*displayScale)),dy=Double(value.translation.height)/(max(1,layer.frame.height*project.canvasHeight*displayScale));cropPreview=CoverRect(x:max(0,min(1-start.width,start.x+dx)),y:max(0,min(1-start.height,start.y+dy)),width:start.width,height:start.height)}.onEnded{_ in cropInteractionStart=nil})
                    ForEach(0..<8,id:\.self){handle in let anchors:[UnitPoint]=[.topLeading,.top,.topTrailing,.leading,.trailing,.bottomLeading,.bottom,.bottomTrailing];Circle().fill(.white).overlay(Circle().stroke(.yellow,lineWidth:1.5)).frame(width:11,height:11).position(x:cx+(anchors[handle].x-0.5)*cw,y:cy+(anchors[handle].y-0.5)*ch).gesture(DragGesture().onChanged{value in if cropInteractionStart == nil{cropInteractionStart=crop};guard let start=cropInteractionStart else{return};let dx=Double(value.translation.width)/max(1,layer.frame.width*project.canvasWidth*displayScale),dy=Double(value.translation.height)/max(1,layer.frame.height*project.canvasHeight*displayScale);cropPreview=resizeCrop(start,dx:dx,dy:dy,handle:handle)}.onEnded{_ in cropInteractionStart=nil})}
                }
                if perspectiveEditing,let layer=selectedLayer,let corners=layer.perspectiveCorners,corners.count==4 { ForEach(0..<4,id:\.self){corner in let p=corners[corner];Circle().fill(.yellow).overlay(Circle().stroke(.black,lineWidth:1)).frame(width:14,height:14).position(x:contentWidth/2+(layer.frame.x+p.x*layer.frame.width-0.5)*project.canvasWidth*displayScale,y:contentHeight/2+(layer.frame.y+p.y*layer.frame.height-0.5)*project.canvasHeight*displayScale).gesture(DragGesture().onChanged{value in if perspectiveDragStart == nil{perspectiveDragStart=corners};guard let start=perspectiveDragStart else{return};mutatePreviewLayer(at:selectedIndex ?? 0){l in var points=start;points[corner].x=max(-0.5,min(1.5,start[corner].x+value.translation.width/(layer.frame.width*project.canvasWidth*displayScale)));points[corner].y=max(-0.5,min(1.5,start[corner].y+value.translation.height/(layer.frame.height*project.canvasHeight*displayScale)));l.perspectiveCorners=points}}.onEnded{_ in perspectiveDragStart=nil})} }
                if project.guidesVisible {
                    Canvas { context,size in drawGuides(context,size:size) }.frame(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale).allowsHitTesting(false)
                }
                if let preview=guidePreview { Canvas{context,size in var path=Path();if preview.0=="Vertical"{path.move(to:CGPoint(x:preview.1*size.width/project.canvasWidth,y:0));path.addLine(to:CGPoint(x:preview.1*size.width/project.canvasWidth,y:size.height))}else{path.move(to:CGPoint(x:0,y:preview.1*size.height/project.canvasHeight));path.addLine(to:CGPoint(x:size.width,y:preview.1*size.height/project.canvasHeight))};context.stroke(path,with:.color(.yellow),lineWidth:1.5)}.frame(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale).allowsHitTesting(false) }
                if !alignmentIndicators.isEmpty { Canvas{context,size in for guide in alignmentIndicators{var path=Path();if guide.y < 0{path.move(to:CGPoint(x:guide.x*size.width,y:0));path.addLine(to:CGPoint(x:guide.x*size.width,y:size.height))}else{path.move(to:CGPoint(x:0,y:guide.y*size.height));path.addLine(to:CGPoint(x:size.width,y:guide.y*size.height))};context.stroke(path,with:.color(.pink.opacity(0.8)),lineWidth:1)}}.frame(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale).allowsHitTesting(false) }
                Color.clear.frame(width:project.canvasWidth*displayScale,height:project.canvasHeight*displayScale).contentShape(Rectangle()).allowsHitTesting(!(activeTool == .crop && cropPreview != nil) && !perspectiveEditing).gesture(DragGesture(minimumDistance:0).onChanged{value in canvasFocused=true;if activeTool == .hand{let local=CGSize(width:value.translation.width-panLastTranslation.width,height:value.translation.height-panLastTranslation.height),delta=screenDelta(local);panOffset.width += delta.width;panOffset.height += delta.height;panLastTranslation=value.translation}else if activeTool == .zoom { if zoomScrubStart == nil{zoomScrubStart=(value.startLocation,zoom)};if let start=zoomScrubStart{let target=max(0.1,min(8,start.1*exp(Double(value.translation.width)/240)));zoomAt(start.0,factor:target/max(0.001,zoom),canvas:canvasSize)} }else if activeTool == .rotateView {if rotateViewStart == nil{rotateViewStart=viewRotation};if let start=rotateViewStart{viewRotation=start+Double(value.translation.width)*0.5}}else{if canvasDragPoints.count<4096{canvasDragPoints.append(value.location)};if [.rectangle,.ellipse].contains(activeTool){updateMarqueePreview(at:value.location,canvasSize:canvasSize,layerFrame:selectedLayer?.frame ?? CoverRect(),pixels:selectionPixelSize)};if activeTool == .crop,let layer=selectedLayer,let bytes=layer.imageData,let img=NSImage(data:bytes),let rep=img.representations.first,let first=canvasDragPoints.first{let end=value.location;let rect=CGRect(x:min(first.x,end.x),y:min(first.y,end.y),width:abs(end.x-first.x),height:abs(end.y-first.y));cropPreview=CoverEditorEngine.cropSourceRect(layer:layer,canvasDrag:rect,canvasSize:canvasSize,imagePixels:CGSize(width:rep.pixelsWide,height:rep.pixelsHigh))}}}.onEnded{value in if activeTool == .hand{panLastTranslation = .zero;return};if activeTool == .zoom{zoomScrubStart=nil;if abs(value.translation.width)<4{let factor=NSEvent.modifierFlags.contains(.option) ? 0.8:1.25;zoomAt(value.location,factor:factor,canvas:canvasSize)};return};if activeTool == .rotateView{rotateViewStart=nil;return};let points=activeTool == .gradient && maskSelected ? canvasDragPoints + [value.location] : canvasDragPoints;canvasDragPoints=[];selectionDragPreview=nil;handleCanvasGesture(points:points,canvasSize:canvasSize)})
                ForEach(Array((project.userGuidesX ?? []).enumerated()),id:\.offset){index,position in Rectangle().fill(.clear).contentShape(Rectangle()).frame(width:12,height:project.canvasHeight*displayScale).position(x:contentWidth/2+(position-0.5)*project.canvasWidth*displayScale,y:contentHeight/2).gesture(DragGesture(minimumDistance:1).onChanged{value in guard project.guidesLocked != true else{return};if !guideDragActive{pushUndo();guideDragActive=true};let next=position+Double(value.translation.width/displayScale);projects[projectIndex].userGuidesX?[index]=next}.onEnded{value in let next=position+Double(value.translation.width/displayScale);if next<0 || next>project.canvasWidth{projects[projectIndex].userGuidesX?.remove(at:index)};guideDragActive=false}) }
                ForEach(Array((project.userGuidesY ?? []).enumerated()),id:\.offset){index,position in Rectangle().fill(.clear).contentShape(Rectangle()).frame(width:project.canvasWidth*displayScale,height:12).position(x:contentWidth/2,y:contentHeight/2+(position-0.5)*project.canvasHeight*displayScale).gesture(DragGesture(minimumDistance:1).onChanged{value in guard project.guidesLocked != true else{return};if !guideDragActive{pushUndo();guideDragActive=true};let next=position+Double(value.translation.height/displayScale);projects[projectIndex].userGuidesY?[index]=next}.onEnded{value in let next=position+Double(value.translation.height/displayScale);if next<0 || next>project.canvasHeight{projects[projectIndex].userGuidesY?.remove(at:index)};guideDragActive=false}) }
                if let bounds=transformableSelectedBounds,((activeTool == .move && showTransformControls) || transformSnapshot != nil),activeTool != .crop {
                    Rectangle().stroke(Color.accentColor,lineWidth:1.5).frame(width:bounds.width*project.canvasWidth*displayScale,height:bounds.height*project.canvasHeight*displayScale).overlay{GeometryReader{box in ForEach(0..<8,id:\.self){index in let anchors:[UnitPoint]=[.topLeading,.top,.topTrailing,.leading,.trailing,.bottomLeading,.bottom,.bottomTrailing];Circle().fill(.white).overlay(Circle().stroke(Color.accentColor,lineWidth:1.5)).frame(width:11,height:11).position(x:anchors[index].x*box.size.width,y:anchors[index].y*box.size.height).gesture(DragGesture().onEnded{value in resizeSelectedLayers(bounds:bounds,translation:value.translation,scale:displayScale,handle:index,center:NSEvent.modifierFlags.contains(.option))})}}}.overlay(alignment:.top){if transformSnapshot != nil && !perspectiveEditing{VStack(spacing:0){Rectangle().fill(Color.accentColor).frame(width:1,height:18);Circle().fill(.white).overlay(Circle().stroke(Color.accentColor,lineWidth:1.5)).frame(width:12,height:12)}.offset(y:-29).gesture(DragGesture().onEnded{value in rotateSelection(Double(value.translation.width)*0.5,snapping:NSEvent.modifierFlags.contains(.shift))})}}.contentShape(Rectangle()).position(x:contentWidth/2+(bounds.midX-0.5)*project.canvasWidth*displayScale,y:contentHeight/2+(bounds.midY-0.5)*project.canvasHeight*displayScale).gesture(DragGesture().onEnded{value in moveSelectedLayers(translation:value.translation,scale:displayScale)})
                }
            }.frame(width:contentWidth,height:contentHeight).rotationEffect(.degrees(viewRotation)).offset(panOffset)}.frame(maxWidth:.infinity,maxHeight:.infinity).focusable().focused($canvasFocused).simultaneousGesture(MagnificationGesture().onChanged{factor in if pinchStartZoom == nil{pinchStartZoom=zoom};zoom=max(0.1,min(8,(pinchStartZoom ?? zoom)*factor))}.onEnded{_ in pinchStartZoom=nil}).onExitCommand{if transformSnapshot != nil{cancelTransform()}else if activeTool == .crop{cancelCrop()}}.onMoveCommand{direction in let step=projectUnitInches*(NSEvent.modifierFlags.contains(.shift) ? 10:1);switch direction{case .left:nudge(-step,0);case .right:nudge(step,0);case .up:nudge(0,-step);case .down:nudge(0,step);@unknown default:break}}.onAppear{fitScaleEstimate=fitScale;canvasViewportSize=geo.size}.onChange(of:fitScale){_,value in fitScaleEstimate=value}.onChange(of:geo.size){_,value in canvasViewportSize=value}
        }
    }

    private var horizontalRuler:some View{GeometryReader{geo in Canvas{context,size in guard abs(viewRotation.truncatingRemainder(dividingBy:180))<0.1 else{return};let step=rulerStep,scale=fitScaleEstimate*zoom,origin=rulerOriginX(viewportWidth:size.width);for i in 0...max(1,Int(project.canvasWidth/step)){let document=Double(i)*step,x=origin+document*scale+panOffset.width;guard x>=0,x<=size.width else{continue};let major=i%5==0;var tick=Path();tick.move(to:CGPoint(x:x,y:size.height));tick.addLine(to:CGPoint(x:x,y:size.height-(major ? 12:5)));context.stroke(tick,with:.color(.primary.opacity(0.7)),lineWidth:0.7);if major{context.draw(Text(rulerLabel(document)).font(.system(size:8)),at:CGPoint(x:x+18,y:6))}}}.background(Color(nsColor:.controlBackgroundColor)).onTapGesture(coordinateSpace:.local){point in guard project.guidesLocked != true else{return};let position=max(0,min(project.canvasWidth,(Double(point.x)-rulerOriginX(viewportWidth:geo.size.width)-panOffset.width)/(fitScaleEstimate*zoom)));updateProject{$0.userGuidesX=($0.userGuidesX ?? [])+[position]}}.simultaneousGesture(DragGesture(minimumDistance:4,coordinateSpace:.local).onChanged{value in guard project.guidesLocked != true else{return};guidePreview=("Vertical",max(0,min(project.canvasWidth,(Double(value.location.x)-rulerOriginX(viewportWidth:geo.size.width)-panOffset.width)/(fitScaleEstimate*zoom))))}.onEnded{value in guard project.guidesLocked != true else{return};let position=max(0,min(project.canvasWidth,(Double(value.location.x)-rulerOriginX(viewportWidth:geo.size.width)-panOffset.width)/(fitScaleEstimate*zoom)));updateProject{$0.userGuidesX=($0.userGuidesX ?? [])+[position]};guidePreview=nil})}}
    private var verticalRuler:some View{GeometryReader{geo in Canvas{context,size in guard abs(viewRotation.truncatingRemainder(dividingBy:180))<0.1 else{return};let step=rulerStep,scale=fitScaleEstimate*zoom,origin=rulerOriginY(viewportHeight:size.height);for i in 0...max(1,Int(project.canvasHeight/step)){let document=Double(i)*step,y=origin+document*scale+panOffset.height;guard y>=0,y<=size.height else{continue};let major=i%5==0;var tick=Path();tick.move(to:CGPoint(x:size.width,y:y));tick.addLine(to:CGPoint(x:size.width-(major ? 12:5),y:y));context.stroke(tick,with:.color(.primary.opacity(0.7)),lineWidth:0.7);if major{context.draw(Text(rulerLabel(document)).font(.system(size:8)),at:CGPoint(x:10,y:y+6))}}}.background(Color(nsColor:.controlBackgroundColor)).onTapGesture(coordinateSpace:.local){point in guard project.guidesLocked != true else{return};let position=max(0,min(project.canvasHeight,(Double(point.y)-rulerOriginY(viewportHeight:geo.size.height)-panOffset.height)/(fitScaleEstimate*zoom)));updateProject{$0.userGuidesY=($0.userGuidesY ?? [])+[position]}}.simultaneousGesture(DragGesture(minimumDistance:4,coordinateSpace:.local).onChanged{value in guard project.guidesLocked != true else{return};guidePreview=("Horizontal",max(0,min(project.canvasHeight,(Double(value.location.y)-rulerOriginY(viewportHeight:geo.size.height)-panOffset.height)/(fitScaleEstimate*zoom))))}.onEnded{value in guard project.guidesLocked != true else{return};let position=max(0,min(project.canvasHeight,(Double(value.location.y)-rulerOriginY(viewportHeight:geo.size.height)-panOffset.height)/(fitScaleEstimate*zoom)));updateProject{$0.userGuidesY=($0.userGuidesY ?? [])+[position]};guidePreview=nil})}}
    private var rulerStep:Double{let unit=project.unit ?? "in";return unit=="mm" ? 1:(unit=="px" ? max(1,project.dpi/8)/project.dpi:1)}
    private func rulerOriginX(viewportWidth:CGFloat)->Double{let displayed=project.canvasWidth*fitScaleEstimate*zoom,content=max(Double(viewportWidth),displayed+60);return (content-displayed)/2}
    private func rulerOriginY(viewportHeight:CGFloat)->Double{let displayed=project.canvasHeight*fitScaleEstimate*zoom,content=max(Double(viewportHeight),displayed+60);return (content-displayed)/2}
    private func rulerLabel(_ inches:Double)->String{switch project.unit ?? "in"{case "mm":String(format:"%.0f",inches*25.4);case "px":String(format:"%.0f",inches*project.dpi);default:String(format:"%.1f",inches)}}

}

// MARK: - Existing editing actions

private extension BookCoverCreatorView {
    private func binding<T>(_ keyPath:WritableKeyPath<CoverProject,T>)->Binding<T>{Binding(get:{project[keyPath:keyPath]},set:{value in updateProject{$0[keyPath:keyPath]=value}})}
    private func selectTool(_ tool:CoverEditorTool){activeTool=tool;if tool == .crop,selectedLayer?.imageData != nil{cropPreview=CoverRect();cropStraighten=0}}
    private func installCanvasKeyMonitor(){guard keyMonitor == nil else{return};keyMonitor=NSEvent.addLocalMonitorForEvents(matching:[.keyDown,.keyUp,.scrollWheel]){event in guard canvasFocused else{return event};if event.type == .scrollWheel{if NSEvent.modifierFlags.contains(.option) || NSEvent.modifierFlags.contains(.control){let center=CGPoint(x:canvasViewportSize.width/2,y:canvasViewportSize.height/2),factor=exp(-event.scrollingDeltaY/300);zoomAt(center,factor:factor,canvas:canvasViewportSize)}else{panOffset.width -= event.scrollingDeltaX;panOffset.height -= event.scrollingDeltaY};return nil};if event.type == .keyDown {if event.keyCode==53{if selectionTransformSnapshot != nil{activeSelection=selectionTransformSnapshot;selectionTransformSnapshot=nil}else if !constructionPoints.isEmpty{constructionPoints=[];selectionDragPreview=nil}else{canvasDragPoints=[];selectionDragPreview=nil};return nil};if event.keyCode==51,activeTool == .lasso,lassoMode==1,!constructionPoints.isEmpty{constructionPoints.removeLast();return nil};if event.keyCode==36,activeTool == .lasso,lassoMode==1,constructionPoints.count>=3{finishPolygonSelection();return nil};if event.keyCode==49{guard activeTool != .hand,cropPreview==nil,transformSnapshot==nil else{return nil};previousTool=activeTool;activeTool = .hand;return nil};if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers?.lowercased()=="a"{selectAll();return nil};if event.modifierFlags.contains(.command),event.charactersIgnoringModifiers?.lowercased()=="d"{deselect();return nil};if event.modifierFlags.contains([.command,.shift]),event.charactersIgnoringModifiers?.lowercased()=="d"{reselect();return nil}}else if event.keyCode==49{if let previousTool{activeTool=previousTool;self.previousTool=nil};return nil};return event}}
    private func typographyOptionalBinding<T>(
        _ index: Int,
        _ keyPath: WritableKeyPath<CoverLayer,T?>,
        default defaultValue: T
    ) -> Binding<T> {
        Binding(
            get: {
                projects[projectIndex]
                    .layers[index][
                        keyPath: keyPath
                    ]
                ?? defaultValue
            },
            set: { newValue in
                mutateLayer(
                    at: index
                ) {
                    $0[
                        keyPath: keyPath
                    ] = newValue
                }
            }
        )
    }

    private func effectValueBinding<Effect,Value>(
        _ index:Int,
        effect effectKeyPath:WritableKeyPath<CoverLayer,Effect?>,
        defaultValue:@escaping ()->Effect,
        value valueKeyPath:WritableKeyPath<Effect,Value>
    )->Binding<Value>{
        Binding(
            get:{
                let effect =
                    projects[projectIndex]
                        .layers[index][
                            keyPath:
                                effectKeyPath
                        ]
                    ?? defaultValue()

                return effect[
                    keyPath:
                        valueKeyPath
                ]
            },
            set:{newValue in
                mutateLayer(
                    at:index
                ){layer in
                    var effect =
                        layer[
                            keyPath:
                                effectKeyPath
                        ]
                        ?? defaultValue()

                    effect[
                        keyPath:
                            valueKeyPath
                    ] = newValue

                    layer[
                        keyPath:
                            effectKeyPath
                    ] = effect
                }
            }
        )
    }

    private func effectEnabledBinding<Effect>(
        _ index:Int,
        effect effectKeyPath:WritableKeyPath<CoverLayer,Effect?>,
        defaultValue:@escaping ()->Effect,
        enabled enabledKeyPath:WritableKeyPath<Effect,Bool>
    )->Binding<Bool>{
        Binding(
            get:{
                guard
                    let effect =
                        projects[projectIndex]
                            .layers[index][
                                keyPath:
                                    effectKeyPath
                            ]
                else {
                    return false
                }

                return effect[
                    keyPath:
                        enabledKeyPath
                ]
            },
            set:{newValue in
                mutateLayer(
                    at:index
                ){layer in
                    var effect =
                        layer[
                            keyPath:
                                effectKeyPath
                        ]
                        ?? defaultValue()

                    effect[
                        keyPath:
                            enabledKeyPath
                    ] = newValue

                    layer[
                        keyPath:
                            effectKeyPath
                    ] = effect
                }
            }
        )
    }

    @ViewBuilder
    private func layerEffectsPanel(
        _ index:Int
    )->some View{
        VStack(
            alignment:.leading,
            spacing:8
        ){
            dropShadowControls(
                index
            )

            Divider()

            innerShadowControls(
                index
            )

            Divider()

            strokeEffectControls(
                index
            )

            Divider()

            colorOverlayControls(
                index
            )

            Divider()

            gradientOverlayControls(
                index
            )

            Divider()

            outerGlowControls(
                index
            )
        }
        .font(.caption)
    }

    @ViewBuilder
    private func dropShadowControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.dropShadow,
                defaultValue:{
                    CoverDropShadow()
                },
                enabled:\.enabled
            )

        Toggle(
            "Drop Shadow",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .dropShadow?
                .enabled == true
        {
            TextField(
                "Color (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.dropShadow,
                        defaultValue:{
                            CoverDropShadow()
                        },
                        value:\.colorHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.dropShadow,
                        defaultValue:{
                            CoverDropShadow()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )

            effectSlider(
                "Angle",
                value:
                    effectValueBinding(
                        index,
                        effect:\.dropShadow,
                        defaultValue:{
                            CoverDropShadow()
                        },
                        value:\.angle
                    ),
                range:-180...180
            )

            effectSlider(
                "Distance",
                value:
                    effectValueBinding(
                        index,
                        effect:\.dropShadow,
                        defaultValue:{
                            CoverDropShadow()
                        },
                        value:\.distance
                    ),
                range:0...0.25
            )

            effectSlider(
                "Blur",
                value:
                    effectValueBinding(
                        index,
                        effect:\.dropShadow,
                        defaultValue:{
                            CoverDropShadow()
                        },
                        value:\.blur
                    ),
                range:0...0.25
            )
        }
    }

    @ViewBuilder
    private func innerShadowControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.innerShadow,
                defaultValue:{
                    CoverInnerShadow()
                },
                enabled:\.enabled
            )

        Toggle(
            "Inner Shadow",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .innerShadow?
                .enabled == true
        {
            TextField(
                "Color (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.innerShadow,
                        defaultValue:{
                            CoverInnerShadow()
                        },
                        value:\.colorHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.innerShadow,
                        defaultValue:{
                            CoverInnerShadow()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )

            effectSlider(
                "Angle",
                value:
                    effectValueBinding(
                        index,
                        effect:\.innerShadow,
                        defaultValue:{
                            CoverInnerShadow()
                        },
                        value:\.angle
                    ),
                range:-180...180
            )

            effectSlider(
                "Distance",
                value:
                    effectValueBinding(
                        index,
                        effect:\.innerShadow,
                        defaultValue:{
                            CoverInnerShadow()
                        },
                        value:\.distance
                    ),
                range:0...0.25
            )

            effectSlider(
                "Blur",
                value:
                    effectValueBinding(
                        index,
                        effect:\.innerShadow,
                        defaultValue:{
                            CoverInnerShadow()
                        },
                        value:\.blur
                    ),
                range:0...0.25
            )
        }
    }

    @ViewBuilder
    private func strokeEffectControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.strokeEffect,
                defaultValue:{
                    CoverStrokeEffect()
                },
                enabled:\.enabled
            )

        Toggle(
            "Stroke",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .strokeEffect?
                .enabled == true
        {
            TextField(
                "Color (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.strokeEffect,
                        defaultValue:{
                            CoverStrokeEffect()
                        },
                        value:\.colorHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.strokeEffect,
                        defaultValue:{
                            CoverStrokeEffect()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )

            effectSlider(
                "Width",
                value:
                    effectValueBinding(
                        index,
                        effect:\.strokeEffect,
                        defaultValue:{
                            CoverStrokeEffect()
                        },
                        value:\.width
                    ),
                range:0...0.12
            )
        }
    }

    @ViewBuilder
    private func colorOverlayControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.colorOverlay,
                defaultValue:{
                    CoverColorOverlay()
                },
                enabled:\.enabled
            )

        Toggle(
            "Color Overlay",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .colorOverlay?
                .enabled == true
        {
            TextField(
                "Color (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.colorOverlay,
                        defaultValue:{
                            CoverColorOverlay()
                        },
                        value:\.colorHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.colorOverlay,
                        defaultValue:{
                            CoverColorOverlay()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )
        }
    }

    @ViewBuilder
    private func gradientEditorControls(
        _ index:Int
    )->some View {
        let stops=gradientStopsForEditing(index)

        VStack(alignment:.leading,spacing:10) {
            HStack {
                Text("Gradient Editor")
                    .font(.headline)

                Spacer()

                Button(
                    project.layers[index].gradientReversed == true
                    ? "Unreverse"
                    : "Reverse"
                ) {
                    updateProject {
                        $0.layers[index].gradientReversed =
                            !($0.layers[index].gradientReversed ?? false)
                    }
                }
            }

            Picker(
                "Type",
                selection:Binding(
                    get:{
                        project.layers[index].gradientRadial == true ? 1 : 0
                    },
                    set:{
                        value in
                        updateProject {
                            $0.layers[index].gradientRadial = value == 1
                        }
                    }
                )
            ) {
                Text("Linear").tag(0)
                Text("Radial").tag(1)
            }
            .pickerStyle(.segmented)

            GeometryReader {
                geometry in

                ZStack(alignment:.leading) {
                    RoundedRectangle(cornerRadius:5)
                        .fill(
                            LinearGradient(
                                gradient:Gradient(
                                    stops:gradientPreviewStops(index)
                                ),
                                startPoint:.leading,
                                endPoint:.trailing
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius:5)
                                .stroke(
                                    Color.white.opacity(0.22),
                                    lineWidth:1
                                )
                        )
                        .frame(height:30)

                    ForEach(stops) {
                        stop in

                        VStack(spacing:1) {
                            Image(systemName:"triangle.fill")
                                .font(.system(size:8))
                                .foregroundStyle(.white)

                            Circle()
                                .fill(
                                    Color(
                                        nsColor:NSColor(hex:stop.colorHex)
                                    )
                                    .opacity(stop.opacity)
                                )
                                .overlay(
                                    Circle()
                                        .stroke(.white,lineWidth:1)
                                )
                                .frame(width:13,height:13)
                        }
                        .position(
                            x:max(
                                8,
                                min(
                                    geometry.size.width-8,
                                    CGFloat(stop.location) *
                                    geometry.size.width
                                )
                            ),
                            y:39
                        )
                        .gesture(
                            DragGesture(minimumDistance:0)
                                .onChanged {
                                    value in

                                    let location=max(
                                        0,
                                        min(
                                            1,
                                            Double(
                                                value.location.x /
                                                max(
                                                    1,
                                                    geometry.size.width
                                                )
                                            )
                                        )
                                    )

                                    setGradientStopLocation(
                                        layerIndex:index,
                                        stopID:stop.id,
                                        location:location
                                    )
                                }
                        )
                    }
                }
            }
            .frame(height:54)

            ForEach(
                Array(stops.enumerated()),
                id:\.element.id
            ) {
                offset,
                stop in

                VStack(alignment:.leading,spacing:5) {
                    HStack(spacing:6) {
                        Circle()
                            .fill(
                                Color(
                                    nsColor:NSColor(hex:stop.colorHex)
                                )
                                .opacity(stop.opacity)
                            )
                            .overlay(
                                Circle()
                                    .stroke(
                                        Color.white.opacity(0.35),
                                        lineWidth:1
                                    )
                            )
                            .frame(width:16,height:16)

                        TextField(
                            "#RRGGBB",
                            text:Binding(
                                get:{
                                    gradientStop(
                                        layerIndex:index,
                                        stopID:stop.id
                                    )?.colorHex ?? stop.colorHex
                                },
                                set:{
                                    value in
                                    mutateGradientStop(
                                        layerIndex:index,
                                        stopID:stop.id
                                    ) {
                                        $0.colorHex=value
                                    }
                                }
                            )
                        )
                        .textFieldStyle(.roundedBorder)

                        Text(
                            "\(Int((stop.location*100).rounded()))%"
                        )
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width:42,alignment:.trailing)

                        Button(role:.destructive) {
                            removeGradientStop(
                                layerIndex:index,
                                stopID:stop.id
                            )
                        } label:{
                            Image(systemName:"minus.circle")
                        }
                        .buttonStyle(.plain)
                        .disabled(stops.count<=2)
                    }

                    HStack {
                        Text("Location")
                            .font(.caption)
                            .frame(width:58,alignment:.leading)

                        Slider(
                            value:Binding(
                                get:{
                                    gradientStop(
                                        layerIndex:index,
                                        stopID:stop.id
                                    )?.location ?? stop.location
                                },
                                set:{
                                    value in
                                    setGradientStopLocation(
                                        layerIndex:index,
                                        stopID:stop.id,
                                        location:value
                                    )
                                }
                            ),
                            in:0...1
                        )
                    }

                    HStack {
                        Text("Opacity")
                            .font(.caption)
                            .frame(width:58,alignment:.leading)

                        Slider(
                            value:Binding(
                                get:{
                                    gradientStop(
                                        layerIndex:index,
                                        stopID:stop.id
                                    )?.opacity ?? stop.opacity
                                },
                                set:{
                                    value in
                                    mutateGradientStop(
                                        layerIndex:index,
                                        stopID:stop.id
                                    ) {
                                        $0.opacity=value
                                    }
                                }
                            ),
                            in:0...1
                        )

                        Text(
                            "\(Int((stop.opacity*100).rounded()))%"
                        )
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width:38,alignment:.trailing)
                    }

                    if offset<stops.count-1 {
                        HStack {
                            Text("Midpoint")
                                .font(.caption)
                                .frame(width:58,alignment:.leading)

                            Slider(
                                value:Binding(
                                    get:{
                                        gradientStop(
                                            layerIndex:index,
                                            stopID:stop.id
                                        )?.midpoint ?? stop.midpoint
                                    },
                                    set:{
                                        value in
                                        mutateGradientStop(
                                            layerIndex:index,
                                            stopID:stop.id
                                        ) {
                                            $0.midpoint=value
                                        }
                                    }
                                ),
                                in:0.05...0.95
                            )

                            Text(
                                "\(Int((stop.midpoint*100).rounded()))%"
                            )
                            .font(.caption)
                            .monospacedDigit()
                            .frame(width:38,alignment:.trailing)
                        }
                    }
                }
                .padding(7)
                .background(Color.white.opacity(0.035))
                .clipShape(RoundedRectangle(cornerRadius:6))
            }

            HStack {
                Button(
                    "Add Stop",
                    systemImage:"plus.circle"
                ) {
                    addGradientStop(layerIndex:index)
                }

                Spacer()

                Text("\(stops.count) stops")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if project.layers[index].gradientRadial == true {
                HStack {
                    Text("Center X")
                        .font(.caption)
                        .frame(width:58,alignment:.leading)

                    Slider(
                        value:optionalGradientBinding(
                            index,
                            \.gradientCenterX,
                            defaultValue:0.5
                        ),
                        in:0...1
                    )
                }

                HStack {
                    Text("Center Y")
                        .font(.caption)
                        .frame(width:58,alignment:.leading)

                    Slider(
                        value:optionalGradientBinding(
                            index,
                            \.gradientCenterY,
                            defaultValue:0.5
                        ),
                        in:0...1
                    )
                }

                HStack {
                    Text("Radius")
                        .font(.caption)
                        .frame(width:58,alignment:.leading)

                    Slider(
                        value:optionalGradientBinding(
                            index,
                            \.gradientRadius,
                            defaultValue:0.75
                        ),
                        in:0.05...2
                    )

                    Text(
                        String(
                            format:"%.2f",
                            project.layers[index].gradientRadius ?? 0.75
                        )
                    )
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width:38,alignment:.trailing)
                }
            } else {
                HStack {
                    Text("Angle")
                        .font(.caption)
                        .frame(width:58,alignment:.leading)

                    Slider(
                        value:optionalGradientBinding(
                            index,
                            \.gradientAngle,
                            defaultValue:0
                        ),
                        in:-180...180
                    )

                    Text(
                        "\(Int((project.layers[index].gradientAngle ?? 0).rounded()))°"
                    )
                    .font(.caption)
                    .monospacedDigit()
                    .frame(width:42,alignment:.trailing)
                }
            }

            Button("Reset Gradient Geometry") {
                updateProject {
                    $0.layers[index].gradientAngle=0
                    $0.layers[index].gradientCenterX=0.5
                    $0.layers[index].gradientCenterY=0.5
                    $0.layers[index].gradientRadius=0.75
                    $0.layers[index].gradientReversed=false
                }
            }
        }
        .onAppear {
            ensureGradientStops(index)
        }
    }

    private func gradientStopsForEditing(
        _ index:Int
    )->[CoverGradientStop] {
        guard project.layers.indices.contains(index) else {
            return []
        }

        if let stops=project.layers[index].gradientStops,
           stops.count>=2
        {
            return stops.sorted(by:{$0.location<$1.location})
        }

        return CoverArtwork.baseGradientStops(
            project.layers[index]
        )
    }

    private func gradientPreviewStops(
        _ index:Int
    )->[Gradient.Stop] {
        guard project.layers.indices.contains(index) else {
            return []
        }

        return CoverArtwork
            .renderedGradientStops(project.layers[index])
            .map {
                Gradient.Stop(
                    color:Color(
                        nsColor:NSColor(hex:$0.colorHex)
                    )
                    .opacity($0.opacity),
                    location:CGFloat($0.location)
                )
            }
    }

    private func ensureGradientStops(
        _ index:Int
    ) {
        guard project.layers.indices.contains(index),
              project.layers[index].kind == .gradient,
              project.layers[index].gradientStops == nil
        else {
            return
        }

        let stops=CoverArtwork.baseGradientStops(
            project.layers[index]
        )

        updateProject {
            $0.layers[index].gradientStops=stops
            $0.layers[index].gradientAngle =
                $0.layers[index].gradientAngle ?? 0
            $0.layers[index].gradientCenterX =
                $0.layers[index].gradientCenterX ?? 0.5
            $0.layers[index].gradientCenterY =
                $0.layers[index].gradientCenterY ?? 0.5
            $0.layers[index].gradientRadius =
                $0.layers[index].gradientRadius ?? 0.75
            $0.layers[index].gradientReversed =
                $0.layers[index].gradientReversed ?? false
        }
    }

    private func gradientStop(
        layerIndex:Int,
        stopID:UUID
    )->CoverGradientStop? {
        guard project.layers.indices.contains(layerIndex) else {
            return nil
        }

        return project.layers[layerIndex]
            .gradientStops?
            .first(where:{$0.id==stopID})
    }

    private func mutateGradientStop(
        layerIndex:Int,
        stopID:UUID,
        _ body:@escaping (inout CoverGradientStop)->Void
    ) {
        guard project.layers.indices.contains(layerIndex) else {
            return
        }

        updateProject {
            project in

            guard project.layers.indices.contains(layerIndex) else {
                return
            }

            var stops =
                project.layers[layerIndex].gradientStops ??
                CoverArtwork.baseGradientStops(
                    project.layers[layerIndex]
                )

            guard let stopIndex=stops.firstIndex(
                where:{$0.id==stopID}
            ) else {
                return
            }

            body(&stops[stopIndex])
            stops.sort(by:{$0.location<$1.location})
            project.layers[layerIndex].gradientStops=stops
            syncLegacyGradientColors(
                &project.layers[layerIndex]
            )
        }
    }

    private func setGradientStopLocation(
        layerIndex:Int,
        stopID:UUID,
        location:Double
    ) {
        mutateGradientStop(
            layerIndex:layerIndex,
            stopID:stopID
        ) {
            $0.location=max(0,min(1,location))
        }
    }

    private func addGradientStop(
        layerIndex:Int
    ) {
        guard project.layers.indices.contains(layerIndex) else {
            return
        }

        updateProject {
            project in

            guard project.layers.indices.contains(layerIndex) else {
                return
            }

            var stops =
                project.layers[layerIndex].gradientStops ??
                CoverArtwork.baseGradientStops(
                    project.layers[layerIndex]
                )

            stops.sort(by:{$0.location<$1.location})

            var location=0.5
            var largestGap = -Double.infinity

            if stops.count>=2 {
                for index in 0..<(stops.count-1) {
                    let gap =
                        stops[index+1].location -
                        stops[index].location

                    if gap>largestGap {
                        largestGap=gap
                        location =
                            (
                                stops[index].location +
                                stops[index+1].location
                            ) / 2
                    }
                }
            }

            stops.append(
                CoverGradientStop(
                    colorHex:foregroundHex,
                    location:location,
                    opacity:1,
                    midpoint:0.5
                )
            )

            stops.sort(by:{$0.location<$1.location})
            project.layers[layerIndex].gradientStops=stops
            syncLegacyGradientColors(
                &project.layers[layerIndex]
            )
        }
    }

    private func removeGradientStop(
        layerIndex:Int,
        stopID:UUID
    ) {
        guard project.layers.indices.contains(layerIndex) else {
            return
        }

        updateProject {
            project in

            guard project.layers.indices.contains(layerIndex) else {
                return
            }

            var stops =
                project.layers[layerIndex].gradientStops ?? []

            guard stops.count>2 else {
                return
            }

            stops.removeAll(where:{$0.id==stopID})
            stops.sort(by:{$0.location<$1.location})
            project.layers[layerIndex].gradientStops=stops
            syncLegacyGradientColors(
                &project.layers[layerIndex]
            )
        }
    }

    private func syncLegacyGradientColors(
        _ layer:inout CoverLayer
    ) {
        guard let stops=layer.gradientStops?
            .sorted(by:{$0.location<$1.location}),
              let first=stops.first,
              let last=stops.last
        else {
            return
        }

        layer.fillHex=first.colorHex
        layer.gradientEndHex=last.colorHex
    }

    private func optionalGradientBinding(
        _ index:Int,
        _ keyPath:WritableKeyPath<CoverLayer,Double?>,
        defaultValue:Double
    )->Binding<Double> {
        Binding(
            get:{
                project.layers[index][keyPath:keyPath] ??
                defaultValue
            },
            set:{
                value in
                updateProject {
                    $0.layers[index][keyPath:keyPath]=value
                }
            }
        )
    }

    @ViewBuilder
    private func gradientOverlayControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.gradientOverlay,
                defaultValue:{
                    CoverGradientOverlay()
                },
                enabled:\.enabled
            )

        Toggle(
            "Gradient Overlay",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .gradientOverlay?
                .enabled == true
        {
            TextField(
                "Start (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.gradientOverlay,
                        defaultValue:{
                            CoverGradientOverlay()
                        },
                        value:\.startHex
                    )
            )

            TextField(
                "End (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.gradientOverlay,
                        defaultValue:{
                            CoverGradientOverlay()
                        },
                        value:\.endHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.gradientOverlay,
                        defaultValue:{
                            CoverGradientOverlay()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )

            effectSlider(
                "Angle",
                value:
                    effectValueBinding(
                        index,
                        effect:\.gradientOverlay,
                        defaultValue:{
                            CoverGradientOverlay()
                        },
                        value:\.angle
                    ),
                range:-180...180
            )
        }
    }

    @ViewBuilder
    private func outerGlowControls(
        _ index:Int
    )->some View{
        let enabled =
            effectEnabledBinding(
                index,
                effect:\.outerGlow,
                defaultValue:{
                    CoverOuterGlow()
                },
                enabled:\.enabled
            )

        Toggle(
            "Outer Glow",
            isOn:enabled
        )

        if
            projects[projectIndex]
                .layers[index]
                .outerGlow?
                .enabled == true
        {
            TextField(
                "Color (#RRGGBB)",
                text:
                    effectValueBinding(
                        index,
                        effect:\.outerGlow,
                        defaultValue:{
                            CoverOuterGlow()
                        },
                        value:\.colorHex
                    )
            )

            effectSlider(
                "Opacity",
                value:
                    effectValueBinding(
                        index,
                        effect:\.outerGlow,
                        defaultValue:{
                            CoverOuterGlow()
                        },
                        value:\.opacity
                    ),
                range:0...1
            )

            effectSlider(
                "Size",
                value:
                    effectValueBinding(
                        index,
                        effect:\.outerGlow,
                        defaultValue:{
                            CoverOuterGlow()
                        },
                        value:\.size
                    ),
                range:0...0.25
            )
        }
    }

    private func effectSlider(
        _ title:String,
        value:Binding<Double>,
        range:ClosedRange<Double>
    )->some View{
        VStack(
            alignment:.leading,
            spacing:2
        ){
            HStack{
                Text(title)
                Spacer()
                Text(
                    String(
                        format:
                            title == "Angle"
                            ? "%.0f°"
                            : "%.2f",
                        value.wrappedValue
                    )
                )
                .foregroundStyle(.secondary)
            }

            Slider(
                value:value,
                in:range
            )
            .accessibilityLabel(title)
        }
    }

    private func layerBinding<T>(_ index:Int,_ keyPath:WritableKeyPath<CoverLayer,T>)->Binding<T>{Binding(get:{projects[projectIndex].layers[index][keyPath:keyPath]},set:{value in mutateLayer(at:index){$0[keyPath:keyPath]=value}})}
    private func frameDimensionBinding(_ index:Int,width:Bool)->Binding<Double>{Binding(get:{width ? projects[projectIndex].layers[index].frame.width:projects[projectIndex].layers[index].frame.height},set:{value in mutateLayer(at:index){layer in let ratio=layer.frame.width/max(0.0001,layer.frame.height);if width{layer.frame.width=value;if proportionalScale{layer.frame.height=min(1,value/ratio)}}else{layer.frame.height=value;if proportionalScale{layer.frame.width=min(1,value*ratio)}}}})}
    private func adjustmentValueBinding(at index:Int,control:CoverAdjustmentControl)->Binding<Double>{
        Binding(
            get:{
                guard projects.indices.contains(projectIndex),
                      projects[projectIndex].layers.indices.contains(index)
                else { return control.initial }
                return control.clamped(
                    projects[projectIndex].layers[index].adjustmentValues?[control.key]
                    ?? control.initial
                )
            },
            set:{ value in
                mutateLayer(at:index){layer in
                    var values=layer.adjustmentValues ?? [:]
                    values[control.key]=control.clamped(value)
                    layer.adjustmentValues=values
                }
            }
        )
    }
    private func pushUndo(){undoStack.append(CoverProjectHistory.snapshot(project)); if undoStack.count>50{undoStack.removeFirst()}; redoStack=[]}
    private func updateProject(_ body:(inout CoverProject)->Void){pushUndo();body(&projects[projectIndex])}
    private func mutateLayer(at index:Int,_ body:(inout CoverLayer)->Void){
        guard project.layers.indices.contains(index), !project.layers[index].locked else { return }
        var layer = project.layers[index]
        body(&layer)
        if layer.kind == .path, var contours = layer.pathContours, !contours.isEmpty, let primary = layer.pathPoints {
            contours[0] = primary; layer.pathContours = contours
        }
        var next = project
        do {
            try CoverProjectOperations.replace(layer,in:&next)
            if next != project { if undoStack.last.map({ !CoverProjectHistory.matches($0, project: project) }) ?? true { pushUndo() }; projects[projectIndex] = next }
        } catch { errorMessage = error.localizedDescription }
    }
    private func addText(
        _ name: String,
        frame: CoverRect,
        size: Double
    ) {
        updateProject {
            $0.layers.append({
                var layer =
                    CoverLayer(
                        kind: .text,
                        name: name,
                        frame: frame
                    )

                layer.text = name
                layer.fontSize = size

                return layer
            }())
        }

        selectedID =
            project.layers.last?.id

        if let selectedID {
            selectedIDs = [selectedID]
        }

        workspace.character = true
        workspace.paragraph = true
        workspace.rightDock = true
    }
    private func convertShapeToPath(
        _ id: UUID
    ) {
        guard let index =
                projects[projectIndex]
                    .layers
                    .firstIndex(
                        where:{
                            $0.id == id
                        }
                    ),
              projects[projectIndex]
                .layers[index]
                .kind == .shape,
              !projects[projectIndex]
                .layers[index]
                .locked,
              let converted =
                CoverEditorEngine
                    .convertedShapeToPath(
                        projects[
                            projectIndex
                        ]
                        .layers[index]
                    )
        else {
            return
        }

        updateProject {
            $0.layers[index] =
                converted
        }

        selectedID = id
        selectedIDs = [id]
        selectedPathContourIndex = 0
        selectedPathPointIndex = 0
        activeTool = .path
        workspace.paths = true
        workspace.rightDock = true
    }

    private func addShape(_ shape:CoverShapeKind){updateProject{$0.layers.append({var l=CoverLayer(kind:.shape,name:shape.rawValue.capitalized,frame:CoverRect(x:0.1,y:0.1,width:0.8,height:0.15));l.shape=shape;return l}())};selectedID=project.layers.last?.id}
    private func copyEbookArt(){guard let source=projects.first(where:{$0.type == .ebookFront}) else{return};updateProject{destination in for var layer in source.layers where !layer.isReferenceLayer {layer.id=UUID();layer.frame.x=(destination.bleed+destination.backWidth+destination.spineWidth)/destination.canvasWidth + layer.frame.x*destination.trimWidth/destination.canvasWidth;layer.frame.y*=destination.trimHeight/destination.canvasHeight;layer.frame.width=layer.frame.width*destination.trimWidth/destination.canvasWidth;layer.frame.height=layer.frame.height*destination.trimHeight/destination.canvasHeight;destination.layers.append(layer)}}}
    private func delete(_ id:UUID){
        guard applyCoverOperation("delete",arguments:["layerID":id.uuidString]) != nil else { return }
        selectedIDs.remove(id)
        if selectedID == id { selectedID = selectedIDs.first }
    }
    private func duplicate(_ id:UUID){
        guard let newID = applyCoverOperation("duplicate",arguments:["layerID":id.uuidString])?.first else { return }
        selectedID = newID; selectedIDs = [newID]
    }
    private func moveLayer(_ delta:Int){
        guard let id = selectedID, let index = project.layers.firstIndex(where:{ $0.id == id }) else { return }
        let next = max(0,min(project.layers.count-1,index+delta))
        _ = applyCoverOperation("reorder",arguments:["layerID":id.uuidString,"index":String(next)])
    }

    @discardableResult
    private func applyCoverOperation(_ operation: String, arguments: [String:String]) -> [UUID]? {
        var next = project
        do {
            let ids = try CoverProjectOperations.apply(operation, to: &next, arguments: arguments)
            if next != project { pushUndo(); projects[projectIndex] = next }
            return ids
        } catch { errorMessage = error.localizedDescription; return nil }
    }

    private func groupSelectedLayers(){
        guard let ids = applyCoverOperation("group", arguments:["layerIDs":selectedIDs.map(\.uuidString).joined(separator:",")]),
              let id = ids.first else { return }
        selectedID = id; selectedIDs = [id]
    }

    private func linkSelectedLayers(){
        let ids = linkEligibleSelectedIDs

        guard ids.count >= 2
        else {
            return
        }

        updateProject{
            project in

            _ = CoverEditorEngine.linkLayers(
                &project.layers,
                ids:ids
            )
        }

        selectedIDs =
            CoverEditorEngine.effectiveLinkedLayerIDs(
                project.layers,
                ids:ids
            )

        if selectedID.map({
            !selectedIDs.contains($0)
        }) ?? true {
            selectedID = selectedIDs.first
        }
    }

    private func unlinkSelectedLayers(){
        let ids =
            selectedIDs.isEmpty
            ? Set([selectedID].compactMap{$0})
            : selectedIDs

        guard !ids.isEmpty
        else {
            return
        }

        updateProject{
            project in

            CoverEditorEngine.unlinkLayers(
                &project.layers,
                ids:ids
            )
        }
    }

    private func selectLinkedLayers(){
        guard let selectedID
        else {
            return
        }

        let linked =
            CoverEditorEngine.linkedLayerIDs(
                project.layers,
                layerID:selectedID
            )

        guard linked.count >= 2
        else {
            return
        }

        selectedIDs = linked
    }
    private func undo(){CoverProjectHistory.undo(project:&projects[projectIndex],undo:&undoStack,redo:&redoStack)}
    private func redo(){CoverProjectHistory.redo(project:&projects[projectIndex],undo:&undoStack,redo:&redoStack)}
    private func jumpToHistory(_ step:Int) {
        let current=undoStack.count
        if step<current { for _ in step..<current { undo() } }
        else if step>current { for _ in current..<min(step,current+redoStack.count) { redo() } }
    }
    private func presentPlaceEmbedded() {
        canvasFocused =
            false

        let panel =
            NSOpenPanel()

        panel.title =
            "Place Embedded Smart Object"

        panel.allowedContentTypes =
            [.pdf]
            + CoverImport.imageTypes

        panel.allowsMultipleSelection =
            false

        panel.canChooseDirectories =
            false

        panel.message =
            "Embed the original source and place a nondestructive Smart Object."

        panel.begin {
            response in

            guard response == .OK,
                  let url =
                    panel.url
            else {
                return
            }

            placeEmbeddedSmartObject(
                url
            )
        }
    }

    private func placeEmbeddedSmartObject(
        _ url: URL
    ) {
        do {
            let layer =
                try CoverImport
                    .smartObjectLayer(
                        from:
                            url,
                        project:
                            project
                    )

            try CoverImport.apply(
                layer,
                project:
                    &projects[
                        projectIndex
                    ],
                undo:
                    &undoStack,
                redo:
                    &redoStack,
                selectedID:
                    &selectedID,
                selectedIDs:
                    &selectedIDs
            )

            selectedMaskLayerID =
                nil

            maskSelected =
                false

            workspace.layers =
                true

            workspace.rightDock =
                true

            hasOpenedProject =
                true

            showingHome =
                false
        } catch {
            errorMessage =
                "Could not place \(url.lastPathComponent) as a Smart Object: \(error.localizedDescription)"
        }
    }

    private func presentPlaceLinked() {
        canvasFocused =
            false

        let panel =
            NSOpenPanel()

        panel.title =
            "Place Linked Smart Object"

        panel.allowedContentTypes =
            CoverImport
                .smartObjectTypes

        panel.allowsMultipleSelection =
            false

        panel.canChooseDirectories =
            false

        panel.message =
            "Link the selected source file while keeping an offline source snapshot and render cache inside the BOLD document."

        panel.begin {
            response in

            guard response == .OK,
                  let url =
                    panel.url
            else {
                return
            }

            placeLinkedSmartObject(
                url
            )
        }
    }

    private func placeLinkedSmartObject(
        _ url: URL
    ) {
        do {
            let layer =
                try CoverImport
                    .linkedSmartObjectLayer(
                        from:
                            url,
                        project:
                            project
                    )

            try CoverImport.apply(
                layer,
                project:
                    &projects[
                        projectIndex
                    ],
                undo:
                    &undoStack,
                redo:
                    &redoStack,
                selectedID:
                    &selectedID,
                selectedIDs:
                    &selectedIDs
            )

            selectedMaskLayerID =
                nil

            maskSelected =
                false

            workspace.layers =
                true

            canvasFocused =
                true
        } catch {
            errorMessage =
                "Could not place \(url.lastPathComponent) as a linked Smart Object: \(error.localizedDescription)"
        }
    }

    private func presentRelinkSmartObject(
        _ layerID: UUID
    ) {
        guard let layer =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              layer.kind == .smartObject,
              layer.smartObject?
                .storageMode
                == .linked,
              !layer.locked
        else {
            return
        }

        canvasFocused =
            false

        let panel =
            NSOpenPanel()

        panel.title =
            "Relink Smart Object"

        panel.allowedContentTypes =
            CoverImport
                .smartObjectTypes

        panel.allowsMultipleSelection =
            false

        panel.canChooseDirectories =
            false

        panel.message =
            "Choose a new external source for this linked Smart Object."

        panel.begin {
            response in

            guard response == .OK,
                  let url =
                    panel.url
            else {
                return
            }

            relinkSmartObject(
                layerID:
                    layerID,
                url:
                    url
            )
        }
    }

    private func relinkSmartObject(
        layerID: UUID,
        url: URL
    ) {
        guard let source =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              source.kind == .smartObject,
              source.smartObject?
                .storageMode
                == .linked,
              !source.locked
        else {
            return
        }

        do {
            guard let replacement =
                    try CoverImport
                        .relinkingSmartObjectContents(
                            in:
                                source,
                            from:
                                url
                        )
            else {
                throw WriterError.message(
                    "The selected layer is not a linked Smart Object."
                )
            }

            updateProject {
                project in

                guard let index =
                        project.layers.firstIndex(
                            where: {
                                $0.id == layerID
                            }
                        )
                else {
                    return
                }

                project.layers[
                    index
                ] =
                    replacement
            }

            canvasFocused =
                true
        } catch {
            errorMessage =
                "Could not relink Smart Object to \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func updateLinkedSmartObjectContents(
        _ layerID: UUID
    ) {
        guard let source =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              source.kind == .smartObject,
              source.smartObject?
                .storageMode
                == .linked,
              !source.locked
        else {
            return
        }

        do {
            guard let replacement =
                    try CoverImport
                        .updatingLinkedSmartObjectContents(
                            in:
                                source
                        )
            else {
                throw WriterError.message(
                    "The selected layer is not an updatable linked Smart Object."
                )
            }

            updateProject {
                project in

                guard let index =
                        project.layers.firstIndex(
                            where: {
                                $0.id == layerID
                            }
                        )
                else {
                    return
                }

                project.layers[
                    index
                ] =
                    replacement
            }
        } catch {
            errorMessage =
                "Could not update linked Smart Object content: \(error.localizedDescription)"
        }
    }

    private func convertLinkedSmartObjectToEmbedded(
        _ layerID: UUID
    ) {
        guard let source =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              !source.locked,
              let embedded =
                CoverEditorEngine
                    .embeddingLinkedSmartObject(
                        in:
                            source
                    )
        else {
            return
        }

        updateProject {
            project in

            guard let index =
                    project.layers.firstIndex(
                        where: {
                            $0.id == layerID
                        }
                    )
            else {
                return
            }

            project.layers[
                index
            ] =
                embedded
        }
    }

    private func presentReplaceSmartObjectContents(
        _ layerID: UUID
    ) {
        guard let layer =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              layer.kind == .smartObject,
              layer.smartObject?.storageMode == .embedded,
              !layer.locked
        else {
            return
        }

        canvasFocused =
            false

        let panel =
            NSOpenPanel()

        panel.title =
            "Replace Smart Object Contents"

        panel.allowedContentTypes =
            CoverImport.smartObjectTypes

        panel.allowsMultipleSelection =
            false

        panel.canChooseDirectories =
            false

        panel.message =
            "Replace the embedded source while preserving this layer's transform, masks, effects, filters, blending, and warp."

        panel.begin {
            response in

            guard response == .OK,
                  let url =
                    panel.url
            else {
                return
            }

            replaceSmartObjectContents(
                layerID:
                    layerID,
                url:
                    url
            )
        }
    }

    private func replaceSmartObjectContents(
        layerID: UUID,
        url: URL
    ) {
        guard let source =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              source.kind == .smartObject,
              !source.locked
        else {
            return
        }

        do {
            guard let replacement =
                try CoverImport
                    .replacingSmartObjectContents(
                        in:
                            source,
                        from:
                            url
                    )
            else {
                throw WriterError.message(
                    "The selected layer is not a replaceable Smart Object."
                )
            }

            updateProject {
                project in

                guard let index =
                    project.layers.firstIndex(
                        where: {
                            $0.id == layerID
                        }
                    )
                else {
                    return
                }

                project.layers[
                    index
                ] =
                    replacement
            }

            selectedID =
                layerID

            selectedIDs = [
                layerID
            ]

            maskSelected =
                false
        } catch {
            errorMessage =
                "Could not replace Smart Object contents with \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func presentReplaceImage(_ layerID: UUID) {
        guard let layer = project.layers.first(where: { $0.id == layerID }),
              layer.kind == .image, !layer.locked, layer.pixelsLocked != true else { return }
        canvasFocused = false
        let panel = NSOpenPanel()
        panel.title = "Replace Image"
        panel.allowedContentTypes = CoverImport.imageTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Replace the embedded image while preserving its editable placement, crop, mask, and effects."
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let replacement = try CoverImport.replacingImageContents(in: layer, from: url)
                guard project.layers.first(where: { $0.id == layerID }) == layer else {
                    throw WriterError.message("The image layer changed while the file picker was open. Choose it again.")
                }
                updateProject { project in
                    guard let index = project.layers.firstIndex(where: { $0.id == layerID }) else { return }
                    project.layers[index] = replacement
                }
                selectedID = layerID
                selectedIDs = [layerID]
                activeSelection = nil
                selectionLayerID = nil
                selectedMaskLayerID = nil
                maskSelected = false
            } catch {
                errorMessage = "Could not replace image: \(error.localizedDescription)"
            }
        }
    }

    private func rasterizeSmartObject(
        _ layerID: UUID
    ) {
        guard let source =
                project.layers.first(
                    where: {
                        $0.id == layerID
                    }
                ),
              !source.locked,
              let rasterized =
                CoverEditorEngine
                    .rasterizingSmartObject(
                        source
                    )
        else {
            return
        }

        updateProject {
            project in

            guard let index =
                project.layers.firstIndex(
                    where: {
                        $0.id == layerID
                    }
                )
            else {
                return
            }

            project.layers[
                index
            ] =
                rasterized
        }

        selectedID =
            layerID

        selectedIDs = [
            layerID
        ]

        maskSelected =
            false
    }
    private func presentImport(template: Bool, asProject: Bool = false) {
        canvasFocused=false
        let panel=NSOpenPanel()
        panel.title=template ? "Import Cover Template" : asProject ? "Open Image as Cover" : "Import Image"
        panel.allowedContentTypes=[.pdf]+CoverImport.imageTypes
        panel.allowsMultipleSelection=false
        panel.canChooseDirectories=false
        panel.message=asProject
            ? "Create a cover canvas at the image's pixel size and resolution. PSD files open with supported editable layers."
            : template
            ? "KDP hardcover PDFs open as a new measured print cover. Other templates become reference overlays, centered and scaled to fit."
            : "Import embedded artwork, centered at the cover resolution and scaled down only when needed. PSD files replace matching cover artwork with supported editable layers."
        panel.begin { response in
            guard response == .OK, let url=panel.url else { return }
            if asProject { openImageProject(url) }
            else { importArtwork(url,template:template) }
        }
    }

    private func handleArtworkDrop(_ providers: [NSItemProvider]) -> Bool {
        let destinationID = project.id
        let destinationWasHome = showingHome
        let destinationWasOpen = hasOpenedProject
        return LocalFileDrop.load(providers) { results in
            guard isActive, project.id == destinationID,
                  showingHome == destinationWasHome, hasOpenedProject == destinationWasOpen else {
                errorMessage = "The destination cover changed while loading the drop. Drop the files again on the intended cover."
                return
            }
            let urls = results.compactMap { try? $0.get() }
            if urls.count > 1 && urls.contains(where: { $0.pathExtension.lowercased() == "psd" }) {
                errorMessage = "Drop a layered PSD separately: PSD import replaces the cover's layers. No files from this drop were imported."
                return
            }
            var failures: [String] = []
            for result in results {
                switch result {
                case .failure(let error): failures.append(error.localizedDescription)
                case .success(let url):
                    errorMessage = nil
                    if hasOpenedProject && !showingHome { importArtwork(url, template: false) }
                    else { openImageProject(url) }
                    if let message = errorMessage { failures.append(message) }
                }
            }
            errorMessage = failures.isEmpty ? nil : failures.joined(separator: "\n")
        }
    }

    private func openImageProject(_ url: URL) {
        do {
            guard CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject) else {
                throw WriterError.message("A manuscript can contain up to eight cover projects.")
            }
            let opened=try CoverImport.project(from:url)
            if hasOpenedProject { projects.append(opened);projectIndex=projects.count-1 }
            else { projects[0]=opened;projectIndex=0 }
            hasOpenedProject=true
            showingHome=false
            selectedID=opened.layers[0].id
            selectedIDs=[opened.layers[0].id]
            undoStack=[]
            redoStack=[]
            fitCover()
            if let warnings = opened.psdImportWarnings, !warnings.isEmpty { errorMessage = warnings.joined(separator:"\n") }
        } catch { errorMessage="Could not open \(url.lastPathComponent): \(error.localizedDescription)" }
    }

    private func importArtwork(_ url: URL, template: Bool) {
        if !template, url.pathExtension.lowercased() == "psd" {
            if !hasOpenedProject { openImageProject(url); return }
            if let ids = applyCoverOperation("psd-import",arguments:["path":url.path]) {
                selectedID = ids.first; selectedIDs = Set(ids)
                if let warnings = project.psdImportWarnings, !warnings.isEmpty { errorMessage = warnings.joined(separator:"\n") }
                fitCover()
            }
            return
        }
        do {
            let templateProject = template ? try CoverImport.project(from:url,asTemplate:true) : nil
            if let opened = templateProject, !hasOpenedProject || opened.activeKDPHardcoverLayout != nil {
                guard CoverProjectOperations.canAppendProject(existingCount: projects.count, hasOpenedProject: hasOpenedProject) else {
                    throw WriterError.message("A manuscript can contain up to eight cover projects.")
                }
                if hasOpenedProject { projects.append(opened); projectIndex=projects.count-1 }
                else { projects[0]=opened; projectIndex=0 }
                undoStack=[]
                redoStack=[]
                hasOpenedProject=true
                showingHome=false
                selectedID=opened.layers[0].id
                selectedIDs=[opened.layers[0].id]
                fitCover()
                droppedURL=nil
                return
            }
            let layer=try CoverImport.layer(from:url,template:template,project:project)
            try CoverImport.apply(layer,project:&projects[projectIndex],undo:&undoStack,redo:&redoStack,
                                  selectedID:&selectedID,selectedIDs:&selectedIDs)
            selectedMaskLayerID=nil
            workspace.layers=true; workspace.rightDock=true
            hasOpenedProject=true
            showingHome=false
            fitCover()
            droppedURL=nil
        } catch { errorMessage="Could not import \(url.lastPathComponent): \(error.localizedDescription)" }
    }

    private func selectAll(){guard let layer=selectedLayer ?? project.layers.reversed().first(where:{$0.imageData != nil}),let image=layer.imageData,let ns=NSImage(data:image),let rep=ns.representations.first else{return};pushUndo();activeSelection=Data(repeating:255,count:rep.pixelsWide*rep.pixelsHigh);selectionLayerID=layer.id}
    private func deselect(){guard let current=activeSelection,let id=selectionLayerID else{return};pushUndo();dismissedSelection=(current,id);activeSelection=nil;selectionLayerID=nil}
    private func reselect(){guard let saved=dismissedSelection else{return};pushUndo();activeSelection=saved.0;selectionLayerID=saved.1}
    private func invertSelection(){guard let mask=activeSelection else{return};pushUndo();activeSelection=CoverEditorEngine.inverted(mask)}
    private func saveSelection(named name:String){guard let data=activeSelection,let layerID=selectionLayerID,let layer=project.layers.first(where:{$0.id==layerID}),let image=layer.imageData,let rep=NSBitmapImageRep(data:image) else{return};pushUndo();_ = CoverEditorEngine.saveSelection(data,width:rep.pixelsWide,height:rep.pixelsHigh,name:name,into:&projects[projectIndex])}
    private func deleteSavedSelection(){guard let id=project.savedSelections?.first?.id else{return};updateProject{$0.savedSelections?.removeAll{$0.id==id}}}
    private func applySelectionFilter(_ operation:SelectionRadiusOperation){guard let mask=activeSelection,let layer=project.layers.first(where:{$0.id==selectionLayerID}),let image=layer.imageData,let rep=NSBitmapImageRep(data:image) else{return};let radius=Int(selectionRadius.rounded());guard radius>0 else{return};let result:Data;switch operation{case .feather:result=CoverEditorEngine.feather(mask,width:rep.pixelsWide,height:rep.pixelsHigh,radius:radius);case .expand:result=CoverEditorEngine.expandSelection(mask,width:rep.pixelsWide,height:rep.pixelsHigh,radius:radius);case .contract:result=CoverEditorEngine.contractSelection(mask,width:rep.pixelsWide,height:rep.pixelsHigh,radius:radius);case .border:result=CoverEditorEngine.borderSelection(mask,width:rep.pixelsWide,height:rep.pixelsHigh,radius:radius)};guard result != mask else{return};pushUndo();activeSelection=result}
    private func applySelectionRadius(_ operation:SelectionRadiusOperation){applySelectionFilter(operation)}
    private func smoothSelection(){guard let mask=activeSelection,let layer=project.layers.first(where:{$0.id==selectionLayerID}),let image=layer.imageData,let rep=NSBitmapImageRep(data:image) else{return};pushUndo();activeSelection=CoverEditorEngine.smoothSelection(mask,width:rep.pixelsWide,height:rep.pixelsHigh,radius:1)}
    private func beginSelectionTransform(){guard let activeSelection else{return};selectionTransformSnapshot=activeSelection}
    private func applySelectionTransform(dx:Double,dy:Double,scale:CGSize,rotation:Double){guard let snapshot=selectionTransformSnapshot,let layer=project.layers.first(where:{$0.id==selectionLayerID}),let image=layer.imageData,let rep=NSBitmapImageRep(data:image) else{return};pushUndo();activeSelection=CoverEditorEngine.transformSelection(snapshot,width:rep.pixelsWide,height:rep.pixelsHigh,translation:CGPoint(x:dx,y:dy),scale:scale,rotation:rotation);selectionTransformSnapshot=nil}
    private func cancelSelectionTransform(){activeSelection=selectionTransformSnapshot;selectionTransformSnapshot=nil}
    private func updateMarqueePreview(at point:CGPoint,canvasSize:CGSize,layerFrame:CoverRect,pixels:CGSize){guard let first=canvasDragPoints.first,canvasSize.width>0,canvasSize.height>0,pixels.width>0 else{return};let start=CGPoint(x:(first.x/canvasSize.width-layerFrame.x)/max(0.0001,layerFrame.width)*pixels.width,y:(first.y/canvasSize.height-layerFrame.y)/max(0.0001,layerFrame.height)*pixels.height),end=CGPoint(x:(point.x/canvasSize.width-layerFrame.x)/max(0.0001,layerFrame.width)*pixels.width,y:(point.y/canvasSize.height-layerFrame.y)/max(0.0001,layerFrame.height)*pixels.height);let dx=end.x-start.x,dy=end.y-start.y,mods=NSEvent.modifierFlags;var w=abs(dx),h=abs(dy);if mods.contains(.shift){w=max(w,h);h=w};let origin=mods.contains(.option) ? CGPoint(x:start.x-w,y:start.y-h):CGPoint(x:min(start.x,end.x),y:min(start.y,end.y));let rect=CGRect(x:origin.x,y:origin.y,width:w,height:h);selectionDragPreview=activeTool == .ellipse ? CoverEditorEngine.ellipseSelection(width:Int(pixels.width),height:Int(pixels.height),rect:rect,antialias:wandAntialias):CoverEditorEngine.rectangleSelection(width:Int(pixels.width),height:Int(pixels.height),rect:rect)}
    private func finishPolygonSelection(){guard let layer=selectedLayer,let image=layer.imageData,let rep=NSBitmapImageRep(data:image) else{constructionPoints=[];return};let next=CoverEditorEngine.lassoSelection(width:rep.pixelsWide,height:rep.pixelsHigh,points:constructionPoints,antialias:wandAntialias);applySelectionResult(next,layer:layer,width:rep.pixelsWide,height:rep.pixelsHigh);constructionPoints=[]}
    private func createPathFromPanel() {
        var layer = CoverLayer(
            kind:.path,
            name:CoverPathPanelModel.nextPathName(
                in:project
            ),
            frame:CoverRect(
                x:0,
                y:0,
                width:1,
                height:1
            )
        )

        layer.pathPoints = []
        layer.pathClosed = false
        layer.fillHex = backgroundColorHex
        layer.strokeHex = foregroundHex
        layer.strokeWidth = 1.5

        updateProject {
            $0.layers.append(layer)
        }

        selectedID = layer.id
        selectedIDs = [layer.id]
        selectedPathPointIndex = nil
        selectedPathAnchors.removeAll()
        selectedPathContourIndex = nil
        maskSelected = false
        activeTool = .pen
        workspace.paths = true
        workspace.rightDock = true
    }

    private func selectPathFromPanel(
        _ id:UUID
    ) {
        guard project.layers.contains(
            where:{
                $0.id == id &&
                $0.kind == .path
            }
        ) else {
            return
        }

        selectedID = id
        selectedIDs = [id]
        selectedPathPointIndex = nil
        selectedPathAnchors.removeAll()
        selectedPathContourIndex = nil
        maskSelected = false
        activeTool = .path
    }

    private func togglePathClosedFromPanel(
        _ id:UUID
    ) {
        guard let index =
            project.layers.firstIndex(
                where:{
                    $0.id == id &&
                    $0.kind == .path
                }
            )
        else {
            return
        }

        let layer =
            project.layers[
                index
            ]

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for: layer
                )

        guard !contours.isEmpty else {
            return
        }

        let requestedContour =
            selectedID == id
            ? (
                selectedPathContourIndex
                ?? 0
            )
            : 0

        let contourIndex =
            contours.indices.contains(
                requestedContour
            )
            ? requestedContour
            : 0

        let closures =
            CoverEditorEngine
                .vectorContourClosures(
                    for: layer,
                    contourCount:
                        contours.count
                )

        let next =
            !closures[
                contourIndex
            ]

        mutateLayer(
            at: index
        ) {
            pathLayer in

            if let updated =
                CoverEditorEngine
                    .settingVectorContourClosed(
                        in:
                            pathLayer,
                        contourIndex:
                            contourIndex,
                        closed:
                            next
                    )
            {
                pathLayer =
                    updated
            }
        }
    }

    private func deletePathFromPanel(
        _ id:UUID
    ) {
        guard project.layers.contains(
            where:{
                $0.id == id &&
                $0.kind == .path
            }
        ) else {
            return
        }

        updateProject {
            $0.layers.removeAll {
                $0.id == id &&
                $0.kind == .path
            }
        }

        if selectedID == id {
            selectedID = nil
            selectedIDs = []
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
            selectedPathContourIndex = nil
            maskSelected = false
        }
    }

    private func performPathBoolean(
        _ operation:CoverVectorBooleanOperation
    ){
        let ids=booleanSelectedPathIDs

        guard ids.count>=2 else {
            return
        }

        let primaryID =
            selectedID.flatMap {
                ids.contains($0)
                ? $0
                : nil
            }
            ?? project.layers
                .reversed()
                .first(
                    where:{
                        ids.contains($0.id)
                    }
                )?
                .id

        guard let primaryID else {
            return
        }

        guard let result =
            CoverEditorEngine.booleanPathLayer(
                project:project,
                ids:ids,
                primaryID:primaryID,
                operation:operation
            )
        else {
            errorMessage =
                "The selected closed paths do not produce a visible \(operation.title.lowercased()) result."
            return
        }

        updateProject {
            current in

            let originalIndex =
                current.layers.firstIndex(
                    where:{
                        $0.id==primaryID
                    }
                )
                ?? current.layers.count

            let insertionIndex =
                current.layers
                    .prefix(originalIndex)
                    .filter {
                        !ids.contains($0.id)
                    }
                    .count

            current.layers.removeAll {
                ids.contains($0.id)
            }

            current.layers.insert(
                result,
                at:min(
                    insertionIndex,
                    current.layers.count
                )
            )
        }

        selectedID=result.id
        selectedIDs=[result.id]
        selectedPathPointIndex = nil
        selectedPathAnchors.removeAll()
        selectedPathContourIndex = nil
        activeTool = .path
        workspace.paths=true
    }

    private func combineSelectedPathLayers() {
        let ids =
            compoundSelectedPathIDs

        guard ids.count >= 2 else {
            return
        }

        let primaryID =
            selectedID.flatMap {
                ids.contains($0)
                ? $0
                : nil
            }
            ?? project.layers
                .reversed()
                .first(
                    where: {
                        ids.contains(
                            $0.id
                        )
                    }
                )?
                .id

        guard let primaryID,
              let mutation =
                CoverEditorEngine
                    .combiningVectorPathLayers(
                        in:
                            project,
                        ids:
                            ids,
                        primaryID:
                            primaryID
                    )
        else {
            return
        }

        updateProject {
            $0 =
                mutation.project
        }

        selectedID =
            mutation.layer.id

        selectedIDs = [
            mutation.layer.id
        ]

        selectedPathAnchors.removeAll()

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        mutation.layer
                )

        selectedPathContourIndex =
            contours.isEmpty
            ? nil
            : 0

        selectedPathPointIndex =
            contours.first?.isEmpty == false
            ? 0
            : nil

        maskSelected = false
        activeTool = .path
        workspace.paths = true
        workspace.rightDock = true
    }

    private func separateSelectedCompoundPath() {
        guard let id =
            selectedID,
              let mutation =
                CoverEditorEngine
                    .separatingVectorPathLayer(
                        in:
                            project,
                        layerID:
                            id
                    ),
              let first =
                mutation.layers.first
        else {
            return
        }

        updateProject {
            $0 =
                mutation.project
        }

        selectedIDs =
            Set(
                mutation.layers.map(
                    \.id
                )
            )

        selectedID =
            first.id

        selectedPathAnchors.removeAll()

        selectedPathContourIndex =
            0

        selectedPathPointIndex =
            first.pathPoints?.isEmpty == false
            ? 0
            : nil

        maskSelected = false
        activeTool = .path
        workspace.paths = true
        workspace.rightDock = true
    }

    private func makeSelectionFromSelectedPath() {
        guard let source =
            selectedLayer,
              source.kind == .path,
              let target =
                pathSelectionTargetLayer,
              let imageData =
                target.imageData,
              let image =
                NSImage(
                    data:
                        imageData
                ),
              let representation =
                image.representations.first
        else {
            return
        }

        let width =
            representation.pixelsWide

        let height =
            representation.pixelsHigh

        guard width > 0,
              height > 0,
              let proposed =
                CoverEditorEngine
                    .selectionFromVectorPath(
                        layer:
                            source,
                        project:
                            project,
                        targetLayer:
                            target,
                        width:
                            width,
                        height:
                            height,
                        antialias:
                            wandAntialias
                    )
        else {
            return
        }

        let adjusted =
            selectionFeather > 0
            ? CoverEditorEngine
                .feather(
                    proposed,
                    width:
                        width,
                    height:
                        height,
                    radius:
                        Int(
                            selectionFeather
                        )
                )
            : proposed

        pushUndo()

        activeSelection =
            adjusted

        selectionLayerID =
            target.id

        selectionDragPreview =
            nil

        dismissedSelection =
            nil
    }

    private func convertSelectionToEditablePath() {
        guard let selection =
            activeSelection,
              let host =
                selectionToPathHostInfo,
              selection.count
                == host.width
                * host.height,
              let mutation =
                CoverEditorEngine
                    .insertingSelectionPathLayer(
                        in:
                            project,
                        hostLayerID:
                            host.layer.id,
                        selection:
                            selection,
                        width:
                            host.width,
                        height:
                            host.height,
                        name:
                            "Selection Path",
                        threshold:
                            128,
                        fillHex:
                            backgroundColorHex,
                        strokeHex:
                            foregroundHex,
                        strokeWidth:
                            1.5
                    )
        else {
            return
        }

        updateProject {
            $0 =
                mutation.project
        }

        selectedID =
            mutation.layer.id

        selectedIDs = [
            mutation.layer.id
        ]

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        mutation.layer
                )

        if let first =
            contours.first,
           !first.isEmpty
        {
            selectedPathContourIndex =
                0

            selectedPathPointIndex =
                0

            selectedPathAnchors = [
                CoverVectorAnchorIndex(
                    contourIndex:
                        0,
                    pointIndex:
                        0
                )
            ]
        } else {
            selectedPathContourIndex =
                nil

            selectedPathPointIndex =
                nil

            selectedPathAnchors.removeAll()
        }

        maskSelected = false
        activeTool = .path
        workspace.paths = true
        workspace.rightDock = true
    }




    private func addPaintLayer(){let layer=CoverEditorEngine.newPaintLayer(name:"Paint Layer",project:project,frame:CoverRect(x:0,y:0,width:1,height:1));if layer.imageData == nil {errorMessage="The canvas is too large for a paint layer.";return};updateProject{$0.layers.append(layer)};selectedID=layer.id}
    private func addAdjustment(
        _ kind:CoverAdjustmentKind
    ){
        var layer =
            CoverLayer(
                kind:.adjustment,
                name:kind.rawValue,
                frame:
                    CoverRect(
                        x:0,
                        y:0,
                        width:1,
                        height:1
                    )
            )

        layer.adjustment = kind

        if kind == .gradientMap {
            layer.fillHex = "#000000"
            layer.gradientEndHex = "#FFFFFF"
        }

        if kind == .monochrome {
            layer.fillHex = "#C7A46A"
        }

        updateProject {
            $0.layers.append(
                layer
            )
        }

        selectedID = layer.id
        selectedIDs = [layer.id]
        workspace.adjustments = true
        workspace.rightDock = true
    }
    private func addGradientLayer(){
        var layer=CoverLayer(
            kind:.gradient,
            name:"Gradient",
            frame:CoverRect(x:0,y:0,width:1,height:1)
        )
        layer.fillHex=foregroundHex
        layer.gradientEndHex=backgroundColorHex
        layer.gradientStops=[
            CoverGradientStop(
                colorHex:foregroundHex,
                location:0,
                opacity:1,
                midpoint:0.5
            ),
            CoverGradientStop(
                colorHex:backgroundColorHex,
                location:1,
                opacity:1,
                midpoint:0.5
            )
        ]
        layer.gradientAngle=0
        layer.gradientCenterX=0.5
        layer.gradientCenterY=0.5
        layer.gradientRadius=0.75
        layer.gradientReversed=false
        updateProject{$0.layers.append(layer)}
        selectedID=layer.id
    }
    private func fillSelection(){guard let mask=activeSelection,let id=selectionLayerID,let target=project.layers.first(where:{$0.id==id}),let data=target.imageData,let image=NSImage(data:data),let rep=image.representations.first,let filled=try? CoverEditorEngine.filledImage(width:rep.pixelsWide,height:rep.pixelsHigh,color:NSColor(hex:foregroundHex),selection:mask) else{return};var layer=CoverLayer(kind:.paint,name:"Selection Fill",frame:target.frame);layer.imageData=filled;updateProject{$0.layers.append(layer)};selectedID=layer.id;selectedIDs=[layer.id]}
    private func applySelectionAsMask(){guard let i=selectedIndex,let data=activeSelection,let bytes=selectedLayer?.imageData,let ns=NSImage(data:bytes),let rep=ns.representations.first,let png=CoverEditorEngine.encodedMask(data,width:rep.pixelsWide,height:rep.pixelsHigh) else{return};mutateLayer(at:i){$0.maskData=png;$0.maskEnabled=true;$0.maskLinked=true};maskSelected=true}
    private func saveSelection(){guard let data=activeSelection,let layer=selectedLayer?.imageData,let ns=NSImage(data:layer),let rep=ns.representations.first else{return};pushUndo();_ = CoverEditorEngine.saveSelection(data,width:rep.pixelsWide,height:rep.pixelsHigh,name:"Selection \((project.savedSelections?.count ?? 0)+1)",into:&projects[projectIndex])}
    private func copyMerged(){if let image=try? CoverArtwork.render(project),let tiff=image.tiffRepresentation{NSPasteboard.general.clearContents();NSPasteboard.general.setData(tiff,forType:.tiff)}}
    private func copySelectedLayer(){guard let layer=selectedLayer else{return};copiedLayer=layer;if let data=layer.imageData{NSPasteboard.general.clearContents();NSPasteboard.general.setData(data,forType:.png)}}
    private func cutSelectedLayer(){copySelectedLayer();if let selectedID{delete(selectedID)}}
    private func pasteClipboard(){if let layer=copiedLayer{var copy=layer;copy.id=UUID();copy.linkSetID=nil;copy.name += " Copy";copy.frame.x=min(0.9,copy.frame.x+0.03);updateProject{$0.layers.append(copy)};selectedID=copy.id;selectedIDs=[copy.id];return};let pb=NSPasteboard.general;let data=pb.data(forType:.png) ?? pb.data(forType:.tiff) ?? pb.data(forType:NSPasteboard.PasteboardType("public.jpeg"));if let data,let layer=try? CoverArtwork.imageLayer(data:data,filename:"Pasted Artwork",frame:CoverRect(x:0.15,y:0.15,width:0.7,height:0.7)){updateProject{$0.layers.append(layer)};selectedID=layer.id;selectedIDs=[layer.id]}}
    private func selectSubject(removeBackground:Bool){guard let layer=selectedLayer ?? project.layers.reversed().first(where:{$0.imageData != nil}),let data=layer.imageData else{errorMessage="Select an image layer first.";return};do{let result=try CoverEditorEngine.selectSubject(imageData:data);activeSelection=result.mask;selectionLayerID=layer.id;selectedID=layer.id;if removeBackground,let index=project.layers.firstIndex(where:{$0.id==layer.id}),let mask=CoverEditorEngine.encodedMask(result.mask,width:result.width,height:result.height){mutateLayer(at:index){$0.maskData=mask}}}catch{errorMessage=error.localizedDescription}}
    private func handleCanvasGesture(points:[CGPoint],canvasSize:CGSize){
        if activeTool == .eyedropper, let point = points.last,
           canvasSize.width > 0, canvasSize.height > 0 {
            do {
                foregroundHex = try CoverEditorEngine.sampledCanvasColor(project: project,
                    point: CGPoint(x: point.x/canvasSize.width, y: point.y/canvasSize.height)).hexRGB
            } catch { errorMessage = error.localizedDescription }
            return
        }
        if activeTool == .move {
            guard let first = points.first, let last = points.last,
                  canvasSize.width > 0, canvasSize.height > 0 else { return }
            // Pick where the drag began, not where it finished. With Auto Select
            // off, keep the current selection so hidden transform handles do not
            // disable moving a layer.
            if autoSelect {
                let x = first.x / canvasSize.width
                let y = first.y / canvasSize.height
                let hit = project.layers.reversed().first {
                    $0.visible && !$0.locked && $0.kind != .group && $0.kind != .adjustment
                    && $0.frame.x <= x && x <= $0.frame.x + $0.frame.width
                    && $0.frame.y <= y && y <= $0.frame.y + $0.frame.height
                }
                if let hit {
                    let modifiers = NSEvent.modifierFlags
                    if modifiers.contains(.command) {
                        if selectedIDs.contains(hit.id) { selectedIDs.remove(hit.id) }
                        else { selectedIDs.insert(hit.id) }
                        selectedID = selectedIDs.contains(hit.id) ? hit.id : selectedIDs.first
                    } else if modifiers.contains(.shift) {
                        selectedIDs.insert(hit.id)
                        selectedID = hit.id
                    } else {
                        selectedID = hit.id
                        selectedIDs = [hit.id]
                    }
                } else {
                    selectedID = nil
                    selectedIDs = []
                }
            }
            moveSelectedLayers(
                translation: CGSize(width: last.x - first.x, height: last.y - first.y),
                scale: canvasSize.width / project.canvasWidth
            )
            return
        }
        if [.type,.shape].contains(activeTool) || (activeTool == .gradient && !maskSelected){createLayerOnCanvas(points:points,canvasSize:canvasSize);return};if activeTool == .pen{handlePenGesture(points:points,canvasSize:canvasSize);return};if activeTool == .path{handlePathSelectionGesture(points:points,canvasSize:canvasSize);return};guard let layer=selectedLayer ?? project.layers.last(where:{$0.imageData != nil}),let data=layer.imageData,let image=NSImage(data:data),let rep=image.representations.first else{return};let pixelPoints=points.map{point in CGPoint(x:(point.x/canvasSize.width-layer.frame.x)/max(0.0001,layer.frame.width)*Double(rep.pixelsWide),y:(point.y/canvasSize.height-layer.frame.y)/max(0.0001,layer.frame.height)*Double(rep.pixelsHigh))};guard let first=pixelPoints.first else{return}
        switch activeTool {
        case .move:break
        case .rectangle,.ellipse: let end=pixelPoints.last ?? first;let mods=NSEvent.modifierFlags;let dx=end.x-first.x,dy=end.y-first.y;var w=abs(dx),h=abs(dy);if mods.contains(.shift){w=max(w,h);h=w};let origin=mods.contains(.option) ? CGPoint(x:first.x-w,y:first.y-h):CGPoint(x:min(first.x,end.x),y:min(first.y,end.y));let rect=CGRect(x:origin.x,y:origin.y,width:w,height:h);let next=activeTool == .ellipse ? CoverEditorEngine.ellipseSelection(width:rep.pixelsWide,height:rep.pixelsHigh,rect:rect,antialias:wandAntialias):CoverEditorEngine.rectangleSelection(width:rep.pixelsWide,height:rep.pixelsHigh,rect:rect);applySelectionResult(next,layer:layer,width:rep.pixelsWide,height:rep.pixelsHigh)
        case .lasso:
            if lassoMode==1 { if constructionPoints.isEmpty{constructionPoints=[first]}else{constructionPoints.append(first)};return }
            let path=lassoMode==2 ? CoverEditorEngine.magneticLassoPath(imageData:data,points:pixelPoints,radius:Int(magneticRadius),contrast:magneticContrast,frequency:Int(magneticFrequency)):pixelPoints
            let next=CoverEditorEngine.lassoSelection(width:rep.pixelsWide,height:rep.pixelsHigh,points:path,antialias:wandAntialias);applySelectionResult(next,layer:layer,width:rep.pixelsWide,height:rep.pixelsHigh)
        case .wand: if let result=try? CoverEditorEngine.colorSelection(imageData:data,sample:first,tolerance:selectionTolerance,contiguous:wandContiguous,antialias:wandAntialias){applySelectionResult(result.mask,layer:layer,width:rep.pixelsWide,height:rep.pixelsHigh)}
        case .eyedropper:if let color=try? CoverEditorEngine.sampledColor(imageData:data,at:first){foregroundHex=color.hexRGB}
        case .brush,.pencil,.eraser,.dodge,.burn,.blur,.sharpen:
            guard let i=project.layers.firstIndex(where:{$0.id==layer.id}),!layer.locked else{return}
            if activeTool == .pencil && !CoverEditorEngine.canPencilPaint(layer,quickMask:quickMask,maskSelected:maskSelected){return}
            let localRetouch = activeTool == .blur || activeTool == .sharpen
            if localRetouch && !quickMask && !maskSelected && layer.kind != .image && layer.kind != .paint { return }
            pushUndo()
            if quickMask {
                let base=activeSelection ?? Data(repeating:255,count:rep.pixelsWide*rep.pixelsHigh)
                activeSelection=activeTool == .pencil ? (try? CoverEditorEngine.pencilMask(base,width:rep.pixelsWide,height:rep.pixelsHigh,points:pixelPoints,diameter:brushDiameter,value:0,flow:brushFlow)) : (try? CoverEditorEngine.paintMask(base,width:rep.pixelsWide,height:rep.pixelsHigh,points:pixelPoints,diameter:brushDiameter,value:activeTool == .eraser ? 255:0,hardness:brushHardness,flow:brushFlow))
                selectionLayerID=layer.id
            }
            else if maskSelected,
                    let bytes=layer.maskData,
                    let mask=CoverEditorEngine.decodedMask(
                        bytes,
                        width:rep.pixelsWide,
                        height:rep.pixelsHigh
                    )
            {
                let changed:Data?
                let maskValue = activeTool == .eraser
                    ? UInt8(255)
                    : CoverEditorEngine.maskValue(for:NSColor(hex:foregroundHex))
                if activeTool == .pencil {
                    changed=try? CoverEditorEngine.pencilMask(
                        mask,
                        width:rep.pixelsWide,
                        height:rep.pixelsHigh,
                        points:pixelPoints,
                        diameter:brushDiameter,
                        value:maskValue,
                        opacity:brushOpacity,
                        flow:brushFlow,
                        selection:selectionLayerID == layer.id ? activeSelection : nil
                    )
                } else {
                    changed=try? CoverEditorEngine.paintMask(
                        mask,
                        width:rep.pixelsWide,
                        height:rep.pixelsHigh,
                        points:pixelPoints,
                        diameter:brushDiameter,
                        value:maskValue,
                        hardness:brushHardness,
                        opacity:brushOpacity,
                        flow:brushFlow,
                        selection:selectionLayerID == layer.id ? activeSelection : nil
                    )
                }
                if let changed,
                   let png=CoverEditorEngine.encodedMask(
                    changed,
                    width:rep.pixelsWide,
                    height:rep.pixelsHigh
                   )
                {
                    projects[projectIndex].layers[i].maskData=png
                }
            }
            else if activeTool == .blur || activeTool == .sharpen {
                projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.blurSharpen(imageData:data,at:pixelPoints,diameter:brushDiameter,strength:brushStrength,sharpen:activeTool == .sharpen,selection:activeSelection,hardness:brushHardness,flow:brushFlow)
            }
            else if activeTool == .dodge || activeTool == .burn {
                projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.dodgeBurn(imageData:data,at:pixelPoints,diameter:brushDiameter,strength:0.2,lighten:activeTool == .dodge)
            }
            else {
                if activeTool == .pencil {
                    projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.pencil(imageData:data,points:pixelPoints,color:NSColor(hex:foregroundHex),diameter:brushDiameter,opacity:brushOpacity,selection:activeSelection,flow:brushFlow)
                } else {
                    projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.paint(imageData:data,points:pixelPoints,color:NSColor(hex:foregroundHex),diameter:brushDiameter,opacity:brushOpacity,erase:activeTool == .eraser,selection:activeSelection,hardness:brushHardness,flow:brushFlow)
                }
            }
        case .gradient:
            guard maskSelected, !layer.locked,
                  let bytes = layer.maskData,
                  let mask = CoverEditorEngine.decodedMask(bytes, width: rep.pixelsWide, height: rep.pixelsHigh),
                  let end = pixelPoints.last,
                  let index = project.layers.firstIndex(where: { $0.id == layer.id })
            else { return }
            let selection = selectionLayerID == layer.id ? activeSelection : nil
            let changed = CoverEditorEngine.gradientMask(
                mask,
                width: rep.pixelsWide,
                height: rep.pixelsHigh,
                start: first,
                end: end,
                radial: gradientRadial,
                reversed: gradientMaskReversed,
                opacity: gradientMaskOpacity,
                selection: selection
            )
            guard changed != mask,
                  let encoded = CoverEditorEngine.encodedMask(changed, width: rep.pixelsWide, height: rep.pixelsHigh)
            else { return }
            pushUndo()
            projects[projectIndex].layers[index].maskData = encoded
        case .clone:if cloneSource == nil{cloneSource=first}else if let source=cloneSource,let i=project.layers.firstIndex(where:{$0.id==layer.id}){pushUndo();projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.clone(imageData:data,source:source,destinationPoints:pixelPoints,diameter:brushDiameter,opacity:brushOpacity,destinationOrigin:first,hardness:brushHardness,flow:brushFlow,selection:activeSelection)}
        case .heal:guard let i=project.layers.firstIndex(where:{$0.id==layer.id}) else{return};pushUndo();projects[projectIndex].layers[i].imageData=try? CoverEditorEngine.heal(imageData:data,center:first,diameter:brushDiameter)
        case .crop:let start=points.first ?? .zero,end=points.last ?? start;let rect=CGRect(x:min(start.x,end.x),y:min(start.y,end.y),width:abs(end.x-start.x),height:abs(end.y-start.y));cropPreview=CoverEditorEngine.cropSourceRect(layer:layer,canvasDrag:rect,canvasSize:canvasSize,imagePixels:CGSize(width:rep.pixelsWide,height:rep.pixelsHigh))
        case .zoom:if let point=points.last{let factor=NSEvent.modifierFlags.contains(.option) ? 0.8:1.25;let next=min(8,max(0.05,zoom*factor));let ratio=next/max(0.001,zoom);panOffset=CGSize(width:point.x-(point.x-panOffset.width)*ratio,height:point.y-(point.y-panOffset.height)*ratio);zoom=next}
        default:break
        }
    }
    private func createLayerOnCanvas(points:[CGPoint],canvasSize:CGSize) {
        guard let first=points.first,let last=points.last,canvasSize.width>0,canvasSize.height>0 else{return}
        let x1=max(0,min(1,first.x/canvasSize.width)), y1=max(0,min(1,first.y/canvasSize.height))
        let x2=max(0,min(1,last.x/canvasSize.width)), y2=max(0,min(1,last.y/canvasSize.height))
        let dragged=abs(x2-x1)>0.01 && abs(y2-y1)>0.01
        let frame:CoverRect
        if dragged {
            frame=CoverRect(x:min(x1,x2),y:min(y1,y2),width:abs(x2-x1),height:abs(y2-y1))
        } else if activeTool == .gradient {
            frame=CoverRect()
        } else {
            frame=CoverRect(x:x1,y:y1,width:min(activeTool == .type ? 0.45:0.25,1-x1),
                            height:min(activeTool == .type ? 0.12:0.18,1-y1))
        }
        guard frame.width>0.005,frame.height>0.005 else{return}
        var layer:CoverLayer
        switch activeTool {
        case .type:
            layer=CoverLayer(kind:.text,name:"Text",frame:frame)
            layer.text="Text";layer.fontSize=24;layer.colorHex=foregroundHex;workspace.character=true;workspace.paragraph=true;workspace.rightDock=true
        case .shape:
            layer=CoverLayer(kind:.shape,name:shapeToolKind.rawValue.capitalized,frame:frame)
            layer.shape=shapeToolKind;layer.fillHex=foregroundHex;layer.strokeHex=backgroundColorHex
            layer.strokeWidth=0
        case .gradient:
            layer=CoverLayer(kind:.gradient,name:"Gradient",frame:frame)
            layer.fillHex=foregroundHex
            layer.gradientEndHex=backgroundColorHex
            layer.gradientRadial=gradientRadial
            layer.gradientStops=[
                CoverGradientStop(
                    colorHex:foregroundHex,
                    location:0,
                    opacity:1,
                    midpoint:0.5
                ),
                CoverGradientStop(
                    colorHex:backgroundColorHex,
                    location:1,
                    opacity:1,
                    midpoint:0.5
                )
            ]
            layer.gradientAngle=0
            layer.gradientCenterX=0.5
            layer.gradientCenterY=0.5
            layer.gradientRadius=0.75
            layer.gradientReversed=false
        default:return
        }
        updateProject{$0.layers.append(layer)}
        selectedID=layer.id;selectedIDs=[layer.id]
        workspace.properties=true;workspace.layers=true;workspace.rightDock=true
    }
    private func normalizedCanvasPoint(
        _ point: CGPoint,
        canvasSize: CGSize
    ) -> CGPoint {
        guard canvasSize.width > 0, canvasSize.height > 0 else {
            return .zero
        }

        return CGPoint(
            x: max(0, min(1, point.x / canvasSize.width)),
            y: max(0, min(1, point.y / canvasSize.height))
        )
    }

    private func localPathPoint(
        _ point: CGPoint,
        layer: CoverLayer
    ) -> CGPoint {
        CGPoint(
            x: (point.x - layer.frame.x) / max(0.0001, layer.frame.width),
            y: (point.y - layer.frame.y) / max(0.0001, layer.frame.height)
        )
    }

    private func handlePenGesture(
        points: [CGPoint],
        canvasSize: CGSize
    ) {
        selectedPathAnchors.removeAll()
        guard let firstScreen = points.first else { return }

        let lastScreen = points.last ?? firstScreen
        let anchor = normalizedCanvasPoint(
            firstScreen,
            canvasSize: canvasSize
        )
        let dragged = normalizedCanvasPoint(
            lastScreen,
            canvasSize: canvasSize
        )

        let draggedEnough = hypot(
            Double(lastScreen.x - firstScreen.x),
            Double(lastScreen.y - firstScreen.y)
        ) > 4

        if let i = selectedIndex,
           project.layers[i].kind == .path,
           CoverEditorEngine
                .vectorContourClosures(
                    for:
                        project.layers[i],
                    contourCount:
                        CoverEditorEngine
                            .vectorContours(
                                for:
                                    project.layers[i]
                            )
                            .count
                )
                .first != true {

            let layer = project.layers[i]
            let existing = layer.pathPoints ?? []

            if existing.count >= 3, let first = existing.first {
                let firstX = (layer.frame.x + first.x * layer.frame.width) * canvasSize.width
                let firstY = (layer.frame.y + first.y * layer.frame.height) * canvasSize.height

                if hypot(
                    Double(firstScreen.x - firstX),
                    Double(firstScreen.y - firstY)
                ) <= 14 {
                    mutateLayer(at: i) {
                        pathLayer in

                        if let updated =
                            CoverEditorEngine
                                .settingVectorContourClosed(
                                    in:
                                        pathLayer,
                                    contourIndex:
                                        0,
                                    closed:
                                        true
                                )
                        {
                            pathLayer =
                                updated
                        }
                    }
                    selectedPathPointIndex = 0
                    selectedPathContourIndex = 0
                    return
                }
            }

            let localAnchor = localPathPoint(
                anchor,
                layer: layer
            )
            let localDrag = localPathPoint(
                dragged,
                layer: layer
            )

            mutateLayer(at: i) { pathLayer in
                pathLayer.pathPoints = CoverEditorEngine.appendedPathPoint(
                    pathLayer.pathPoints ?? [],
                    anchor: localAnchor,
                    draggedTo: draggedEnough ? localDrag : nil
                )
                if let updated =
                    CoverEditorEngine
                        .settingVectorContourClosed(
                            in:
                                pathLayer,
                            contourIndex:
                                0,
                            closed:
                                false
                        )
                {
                    pathLayer =
                        updated
                }
            }

            selectedPathPointIndex = (project.layers[i].pathPoints?.count ?? 1) - 1
            selectedPathContourIndex = 0
            return
        }

        var layer = CoverLayer(
            kind: .path,
            name: "Path",
            frame: CoverRect(
                x: 0,
                y: 0,
                width: 1,
                height: 1
            )
        )

        layer.pathPoints = CoverEditorEngine.appendedPathPoint(
            [],
            anchor: anchor,
            draggedTo: draggedEnough ? dragged : nil
        )
        layer.pathClosed = false
        layer.pathContourClosed = [false]
        layer.fillHex = backgroundColorHex
        layer.strokeHex = foregroundHex
        layer.strokeWidth = 1.5

        updateProject {
            $0.layers.append(layer)
        }

        selectedID = layer.id
        selectedIDs = [layer.id]
        selectedPathPointIndex = 0
        selectedPathContourIndex = 0
        workspace.layers = true
        workspace.paths = true
        workspace.properties = true
        workspace.rightDock = true
    }

    private func selectAdjacentPathContour(
        delta: Int
    ) {
        selectedPathAnchors.removeAll()
        guard let layer = selectedLayer,
              layer.kind == .path
        else {
            return
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for: layer
                )

        guard !contours.isEmpty else {
            selectedPathContourIndex = nil
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
            return
        }

        let current =
            min(
                max(
                    selectedPathContourIndex
                    ?? 0,
                    0
                ),
                contours.count - 1
            )

        let next =
            (
                current
                + delta
                + contours.count
            )
            % contours.count

        selectedPathContourIndex = next

        if contours[next].isEmpty {
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
        } else {
            selectedPathPointIndex =
                min(
                    selectedPathPointIndex
                    ?? 0,
                    contours[next].count - 1
                )
        }
    }

    private func handlePathSelectionGesture(
        points: [CGPoint],
        canvasSize: CGSize
    ) {
        guard let i = selectedIndex,
              project.layers[i].kind == .path,
              let firstScreen = points.first
        else {
            return
        }

        let layer = project.layers[i]

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for: layer
                )

        guard !contours.isEmpty else {
            return
        }

        var nearest:
            (
                contour: Int,
                point: Int,
                distance: Double
            )?

        for contourIndex in contours.indices {
            for pointIndex in contours[contourIndex].indices {
                let point =
                    contours[contourIndex][pointIndex]

                let x =
                    (
                        layer.frame.x
                        + point.x
                        * layer.frame.width
                    )
                    * canvasSize.width

                let y =
                    (
                        layer.frame.y
                        + point.y
                        * layer.frame.height
                    )
                    * canvasSize.height

                let distance = hypot(
                    Double(firstScreen.x - x),
                    Double(firstScreen.y - y)
                )

                if nearest == nil ||
                   distance < nearest!.distance
                {
                    nearest = (
                        contourIndex,
                        pointIndex,
                        distance
                    )
                }
            }
        }

        guard let nearest,
              nearest.distance <= 18
        else {
            let lastScreen =
                points.last
                ?? firstScreen

            let gestureDistance =
                hypot(
                    Double(
                        lastScreen.x
                        - firstScreen.x
                    ),
                    Double(
                        lastScreen.y
                        - firstScreen.y
                    )
                )

            let modifiers =
                NSEvent.modifierFlags

            let canInsertAnchor =
                gestureDistance <= 4
                && !modifiers.contains(
                    .shift
                )
                && !modifiers.contains(
                    .option
                )
                && !modifiers.contains(
                    .command
                )

            let canvasPoint =
                normalizedCanvasPoint(
                    firstScreen,
                    canvasSize:
                        canvasSize
                )

            let localPoint =
                localPathPoint(
                    canvasPoint,
                    layer: layer
                )

            let scaleX =
                max(
                    0.0001,
                    layer.frame.width
                    * Double(
                        canvasSize.width
                    )
                )

            let scaleY =
                max(
                    0.0001,
                    layer.frame.height
                    * Double(
                        canvasSize.height
                    )
                )

            if canInsertAnchor,
               let segment =
                    CoverEditorEngine
                        .nearestVectorSegment(
                            in: layer,
                            to: localPoint,
                            scaleX:
                                scaleX,
                            scaleY:
                                scaleY
                        ),
               segment.distance <= 10,
               let insertion =
                    CoverEditorEngine
                        .insertingVectorPoint(
                            in: layer,
                            contourIndex:
                                segment
                                    .contourIndex,
                            startPointIndex:
                                segment
                                    .startPointIndex,
                            t:
                                segment.t
                        )
            {
                mutateLayer(
                    at: i
                ) {
                    pathLayer in

                    pathLayer =
                        insertion.layer
                }

                selectedPathContourIndex =
                    insertion
                        .anchor
                        .contourIndex

                selectedPathPointIndex =
                    insertion
                        .anchor
                        .pointIndex

                selectedPathAnchors = [
                    insertion.anchor
                ]

                return
            }

            selectedPathContourIndex = nil
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
            return
        }

        let clickedAnchor =
            CoverVectorAnchorIndex(
                contourIndex:
                    nearest.contour,
                pointIndex:
                    nearest.point
            )

        let lastScreen =
            points.last
            ?? firstScreen

        let anchorDragDistance =
            hypot(
                Double(
                    lastScreen.x
                    - firstScreen.x
                ),
                Double(
                    lastScreen.y
                    - firstScreen.y
                )
            )

        let isAnchorDrag =
            anchorDragDistance
            > 0.5

        let modifiers =
            NSEvent.modifierFlags

        let additiveSelection =
            modifiers.contains(
                .shift
            )

        if selectedPathAnchors.isEmpty,
           let legacyPoint =
                selectedPathPointIndex
        {
            let legacyContour =
                selectedPathContourIndex
                ?? 0

            if contours.indices.contains(
                legacyContour
            ),
            contours[
                legacyContour
            ]
            .indices
            .contains(
                legacyPoint
            )
            {
                selectedPathAnchors.insert(
                    CoverVectorAnchorIndex(
                        contourIndex:
                            legacyContour,
                        pointIndex:
                            legacyPoint
                    )
                )
            }
        }

        if additiveSelection
           && !isAnchorDrag
        {
            if selectedPathAnchors.contains(
                clickedAnchor
            )
            {
                selectedPathAnchors.remove(
                    clickedAnchor
                )

                let remaining =
                    selectedPathAnchors
                        .sorted {
                            lhs,
                            rhs in

                            if lhs.contourIndex
                                == rhs.contourIndex
                            {
                                return lhs.pointIndex
                                    < rhs.pointIndex
                            }

                            return lhs.contourIndex
                                < rhs.contourIndex
                        }
                        .first

                if let remaining {
                    selectedPathContourIndex =
                        remaining.contourIndex
                    selectedPathPointIndex =
                        remaining.pointIndex
                } else {
                    selectedPathContourIndex =
                        nil
                    selectedPathPointIndex =
                        nil
                }

                return
            }

            selectedPathAnchors.insert(
                clickedAnchor
            )
        } else if additiveSelection {
            selectedPathAnchors.insert(
                clickedAnchor
            )
        } else if !isAnchorDrag
                  || !selectedPathAnchors.contains(
                        clickedAnchor
                     )
        {
            selectedPathAnchors = [
                clickedAnchor
            ]
        }

        if isAnchorDrag,
           selectedPathAnchors.count > 1,
           !modifiers.contains(
                .option
           ),
           abs(layer.frame.width) > 0.0000001,
           abs(layer.frame.height) > 0.0000001
        {
            let deltaX =
                Double(
                    lastScreen.x
                    - firstScreen.x
                )
                / max(
                    0.0000001,
                    layer.frame.width
                    * Double(
                        canvasSize.width
                    )
                )

            let deltaY =
                Double(
                    lastScreen.y
                    - firstScreen.y
                )
                / max(
                    0.0000001,
                    layer.frame.height
                    * Double(
                        canvasSize.height
                    )
                )

            mutateLayer(
                at: i
            ) {
                pathLayer in

                pathLayer =
                    CoverEditorEngine
                        .translatingVectorAnchors(
                            in:
                                pathLayer,
                            selections:
                                selectedPathAnchors,
                            deltaX:
                                deltaX,
                            deltaY:
                                deltaY
                        )
            }

            selectedPathContourIndex =
                clickedAnchor.contourIndex
            selectedPathPointIndex =
                clickedAnchor.pointIndex
            return
        }
        selectedPathContourIndex =
            nearest.contour

        selectedPathPointIndex =
            nearest.point

        let end =
            points.last
            ?? firstScreen

        let canvasPoint =
            normalizedCanvasPoint(
                end,
                canvasSize: canvasSize
            )

        let destination =
            localPathPoint(
                canvasPoint,
                layer: layer
            )

        mutateLayer(at: i) {
            pathLayer in

            var current =
                CoverEditorEngine
                    .vectorContours(
                        for: pathLayer
                    )

            guard current.indices.contains(
                nearest.contour
            ) else {
                return
            }

            if NSEvent
                .modifierFlags
                .contains(.option)
            {
                current[nearest.contour] =
                    CoverEditorEngine
                        .movedPathControl(
                            current[nearest.contour],
                            index: nearest.point,
                            to: destination,
                            incoming: false,
                            mirrorOpposite: true
                        )
            } else {
                current[nearest.contour] =
                    CoverEditorEngine
                        .movedPathPoint(
                            current[nearest.contour],
                            index: nearest.point,
                            to: destination
                        )
            }

            pathLayer =
                CoverEditorEngine
                    .replacingVectorContour(
                        in: pathLayer,
                        contourIndex:
                            nearest.contour,
                        points:
                            current[
                                nearest.contour
                            ]
                    )
        }
    }

    private var activePathContourIndex: Int {
        selectedPathContourIndex
            ?? 0
    }

    private var activePathContourIsClosed: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        project.layers[i]
                )

        let contourIndex =
            activePathContourIndex

        guard contours.indices.contains(
            contourIndex
        ) else {
            return false
        }

        return CoverEditorEngine
            .vectorContourClosures(
                for:
                    project.layers[i],
                contourCount:
                    contours.count
            )[
                contourIndex
            ]
    }

    private var canToggleActivePathContour: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        project.layers[i]
                )

        let contourIndex =
            activePathContourIndex

        guard contours.indices.contains(
            contourIndex
        ) else {
            return false
        }

        return contours[
            contourIndex
        ]
        .count >= 2
    }

    private func setActivePathContourClosed(
        _ closed: Bool
    ) {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return
        }

        let contourIndex =
            activePathContourIndex

        mutateLayer(
            at: i
        ) {
            pathLayer in

            if let updated =
                CoverEditorEngine
                    .settingVectorContourClosed(
                        in:
                            pathLayer,
                        contourIndex:
                            contourIndex,
                        closed:
                            closed
                    )
            {
                pathLayer =
                    updated
            }
        }
    }

    private var canMutateActivePathContour: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        project.layers[i]
                )

        let contourIndex =
            activePathContourIndex

        return contours.indices.contains(
            contourIndex
        )
        && !contours[
            contourIndex
        ]
        .isEmpty
    }

    private func applyVectorContourMutationResult(
        _ result: CoverVectorContourMutationResult,
        layerIndex: Int
    ) {
        mutateLayer(
            at:
                layerIndex
        ) {
            pathLayer in

            pathLayer =
                result.layer
        }

        selectedPathContourIndex =
            result.contourIndex

        selectedPathAnchors =
            result.selectedAnchors

        selectedPathPointIndex =
            result
                .activeAnchor?
                .pointIndex
    }

    private func duplicateActivePathContour() {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              let result =
                CoverEditorEngine
                    .duplicatingVectorContour(
                        in:
                            project.layers[i],
                        contourIndex:
                            activePathContourIndex
                    )
        else {
            return
        }

        applyVectorContourMutationResult(
            result,
            layerIndex:
                i
        )
    }

    private func reverseActivePathContour() {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              let result =
                CoverEditorEngine
                    .reversingVectorContour(
                        in:
                            project.layers[i],
                        contourIndex:
                            activePathContourIndex
                    )
        else {
            return
        }

        applyVectorContourMutationResult(
            result,
            layerIndex:
                i
        )
    }

    private func canOrderActivePathContour(
        _ move: CoverVectorContourOrderMove
    ) -> Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        project.layers[i]
                )

        guard contours.count >= 2 else {
            return false
        }

        let contourIndex =
            activePathContourIndex

        guard contours.indices.contains(
            contourIndex
        ) else {
            return false
        }

        switch move {
        case .forward,
             .front:
            return contourIndex
                < contours.count - 1

        case .backward,
             .back:
            return contourIndex > 0
        }
    }

    private func orderActivePathContour(
        _ move: CoverVectorContourOrderMove
    ) {
        guard let i = selectedIndex,
              project.layers.indices.contains(i)
        else {
            return
        }

        let previousPointIndex =
            selectedPathPointIndex

        guard let result =
            CoverEditorEngine
                .orderingVectorContour(
                    in:
                        project.layers[i],
                    contourIndex:
                        activePathContourIndex,
                    move:
                        move,
                    selectedAnchors:
                        selectedPathAnchors
                )
        else {
            return
        }

        mutateLayer(
            at: i
        ) {
            pathLayer in

            pathLayer =
                result.layer
        }

        selectedPathContourIndex =
            result.contourIndex

        selectedPathAnchors =
            result.selectedAnchors

        if let active =
            result.activeAnchor
        {
            selectedPathPointIndex =
                active.pointIndex
            return
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for:
                        result.layer
                )

        guard contours.indices.contains(
            result.contourIndex
        ) else {
            selectedPathPointIndex =
                nil
            return
        }

        let contour =
            contours[
                result.contourIndex
            ]

        if let previousPointIndex,
           contour.indices.contains(
            previousPointIndex
           )
        {
            selectedPathPointIndex =
                previousPointIndex
        } else {
            selectedPathPointIndex =
                contour.isEmpty
                ? nil
                : 0
        }
    }

    private var resolvedPathCommandAnchors: Set<CoverVectorAnchorIndex> {
        var anchors =
            selectedPathAnchors

        if anchors.isEmpty,
           let pointIndex =
                selectedPathPointIndex
        {
            anchors.insert(
                CoverVectorAnchorIndex(
                    contourIndex:
                        selectedPathContourIndex
                        ?? 0,
                    pointIndex:
                        pointIndex
                )
            )
        }

        return anchors
    }

    private var canSelectActivePathContourAnchors:
        Bool
    {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path
        else {
            return false
        }

        return !CoverEditorEngine
            .vectorContourAnchorSelection(
                in:
                    project.layers[
                        i
                    ],
                contourIndex:
                    activePathContourIndex
            )
            .isEmpty
    }

    private var canTransformSelectedPathGeometry:
        Bool
    {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path
        else {
            return false
        }

        return CoverEditorEngine
            .selectedVectorGeometryBounds(
                in:
                    project.layers[
                        i
                    ],
                selections:
                    resolvedPathCommandAnchors
            )
            != nil
    }

    private func selectActivePathContourAnchors() {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path
        else {
            return
        }

        let contourIndex =
            activePathContourIndex

        let anchors =
            CoverEditorEngine
                .vectorContourAnchorSelection(
                    in:
                        project.layers[
                            i
                        ],
                    contourIndex:
                        contourIndex
                )

        guard !anchors.isEmpty else {
            return
        }

        selectedPathAnchors =
            anchors

        selectedPathContourIndex =
            contourIndex

        selectedPathPointIndex =
            anchors
                .map(
                    \.pointIndex
                )
                .min()
    }

    private func beginSelectedPathGeometryTransform() {
        guard canTransformSelectedPathGeometry else {
            return
        }

        pathGeometryScaleX =
            1

        pathGeometryScaleY =
            1

        pathGeometryRotation =
            0

        showPathGeometryTransform =
            true
    }

    private func applySelectedPathGeometryTransform(
        scaleX: Double,
        scaleY: Double,
        rotation: Double
    ) {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path,
              scaleX.isFinite,
              scaleY.isFinite,
              rotation.isFinite
        else {
            return
        }

        let anchors =
            resolvedPathCommandAnchors

        guard let bounds =
            CoverEditorEngine
                .selectedVectorGeometryBounds(
                    in:
                        project.layers[
                            i
                        ],
                    selections:
                        anchors
                )
        else {
            return
        }

        var transformed =
            project.layers[
                i
            ]

        if abs(
            scaleX
            - 1
        ) > 0.0000001
            || abs(
                scaleY
                - 1
            ) > 0.0000001
        {
            guard let scaled =
                CoverEditorEngine
                    .scalingVectorAnchors(
                        in:
                            transformed,
                        selections:
                            anchors,
                        scaleX:
                            scaleX,
                        scaleY:
                            scaleY,
                        pivotX:
                            bounds.centerX,
                        pivotY:
                            bounds.centerY
                    )
            else {
                return
            }

            transformed =
                scaled
        }

        if abs(
            rotation
        ) > 0.0000001
        {
            guard let rotated =
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            transformed,
                        selections:
                            anchors,
                        degrees:
                            rotation,
                        pivotX:
                            bounds.centerX,
                        pivotY:
                            bounds.centerY
                    )
            else {
                return
            }

            transformed =
                rotated
        }

        guard transformed
                != project.layers[
                    i
                ]
        else {
            return
        }

        mutateLayer(
            at:
                i
        ) {
            pathLayer in

            pathLayer =
                transformed
        }
    }

    private func rotateSelectedPathGeometry(
        _ degrees: Double
    ) {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path,
              degrees.isFinite
        else {
            return
        }

        let anchors =
            resolvedPathCommandAnchors

        guard let bounds =
                CoverEditorEngine
                    .selectedVectorGeometryBounds(
                        in:
                            project.layers[
                                i
                            ],
                        selections:
                            anchors
                    ),
              let transformed =
                CoverEditorEngine
                    .rotatingVectorAnchors(
                        in:
                            project.layers[
                                i
                            ],
                        selections:
                            anchors,
                        degrees:
                            degrees,
                        pivotX:
                            bounds.centerX,
                        pivotY:
                            bounds.centerY
                    )
        else {
            return
        }

        mutateLayer(
            at:
                i
        ) {
            pathLayer in

            pathLayer =
                transformed
        }
    }

    private func flipSelectedPathGeometry(
        horizontal: Bool
    ) {
        guard let i =
                selectedIndex,
              project.layers.indices.contains(
                i
              ),
              project.layers[
                i
              ]
              .kind == .path
        else {
            return
        }

        let anchors =
            resolvedPathCommandAnchors

        guard let bounds =
                CoverEditorEngine
                    .selectedVectorGeometryBounds(
                        in:
                            project.layers[
                                i
                            ],
                        selections:
                            anchors
                    ),
              let transformed =
                CoverEditorEngine
                    .flippingVectorAnchors(
                        in:
                            project.layers[
                                i
                            ],
                        selections:
                            anchors,
                        horizontal:
                            horizontal,
                        pivotX:
                            bounds.centerX,
                        pivotY:
                            bounds.centerY
                    )
        else {
            return
        }

        mutateLayer(
            at:
                i
        ) {
            pathLayer in

            pathLayer =
                transformed
        }
    }


    private var canSplitSelectedPath: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let anchors =
            resolvedPathCommandAnchors

        guard anchors.count == 1,
              let anchor =
                anchors.first
        else {
            return false
        }

        return CoverEditorEngine
            .splittingVectorPath(
                in:
                    project.layers[i],
                at:
                    anchor
            )
            != nil
    }

    private var canCutSelectedPath: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return false
        }

        let anchors =
            resolvedPathCommandAnchors
                .sorted {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }

        guard anchors.count == 2 else {
            return false
        }

        return CoverEditorEngine
            .cuttingVectorPath(
                in:
                    project.layers[i],
                first:
                    anchors[0],
                second:
                    anchors[1]
            )
            != nil
    }

    private func applyVectorSplitResult(
        _ result: CoverVectorSplitResult,
        layerIndex: Int
    ) {
        mutateLayer(
            at:
                layerIndex
        ) {
            pathLayer in

            pathLayer =
                result.layer
        }

        selectedPathAnchors =
            result.selectedAnchors

        selectedPathContourIndex =
            result
                .activeAnchor
                .contourIndex

        selectedPathPointIndex =
            result
                .activeAnchor
                .pointIndex
    }

    private func splitSelectedPath() {
        guard let i = selectedIndex,
              project.layers.indices.contains(i)
        else {
            return
        }

        let anchors =
            resolvedPathCommandAnchors

        guard anchors.count == 1,
              let anchor =
                anchors.first,
              let result =
                CoverEditorEngine
                    .splittingVectorPath(
                        in:
                            project.layers[i],
                        at:
                            anchor
                    )
        else {
            return
        }

        applyVectorSplitResult(
            result,
            layerIndex:
                i
        )
    }

    private func cutSelectedPath() {
        guard let i = selectedIndex,
              project.layers.indices.contains(i)
        else {
            return
        }

        let anchors =
            resolvedPathCommandAnchors
                .sorted {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }

        guard anchors.count == 2,
              let result =
                CoverEditorEngine
                    .cuttingVectorPath(
                        in:
                            project.layers[i],
                        first:
                            anchors[0],
                        second:
                            anchors[1]
                    )
        else {
            return
        }

        applyVectorSplitResult(
            result,
            layerIndex:
                i
        )
    }

    private var canJoinSelectedPathEndpoints: Bool {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path,
              selectedPathAnchors.count == 2
        else {
            return false
        }

        let anchors =
            selectedPathAnchors
                .sorted {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }

        guard anchors.count == 2 else {
            return false
        }

        return CoverEditorEngine
            .joiningVectorEndpoints(
                in:
                    project.layers[i],
                first:
                    anchors[0],
                second:
                    anchors[1]
            )
            != nil
    }

    private func joinSelectedPathEndpoints() {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path,
              selectedPathAnchors.count == 2
        else {
            return
        }

        let anchors =
            selectedPathAnchors
                .sorted {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }

        guard anchors.count == 2,
              let result =
                CoverEditorEngine
                    .joiningVectorEndpoints(
                        in:
                            project.layers[i],
                        first:
                            anchors[0],
                        second:
                            anchors[1]
                    )
        else {
            return
        }

        mutateLayer(
            at: i
        ) {
            pathLayer in

            pathLayer =
                result.layer
        }

        selectedPathAnchors =
            result.selectedAnchors

        selectedPathContourIndex =
            result
                .activeAnchor
                .contourIndex

        selectedPathPointIndex =
            result
                .activeAnchor
                .pointIndex
    }

    private func setSelectedPathAnchorType(
        _ type: CoverPathAnchorType
    ) {
        guard let i = selectedIndex,
              project.layers.indices.contains(i),
              project.layers[i].kind == .path
        else {
            return
        }

        var selections =
            selectedPathAnchors

        if selections.isEmpty,
           let pointIndex =
                selectedPathPointIndex
        {
            let contourIndex =
                selectedPathContourIndex
                ?? 0

            selections.insert(
                CoverVectorAnchorIndex(
                    contourIndex:
                        contourIndex,
                    pointIndex:
                        pointIndex
                )
            )
        }

        guard !selections.isEmpty else {
            return
        }

        mutateLayer(
            at: i
        ) {
            pathLayer in

            pathLayer =
                CoverEditorEngine
                    .settingVectorAnchorType(
                        in:
                            pathLayer,
                        selections:
                            selections,
                        type:
                            type
                    )
        }

        selectedPathAnchors =
            selections

        if let primary =
            selections.sorted(
                by: {
                    lhs,
                    rhs in

                    if lhs.contourIndex
                        == rhs.contourIndex
                    {
                        return lhs.pointIndex
                            < rhs.pointIndex
                    }

                    return lhs.contourIndex
                        < rhs.contourIndex
                }
            )
            .first
        {
            selectedPathContourIndex =
                primary.contourIndex

            selectedPathPointIndex =
                primary.pointIndex
        }
    }

    private func deleteSelectedPathPoint() {
        selectedPathAnchors.removeAll()
        guard let i = selectedIndex,
              project.layers[i].kind == .path,
              let pointIndex =
                selectedPathPointIndex
        else {
            return
        }

        let contourIndex =
            selectedPathContourIndex
            ?? 0

        mutateLayer(at: i) {
            layer in

            layer =
                CoverEditorEngine
                    .deletingVectorPoint(
                        in: layer,
                        contourIndex:
                            contourIndex,
                        pointIndex:
                            pointIndex
                    )
        }

        let contours =
            CoverEditorEngine
                .vectorContours(
                    for: project.layers[i]
                )

        guard !contours.isEmpty else {
            selectedPathContourIndex = nil
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
            return
        }

        let nextContour =
            min(
                contourIndex,
                contours.count - 1
            )

        selectedPathContourIndex =
            nextContour

        if contours[nextContour].isEmpty {
            selectedPathPointIndex = nil
            selectedPathAnchors.removeAll()
        } else {
            selectedPathPointIndex =
                min(
                    pointIndex,
                    contours[nextContour].count - 1
                )
        }
    }

    private func moveSelectedLayers(translation:CGSize,scale:Double){guard abs(translation.width)>0.5 || abs(translation.height)>0.5 else{return};let ids=transformableSelectedIDs;guard !ids.isEmpty else{return};var dx=translation.width/max(1,project.canvasWidth*scale),dy=translation.height/max(1,project.canvasHeight*scale);if maskSelected,ids.count==1,let primary=selectedLayer,primary.maskData != nil,primary.maskLinked == false{if transformSnapshot == nil{pushUndo()};if let i=selectedIndex{projects[projectIndex].layers[i].maskOffsetX=(primary.maskOffsetX ?? 0)+dx/max(0.001,primary.frame.width);projects[projectIndex].layers[i].maskOffsetY=(primary.maskOffsetY ?? 0)+dy/max(0.001,primary.frame.height)};return};if !NSEvent.modifierFlags.contains(.command),let bounds=transformableSelectedBounds{let proposed=CoverRect(x:bounds.minX+dx,y:bounds.minY+dy,width:bounds.width,height:bounds.height);let movingRotation=ids.count == 1 ? (project.layers.first{ids.contains($0.id)}?.rotation ?? 0) : 0;let snap=CoverEditorEngine.snap(proposed,layerID:nil,project:project,displayedCanvas:CGSize(width:project.canvasWidth*scale,height:project.canvasHeight*scale),otherLayers:project.layers.filter{!ids.contains($0.id)},rotationDegrees:movingRotation);dx += snap.frame.x-proposed.x;dy += snap.frame.y-proposed.y;alignmentIndicators=snap.indicators;if !alignmentIndicators.isEmpty{DispatchQueue.main.asyncAfter(deadline:.now()+0.7){alignmentIndicators=[]}}};if transformSnapshot == nil{pushUndo()};CoverEditorEngine.moveLayers(&projects[projectIndex].layers,ids:ids,dx:dx,dy:dy)}
    private func resizeSelectedLayers(bounds:CGRect,translation:CGSize,scale:Double,handle:Int=7,center:Bool=false){guard bounds.width>0,bounds.height>0 else{return};let dx=translation.width/max(1,project.canvasWidth*scale),dy=translation.height/max(1,project.canvasHeight*scale);var sx=1.0,sy=1.0
        if [0,3,5].contains(handle){sx=(bounds.width-dx)/bounds.width};if [2,4,7].contains(handle){sx=(bounds.width+dx)/bounds.width}
        if [0,1,2].contains(handle){sy=(bounds.height-dy)/bounds.height};if [5,6,7].contains(handle){sy=(bounds.height+dy)/bounds.height}
        let linked=NSEvent.modifierFlags.contains(.shift) ? !proportionalScale:proportionalScale;if linked {let f=abs(sx-1)>abs(sy-1) ? sx:sy;sx=f;sy=f};sx=max(0.02,sx);sy=max(0.02,sy)
        let anchorX=center ? bounds.midX : ([0,3,5].contains(handle) ? bounds.maxX:bounds.minX),anchorY=center ? bounds.midY : ([0,1,2].contains(handle) ? bounds.maxY:bounds.minY),ids=transformableSelectedIDs
        if transformSnapshot == nil{pushUndo()};CoverEditorEngine.scaleLayers(&projects[projectIndex].layers,ids:ids,around:CGPoint(x:anchorX,y:anchorY),scaleX:sx,scaleY:sy)
        let projected=CoverRect(x:anchorX+(bounds.minX-anchorX)*sx,y:anchorY+(bounds.minY-anchorY)*sy,width:bounds.width*sx,height:bounds.height*sy)
        if !NSEvent.modifierFlags.contains(.command){let others=project.layers.filter{!ids.contains($0.id)};let snap=CoverEditorEngine.snap(projected,layerID:nil,project:project,displayedCanvas:CGSize(width:project.canvasWidth*scale,height:project.canvasHeight*scale),otherLayers:others);let dx=snap.frame.x-projected.x,dy=snap.frame.y-projected.y;if dx != 0 || dy != 0{CoverEditorEngine.moveLayers(&projects[projectIndex].layers,ids:ids,dx:dx,dy:dy)};alignmentIndicators=snap.indicators;DispatchQueue.main.asyncAfter(deadline:.now()+0.6){alignmentIndicators=[]}}
    }
    private func zoomAt(_ point:CGPoint,factor:Double,canvas:CGSize){var viewport=CoverViewport(zoom:zoom,pan:CGPoint(x:panOffset.width,y:panOffset.height),rotation:viewRotation);viewport.zoomAt(point,center:CGPoint(x:canvas.width/2,y:canvas.height/2),factor:factor);zoom=viewport.zoom;panOffset=CGSize(width:viewport.pan.x,height:viewport.pan.y)}
    private func screenDelta(_ local:CGSize)->CGSize{let r=viewRotation * .pi/180;return CGSize(width:local.width*cos(r)-local.height*sin(r),height:local.width*sin(r)+local.height*cos(r))}
    private func fitCover(){zoom=1;panOffset = .zero}
    private func fitSelected(){guard let b=selectedBounds,b.width>0,b.height>0 else{return};zoom=min(0.8/max(b.width,b.height),8);let scale=fitScaleEstimate*zoom,originX=rulerOriginX(viewportWidth:canvasViewportSize.width),originY=rulerOriginY(viewportHeight:canvasViewportSize.height);panOffset=CGSize(width:canvasViewportSize.width/2-originX-b.midX*project.canvasWidth*scale,height:canvasViewportSize.height/2-originY-b.midY*project.canvasHeight*scale)}
    private func warpAmountBinding(_ index:Int)->Binding<Double>{Binding(get:{project.layers[index].warpAmount ?? 0},set:{value in mutatePreviewLayer(at:index){$0.warpPreset=warpPreset;$0.warpAmount=value}})}
    private func warpToggleBinding(_ index:Int)->Binding<Bool>{Binding(get:{warpEditing},set:{enabled in warpEditing=enabled;mutatePreviewLayer(at:index){layer in if enabled{layer.warpPreset=warpPreset;layer.warpAmount=layer.warpAmount ?? 0.25}else{layer.warpPreset=nil;layer.warpAmount=nil}}})}
    private func warpPresetBinding(_ index:Int)->Binding<CoverWarpPreset>{Binding(get:{warpPreset},set:{value in warpPreset=value;mutatePreviewLayer(at:index){$0.warpPreset=value;$0.warpAmount=$0.warpAmount ?? 0.25}})}
    private func nudge(_ dx:Double,_ dy:Double){let ids=transformableSelectedIDs;guard !ids.isEmpty else{return};if !nudgeUndoOpen{pushUndo();nudgeUndoOpen=true};CoverEditorEngine.nudgeLayers(&projects[projectIndex].layers,ids:ids,dx:dx/project.canvasWidth,dy:dy/project.canvasHeight);nudgeGeneration += 1;let generation=nudgeGeneration;DispatchQueue.main.asyncAfter(deadline:.now()+0.45){if nudgeGeneration==generation{nudgeUndoOpen=false}}}
    private func rotateSelection(_ degrees:Double,snapping:Bool=false){let ids=transformableSelectedIDs;guard !ids.isEmpty,let bounds=transformableSelectedBounds else{return};let angle=snapping ? (degrees/15).rounded()*15:degrees,anchor=pivotPoint(in:bounds);if transformSnapshot == nil{updateProject{CoverEditorEngine.rotateLayers(&$0.layers,ids:ids,around:anchor,degrees:angle,canvasSize:CGSize(width:project.canvasWidth,height:project.canvasHeight))}}else{CoverEditorEngine.rotateLayers(&projects[projectIndex].layers,ids:ids,around:anchor,degrees:angle,canvasSize:CGSize(width:project.canvasWidth,height:project.canvasHeight))}}
    private func pivotPoint(in bounds:CGRect)->CGPoint{let x:CGFloat,y:CGFloat;switch transformPivot{case "Top Left":x=0;y=0;case "Top Center":x=0.5;y=0;case "Top Right":x=1;y=0;case "Center Left":x=0;y=0.5;case "Center Right":x=1;y=0.5;case "Bottom Left":x=0;y=1;case "Bottom Center":x=0.5;y=1;case "Bottom Right":x=1;y=1;default:x=0.5;y=0.5};return CGPoint(x:bounds.minX+bounds.width*x,y:bounds.minY+bounds.height*y)}
    private func flipSelection(horizontal:Bool){
        let ids = transformableSelectedIDs

        guard !ids.isEmpty,
              let bounds = transformableSelectedBounds
        else {
            return
        }

        let center =
            horizontal
            ? bounds.midX
            : bounds.midY

        let action:
            (inout [CoverLayer])->Void =
            {
                layers in

                CoverEditorEngine.flipLayers(
                    &layers,
                    ids:ids,
                    around:center,
                    horizontal:horizontal
                )
            }

        if transformSnapshot == nil {
            updateProject{
                action(&$0.layers)
            }
        } else {
            action(
                &projects[projectIndex].layers
            )
        }
    }
    private func applySelectionResult(_ proposed:Data,layer:CoverLayer,width:Int,height:Int){let adjusted=selectionFeather>0 ? CoverEditorEngine.feather(proposed,width:width,height:height,radius:Int(selectionFeather)):proposed;pushUndo();activeSelection=CoverEditorEngine.applyingSelection(adjusted,toLayer:layer.id,existing:activeSelection,existingLayerID:selectionLayerID,mode:selectionMode);selectionLayerID=layer.id}
    private func commitCrop(){guard let crop=cropPreview,let index=selectedIndex else{return};pushUndo();projects[projectIndex].layers[index].sourceCrop=CoverEditorEngine.composeCrop(existing:projects[projectIndex].layers[index].sourceCrop,selection:crop);projects[projectIndex].layers[index].rotation += cropStraighten;cropPreview=nil;cropStraighten=0}
    private func cancelCrop(){cropPreview=nil;cropStraighten=0;cropInteractionStart=nil}
    private func resizeCrop(_ start:CoverRect,dx:Double,dy:Double,handle:Int)->CoverRect{
        var left=start.x,right=start.x+start.width,top=start.y,bottom=start.y+start.height
        if [0,3,5].contains(handle){left=min(right-0.005,max(0,left+dx))};if [2,4,7].contains(handle){right=max(left+0.005,min(1,right+dx))}
        if [0,1,2].contains(handle){top=min(bottom-0.005,max(0,top+dy))};if [5,6,7].contains(handle){bottom=max(top+0.005,min(1,bottom+dy))}
        if cropAspect != "Free" {let sourceAspect=selectedLayer.flatMap{$0.imageData}.flatMap{NSImage(data:$0)}?.representations.first.map{Double($0.pixelsWide)/Double(max(1,$0.pixelsHigh))} ?? 1;let ratio=cropAspect == "Original" ? 1:(cropWidth/max(0.001,cropHeight))/sourceAspect;let width=right-left,height=bottom-top;if width/max(0.001,height)>ratio {let h=width/ratio;if [0,1,2].contains(handle){top=max(0,bottom-h)}else{bottom=min(1,top+h)}}else{let w=height*ratio;if [0,3,5].contains(handle){left=max(0,right-w)}else{right=min(1,left+w)}}}
        return CoverRect(x:left,y:top,width:right-left,height:bottom-top)
    }
    private func invertMask(at i:Int){
        _ = applyCoverOperation("mask-invert", arguments:["layerID":project.layers[i].id.uuidString])
    }
    private func applyMask(at i:Int){
        if applyCoverOperation("mask-apply", arguments:["layerID":project.layers[i].id.uuidString]) != nil { maskSelected=false }
    }
    private func toggleClip(at i:Int){let current=project.layers[i];if current.clippedToLayerID != nil{mutateLayer(at:i){$0.clippedToLayerID=nil};return};guard i>0 else{return};let previous=project.layers[..<i].reversed().first{$0.kind != .group && $0.kind != .adjustment && $0.groupID==current.groupID};guard let previous else{return};mutateLayer(at:i){$0.clippedToLayerID=previous.id}}
    private var canAlignSelection: Bool {
        !explicitTransformableSelectedIDs.isEmpty && (alignmentReference != "Selection Bounds" || explicitTransformableSelectedIDs.count >= 2)
        && !project.layers.contains { explicitTransformableSelectedIDs.contains($0.id) && $0.kind == .group }
    }
    private func alignSelection(_ edge: CoverAlignEdge) {
        guard canAlignSelection else { return }
        let edges: [CoverAlignEdge:String] = [.left:"left",.centerX:"centerX",.right:"right",.top:"top",.centerY:"centerY",.bottom:"bottom"]
        let reference = ["Canvas":"canvas","Front Cover":"front","Back Cover":"back","Spine":"spine"][alignmentReference] ?? "selection"
        _ = applyCoverOperation("align",arguments:["layerIDs":explicitTransformableSelectedIDs.map(\.uuidString).joined(separator:","),"edge":edges[edge]!,"reference":reference])
    }
    private var canAutoFitPanel: Bool {
        guard project.type == .printFullWrap, let layer = selectedLayer else { return false }
        return explicitTransformableSelectedIDs.count == 1 && (layer.imageData != nil || layer.kind == .shape) && !layer.locked && layer.positionLocked != true && !layer.isReferenceLayer
    }
    private func fitArtworkToPanel(_ panel: String) {
        guard canAutoFitPanel, let id = selectedID else { return }
        _ = applyCoverOperation("fit-panel",arguments:["layerID":id.uuidString,"panel":panel])
    }
    private var autoFitPanelMenu: some View {
        Menu("Auto Fit Artwork") {
            Button("Front Cover + Bleed / Wrap") { fitArtworkToPanel("front") }
            Button("Spine Inside Borders") { fitArtworkToPanel("spine") }
            Button("Back Cover + Bleed / Wrap") { fitArtworkToPanel("back") }
        }.disabled(!canAutoFitPanel)
    }
    private func distributeSelection(_ axis:CoverDistributionAxis){let ids=explicitTransformableSelectedIDs;guard ids.count>=3 else{return};updateProject{CoverEditorEngine.distribute(&$0.layers,ids:ids,axis:axis,canvasSize:CGSize(width:$0.canvasWidth,height:$0.canvasHeight))}}
    private func beginTransform(){guard !transformableSelectedIDs.isEmpty else{return};transformSnapshot=project;warpEditing=selectedLayer?.warpPreset != nil;if let preset=selectedLayer?.warpPreset{warpPreset=preset}}
    private func commitTransform(){guard let snapshot=transformSnapshot else{return};undoStack.append(CoverProjectHistory.snapshot(snapshot));redoStack=[];if undoStack.count>50{undoStack.removeFirst()};transformSnapshot=nil;perspectiveEditing=false}
    private func cancelTransform(){guard let snapshot=transformSnapshot else{return};projects[projectIndex]=snapshot;transformSnapshot=nil;perspectiveEditing=false;perspectiveDragStart=nil}
    private func beginPerspective(){guard let i=selectedIndex,selectedLayer?.imageData != nil else{return};beginTransform();perspectiveEditing=true;if project.layers[i].perspectiveCorners == nil{mutatePreviewLayer(at:i){$0.perspectiveCorners=[CoverPathPoint(x:0,y:0),CoverPathPoint(x:1,y:0),CoverPathPoint(x:1,y:1),CoverPathPoint(x:0,y:1)]}}}
    private func mutatePreviewLayer(at i:Int,_ body:(inout CoverLayer)->Void){guard projects[projectIndex].layers.indices.contains(i),!projects[projectIndex].layers[i].locked,projects[projectIndex].layers[i].positionLocked != true else{return};body(&projects[projectIndex].layers[i])}
    private func rotationBinding(_ index:Int)->Binding<Double>{Binding(get:{project.layers[index].rotation},set:{value in let delta=value-project.layers[index].rotation,ids=transformableSelectedIDs,bounds=transformableSelectedBounds ?? .zero;if transformSnapshot == nil{updateProject{CoverEditorEngine.rotateLayers(&$0.layers,ids:ids,around:pivotPoint(in:bounds),degrees:delta,canvasSize:CGSize(width:project.canvasWidth,height:project.canvasHeight))}}else{CoverEditorEngine.rotateLayers(&projects[projectIndex].layers,ids:ids,around:pivotPoint(in:bounds),degrees:delta,canvasSize:CGSize(width:project.canvasWidth,height:project.canvasHeight))}})}
    private var displayUnitsPerInch:Double{switch project.unit ?? "in"{case "mm":25.4;case "px":project.dpi;default:1}}
    private func transformReferenceBinding(_ i:Int,horizontal:Bool)->Binding<Double>{let p:Double;switch transformPivot{case "Top Left","Center Left","Bottom Left":p=0;case "Top Center","Center","Bottom Center":p=0.5;default:p=1};return Binding(get:{let l=project.layers[i],position=horizontal ? l.frame.x+l.frame.width*p:l.frame.y+l.frame.height*(transformPivot.hasPrefix("Top") ? 0:transformPivot.hasPrefix("Bottom") ? 1:p),dimension=horizontal ? project.canvasWidth:project.canvasHeight;return position*dimension*displayUnitsPerInch},set:{value in mutatePreviewLayer(at:i){l in if horizontal{l.frame.x=value/(displayUnitsPerInch*project.canvasWidth)-l.frame.width*p}else{let py=transformPivot.hasPrefix("Top") ? 0.0:transformPivot.hasPrefix("Bottom") ? 1.0:p;l.frame.y=value/(displayUnitsPerInch*project.canvasHeight)-l.frame.height*py}}})}
    private func transformDimensionBinding(_ i:Int,width:Bool)->Binding<Double>{Binding(get:{(width ? project.layers[i].frame.width*project.canvasWidth:project.layers[i].frame.height*project.canvasHeight)*displayUnitsPerInch},set:{value in mutatePreviewLayer(at:i){layer in let aspect=layer.frame.width*project.canvasWidth/max(0.0001,layer.frame.height*project.canvasHeight),normalized=max(0.001,value/(displayUnitsPerInch*(width ? project.canvasWidth:project.canvasHeight)));if width{layer.frame.width=normalized;if proportionalScale{layer.frame.height=layer.frame.width*project.canvasWidth/(aspect*project.canvasHeight)}}else{layer.frame.height=normalized;if proportionalScale{layer.frame.width=layer.frame.height*project.canvasHeight*aspect/project.canvasWidth}}}})}
    private func optionalTransformBinding(_ i:Int,_ keyPath:WritableKeyPath<CoverLayer,Double?>)->Binding<Double>{Binding(get:{project.layers[i][keyPath:keyPath] ?? 0},set:{value in mutatePreviewLayer(at:i){$0[keyPath:keyPath]=value}})}
    private func projectBoolBinding(_ keyPath:WritableKeyPath<CoverProject,Bool?>)->Binding<Bool>{Binding(get:{project[keyPath:keyPath] ?? true},set:{value in updateProject{$0[keyPath:keyPath]=value}})}
    private func addGuide(axis:String,position:Double){
        let inches=(project.unit ?? "in")=="mm" ? position/25.4:(project.unit ?? "in")=="px" ? position/max(1,project.dpi):position
        if applyCoverOperation("guide-add",arguments:["axis":axis=="Vertical" ? "x":"y","position":String(inches)]) != nil { showNewGuide=false }
    }
    private func applyProductionTemplate(
        _ template:
            BookProductionTemplate
    ) {
        guard
            project.type
                == .printFullWrap
        else {
            return
        }

        if template == .custom {
            updateProject {
                $0.productionTemplate =
                    .custom
            }

            saveProjects()
            return
        }

        let currentPageCount =
            max(
                1,
                pageCount
            )

        if let updated =
            PhysicalBookGeometry
                .applyingProductionTemplate(
                    template,
                    to:
                        project,
                    pageCount:
                        currentPageCount
                )
        {
            updateProject {
                project in

                project =
                    updated
            }

            if let updatedCaliper =
                updated.spineCaliperInches
            {
                caliper =
                    updatedCaliper
            }

            pageCount =
                updated.spinePageCount
                ?? currentPageCount

            manualSpine =
                updated.spineWidth

            useCaliper =
                updated.spinePageCount
                    != nil
                && updated.spineCaliperInches
                    != nil
        }

        onApplyProductionTemplate(
            template
        )

        saveProjects()
    }

    private func applyPaperStockPreset(
        _ preset: PrintPaperStockPreset
    ) {
        if let presetCaliper =
            preset.caliperInches
        {
            caliper =
                presetCaliper

            useCaliper =
                true
        }

        updateProject {
            value in

            value.paperStockPreset =
                preset

            if let presetCaliper =
                preset.caliperInches
            {
                value.spineCaliperInches =
                    presetCaliper
            }
        }

        if preset.caliperInches != nil {
            recalculate()
        }
    }

    private func recalculate() {
        do {
            let spine =
                useCaliper
                ? try CoverCalculator.spineWidth(
                    pageCount:
                        pageCount,
                    caliperInches:
                        caliper
                )
                : manualSpine

            guard
                let updated =
                    PhysicalBookGeometry
                        .resizedPrintCover(
                            project,
                            spineWidth:
                                spine,
                            pageCount:
                                useCaliper
                                ? pageCount
                                : nil,
                            caliper:
                                useCaliper
                                ? caliper
                                : nil
                        )
            else {
                return
            }

            updateProject {
                value in

                value =
                    updated
            }

            manualSpine =
                updated.spineWidth
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
    private func export(
        format: String,
        proof: Bool
    ) {
        do {
            if format.lowercased() == "pdf", !proof, project.type == .printFullWrap {
                let assessment = try productionPreflight(project)
                guard assessment.isReady else {
                    let findings = assessment.errors + assessment.warnings
                    errorMessage = "Print-ready PDF blocked (\(assessment.status.rawValue)). " + findings.joined(separator: " ")
                    return
                }
            }
            let data =
                try CoverArtwork.export(
                    project,
                    format:
                        format,
                    proof:
                        proof
                )

            let panel =
                NSSavePanel()

            let type =
                format.lowercased()

            panel.nameFieldStringValue = type == "png-transparent"
                ? "Cover-Transparent.png"
                : "Cover."
                    + (type == "jpeg" ? "jpg" : type)

            if type == "pdf" {
                panel.allowedContentTypes =
                    [
                        .pdf
                    ]
            } else if type == "jpeg"
                        || type == "jpg"
            {
                panel.allowedContentTypes =
                    [
                        .jpeg
                    ]
            } else if type == "psd" {
                panel.allowedContentTypes =
                    [
                        UTType(
                            filenameExtension:
                                "psd"
                        )
                        ?? .data
                    ]
            } else {
                panel.allowedContentTypes =
                    [
                        .png
                    ]
            }


        if type == "svg",
           let svgType = UTType(filenameExtension: "svg")
        {
            panel.allowedContentTypes = [svgType]
        }

panel.begin {
                response in

                if response == .OK,
                   let url =
                    panel.url
                {
                    do {
                        try data.write(
                            to:
                                url,
                            options:
                                .atomic
                        )
                    } catch {
                        errorMessage =
                            error.localizedDescription
                    }
                }
            }
        } catch {
            errorMessage =
                error.localizedDescription
        }
    }
    private func placeImage(at index:Int,region:CoverRect,fill:Bool){
        guard project.layers.indices.contains(index),!project.layers[index].locked else{return}
        CoverProjectHistory.placeImage(project:&projects[projectIndex],layerID:project.layers[index].id,region:region,fill:fill,undo:&undoStack,redo:&redoStack)
    }
    private func drawGuides(_ context:GraphicsContext,size:CGSize){
        let sx=size.width/project.canvasWidth,sy=size.height/project.canvasHeight,bleed=project.bleed
        let trim=CGRect(x:bleed*sx,y:bleed*sy,width:(project.canvasWidth-2*bleed)*sx,height:(project.canvasHeight-2*bleed)*sy)
        context.stroke(Path(trim),with:.color(.red.opacity(0.7)),lineWidth:1)
        for x in project.userGuidesX ?? [] {var p=Path();p.move(to:CGPoint(x:x*sx,y:0));p.addLine(to:CGPoint(x:x*sx,y:size.height));context.stroke(p,with:.color(.cyan.opacity(0.8)),lineWidth:1)}
        for y in project.userGuidesY ?? [] {var p=Path();p.move(to:CGPoint(x:0,y:y*sy));p.addLine(to:CGPoint(x:size.width,y:y*sy));context.stroke(p,with:.color(.cyan.opacity(0.8)),lineWidth:1)}
        if project.type == .printFullWrap {let x1=(bleed+project.backWidth)*sx,x2=x1+project.spineWidth*sx;var spine=Path();spine.move(to:CGPoint(x:x1,y:0));spine.addLine(to:CGPoint(x:x1,y:size.height));spine.move(to:CGPoint(x:x2,y:0));spine.addLine(to:CGPoint(x:x2,y:size.height));context.stroke(spine,with:.color(.red),lineWidth:1)}
        for safe in CoverEditorEngine
            .safeZoneRects(
                project:
                    project
            ) {

            let safeRect =
                CGRect(
                    x:
                        safe.x
                        * size.width,
                    y:
                        safe.y
                        * size.height,
                    width:
                        safe.width
                        * size.width,
                    height:
                        safe.height
                        * size.height
                )

            context.stroke(
                Path(
                    safeRect
                ),
                with:
                    .color(
                        .green
                            .opacity(
                                0.72
                            )
                    ),
                style:
                    StrokeStyle(
                        lineWidth:
                            1,
                        dash:
                            [
                                5,
                                3
                            ]
                    )
            )
        }
        if project.gridVisible,let spacing=project.gridSpacingInches,spacing>0 {var grid=Path();var x=spacing;while x<project.canvasWidth{grid.move(to:CGPoint(x:x*sx,y:0));grid.addLine(to:CGPoint(x:x*sx,y:size.height));x += spacing};var y=spacing;while y<project.canvasHeight{grid.move(to:CGPoint(x:0,y:y*sy));grid.addLine(to:CGPoint(x:size.width,y:y*sy));y += spacing};context.stroke(grid,with:.color(.gray.opacity(0.24)),lineWidth:0.5)}
        if project.pixelGridVisible == true,zoom>=8 {var pixels=Path();let step=project.dpi>0 ? sx/project.dpi:0; if step>0{var x=step;while x<size.width{pixels.move(to:CGPoint(x:x,y:0));pixels.addLine(to:CGPoint(x:x,y:size.height));x += step};var y=step;while y<size.height{pixels.move(to:CGPoint(x:0,y:y));pixels.addLine(to:CGPoint(x:size.width,y:y));y += step};context.stroke(pixels,with:.color(.gray.opacity(0.18)),lineWidth:0.35)}}
    }
}

/// Reuse the composed canvas when only selection, tool options, or dock UI changes.
final class CoverCanvasRenderCache {
    private var project: CoverProject?
    private var scale: Double = 0
    private var rendered: NSImage?
    func image(project: CoverProject, scale: Double) -> NSImage? {
        if self.project == project, self.scale == scale, let rendered { return rendered }
        let image = try? CoverArtwork.render(project, includeGuides: false, includeTemplate: true, scale: scale)
        self.project = project; self.scale = scale; self.rendered = image
        return image
    }
}
