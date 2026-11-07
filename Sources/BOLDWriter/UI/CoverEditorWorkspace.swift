import AppKit
import SwiftUI

enum CoverDockTab: String, CaseIterable, Identifiable {
    case history
    case swatches
    case layers
    case paths
    case properties
    case character
    case paragraph
    case adjustments
    case channels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .history: return "History"
        case .swatches: return "Swatches"
        case .layers: return "Layers"
        case .paths: return "Paths"
        case .properties: return "Properties"
        case .character: return "Character"
        case .paragraph: return "Paragraph"
        case .adjustments: return "Adjustments"
        case .channels: return "Channels"
        }
    }

    var compactTitle: String {
        switch self {
        case .history: return "History"
        case .swatches: return "Swatch"
        case .layers: return "Layers"
        case .paths: return "Paths"
        case .properties: return "Props"
        case .character: return "Type"
        case .paragraph: return "Para"
        case .adjustments: return "Adjust"
        case .channels: return "Channels"
        }
    }

    var symbol: String {
        switch self {
        case .history: return "clock.arrow.circlepath"
        case .swatches: return "paintpalette"
        case .layers: return "square.3.layers.3d"
        case .paths: return "point.topleft.down.curvedto.point.bottomright.up"
        case .properties: return "slider.horizontal.3"
        case .character: return "textformat"
        case .paragraph: return "paragraphsign"
        case .adjustments: return "dial.medium"
        case .channels: return "circle.grid.3x3"
        }
    }
}

/// Session-only chrome. Panel changes never enter CoverProject or its undo history.
struct CoverWorkspaceState {
    var toolbar = true
    var rightDock = true
    var layers = true
    var paths = true
    var properties = true
    var character = false
    var paragraph = false
    var adjustments = true
    var channels = false
    var historyAndSwatches = true
    var rulers = true

    var hasPanels: Bool {
        layers || paths || properties || character || paragraph
            || adjustments || channels || historyAndSwatches
    }

    /// The dock launcher always exposes the complete editor surface.
    /// A disabled panel remains visible as a launcher and is restored
    /// automatically when the user chooses it.
    var availableDockTabs: [CoverDockTab] {
        CoverDockTab.allCases
    }

    var visibleDockTabs: [CoverDockTab] {
        availableDockTabs.filter(isDockTabVisible)
    }

    func isDockTabVisible(_ tab: CoverDockTab) -> Bool {
        switch tab {
        case .history, .swatches:
            return historyAndSwatches
        case .layers:
            return layers
        case .paths:
            return paths
        case .properties:
            return properties
        case .character:
            return character
        case .paragraph:
            return paragraph
        case .adjustments:
            return adjustments
        case .channels:
            return channels
        }
    }

    mutating func setDockTabVisible(_ tab: CoverDockTab, _ visible: Bool) {
        switch tab {
        case .history, .swatches:
            historyAndSwatches = visible
        case .layers:
            layers = visible
        case .paths:
            paths = visible
        case .properties:
            properties = visible
        case .character:
            character = visible
        case .paragraph:
            paragraph = visible
        case .adjustments:
            adjustments = visible
        case .channels:
            channels = visible
        }
    }

    mutating func revealDockTab(_ tab: CoverDockTab) {
        rightDock = true
        setDockTabVisible(tab, true)
    }

    mutating func showAllDockPanels() {
        rightDock = true
        historyAndSwatches = true
        layers = true
        paths = true
        properties = true
        character = true
        paragraph = true
        adjustments = true
        channels = true
    }

    enum PropertiesTarget { case document, layer, mask }

    func propertiesTarget(layer: CoverLayer?, maskSelected: Bool) -> PropertiesTarget {
        guard let layer else { return .document }
        return maskSelected && layer.maskData != nil ? .mask : .layer
    }
}

extension CoverEditorTool {
    enum Options { case move, selection, paint, crop, navigation, color, none }
    var options: Options {
        switch self {
        case .move: return .move
        case .rectangle, .ellipse, .lasso, .wand: return .selection
        case .brush, .pencil, .eraser, .clone, .heal, .blur, .sharpen, .dodge, .burn: return .paint
        case .crop: return .crop
        case .hand, .zoom, .rotateView: return .navigation
        case .eyedropper, .gradient, .type, .shape: return .color
        default: return .none
        }
    }
    static let toolbarGroups: [[CoverEditorTool]] = [
        [.move], [.rectangle, .ellipse], [.lasso], [.wand], [.crop], [.eyedropper],
        [.brush, .pencil], [.eraser], [.clone, .heal], [.blur, .sharpen], [.gradient], [.dodge, .burn],
        [.type], [.pen, .path], [.shape], [.hand], [.rotateView], [.zoom]
    ]
}

