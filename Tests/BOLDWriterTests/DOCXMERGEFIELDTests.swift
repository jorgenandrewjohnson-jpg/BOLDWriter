import AppKit
import XCTest
@testable import BOLDWriter

@MainActor
final class DOCXMERGEFIELDTests:
    XCTestCase
{
    private func normalizedInstruction(
        _ value: String
    ) -> String {
        value
            .split(
                whereSeparator:
                    \.isWhitespace
            )
            .map(
                String.init
            )
            .joined(
                separator:
                    " "
            )
    }

    private func wordFields(
        in text: NSAttributedString
    ) -> [
        (
            field: WordField,
            range: NSRange
        )
    ] {
        guard text.length > 0 else {
            return []
        }

        var result:
            [
                (
                    field: WordField,
                    range: NSRange
                )
            ] = []

        text.enumerateAttribute(
            .boldWriterField,
            in:
                NSRange(
                    location:
                        0,
                    length:
                        text.length
                )
        ) {
            value,
            range,
            _ in

            guard
                let field =
                    value as? WordField,
                range.length > 0
            else {
                return
            }

            result.append(
                (
                    field:
                        field,
                    range:
                        range
                )
            )
        }

        return result
    }

    private func documentXML(
        from data: Data
    ) throws -> String {
        let entries =
            try DOCXPackage.entries(
                in:
                    data
            )

        let document =
            try XCTUnwrap(
                entries.first {
                    $0.path
                        == "word/document.xml"
                }
            )

        return String(
            decoding:
                document.data,
            as:
                UTF8.self
        )
    }

    func testIndependentWordMERGEFIELDRoundTripsThroughTwoDOCXCycles()
        throws
    {
        // Independent Word-style fixture. It is deliberately not
        // produced by DOCXExporter so importer compatibility is tested.
        let fixture =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "UEsDBBQAAAAIADaBPF2dxYoq8gAAALkBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH2QzU7DMBCE73kKy1eUOHBACCXpgZ8jcCgPsLI3iVV7bXnd0r49TgtFQpSjNfPNrKdb7b0TO0xsA/XyummlQNLBWJp6+b5+ru+k4AxkwAXCXh6Q5WqouvUhIosCE/dyzjneK8V6Rg/chIhUlDEkD7k806Qi6A1MqG7a9lbpQBkp13nJkEMlRPeII2xdFk/7opxuSehYioeTd6nrJcTorIZcdLUj86uo/ippCnn08GwjXxWDVJdKFvFyxw/6WiZK1qB4g5RfwBej+gjJKBP01he4+T/pj2vDOFqNZ35JiyloZC7be9ecFQ+Wvn/RqePwQ/UJUEsDBBQAAAAIADaBPF3UXMrItwAAADsBAAALAAAAX3JlbHMvLnJlbHONj8sOgjAQRfd8RTN7KbgwxlDYGBO2Bj+gaYdCpI+09cHf2xgWYly4PLkz5+ZWzVNP5I4+jNYwKPMCCBph5WgUg0t32uyBhMiN5JM1yGDGAE2dVWeceEw/YRhdIEliAoMhRnegNIgBNQ+5dWhS0luveUzoFXVcXLlCui2KHfWfDqgzQlbaxIS0koFvZQlv6maH/9TYvh8FHq24aTTxR9vXxWLnXmFk8LBeUrlEeVIDTYvpanKdvQBQSwMEFAAAAAgANoE8XVYyBX6sAQAAYgQAABEAAAB3b3JkL2RvY3VtZW50LnhtbK1UTU8bMRC951dYPlZqNkQUUJRdRCFBSAQqmt56cdazH9L6Q+MJSfj1jLOwJQpBqO3FevN29r0Ze+zx+do04hEw1M6m8qg/kAJs7nRty1T+mk+/nkkRSFmtGmchlRsI8jzrjVcj7fKlAUs9wRI2jFaprIj8KElCXoFRoe88WP5WODSKOMQyWTnUHl0OIbCDaZLhYHCSGFVb+aqDn9FxRVHncPVSQquC0CjiNkJV+yCznhBc5cLpTYTbwLdoizHjhaLnKHiVc2seIQA+gsy+A3uBGCeckcUVd358wduoaPRlpVB0aL7xrLWAkltiVtdIm1QSLkEmncqHkrUNhHNYHyhOzCYP15Mo0SX+F93pzeT2SsjLZSBnAMWdMiDF7y+t3/T+YXYxF39he2CHAniFij69K5RdNHzkYrJWxjfQns2/FABWf+R9eDqEKgiwvzcdEfpu1gLk9OOtpC9/PnENfE2OhsPjQRyOivG3M8bJTt5MYVc/ezjPacec9YbEuqxon1444sPb5xso3smuQGng63Y63KEL5+gdulzSlu6qjf3+6TJG7WWL6PVxyHrPUEsDBBQAAAAIADaBPF3V6iDXeQAAAI4AAAAcAAAAd29yZC9fcmVscy9kb2N1bWVudC54bWwucmVsc02MQQ7CIBAA730F2bsFPRhjSnvrA4w+YENXaISFsMTo7+XocTKZmZZPiupNVfbMFo6jAUXs8razt/C4r4cLKGnIG8bMZOFLAss8TDeK2HojYS+i+oTFQmitXLUWFyihjLkQd/PMNWHrWL0u6F7oSZ+MOev6/wA9Dz9QSwECFAMUAAAACAA2gTxdncWKKvIAAAC5AQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIADaBPF3UXMrItwAAADsBAAALAAAAAAAAAAAAAACAASMBAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIADaBPF1WMgV+rAEAAGIEAAARAAAAAAAAAAAAAACAAQMCAAB3b3JkL2RvY3VtZW50LnhtbFBLAQIUAxQAAAAIADaBPF3V6iDXeQAAAI4AAAAcAAAAAAAAAAAAAACAAd4DAAB3b3JkL19yZWxzL2RvY3VtZW50LnhtbC5yZWxzUEsFBgAAAAAEAAQAAwEAAJEEAAAAAA=="
                )
            )

        let firstImport =
            try DOCXImporter
                .importedDocument(
                    from:
                        fixture
                )

        XCTAssertEqual(
            firstImport.text.string,
            "Before Alice Example after."
        )

        XCTAssertFalse(
            firstImport.text.string
                .uppercased()
                .contains(
                    "MERGEFIELD"
                )
        )

        let firstFields =
            wordFields(
                in:
                    firstImport.text
            )

        XCTAssertEqual(
            firstFields.count,
            1
        )

        let firstField =
            try XCTUnwrap(
                firstFields.first
            )

        XCTAssertEqual(
            firstField.field.kind,
            .complex
        )

        XCTAssertEqual(
            (
                firstImport.text.string
                    as NSString
            )
            .substring(
                with:
                    firstField.range
            ),
            "Alice Example"
        )

        let firstInstruction =
            normalizedInstruction(
                firstField.field
                    .instruction
            )

        XCTAssertTrue(
            firstInstruction
                .uppercased()
                .hasPrefix(
                    "MERGEFIELD"
                )
        )

        XCTAssertTrue(
            firstInstruction
                .contains(
                    "\"Customer Name\""
                )
        )

        XCTAssertTrue(
            firstInstruction
                .uppercased()
                .contains(
                    "\\* MERGEFORMAT"
                )
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    firstImport.text,
                title:
                    "MERGEFIELD Round Trip",
                settings:
                    firstImport.page,
                sections:
                    firstImport.sections,
                comments:
                    [],
                bookmarks:
                    [],
                namedStyles:
                    []
            )

        let firstXML =
            try documentXML(
                from:
                    firstExport
            )

        XCTAssertTrue(
            firstXML.uppercased()
                .contains(
                    "MERGEFIELD"
                )
        )

        XCTAssertTrue(
            firstXML.contains(
                "Customer Name"
            )
        )

        XCTAssertTrue(
            firstXML.uppercased()
                .contains(
                    "MERGEFORMAT"
                )
        )

        XCTAssertTrue(
            firstXML.contains(
                "fldCharType=\"begin\""
            )
        )

        XCTAssertTrue(
            firstXML.contains(
                "fldCharType=\"separate\""
            )
        )

        XCTAssertTrue(
            firstXML.contains(
                "fldCharType=\"end\""
            )
        )

        XCTAssertTrue(
            firstXML.contains(
                "Alice Example"
            )
        )

        let secondImport =
            try DOCXImporter
                .importedDocument(
                    from:
                        firstExport
                )

        XCTAssertEqual(
            secondImport.text.string,
            firstImport.text.string
        )

        let secondFields =
            wordFields(
                in:
                    secondImport.text
            )

        XCTAssertEqual(
            secondFields.count,
            1
        )

        let secondField =
            try XCTUnwrap(
                secondFields.first
            )

        XCTAssertEqual(
            normalizedInstruction(
                secondField.field
                    .instruction
            ),
            firstInstruction
        )

        XCTAssertEqual(
            (
                secondImport.text.string
                    as NSString
            )
            .substring(
                with:
                    secondField.range
            ),
            "Alice Example"
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    secondImport.text,
                title:
                    "MERGEFIELD Round Trip 2",
                settings:
                    secondImport.page,
                sections:
                    secondImport.sections,
                comments:
                    [],
                bookmarks:
                    [],
                namedStyles:
                    []
            )

        let secondXML =
            try documentXML(
                from:
                    secondExport
            )

        XCTAssertTrue(
            secondXML.uppercased()
                .contains(
                    "MERGEFIELD"
                )
        )

        XCTAssertTrue(
            secondXML.contains(
                "Customer Name"
            )
        )

        XCTAssertTrue(
            secondXML.uppercased()
                .contains(
                    "MERGEFORMAT"
                )
        )

        XCTAssertTrue(
            secondXML.contains(
                "fldCharType=\"begin\""
            )
        )

        XCTAssertTrue(
            secondXML.contains(
                "fldCharType=\"separate\""
            )
        )

        XCTAssertTrue(
            secondXML.contains(
                "fldCharType=\"end\""
            )
        )

        XCTAssertTrue(
            secondXML.contains(
                "Alice Example"
            )
        )

        print(
            "MERGEFIELD_REGRESSION "
            + "visible=\(secondImport.text.string) "
            + "instruction=\(normalizedInstruction(secondField.field.instruction))"
        )
    }
}
