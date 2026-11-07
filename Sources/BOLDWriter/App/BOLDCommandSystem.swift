import Foundation

enum BOLDCommandSource: String, Codable, CaseIterable, Hashable {
    case userInterface
    case keyboard
    case commandPalette
    case terminal
    case automation
    case artificialIntelligence
}

enum BOLDCommandWorkspace: String, Codable, CaseIterable, Hashable {
    case manuscript
    case cover
    case studio
    case publishing
    case application
}

enum BOLDProjectActionKind: String, Codable, CaseIterable, Hashable {
    case documentOpen
    case documentSave
    case documentSaveAs
    case documentExport
    case documentFind
    case documentReplace

    case manuscriptSetTrimSize
    case manuscriptSetMargins
    case manuscriptSetPageSize
    case manuscriptSetMetadata

    case coverOpen
    case coverInspect
    case coverUpdateLayer
    case coverEdit
    case coverAddText
    case coverPlaceImage
    case coverSetBackground
    case coverExport
    case coverConvertPaperback
    case coverFocusFront
    case coverFocusSpine
    case coverFocusBack

    case studioOpen
    case studioSetBinding
    case studioApplyPreset
    case studioSetCamera
    case studioSetLighting
    case studioRenderStill
    case studioRenderAnimation

    case publishingPreflight
    case publishingExportPDF
    case publishingExportEPUB
    case publishingExportDOCX

    case applicationUndo
    case applicationRedo
}

struct BOLDProjectAction: Codable, Equatable {
    var id: UUID
    var kind: BOLDProjectActionKind
    var workspace: BOLDCommandWorkspace
    var source: BOLDCommandSource
    var arguments: [String: String]

    init(
        id: UUID = UUID(),
        kind: BOLDProjectActionKind,
        workspace: BOLDCommandWorkspace,
        source: BOLDCommandSource,
        arguments: [String: String] = [:]
    ) {
        self.id = id
        self.kind = kind
        self.workspace = workspace
        self.source = source
        self.arguments = arguments
    }

    func value(for key: String) -> String? {
        arguments[key]
    }
}

struct BOLDCommandResult: Codable, Equatable {
    var actionID: UUID
    var succeeded: Bool
    var message: String
    var values: [String: String]

    init(
        actionID: UUID,
        succeeded: Bool = true,
        message: String = "",
        values: [String: String] = [:]
    ) {
        self.actionID = actionID
        self.succeeded = succeeded
        self.message = message
        self.values = values
    }
}

enum BOLDCommandError: Error, LocalizedError, Equatable {
    case duplicateRegistration(BOLDProjectActionKind)
    case unsupportedAction(BOLDProjectActionKind)
    case invalidTerminalCommand(String)
    case missingArgument(String)
    case handlerFailure(BOLDProjectActionKind, String)

    var errorDescription: String? {
        switch self {
        case let .duplicateRegistration(kind):
            return "A command handler is already registered for \(kind.rawValue)."

        case let .unsupportedAction(kind):
            return "No command handler is registered for \(kind.rawValue)."

        case let .invalidTerminalCommand(command):
            return "Unknown BOLD Writer command: \(command)"

        case let .missingArgument(argument):
            return "Missing required command argument: \(argument)"

        case let .handlerFailure(kind, message):
            return "\(kind.rawValue) failed: \(message)"
        }
    }
}

final class BOLDCommandBus {
    typealias Handler =
        (BOLDProjectAction) throws -> BOLDCommandResult

    private let lock = NSLock()
    private var handlers:
        [BOLDProjectActionKind: Handler] = [:]

    var registeredKinds: Set<BOLDProjectActionKind> {
        lock.lock()
        defer { lock.unlock() }
        return Set(handlers.keys)
    }

    func register(
        _ kind: BOLDProjectActionKind,
        handler: @escaping Handler
    ) throws {
        lock.lock()
        defer { lock.unlock() }

        guard handlers[kind] == nil else {
            throw BOLDCommandError
                .duplicateRegistration(kind)
        }

        handlers[kind] = handler
    }

    func replace(
        _ kind: BOLDProjectActionKind,
        handler: @escaping Handler
    ) {
        lock.lock()
        handlers[kind] = handler
        lock.unlock()
    }

    func unregister(
        _ kind: BOLDProjectActionKind
    ) {
        lock.lock()
        handlers.removeValue(forKey: kind)
        lock.unlock()
    }

    func canExecute(
        _ kind: BOLDProjectActionKind
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return handlers[kind] != nil
    }