enum CoverPathPanelModel {
    static func layers(
        in project: CoverProject
    ) -> [CoverLayer] {
        Array(
            project.layers
                .filter { $0.kind == .path }
                .reversed()
        )
    }

    static func nextPathName(
        in project: CoverProject
    ) -> String {
        let pathCount = project.layers.filter {
            $0.kind == .path
        }.count

        return "Path \(pathCount + 1)"
    }

    static func anchorCount(
        for layer: CoverLayer
    ) -> Int {
        CoverEditorEngine.vectorAnchorCount(
            for: layer
        )
    }

    static func isClosed(
        _ layer: CoverLayer
    ) -> Bool {
        let contours =
            CoverEditorEngine
                .vectorContours(
                    for: layer
                )

        guard !contours.isEmpty else {
            return layer.pathClosed
                ?? false
        }

        return CoverEditorEngine
            .vectorContourClosures(
                for: layer,
                contourCount:
                    contours.count
            )
            .first
            ?? false
    }

    static func status(
        for layer: CoverLayer
    ) -> String {
        isClosed(layer) ? "Closed" : "Open"
    }
}

struct CoverCommandAvailability {
    var hasLayer: Bool
    var hasImage: Bool
    var hasSelection: Bool
    var hasDismissedSelection: Bool
    var canMask: Bool { hasImage && hasSelection }
    var canReselect: Bool { hasDismissedSelection }
}

struct CoverToolButton: View {
    let title: String
    let symbol: String
    var selected = false
    let action: () -> Void
    @State private var hovered = false
    var body: some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:15)).frame(width:30,height:29)
                .background(selected ? Color.accentColor.opacity(0.65) : hovered ? Color.primary.opacity(0.08) : .clear)
                .clipShape(RoundedRectangle(cornerRadius:4))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct CoverDockPanel<Content: View>: View {
    let title: String
    let hide: () -> Void
    @ViewBuilder var content: Content
    var body: some View {
        VStack(spacing:0) {
            HStack {
                Text(title).fontWeight(.semibold)
                Spacer()
                Button(action:hide) { Image(systemName:"minus") }.buttonStyle(.plain)
                    .help("Hide \(title)").accessibilityLabel("Hide \(title)")
            }.padding(.horizontal,10).padding(.vertical,7)
                .background(Color.white.opacity(0.045))
            Divider()
            content
        }
    }
}

/// Every control uses the parameter key and range consumed by CoverArtwork.
struct CoverAdjustmentControl: Identifiable {
    let key: String
    let title: String
    let range: ClosedRange<Double>
    let initial: Double
    var id: String { key }

    func clamped(_ value: Double) -> Double {
        guard value.isFinite else { return initial }
        return min(range.upperBound, max(range.lowerBound, value))
    }

