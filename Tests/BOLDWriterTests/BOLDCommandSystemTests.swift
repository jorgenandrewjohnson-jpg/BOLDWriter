import Foundation
import XCTest
@testable import BOLDWriter

final class BOLDCommandSystemTests:
    XCTestCase
{
    func testPaperbackConversionCommandUsesExplicitPaperProfile() throws {
        let action = try BOLDTerminalCommandParser.parse(["cover", "convert-paperback", "paper=cream"])
        XCTAssertEqual(action.kind, .coverConvertPaperback)
        XCTAssertEqual(action.arguments["paper"], "cream")
        XCTAssertEqual(BOLDCommandSafety.classification(for: action.kind), .reversibleMutation)
    }

    func testProjectActionRoundTrips()
        throws
    {
        let original =
            BOLDProjectAction(
                kind:
                    .studioRenderStill,
                workspace: .studio,
                source:
                    .artificialIntelligence,
                arguments: [
                    "path":
                        "/tmp/mockup.png"
                ]
            )

        let data =
            try JSONEncoder()
                .encode(original)

        let decoded =
            try JSONDecoder()
                .decode(
                    BOLDProjectAction.self,
                    from: data
                )

        XCTAssertEqual(
            decoded,
            original
        )
    }

    func testBusDispatchesExactAction()
        throws
    {
        let bus =
            BOLDCommandBus()

        var received:
            BOLDProjectAction?

        try bus.register(
            .coverAddText
        ) { action in
            received = action

            return BOLDCommandResult(
                actionID: action.id,
                message: "added",
                values: [
                    "text":
                        action.arguments[
                            "text"
                        ] ?? ""
                ]
            )
        }

        let action =
            BOLDProjectAction(
                kind:
                    .coverAddText,
                workspace: .cover,
                source: .terminal,
                arguments: [
                    "text": "My Book"
                ]
            )

        let result =
            try bus.execute(action)

        XCTAssertEqual(
            received,
            action
        )

        XCTAssertEqual(
            result.actionID,
            action.id
        )

        XCTAssertEqual(
            result.values["text"],
            "My Book"
        )
    }

    func testDuplicateRegistrationFails()
        throws
    {
        let bus =
            BOLDCommandBus()

        try bus.register(
            .documentSave
        ) { action in
            BOLDCommandResult(
                actionID: action.id
            )
        }

        XCTAssertThrowsError(
            try bus.register(
                .documentSave
            ) { action in
                BOLDCommandResult(
                    actionID: action.id
                )
            }
        )
    }

    func testUnsupportedActionFails()
    {
        let bus =
            BOLDCommandBus()

        let action =
            BOLDProjectAction(
                kind:
                    .studioRenderStill,
                workspace: .studio,
                source: .automation
            )

        XCTAssertThrowsError(
            try bus.execute(action)
        )
    }

    func testTerminalParsesBookTrim()
        throws
    {
        let action =
            try BOLDTerminalCommandParser
                .parse(
                    [
                        "bold",
                        "book",
                        "trim",
                        "6x9"
                    ]
                )

        XCTAssertEqual(
            action.kind,
            .manuscriptSetTrimSize
        )

        XCTAssertEqual(
            action.arguments["preset"],
            "6x9"
        )
    }

    func testTerminalParsesCoverText()
        throws
    {
        let action =
            try BOLDTerminalCommandParser
                .parse(
                    [
                        "cover",
                        "add-text",
                        "Sample",
                        "Book"
                    ]
                )

        XCTAssertEqual(
            action.kind,
            .coverAddText
        )

        XCTAssertEqual(
            action.arguments["text"],
            "Sample Book"
        )
    }

    func testTerminalParsesStudioPreset()
        throws
    {
        let action =
            try BOLDTerminalCommandParser
                .parse(
                    [
                        "studio",
                        "preset",
                        "hero-front"
                    ]
                )

        XCTAssertEqual(
            action.kind,
            .studioApplyPreset
        )

        XCTAssertEqual(
            action.arguments["preset"],
            "hero-front"
        )
    }

    func testEveryActionHasAITool()
    {
        XCTAssertEqual(
            Set(
                BOLDAIProjectToolCatalog
                    .definitions
                    .map(\.name)
            ),
            Set(
                BOLDProjectActionKind
                    .allCases
                    .map(\.rawValue)
            )
        )
    }

    func testRegistryBuildsRuntime()
        throws
    {
        var registry =
            BOLDCommandHandlerRegistry()

        try registry.register(
            .applicationUndo
        ) { action in
            BOLDCommandResult(
                actionID: action.id,
                message: "undo"
            )
        }

        try registry.register(
            .applicationRedo
        ) { action in
            BOLDCommandResult(
                actionID: action.id,
                message: "redo"
            )
        }

        let runtime =
            try BOLDCommandRuntime(
                registry: registry
            )

        XCTAssertEqual(
            runtime.registeredKinds,
            [
                .applicationUndo,
                .applicationRedo
            ]
        )

        XCTAssertTrue(
            runtime.missingKinds
                .contains(
                    .coverAddText
                )
        )
    }

    func testRuntimeDispatchesRegisteredHandler()
        throws
    {
        var registry =
            BOLDCommandHandlerRegistry()

        try registry.register(
            .studioApplyPreset
        ) { action in
            BOLDCommandResult(
                actionID: action.id,
                values: [
                    "preset":
                        action.arguments[
                            "preset"
                        ] ?? ""
                ]
            )
        }

        let runtime =
            try BOLDCommandRuntime(
                registry: registry
            )

        let action =
            BOLDProjectAction(
                kind:
                    .studioApplyPreset,
                workspace: .studio,
                source:
                    .artificialIntelligence,
                arguments: [
                    "preset":
                        "hero-front"
                ]
            )

        let result =
            try runtime.execute(
                action
            )

        XCTAssertEqual(
            result.values["preset"],
            "hero-front"
        )
    }

    func testManifestReportsMissingActions()
    {
        let manifest =
            BOLDCommandManifest(
                supported: [
                    .documentSave,
                    .applicationUndo
                ]
            )

        XCTAssertFalse(
            manifest.isComplete
        )

        XCTAssertTrue(
            manifest.unsupported
                .contains(
                    .studioRenderStill
                )
        )
    }

    func testSafetyClassificationSeparatesWrites()
    {
        XCTAssertEqual(
            BOLDCommandSafety
                .classification(
                    for:
                        .publishingPreflight
                ),
            .readOnly
        )

        XCTAssertEqual(
            BOLDCommandSafety
                .classification(
                    for:
                        .coverAddText
                ),
            .reversibleMutation
        )

        XCTAssertEqual(
            BOLDCommandSafety
                .classification(
                    for:
                        .publishingExportPDF
                ),
            .filesystemWrite
        )
    }

    func testFilesystemWriteEnvelopeRequiresApproval()
    {
        let action =
            BOLDProjectAction(
                kind:
                    .publishingExportPDF,
                workspace:
                    .publishing,
                source:
                    .artificialIntelligence,
                arguments: [
                    "path":
                        "/tmp/book.pdf"
                ]
            )

        XCTAssertTrue(
            BOLDCommandEnvelope(
                action: action
            )
            .requiresExplicitWriteApproval
        )
    }

    func testReversibleMutationDoesNotRequireWriteApproval()
    {
        let action =
            BOLDProjectAction(
                kind:
                    .coverAddText,
                workspace: .cover,
                source:
                    .artificialIntelligence,
                arguments: [
                    "text": "Title"
                ]
            )

        XCTAssertFalse(
            BOLDCommandEnvelope(
                action: action
            )
            .requiresExplicitWriteApproval
        )
    }
}