    func execute(
        _ action: BOLDProjectAction
    ) throws -> BOLDCommandResult {
        let handler: Handler?

        lock.lock()
        handler = handlers[action.kind]
        lock.unlock()

        guard let handler else {
            throw BOLDCommandError
                .unsupportedAction(action.kind)
        }

        return try handler(action)
    }

    func execute(
        _ actions: [BOLDProjectAction]
    ) throws -> [BOLDCommandResult] {
        try actions.map { action in
            try execute(action)
        }
    }
}

struct BOLDTerminalCommandParser {
    static func parse(
        _ rawArguments: [String],
        source: BOLDCommandSource = .terminal
    ) throws -> BOLDProjectAction {
        let arguments =
            normalized(rawArguments)

        guard let namespace =
            arguments.first
        else {
            throw BOLDCommandError
                .invalidTerminalCommand("")
        }

        let tail =
            Array(arguments.dropFirst())

        switch namespace.lowercased() {
        case "document":
            return try parseDocument(
                tail,
                source: source
            )

        case "book", "manuscript":
            return try parseManuscript(
                tail,
                source: source
            )

        case "cover":
            return try parseCover(
                tail,
                source: source
            )

        case "studio", "3d":
            return try parseStudio(
                tail,
                source: source
            )

        case "publish", "publishing":
            return try parsePublishing(
                tail,
                source: source
            )

        case "undo":
            return BOLDProjectAction(
                kind: .applicationUndo,
                workspace: .application,
                source: source
            )

        case "redo":
            return BOLDProjectAction(
                kind: .applicationRedo,
                workspace: .application,
                source: source
            )

        default:
            throw BOLDCommandError
                .invalidTerminalCommand(
                    arguments.joined(
                        separator: " "
                    )
                )
        }
    }

    static let examples: [String] = [
        "bold document open /path/to/book.bold",
        "bold document save",
        "bold document export /path/to/book.docx docx",
        "bold book trim 6x9",
        "bold cover open",
        "bold cover add-text \"Book Title\"",
        "bold cover place-image /path/to/art.png",
        "bold cover focus front",
        "bold studio open",
        "bold studio binding hardcover",
        "bold studio preset hero-front",
        "bold studio camera front",
        "bold studio lighting soft-studio",
        "bold studio render /path/to/mockup.png",
        "bold studio animate /path/to/turntable.mp4",
        "bold publish preflight",
        "bold publish pdf /path/to/interior.pdf",
        "bold undo",
        "bold redo"
    ]

    private static func normalized(
        _ rawArguments: [String]
    ) -> [String] {
        guard let first =
            rawArguments.first
        else {
            return []
        }

        let executable =
            URL(fileURLWithPath: first)
                .lastPathComponent
                .lowercased()

        if executable == "bold"
            || executable == "boldwriter"
            || executable == "bold-writer"
        {
            return Array(
                rawArguments.dropFirst()
            )
        }

        return rawArguments
    }

    private static func parseDocument(
        _ arguments: [String],
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        guard let verb =
            arguments.first?.lowercased()
        else {
            throw BOLDCommandError
                .missingArgument(
                    "document command"
                )
        }

        switch verb {
        case "open":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind: .documentOpen,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        case "save":
            return BOLDProjectAction(
                kind: .documentSave,
                workspace: .manuscript,
                source: source
            )

        case "save-as":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind: .documentSaveAs,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        case "export":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            var values = [
                "path": path
            ]

            if arguments.count > 2 {
                values["format"] =
                    arguments[2]
            }

            return BOLDProjectAction(
                kind: .documentExport,
                workspace: .publishing,
                source: source,
                arguments: values
            )

        case "find":
            guard arguments.count > 1 else {
                throw BOLDCommandError
                    .missingArgument("query")
            }

            return BOLDProjectAction(
                kind: .documentFind,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "query":
                        arguments
                            .dropFirst()
                            .joined(
                                separator: " "
                            )
                ]
            )

        case "replace":
            guard arguments.count > 2 else {
                throw BOLDCommandError
                    .missingArgument(
                        "query and replacement"
                    )
            }

            return BOLDProjectAction(
                kind: .documentReplace,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "query":
                        arguments[1],
                    "replacement":
                        arguments
                            .dropFirst(2)
                            .joined(
                                separator: " "
                            )
                ]
            )