    static func controls(for kind: CoverAdjustmentKind) -> [Self] {
        switch kind {
        case .brightnessContrast:
            return [.init(key:"brightness",title:"Brightness",range:-1...1,initial:0), .init(key:"contrast",title:"Contrast",range:0...4,initial:1)]
        case .levels:
            return [
                .init(key:"inputBlack",title:"Input Black",range:0...1,initial:0),
                .init(key:"gamma",title:"Gamma",range:0.1...10,initial:1),
                .init(key:"inputWhite",title:"Input White",range:0...1,initial:1),
                .init(key:"outputBlack",title:"Output Black",range:0...1,initial:0),
                .init(key:"outputWhite",title:"Output White",range:0...1,initial:1)
            ]
        case .exposure: return [.init(key:"exposure",title:"Exposure",range:-4...4,initial:0)]
        case .curves:
            return [
                .init(key:"curve0",title:"Black",range:0...1,initial:0),
                .init(key:"curve1",title:"Shadows",range:0...1,initial:0.25),
                .init(key:"curve2",title:"Midtones",range:0...1,initial:0.5),
                .init(key:"curve3",title:"Highlights",range:0...1,initial:0.75),
                .init(key:"curve4",title:"White",range:0...1,initial:1)
            ]
        case .hueSaturation: return [.init(key:"saturation",title:"Saturation",range:0...2,initial:1)]
        case .vibrance: return [.init(key:"amount",title:"Vibrance",range:-1...1,initial:0.5)]
        case .temperatureTint: return [.init(key:"temperature",title:"Temperature",range:-1...1,initial:0), .init(key:"tint",title:"Tint",range:-1...1,initial:0)]
        case .colorBalance: return [.init(key:"cyanRed",title:"Cyan ↔ Red",range:-1...1,initial:0), .init(key:"magentaGreen",title:"Magenta ↔ Green",range:-1...1,initial:0), .init(key:"yellowBlue",title:"Yellow ↔ Blue",range:-1...1,initial:0)]
        case .threshold: return [.init(key:"threshold",title:"Threshold",range:0...1,initial:0.5)]
        case .posterize: return [.init(key:"levels",title:"Levels",range:2...30,initial:6)]
        case .gradientMap: return []
        case .channelMixer: return [.init(key:"redRed",title:"Red ← Red",range:-2...2,initial:1), .init(key:"redGreen",title:"Red ← Green",range:-2...2,initial:0), .init(key:"redBlue",title:"Red ← Blue",range:-2...2,initial:0), .init(key:"redConstant",title:"Red Constant",range:-1...1,initial:0), .init(key:"greenRed",title:"Green ← Red",range:-2...2,initial:0), .init(key:"greenGreen",title:"Green ← Green",range:-2...2,initial:1), .init(key:"greenBlue",title:"Green ← Blue",range:-2...2,initial:0), .init(key:"greenConstant",title:"Green Constant",range:-1...1,initial:0), .init(key:"blueRed",title:"Blue ← Red",range:-2...2,initial:0), .init(key:"blueGreen",title:"Blue ← Green",range:-2...2,initial:0), .init(key:"blueBlue",title:"Blue ← Blue",range:-2...2,initial:1), .init(key:"blueConstant",title:"Blue Constant",range:-1...1,initial:0)]
        case .selectiveColor: return []
        case .gaussianBlur: return [.init(key:"radius",title:"Radius",range:0...30,initial:3)]
        case .sharpen: return [.init(key:"amount",title:"Sharpness",range:0...2,initial:0.4)]
        case .monochrome:
            return [
                .init(key:"bwReds",title:"Reds",range:0...2,initial:0.40),
                .init(key:"bwYellows",title:"Yellows",range:0...2,initial:0.60),
                .init(key:"bwGreens",title:"Greens",range:0...2,initial:0.40),
                .init(key:"bwCyans",title:"Cyans",range:0...2,initial:0.60),
                .init(key:"bwBlues",title:"Blues",range:0...2,initial:0.20),
                .init(key:"bwMagentas",title:"Magentas",range:0...2,initial:0.80)
            ]
        case .invert: return []
        }
    }
}

/// A precise, resettable control shared by adjustment layers and selective color.
/// The slider and numeric field use the same persisted parameter binding.
struct CoverAdjustmentControlRow: View {
    let control: CoverAdjustmentControl
    @Binding var value: Double
    let accessibilityTitle: String

    init(
        control: CoverAdjustmentControl,
        value: Binding<Double>,
        accessibilityTitle: String? = nil
    ) {
        self.control = control
        self._value = value
        self.accessibilityTitle = accessibilityTitle ?? control.title
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(control.title)
                .frame(width: 75, alignment: .leading)

            Slider(
                value: Binding(
                    get: { control.clamped(value) },
                    set: { value = control.clamped($0) }
                ),
                in: control.range
            )
            .accessibilityLabel(accessibilityTitle)

            TextField(
                "Value",
                value: Binding(
                    get: { control.clamped(value) },
                    set: { value = control.clamped($0) }
                ),
                format: .number.precision(.fractionLength(0...4))
            )
            .textFieldStyle(.roundedBorder)
            .frame(width: 62)
            .accessibilityLabel("\(accessibilityTitle) value")

            Button {
                value = control.initial
            } label: {
                Image(systemName: "arrow.counterclockwise")
                    .frame(width: 18)
            }
            .buttonStyle(.borderless)
            .help("Reset \(accessibilityTitle) to \(control.initial)")
            .accessibilityLabel("Reset \(accessibilityTitle)")
            .disabled(abs(control.clamped(value) - control.initial) < 0.0000001)
        }
    }
}

