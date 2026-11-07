import AppKit
import XCTest
@testable import BOLDWriter

final class DOCXTableSemanticsTests:
    XCTestCase
{
    private let semanticFixture =
        Data(
            base64Encoded:
                "UEsDBBQAAAAIAIuYPF2yT4cB8gAAALgBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQzU7DMBCE73kKa68oceCAEErSAz9H4FAeYGVvEqv+k9ct7dvjtJADUg8crflmZj3d5uisOFBiE3wPt00LgrwK2viph8/ta/0AgjN6jTZ46uFEDJuh6ranSCyK2XMPc87xUUpWMznkJkTyRRlDcpjLM00yotrhRPKube+lCj6Tz3VeMmCoRPdMI+5tFi/HIlxOSWQZxNMFXdp6wBitUZiLLg9e/+mpfzqa4jwzPJvINwUAeaVj0a5XrM73sk8ymsQHpvyGrnDyKyQtdVB7V7zNglbiX9eGcTSK1oQlL6agiLlM72yzKg6N//1FJ8+7D9U3UEsDBBQAAAAIAIuYPF32DOmVtQAAADIBAAALAAAAX3JlbHMvLnJlbHONz8sKwjAQBdB9viLM3qZ1ISKm3YjQrdQPCMk0LTYPkvjo3xvEhRUXLoc7c4a7bx5mojcMcXSWQ1WUQNFKp0arOZy742oLNCZhlZicRQ4zRmhqsj/hJFK+icPoI82IjRyGlPyOsSgHNCIWzqPNSe+CESmPQTMv5EVoZOuy3LDwaUBN6EKlreIQWlUBobSbPf7ju74fJR6cvBq06cebr42XLYLGxOHugmLqHRQZBpaLskXTmjwBUEsDBBQAAAAIAIuYPF2EKrYnkgEAAAoFAAARAAAAd29yZC9kb2N1bWVudC54bWy9VFFvgjAQfudXkL5jmcs2NYJBB8sSFaMYnytUJIGWtFXk368FZGZxmT64l8t3vet3d/3ghqNTlupHzHhCiQWeOibQMQlplJDYAuvAM3pA5wKRCKWUYAuUmIORrQ2LQUTDQ4aJ0HRJQfigsMBeiHwAIQ/3OEO8Q3NMZGxHWYaEdFkMC8qinNEQcy4rZCnsmuYrzFBCgK3pknVLo1IiBXNbGqaMsMeu5y9dI3DGU9dYuTNnHnxOVkOoYsqyyubNTbFNFWrgglVO4230QrX6ZppyVHlS5nKq6IQAvMyaopIeRBvfJSccNRlV0Za1Tv9gSdRej6UzoWld5/lF1oF/xhrSlkfRXrTNFtU7hIiIVZ4mAlbjVsdtTljDGp8Djbu5KHht6Crt6KRJTGT4iFILCJq30arYN+cPbWpRAn9h9Lu9bv+qKGeOh7Ubyi8Rs7s6nrjzwF3e2nT94L+IAx8215YKQbO75hr7QeDP/k+MW3p6dz1nPQ3uf+zmx7iyEhxPqXfjRuA4FLVM6rReMgqdl5itfQFQSwMEFAAAAAgAi5g8XdXqINd5AAAAjgAAABwAAAB3b3JkL19yZWxzL2RvY3VtZW50LnhtbC5yZWxzTYxBDsIgEADvfQXZuwU9GGNKe+sDjD5gQ1dohIWwxOjv5ehxMpmZlk+K6k1V9swWjqMBRezytrO38Livhwsoacgbxsxk4UsCyzxMN4rYeiNhL6L6hMVCaK1ctRYXKKGMuRB388w1YetYvS7oXuhJn4w56/r/AD0PP1BLAQIUAxQAAAAIAIuYPF2yT4cB8gAAALgBAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAi5g8XfYM6ZW1AAAAMgEAAAsAAAAAAAAAAAAAAIABIwEAAF9yZWxzLy5yZWxzUEsBAhQDFAAAAAgAi5g8XYQqtieSAQAACgUAABEAAAAAAAAAAAAAAIABAQIAAHdvcmQvZG9jdW1lbnQueG1sUEsBAhQDFAAAAAgAi5g8XdXqINd5AAAAjgAAABwAAAAAAAAAAAAAAIABwgMAAHdvcmQvX3JlbHMvZG9jdW1lbnQueG1sLnJlbHNQSwUGAAAAAAQABAADAQAAdQQAAAAA"
        )!

    private let plainFixture =
        Data(
            base64Encoded:
                "UEsDBBQAAAAIAIuYPF2yT4cB8gAAALgBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQzU7DMBCE73kKa68oceCAEErSAz9H4FAeYGVvEqv+k9ct7dvjtJADUg8crflmZj3d5uisOFBiE3wPt00LgrwK2viph8/ta/0AgjN6jTZ46uFEDJuh6ranSCyK2XMPc87xUUpWMznkJkTyRRlDcpjLM00yotrhRPKube+lCj6Tz3VeMmCoRPdMI+5tFi/HIlxOSWQZxNMFXdp6wBitUZiLLg9e/+mpfzqa4jwzPJvINwUAeaVj0a5XrM73sk8ymsQHpvyGrnDyKyQtdVB7V7zNglbiX9eGcTSK1oQlL6agiLlM72yzKg6N//1FJ8+7D9U3UEsDBBQAAAAIAIuYPF32DOmVtQAAADIBAAALAAAAX3JlbHMvLnJlbHONz8sKwjAQBdB9viLM3qZ1ISKm3YjQrdQPCMk0LTYPkvjo3xvEhRUXLoc7c4a7bx5mojcMcXSWQ1WUQNFKp0arOZy742oLNCZhlZicRQ4zRmhqsj/hJFK+icPoI82IjRyGlPyOsSgHNCIWzqPNSe+CESmPQTMv5EVoZOuy3LDwaUBN6EKlreIQWlUBobSbPf7ju74fJR6cvBq06cebr42XLYLGxOHugmLqHRQZBpaLskXTmjwBUEsDBBQAAAAIAIuYPF3W4+A1aQEAAKkEAAARAAAAd29yZC9kb2N1bWVudC54bWzNVN9vgjAQfuevaPqOZS7b1AgGHSxLdBjF+IxQlQRa0tYh//1aqIQtJnMvZi+X73q97767/hhPznkGPjHjKSU2fOhZEGAS0yQlBxtuQt8cQMBFRJIoowTbsMIcThxjXI4SGp9yTIQBJAXho9KGRyGKEUI8PuI84j1aYCJje8rySEiXHVBJWVIwGmPOZYU8Q33LekZ5lBLoGECy7mhSSaRg4UjDlBHO1PODlWeG7nTumWtv4X6E77P1GKmYsqy2hc4Uu0whDZesdrS3BaWS+mJZslW5UhWyq+QcQdTdNY8qehJtfJ+ecaJ31EVb1mb7G0uTNv0gnRnNmjqPT7IO+jWmSVseRduRzZasIy9uYIMv3Wl326G+1h4AOhd9S/4x7mbOYbA0h/1Bf3h1zheO++uaeR+ht7pVWg3Z/5nqNAjDYHG/wd6i6dXz3c08/PtI9b298mJdX53RjQ+W41g0h6FWmz9Aocsf4xhfUEsDBBQAAAAIAIuYPF3V6iDXeQAAAI4AAAAcAAAAd29yZC9fcmVscy9kb2N1bWVudC54bWwucmVsc02MQQ7CIBAA730F2bsFPRhjSnvrA4w+YENXaISFsMTo7+XocTKZmZZPiupNVfbMFo6jAUXs8razt/C4r4cLKGnIG8bMZOFLAss8TDeK2HojYS+i+oTFQmitXLUWFyihjLkQd/PMNWHrWL0u6F7oSZ+MOev6/wA9Dz9QSwECFAMUAAAACACLmDxdsk+HAfIAAAC4AQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAIuYPF32DOmVtQAAADIBAAALAAAAAAAAAAAAAACAASMBAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIAIuYPF3W4+A1aQEAAKkEAAARAAAAAAAAAAAAAACAAQECAAB3b3JkL2RvY3VtZW50LnhtbFBLAQIUAxQAAAAIAIuYPF3V6iDXeQAAAI4AAAAcAAAAAAAAAAAAAACAAZkDAAB3b3JkL19yZWxzL2RvY3VtZW50LnhtbC5yZWxzUEsFBgAAAAAEAAQAAwEAAEwEAAAAAA=="
        )!

    private func documentXML(
        _ data:
            Data
    ) throws -> String {
        let directory =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory:
                        true
                )

        try FileManager.default.createDirectory(
            at:
                directory,
            withIntermediateDirectories:
                true
        )

        defer {
            try? FileManager.default.removeItem(
                at:
                    directory
            )
        }

        let file =
            directory.appendingPathComponent(
                "table-semantics.docx"
            )

        try data.write(
            to:
                file
        )

        let process =
            Process()

        process.executableURL =
            URL(
                fileURLWithPath:
                    "/usr/bin/unzip"
            )

        process.arguments =
            [
                "-p",
                file.path,
                "word/document.xml"
            ]

        let output =
            Pipe()

        process.standardOutput =
            output

        try process.run()
        process.waitUntilExit()

        XCTAssertEqual(
            process.terminationStatus,
            0
        )

        return String(
            data:
                output.fileHandleForReading
                    .readDataToEndOfFile(),
            encoding:
                .utf8
        )
        ?? ""
    }

    private func model(
        in text:
            NSAttributedString
    ) throws -> WriterTable {
        try XCTUnwrap(
            Tables.models(
                in:
                    text
            )
            .first
        )
    }

    private func assertSemanticModel(
        _ table:
            WriterTable,
        file:
            StaticString = #filePath,
        line:
            UInt = #line
    ) {
        XCTAssertEqual(
            table.rows,
            2,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            table.columns,
            2,
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            table.verticalAlignments[0][0],
            "top",
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            table.verticalAlignments[0][1],
            "center",
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            table.verticalAlignments[1][0],
            "bottom",
            file:
                file,
            line:
                line
        )

        XCTAssertNil(
            table.verticalAlignments[1][1],
            file:
                file,
            line:
                line
        )

        XCTAssertEqual(
            table.rowCantSplit,
            [
                true,
                false
            ],
            file:
                file,
            line:
                line
        )
    }

    private func assertSemanticXML(
        _ xml:
            String,
        file:
            StaticString = #filePath,
        line:
            UInt = #line
    ) {
        XCTAssertTrue(
            xml.contains(
                "<w:vAlign w:val=\"top\"/>"
            ),
            file:
                file,
            line:
                line
        )

        XCTAssertTrue(
            xml.contains(
                "<w:vAlign w:val=\"center\"/>"
            ),
            file:
                file,
            line:
                line
        )

        XCTAssertTrue(
            xml.contains(
                "<w:vAlign w:val=\"bottom\"/>"
            ),
            file:
                file,
            line:
                line
        )

        XCTAssertTrue(
            xml.contains(
                "<w:cantSplit/>"
            ),
            file:
                file,
            line:
                line
        )
    }

    func testWordTableSemanticsRoundTripTwice()
        throws
    {
        let first =
            try DOCXImporter
                .importedDocument(
                    from:
                        semanticFixture
                )

        XCTAssertTrue(
            first.text.string.contains(
                "BEFORE-TABLE-SEMANTICS"
            )
        )

        XCTAssertTrue(
            first.text.string.contains(
                "AFTER-TABLE-SEMANTICS"
            )
        )

        assertSemanticModel(
            try model(
                in:
                    first.text
            )
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    first.text,
                title:
                    "Word Table Semantics",
                settings:
                    first.page,
                sections:
                    first.sections
            )

        let firstXML =
            try documentXML(
                firstExport
            )

        assertSemanticXML(
            firstXML
        )

        let second =
            try DOCXImporter
                .importedDocument(
                    from:
                        firstExport
                )

        assertSemanticModel(
            try model(
                in:
                    second.text
            )
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    second.text,
                title:
                    "Word Table Semantics Cycle 2",
                settings:
                    second.page,
                sections:
                    second.sections
            )

        let secondXML =
            try documentXML(
                secondExport
            )

        assertSemanticXML(
            secondXML
        )

        print(
            [
                "WORD_TABLE_SEMANTICS",
                "cycles=2",
                "top=true",
                "center=true",
                "bottom=true",
                "cantSplit=true",
            ]
            .joined(
                separator:
                    "|"
            )
        )
    }

    func testWordTableSemanticsSurviveNativeBOLDReopen()
        throws
    {
        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        semanticFixture
                )

        let package =
            try BOLDWriterDocument
                .packageWrapper(
                    text:
                        imported.text,
                    metadata:
                        DocumentMetadata(
                            title:
                                "Word Table Semantics Native"
                        )
                )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper:
                    package,
                contentType:
                    .boldWriterDocument
            )

        let reopenedModel =
            try model(
                in:
                    reopened.text
            )

        assertSemanticModel(
            reopenedModel
        )

        let export =
            try DOCXExporter.data(
                from:
                    reopened.text,
                title:
                    "Word Table Semantics Native Export",
                settings:
                    reopened.metadata.page,
                sections:
                    reopened.metadata.sections
            )

        assertSemanticXML(
            try documentXML(
                export
            )
        )

        print(
            [
                "WORD_TABLE_NATIVE",
                "top=true",
                "center=true",
                "bottom=true",
                "cantSplit=true",
            ]
            .joined(
                separator:
                    "|"
            )
        )
    }

    func testOrdinaryWordTableDoesNotGainSemanticOverrides()
        throws
    {
        let imported =
            try DOCXImporter
                .importedDocument(
                    from:
                        plainFixture
                )

        let table =
            try model(
                in:
                    imported.text
            )

        XCTAssertEqual(
            table.rowCantSplit,
            [
                false,
                false
            ]
        )

        XCTAssertTrue(
            table.verticalAlignments
                .flatMap {
                    $0
                }
                .allSatisfy {
                    $0 == nil
                }
        )

        let export =
            try DOCXExporter.data(
                from:
                    imported.text,
                title:
                    "Ordinary Word Table",
                settings:
                    imported.page,
                sections:
                    imported.sections
            )

        let xml =
            try documentXML(
                export
            )

        XCTAssertFalse(
            xml.contains(
                "<w:vAlign"
            )
        )

        XCTAssertFalse(
            xml.contains(
                "<w:cantSplit"
            )
        )

        print(
            "WORD_TABLE_DEFAULTS|vAlign=false|cantSplit=false"
        )
    }
}