        default:
            throw invalid(
                namespace: "document",
                arguments: arguments
            )
        }
    }

    private static func parseManuscript(
        _ arguments: [String],
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        guard let verb =
            arguments.first?.lowercased()
        else {
            throw BOLDCommandError
                .missingArgument(
                    "book command"
                )
        }

        switch verb {
        case "trim":
            let value =
                try required(
                    arguments,
                    index: 1,
                    name: "trim preset"
                )

            return BOLDProjectAction(
                kind: .manuscriptSetTrimSize,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "preset": value
                ]
            )

        case "page-size":
            let value =
                try required(
                    arguments,
                    index: 1,
                    name: "page size"
                )

            return BOLDProjectAction(
                kind: .manuscriptSetPageSize,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "size": value
                ]
            )

        case "margins":
            guard arguments.count > 1 else {
                throw BOLDCommandError
                    .missingArgument(
                        "margin values"
                    )
            }

            return BOLDProjectAction(
                kind: .manuscriptSetMargins,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "value":
                        arguments
                            .dropFirst()
                            .joined(
                                separator: " "
                            )
                ]
            )

        case "metadata":
            guard arguments.count > 1 else {
                throw BOLDCommandError
                    .missingArgument(
                        "metadata"
                    )
            }

            return BOLDProjectAction(
                kind: .manuscriptSetMetadata,
                workspace: .manuscript,
                source: source,
                arguments: [
                    "value":
                        arguments
                            .dropFirst()
                            .joined(
                                separator: " "
                            )
                ]
            )

        default:
            throw invalid(
                namespace: "book",
                arguments: arguments
            )
        }
    }

    private static func parseCover(
        _ arguments: [String],
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        guard let verb =
            arguments.first?.lowercased()
        else {
            throw BOLDCommandError
                .missingArgument(
                    "cover command"
                )
        }

        switch verb {
        case "open":
            return BOLDProjectAction(
                kind: .coverOpen,
                workspace: .cover,
                source: source
            )

        case "edit":
            let operation = try required(arguments, index: 1, name: "operation")
            guard CoverProjectOperations.operations.contains(operation) else { throw invalid(namespace:"cover",arguments:arguments) }
            var fields = ["operation":operation]
            for argument in arguments.dropFirst(2) {
                let parts = argument.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false)
                guard parts.count == 2, !parts[0].isEmpty, fields[String(parts[0])] == nil else { throw invalid(namespace:"cover",arguments:arguments) }
                fields[String(parts[0])] = String(parts[1])
            }
            return BOLDProjectAction(kind:.coverEdit,workspace:.cover,source:source,arguments:fields)

        case "inspect":
            guard arguments.count == 1 else { throw invalid(namespace: "cover", arguments: arguments) }
            return BOLDProjectAction(kind: .coverInspect, workspace: .cover, source: source)

        case "update-layer":
            let id = try required(arguments, index: 1, name: "layerID")
            var fields = ["layerID": id]
            guard arguments.count > 2 else { throw BOLDCommandError.missingArgument("field=value") }
            for argument in arguments.dropFirst(2) {
                let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, CoverLayerCommands.editableFields.contains(String(parts[0])),
                      fields[String(parts[0])] == nil else {
                    throw invalid(namespace: "cover", arguments: arguments)
                }
                fields[String(parts[0])] = String(parts[1])
            }
            return BOLDProjectAction(kind: .coverUpdateLayer, workspace: .cover, source: source, arguments: fields)

        case "add-text":
            guard arguments.count > 1 else {
                throw BOLDCommandError
                    .missingArgument("text")
            }

            return BOLDProjectAction(
                kind: .coverAddText,
                workspace: .cover,
                source: source,
                arguments: [
                    "text":
                        arguments
                            .dropFirst()
                            .joined(
                                separator: " "
                            )
                ]
            )

        case "place-image":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind: .coverPlaceImage,
                workspace: .cover,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        case "background":
            guard arguments.count > 1 else {
                throw BOLDCommandError
                    .missingArgument(
                        "background"
                    )
            }

            return BOLDProjectAction(
                kind: .coverSetBackground,
                workspace: .cover,
                source: source,
                arguments: [
                    "value":
                        arguments
                            .dropFirst()
                            .joined(
                                separator: " "
                            )
                ]
            )

        case "focus":
            let target =
                try required(
                    arguments,
                    index: 1,
                    name:
                        "front, spine, or back"
                )
                .lowercased()

            let kind:
                BOLDProjectActionKind

            switch target {
            case "front":
                kind =
                    .coverFocusFront

            case "spine":
                kind =
                    .coverFocusSpine

            case "back":
                kind =
                    .coverFocusBack

            default:
                throw invalid(
                    namespace: "cover",
                    arguments: arguments
                )
            }

            return BOLDProjectAction(
                kind: kind,
                workspace: .cover,
                source: source
            )

        case "convert-paperback":
            var fields: [String: String] = [:]
            for argument in arguments.dropFirst() {
                let parts = argument.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, !parts[0].isEmpty, fields[String(parts[0])] == nil else {
                    throw invalid(namespace: "cover", arguments: arguments)
                }
                fields[String(parts[0])] = String(parts[1])
            }
            guard Set(fields.keys) == ["paper"] else {
                throw BOLDCommandError.missingArgument("paper=white|cream")
            }
            return BOLDProjectAction(kind: .coverConvertPaperback, workspace: .cover, source: source, arguments: fields)

        case "export":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind: .coverExport,
                workspace: .cover,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        default:
            throw invalid(
                namespace: "cover",
                arguments: arguments
            )
        }
    }

    private static func parseStudio(
        _ arguments: [String],
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        guard let verb =
            arguments.first?.lowercased()
        else {
            throw BOLDCommandError
                .missingArgument(
                    "studio command"
                )
        }

        switch verb {
        case "open":
            return BOLDProjectAction(
                kind: .studioOpen,
                workspace: .studio,
                source: source
            )

        case "binding":
            let value =
                try required(
                    arguments,
                    index: 1,
                    name: "binding"
                )

            return BOLDProjectAction(
                kind: .studioSetBinding,
                workspace: .studio,
                source: source,
                arguments: [
                    "binding": value
                ]
            )

        case "preset":
            let value =
                try required(
                    arguments,
                    index: 1,
                    name: "preset"
                )

            return BOLDProjectAction(
                kind: .studioApplyPreset,
                workspace: .studio,
                source: source,
                arguments: [
                    "preset": value
                ]
            )

        case "camera":
            let value = try required(arguments,index:1,name:"camera")
            var fields=["camera":value]
            for argument in arguments.dropFirst(2) {
                let parts=argument.split(separator:"=",maxSplits:1,omittingEmptySubsequences:false)
                guard parts.count==2,parts[0]=="productionMargins",fields[String(parts[0])]==nil,
                      ["true","false"].contains(String(parts[1])) else { throw invalid(namespace:"studio",arguments:arguments) }
                fields[String(parts[0])]=String(parts[1])
            }
            return BOLDProjectAction(kind:.studioSetCamera,workspace:.studio,source:source,arguments:fields)

        case "lighting":
            let value =
                try required(
                    arguments,
                    index: 1,
                    name: "lighting"
                )

            return BOLDProjectAction(
                kind: .studioSetLighting,
                workspace: .studio,
                source: source,
                arguments: [
                    "lighting": value
                ]
            )

        case "render":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind: .studioRenderStill,
                workspace: .studio,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        case "animate":
            let path =
                try required(
                    arguments,
                    index: 1,
                    name: "path"
                )

            return BOLDProjectAction(
                kind:
                    .studioRenderAnimation,
                workspace: .studio,
                source: source,
                arguments: [
                    "path": path
                ]
            )

        default:
            throw invalid(
                namespace: "studio",
                arguments: arguments
            )
        }
    }

    private static func parsePublishing(
        _ arguments: [String],
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        guard let verb =
            arguments.first?.lowercased()
        else {
            throw BOLDCommandError
                .missingArgument(
                    "publishing command"
                )
        }

        switch verb {
        case "preflight":
            return BOLDProjectAction(
                kind:
                    .publishingPreflight,
                workspace: .publishing,
                source: source
            )

        case "pdf":
            return try publishingExport(
                arguments,
                kind:
                    .publishingExportPDF,
                source: source
            )

        case "epub":
            return try publishingExport(
                arguments,
                kind:
                    .publishingExportEPUB,
                source: source
            )

        case "docx":
            return try publishingExport(
                arguments,
                kind:
                    .publishingExportDOCX,
                source: source
            )

        default:
            throw invalid(
                namespace: "publish",
                arguments: arguments
            )
        }
    }

    private static func publishingExport(
        _ arguments: [String],
        kind: BOLDProjectActionKind,
        source: BOLDCommandSource
    ) throws -> BOLDProjectAction {
        let path =
            try required(
                arguments,
                index: 1,
                name: "path"
            )

        return BOLDProjectAction(
            kind: kind,
            workspace: .publishing,
            source: source,
            arguments: [
                "path": path
            ]
        )
    }

    private static func required(
        _ arguments: [String],
        index: Int,
        name: String
    ) throws -> String {
        guard arguments.indices
            .contains(index)
        else {
            throw BOLDCommandError
                .missingArgument(name)
        }

        return arguments[index]
    }

    private static func invalid(
        namespace: String,
        arguments: [String]
    ) -> BOLDCommandError {
        .invalidTerminalCommand(
            ([namespace] + arguments)
                .joined(separator: " ")
        )
    }
}