enum CoverSelectiveColor {
    static let targets = [
        "reds",
        "yellows",
        "greens",
        "cyans",
        "blues",
        "magentas",
        "whites",
        "neutrals",
        "blacks"
    ]

    static func title(
        for target:String
    ) -> String {
        switch target {
        case "reds": return "Reds"
        case "yellows": return "Yellows"
        case "greens": return "Greens"
        case "cyans": return "Cyans"
        case "blues": return "Blues"
        case "magentas": return "Magentas"
        case "whites": return "Whites"
        case "neutrals": return "Neutrals"
        case "blacks": return "Blacks"
        default: return target.capitalized
        }
    }

    static func controls(
        for target:String
    ) -> [CoverAdjustmentControl] {
        [
            .init(
                key:"\(target)Cyan",
                title:"Cyan",
                range:-1...1,
                initial:0
            ),
            .init(
                key:"\(target)Magenta",
                title:"Magenta",
                range:-1...1,
                initial:0
            ),
            .init(
                key:"\(target)Yellow",
                title:"Yellow",
                range:-1...1,
                initial:0
            ),
            .init(
                key:"\(target)Black",
                title:"Black",
                range:-1...1,
                initial:0
            )
        ]
    }
}

struct CoverEditorToolbar: View {
    let activeTool: CoverEditorTool
    @Binding var lassoMode: Int
    let selectTool: (CoverEditorTool) -> Void
    var body: some View {
        ScrollView {
            VStack(spacing:2) {
                ForEach(CoverEditorTool.toolbarGroups.indices,id:\.self) { index in
                    let group=CoverEditorTool.toolbarGroups[index]
                    let tool=group.contains(activeTool) ? activeTool:group[0]
                    HStack(spacing:0) {
                        CoverToolButton(title:tool.title,symbol:tool.symbol,selected:group.contains(activeTool)){selectTool(tool)}
                        if group.count>1 || tool == .lasso {
                            CoverToolFlyout(title:"\(tool.title) tools",symbol:"arrowtriangle.down.fill",selected:false,compact:true) {
                                ForEach(group){member in Button(member.title){selectTool(member)}}
                                if tool == .lasso {
                                    Button("Freehand Lasso"){lassoMode=0;selectTool(.lasso)}
                                    Button("Polygonal Lasso"){lassoMode=1;selectTool(.lasso)}
                                    Button("Magnetic Lasso"){lassoMode=2;selectTool(.lasso)}
                                }
                            }
                        }
                    }.frame(width:42)
                }
            }.padding(.vertical,5)
        }.scrollIndicators(.hidden).frame(width:46)
            .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct CoverToolFlyout<Content: View>: View {
    let title: String
    let symbol: String
    let selected: Bool
    var compact = false
    @ViewBuilder var content: Content
    @State private var hovered = false
    var body: some View {
        Menu { content } label: {
            Image(systemName:symbol).font(.system(size:compact ? 6:15))
                .frame(width:compact ? 10:30,height:29)
                .background(selected ? Color.accentColor.opacity(0.65):hovered ? Color.primary.opacity(0.08):.clear)
                .cornerRadius(4)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden)
            .onHover { hovered=$0 }.help(title).accessibilityLabel(title)
            .accessibilityAddTraits(selected ? .isSelected:[])
    }
}

extension CoverAdjustmentKind {
    var workspaceTitle: String {
        switch self {
        case .brightnessContrast: return "Brightness / Contrast"
        case .exposure: return "Exposure"
        case .levels: return "Levels"
        case .curves: return "Curves"
        case .hueSaturation: return "Saturation"
        case .vibrance: return "Vibrance"
        case .temperatureTint: return "Temperature / Tint"
        case .colorBalance: return "Color Balance"
        case .threshold: return "Threshold"
        case .posterize: return "Posterize"
        case .gradientMap: return "Gradient Map"
        case .channelMixer: return "Channel Mixer"
        case .selectiveColor: return "Selective Color"
        case .monochrome: return "Black & White"
        case .invert: return "Invert"
        case .gaussianBlur: return "Gaussian Blur"
        case .sharpen: return "Sharpen"
        }
    }
}
