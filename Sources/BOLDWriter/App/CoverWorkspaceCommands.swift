import AppKit
import SwiftUI

/// Native macOS menus contain the same view actions as the Cover Creator ribbon.
struct CoverWorkspaceMenus {
    var file: AnyView; var edit: AnyView; var image: AnyView; var layer: AnyView
    var selection: AnyView; var filter: AnyView; var view: AnyView; var window: AnyView
    var open: () -> Void; var save: () -> Void; var undo: () -> Void; var redo: () -> Void
    var canUndo: Bool; var canRedo: Bool
}
private struct StudioWorkspaceMenusKey: FocusedValueKey { typealias Value = AnyView }
struct StudioUndoActions {
    weak var manager: UndoManager?
    func undo() { manager?.undo() }
    func redo() { manager?.redo() }
}
private struct StudioUndoActionsKey: FocusedValueKey { typealias Value = StudioUndoActions }
private struct CoverWorkspaceMenusKey: FocusedValueKey { typealias Value = CoverWorkspaceMenus }
extension FocusedValues {
    var studioUndoActions: StudioUndoActions? {
        get { self[StudioUndoActionsKey.self] }
        set { self[StudioUndoActionsKey.self] = newValue }
    }
    var studioWorkspaceMenus: AnyView? {
        get { self[StudioWorkspaceMenusKey.self] }
        set { self[StudioWorkspaceMenusKey.self] = newValue }
    }

    var coverWorkspaceMenus: CoverWorkspaceMenus? {
        get { self[CoverWorkspaceMenusKey.self] }
        set { self[CoverWorkspaceMenusKey.self] = newValue }
    }
}
struct CoverWorkspaceCommands: Commands {
    @FocusedValue(\.coverWorkspaceMenus) private var cover
    @FocusedValue(\.studioWorkspaceMenus) private var studio
    var body: some Commands {
        // DocumentGroup owns New/Open/Recent. Accessing NSDocumentController.shared
        // while building commands creates it before SwiftUI registers its document
        // formulas and crashes PlatformDocumentController at application launch.
        CommandGroup(after: .newItem) { if let cover { Divider(); cover.file } }
        if let studio { CommandMenu("3D Studio") { studio } }
        if let cover {
            CommandMenu("Image") { cover.image }
            CommandMenu("Layer") { cover.layer }
            CommandMenu("Select") { cover.selection }
            CommandMenu("Filter") { cover.filter }
            CommandMenu("Cover View") { cover.view }
            CommandMenu("Cover Panels") { cover.window }
            CommandGroup(after: .pasteboard) { cover.edit }
        }
    }
}