struct BOLDAIToolProperty:
    Codable,
    Equatable
{
    var name: String
    var required: Bool
    var description: String
}

struct BOLDAIToolDefinition:
    Codable,
    Equatable
{
    var name: String
    var description: String
    var workspace:
        BOLDCommandWorkspace
    var properties:
        [BOLDAIToolProperty]
}

enum BOLDAIProjectToolCatalog {
    static var definitions:
        [BOLDAIToolDefinition]
    {
        BOLDProjectActionKind
            .allCases
            .map(definition)
    }

    static func definition(
        for kind:
            BOLDProjectActionKind
    ) -> BOLDAIToolDefinition {
        BOLDAIToolDefinition(
            name: kind.rawValue,
            description:
                description(for: kind),
            workspace:
                workspace(for: kind),
            properties:
                properties(for: kind)
        )
    }

    private static func workspace(
        for kind:
            BOLDProjectActionKind
    ) -> BOLDCommandWorkspace {
        switch kind {
        case .documentOpen,
             .documentSave,
             .documentSaveAs,
             .documentFind,
             .documentReplace,
             .manuscriptSetTrimSize,
             .manuscriptSetMargins,
             .manuscriptSetPageSize,
             .manuscriptSetMetadata:
            return .manuscript

        case .coverOpen,
             .coverInspect,
             .coverUpdateLayer,
             .coverEdit,
             .coverAddText,
             .coverPlaceImage,
             .coverSetBackground,
             .coverExport,
             .coverConvertPaperback,
             .coverFocusFront,
             .coverFocusSpine,
             .coverFocusBack:
            return .cover

        case .studioOpen,
             .studioSetBinding,
             .studioApplyPreset,
             .studioSetCamera,
             .studioSetLighting,
             .studioRenderStill,
             .studioRenderAnimation:
            return .studio

        case .documentExport,
             .publishingPreflight,
             .publishingExportPDF,
             .publishingExportEPUB,
             .publishingExportDOCX:
            return .publishing

        case .applicationUndo,
             .applicationRedo:
            return .application
        }
    }

