import AppKit
import SwiftUI

/// Edits the production layer itself, so preview, Cover Creator and print export
/// all consume the same artwork. Scene transforms never enter print metadata.
struct BookStudioArtworkInspector: View {
    @ObservedObject var document: BOLDWriterDocument
    let projectID: UUID
    var panel: CoverPanelAnchor? = nil
    let onOpenCover: () -> Void
    @Environment(\.undoManager) private var undoManager
    @State private var selectedID: UUID?
    @State private var error: String?

    private var project: CoverProject? {
        document.metadata.coverProjects?.first { $0.id == projectID }
    }
    private var layers: [CoverLayer] {
        (project?.layers ?? []).filter {
            !$0.isReferenceLayer && $0.kind != .group && $0.kind != .adjustment
        }
    }
    private var selected: CoverLayer? {
        layers.first { $0.id == selectedID }
    }

    var body: some View {
        GroupBox("Live cover artwork") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Changes update this book and Cover Creator immediately.")
                    .font(.caption).foregroundStyle(.secondary)
                Picker("Layer", selection: $selectedID) {
                    Text("Choose artwork").tag(nil as UUID?)
                    ForEach(layers) { layer in
                        Text(layer.name).tag(Optional(layer.id))
                    }
                }
                if let layer = selected, let project {
                    if layer.imageData != nil || layer.kind == .shape {
                        Menu("Auto Fit Artwork") {
                            Button("Front Cover + Bleed / Wrap") { fit("front") }
                            Button("Spine Inside Borders") { fit("spine") }
                            Button("Back Cover + Bleed / Wrap") { fit("back") }
                        }.disabled(layer.locked || layer.positionLocked == true)
                    }
                    Toggle("Visible", isOn: value(\.visible, fallback: layer.visible))
                        .disabled(layer.locked)
                    if layer.locked {
                        Text("Unlock this layer in Cover Creator to edit it.")
                            .font(.caption)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Position and size in inches from the full wrap’s top left.")
                            .font(.caption).foregroundStyle(.secondary)
                        number("X", frameValue(\.x, extent: project.canvasWidth))
                        number("Y", frameValue(\.y, extent: project.canvasHeight))
                        number("Width", frameValue(\.width, extent: project.canvasWidth))
                        number("Height", frameValue(\.height, extent: project.canvasHeight))
                        number("Rotation °", value(\.rotation, fallback: layer.rotation))
                    }
                    .disabled(layer.locked || layer.positionLocked == true)
                    VStack(alignment: .leading, spacing: 8) {
                        if layer.kind == .text {
                            TextField("Cover text", text: value(\.text, fallback: layer.text), axis: .vertical)
                                .lineLimit(2...6)
                            number("Type size", value(\.fontSize, fallback: layer.fontSize))
                            TextField("Text color (#RRGGBB)", text: value(\.colorHex, fallback: layer.colorHex))
                        }
                        if layer.kind == .shape {
                            TextField("Fill color (#RRGGBB)", text: value(\.fillHex, fallback: layer.fillHex))
                        }
                        if layer.imageData != nil {
                            Picker("Image fit", selection: value(\.cropMode, fallback: layer.cropMode)) {
                                Text("Fill").tag(CoverCropMode.fill)
                                Text("Fit").tag(CoverCropMode.fit)
                            }
                            Toggle("Flip horizontally", isOn: value(\.flipHorizontal, fallback: layer.flipHorizontal))
                            Toggle("Flip vertically", isOn: value(\.flipVertical, fallback: layer.flipVertical))
                            Text("Crop position").font(.caption)
                            Slider(value: value(\.cropOffsetX, fallback: layer.cropOffsetX), in: -1...1)
                                .accessibilityLabel("Horizontal crop position")
                            Slider(value: value(\.cropOffsetY, fallback: layer.cropOffsetY), in: -1...1)
                                .accessibilityLabel("Vertical crop position")
                        }
                        HStack {
                            Text("Opacity")
                            Slider(value: value(\.opacity, fallback: layer.opacity), in: 0...1)
                        }
                    }
                    .disabled(layer.locked || layer.pixelsLocked == true)
                }
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                Button("Continue in Cover Creator", action: onOpenCover)
                Text("Drag the book to orbit; scroll to zoom. Artwork edits use the controls above.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onChange(of: projectID) { _, _ in selectedID = nil; error = nil; selectPanelArtwork() }
        .onChange(of: panel) { _, _ in selectPanelArtwork() }
        .onAppear { selectPanelArtwork() }
    }

    private func selectPanelArtwork() {
        guard let panel, let project else { return }
        selectedID = BookCoverCreatorView.preferredLayerID(for:panel,in:project)
    }
    private func fit(_ panel: String) {
        guard let project, let id=selectedID else { return }
        do {
            var next=project
            try CoverProjectOperations.apply("fit-panel",to:&next,arguments:["layerID":id.uuidString,"panel":panel])
            guard let layer=next.layers.first(where:{$0.id==id}) else { return }
            try BookStudioArtworkEditing.replace(layer,projectID:projectID,in:document,undoManager:undoManager)
            error=nil
        } catch { self.error=error.localizedDescription }
    }

    private func number(_ title: String, _ binding: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: binding, format: .number.precision(.fractionLength(0...3)))
                .frame(width: 88).multilineTextAlignment(.trailing)
        }
    }

    private func value<T>(_ key: WritableKeyPath<CoverLayer, T>, fallback: T) -> Binding<T> {
        Binding(get: { selected?[keyPath: key] ?? fallback }, set: { newValue in
            edit { $0[keyPath: key] = newValue }
        })
    }

    private func frameValue(_ key: WritableKeyPath<CoverRect, Double>, extent: Double) -> Binding<Double> {
        Binding(get: { (selected?.frame[keyPath: key] ?? 0) * extent }, set: { inches in
            guard extent > 0, inches.isFinite else { return }
            edit { $0.frame[keyPath: key] = inches / extent }
        })
    }

    private func edit(_ body: (inout CoverLayer) -> Void) {
        guard var layer = selected, !layer.locked else { return }
        body(&layer)
        do {
            try BookStudioArtworkEditing.replace(layer, projectID: projectID,
                                                  in: document, undoManager: undoManager)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

@MainActor
enum BookStudioArtworkEditing {
    static func replace(_ layer: CoverLayer, projectID: UUID,
                        in document: BOLDWriterDocument, undoManager: UndoManager?) throws {
        guard var projects = document.metadata.coverProjects,
              let p = projects.firstIndex(where: { $0.id == projectID }),
              let l = projects[p].layers.firstIndex(where: { $0.id == layer.id }) else { return }
        let previous = projects[p].layers[l]
        guard previous != layer else { return }
        try CoverProjectOperations.replace(layer, in: &projects[p])
        try CoverProject.validate(projects)
        document.metadata.coverProjects = projects
        undoManager?.registerUndo(withTarget: document) { [weak undoManager] target in
            try? replace(previous, projectID: projectID, in: target, undoManager: undoManager)
        }
        undoManager?.setActionName("Edit Cover Artwork in 3D")
    }
}
