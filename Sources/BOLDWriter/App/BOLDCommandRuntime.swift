import Foundation

struct BOLDCommandHandlerRegistry {
    typealias Handler =
        BOLDCommandBus.Handler

    private var handlers:
        [BOLDProjectActionKind: Handler] = [:]

    var registeredKinds:
        Set<BOLDProjectActionKind>
    {
        Set(handlers.keys)
    }

    mutating func register(
        _ kind: BOLDProjectActionKind,
        handler: @escaping Handler
    ) throws {
        guard handlers[kind] == nil else {
            throw BOLDCommandError
                .duplicateRegistration(kind)
        }

        handlers[kind] = handler
    }

    mutating func replace(
        _ kind: BOLDProjectActionKind,
        handler: @escaping Handler
    ) {
        handlers[kind] = handler
    }

    func handler(
        for kind:
            BOLDProjectActionKind
    ) -> Handler? {
        handlers[kind]
    }
}

final class BOLDCommandRuntime {
    let bus: BOLDCommandBus

    init(
        registry:
            BOLDCommandHandlerRegistry
    ) throws {
        let bus =
            BOLDCommandBus()

        for kind in
            BOLDProjectActionKind.allCases
        {
            guard let handler =
                registry.handler(
                    for: kind
                )
            else {
                continue
            }

            try bus.register(
                kind,
                handler: handler
            )
        }

        self.bus = bus
    }

    var registeredKinds:
        Set<BOLDProjectActionKind>
    {
        bus.registeredKinds
    }

    var missingKinds:
        Set<BOLDProjectActionKind>
    {
        Set(
            BOLDProjectActionKind
                .allCases
        )
        .subtracting(
            registeredKinds
        )
    }

    func execute(
        _ action:
            BOLDProjectAction
    ) throws -> BOLDCommandResult {
        try bus.execute(action)
    }

    func execute(
        _ actions:
            [BOLDProjectAction]
    ) throws -> [BOLDCommandResult] {
        try bus.execute(actions)
    }
}

struct BOLDCommandManifest {
    var supported:
        Set<BOLDProjectActionKind>

    var unsupported:
        Set<BOLDProjectActionKind>
    {
        Set(
            BOLDProjectActionKind
                .allCases
        )
        .subtracting(supported)
    }

    var isComplete: Bool {
        unsupported.isEmpty
    }

    func supports(
        _ action:
            BOLDProjectAction
    ) -> Bool {
        supported.contains(
            action.kind
        )
    }
}

enum BOLDCommandSafetyClass: Equatable {
    case readOnly
    case reversibleMutation
    case filesystemWrite
}

enum BOLDCommandSafety {
    static func classification(
        for kind:
            BOLDProjectActionKind
    ) -> BOLDCommandSafetyClass {
        switch kind {
        case .documentFind,
             .coverInspect,
             .coverOpen,
             .coverFocusFront,
             .coverFocusSpine,
             .coverFocusBack,
             .studioOpen,
             .publishingPreflight:
            return .readOnly

        case .documentReplace,
             .manuscriptSetTrimSize,
             .manuscriptSetMargins,
             .manuscriptSetPageSize,
             .manuscriptSetMetadata,
             .coverAddText,
             .coverUpdateLayer,
             .coverEdit,
             .coverPlaceImage,
             .coverSetBackground,
             .coverConvertPaperback,
             .studioSetBinding,
             .studioApplyPreset,
             .studioSetCamera,
             .studioSetLighting,
             .applicationUndo,
             .applicationRedo:
            return .reversibleMutation

        case .documentOpen,
             .documentSave,
             .documentSaveAs,
             .documentExport,
             .coverExport,
             .studioRenderStill,
             .studioRenderAnimation,
             .publishingExportPDF,
             .publishingExportEPUB,
             .publishingExportDOCX:
            return .filesystemWrite
        }
    }
}

struct BOLDCommandEnvelope {
    var action:
        BOLDProjectAction

    var requiresExplicitWriteApproval:
        Bool
    {
        switch BOLDCommandSafety
            .classification(
                for: action.kind
            )
        {
        case .readOnly,
             .reversibleMutation:
            return false

        case .filesystemWrite:
            return true
        }
    }
}