    private static func description(
        for kind:
            BOLDProjectActionKind
    ) -> String {
        switch kind {
        case .documentOpen:
            return "Open a BOLD Writer project or supported document."
        case .documentSave:
            return "Save the current project."
        case .documentSaveAs:
            return "Save the current project to a new path."
        case .documentExport:
            return "Export the current document."
        case .documentFind:
            return "Find text in the manuscript."
        case .documentReplace:
            return "Replace text in the manuscript."
        case .manuscriptSetTrimSize:
            return "Set publication trim size."
        case .manuscriptSetMargins:
            return "Set manuscript margins."
        case .manuscriptSetPageSize:
            return "Set manuscript page size."
        case .manuscriptSetMetadata:
            return "Set publication metadata."
        case .coverOpen:
            return "Open Cover Studio."
        case .coverInspect:
            return "Inspect the selected cover's ordered layers, IDs, visibility, opacity, text, guides and normalized/inch/pixel frames. No artwork bytes are returned."
        case .coverEdit:
            return "Apply an atomic cover operation through the shared editor engine: " + CoverProjectOperations.operations.joined(separator:", ")
        case .coverUpdateLayer:
            return "Edit an existing cover layer by layerID from coverInspect. Frames are normalized canvas fractions, opacity is 0...1 and rotation is degrees. Locked layers must first be unlocked."
        case .coverAddText:
            return "Add editable cover text."
        case .coverPlaceImage:
            return "Place artwork into the cover."
        case .coverSetBackground:
            return "Change the cover background."
        case .coverExport:
            return "Export cover artwork."
        case .coverConvertPaperback:
            return "Create a new KDP paperback wrap from editable cover artwork."
        case .coverFocusFront:
            return "Focus the front cover."
        case .coverFocusSpine:
            return "Focus the spine."
        case .coverFocusBack:
            return "Focus the back cover."
        case .studioOpen:
            return "Open 3D Book Studio."
        case .studioSetBinding:
            return "Change physical binding."
        case .studioApplyPreset:
            return "Apply a mockup preset."
        case .studioSetCamera:
            return "Change the 3D camera."
        case .studioSetLighting:
            return "Change 3D lighting."
        case .studioRenderStill:
            return "Render a still image."
        case .studioRenderAnimation:
            return "Render an animation."
        case .publishingPreflight:
            return "Run publication preflight."
        case .publishingExportPDF:
            return "Export publication PDF."
        case .publishingExportEPUB:
            return "Export EPUB."
        case .publishingExportDOCX:
            return "Export DOCX."
        case .applicationUndo:
            return "Undo a reversible operation."
        case .applicationRedo:
            return "Redo a reversible operation."
        }
    }

    private static func properties(
        for kind:
            BOLDProjectActionKind
    ) -> [BOLDAIToolProperty] {
        switch kind {
        case .documentOpen,
             .documentSaveAs,
             .coverPlaceImage,
             .coverExport,
             .studioRenderStill,
             .studioRenderAnimation,
             .publishingExportPDF,
             .publishingExportEPUB,
             .publishingExportDOCX:
            return [
                .init(
                    name: "path",
                    required: true,
                    description:
                        "Filesystem path."
                )
            ]

        case .coverConvertPaperback:
            return [
                .init(name: "paper", required: true, description: "KDP B&W paper: white or cream.")
            ]

        case .documentExport:
            return [
                .init(
                    name: "path",
                    required: true,
                    description:
                        "Export destination."
                ),
                .init(
                    name: "format",
                    required: false,
                    description:
                        "Export format."
                )
            ]

        case .documentFind:
            return [
                .init(
                    name: "query",
                    required: true,
                    description:
                        "Text to find."
                )
            ]

        case .documentReplace:
            return [
                .init(
                    name: "query",
                    required: true,
                    description:
                        "Text to find."
                ),
                .init(
                    name: "replacement",
                    required: true,
                    description:
                        "Replacement text."
                )
            ]

        case .manuscriptSetTrimSize:
            return [
                .init(
                    name: "preset",
                    required: true,
                    description:
                        "Trim preset such as 6x9."
                )
            ]

        case .manuscriptSetPageSize:
            return [
                .init(
                    name: "size",
                    required: true,
                    description:
                        "Page size."
                )
            ]

        case .manuscriptSetMargins,
             .manuscriptSetMetadata:
            return [
                .init(
                    name: "value",
                    required: true,
                    description:
                        "Structured command value."
                )
            ]

        case .coverEdit:
            return [.init(name:"operation",required:true,description:CoverProjectOperations.operations.joined(separator:", "))]
                + ["layerID","layerIDs","dx","dy","scaleX","scaleY","pivotX","pivotY","degrees","x","y","width","height","axis","position","anchorX","anchorY","coverage","name","index"].map {
                    .init(name:$0,required:false,description:"Operation parameter. Coordinates normalized; guides and canvas dimensions in inches.")
                }

        case .coverUpdateLayer:
            return [.init(name: "layerID", required: true, description: "UUID from coverInspect.")]
                + CoverLayerCommands.editableFields.map {
                    .init(name: $0, required: false, description: "Layer property; booleans are true/false, frames are normalized fractions, opacity is 0...1.")
                }

        case .coverAddText:
            return [
                .init(
                    name: "text",
                    required: true,
                    description:
                        "Text to add."
                )
            ]

        case .coverSetBackground:
            return [
                .init(
                    name: "value",
                    required: true,
                    description:
                        "Background value."
                )
            ]

        case .studioSetBinding:
            return [
                .init(
                    name: "binding",
                    required: true,
                    description:
                        "Binding type."
                )
            ]

        case .studioApplyPreset:
            return [
                .init(
                    name: "preset",
                    required: true,
                    description:
                        "Mockup preset."
                )
            ]

        case .studioSetCamera:
            return [
                .init(
                    name: "camera",
                    required: true,
                    description:
                        "Camera preset."
                ),
                .init(name:"productionMargins",required:false,description:"Show bleed/wrap guides without changing finished book geometry or print exports. true or false.")
            ]

        case .studioSetLighting:
            return [
                .init(
                    name: "lighting",
                    required: true,
                    description:
                        "Lighting preset."
                )
            ]

        case .documentSave,
             .coverOpen,
             .coverInspect,
             .coverFocusFront,
             .coverFocusSpine,
             .coverFocusBack,
             .studioOpen,
             .publishingPreflight,
             .applicationUndo,
             .applicationRedo:
            return []
        }
    }
}
