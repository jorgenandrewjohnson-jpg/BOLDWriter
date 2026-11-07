import AppKit
import XCTest
@testable import BOLDWriter

final class DOCXNUMPAGESTests: XCTestCase {
    private func fields(
        in text: NSAttributedString
    ) -> [(WordField, NSRange)] {
        var values:
            [(WordField, NSRange)] = []

        guard
            text.length > 0
        else {
            return values
        }

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

            if let field =
                value as? WordField {
                values.append(
                    (
                        field,
                        range
                    )
                )
            }
        }

        return values
    }

    func testIndependentComplexNUMPAGESRoundTripsTwice()
        throws
    {
        let fixture =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        "UEsDBBQAAAAIAO+CPF2dxYoq8gAAALkBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbH2QzU7DMBCE73kKy1eUOHBACCXpgZ8jcCgPsLI3iVV7bXnd0r49TgtFQpSjNfPNrKdb7b0TO0xsA/XyummlQNLBWJp6+b5+ru+k4AxkwAXCXh6Q5WqouvUhIosCE/dyzjneK8V6Rg/chIhUlDEkD7k806Qi6A1MqG7a9lbpQBkp13nJkEMlRPeII2xdFk/7opxuSehYioeTd6nrJcTorIZcdLUj86uo/ippCnn08GwjXxWDVJdKFvFyxw/6WiZK1qB4g5RfwBej+gjJKBP01he4+T/pj2vDOFqNZ35JiyloZC7be9ecFQ+Wvn/RqePwQ/UJUEsDBBQAAAAIAO+CPF3U/aHWtQAAADcBAAALAAAAX3JlbHMvLnJlbHONjzkOwjAQRfucYjQ9cUKBEMJJg5DSonAAy54sIl5kmyW3x0UKgigoR2/++/rH+qUneJAPozUcy7xAICOtGk3P8dqeN3uEEIVRYrKGOM4UsK6y44UmEVMmDKMLkCQmcBxidAfGghxIi5BbRyaRznotYjp9z5yQN9ET2xbFjvlPB1YZwEoLjeLoG1ViIgDt7OifCtt1o6STlXdNJv5o+vpY7ML3FDk+rVdMLShPamRpLVvNrbI3UEsDBBQAAAAIAO+CPF3jEXr/HgEAAKECAAARAAAAd29yZC9kb2N1bWVudC54bWydUstOwzAQvPcrLB+RqAsHiqLGVUFpT4WqpDcubrx5SIlt7Zo+/h4nqDlAIwGX1ay8M7MPz+anpmYHQKqsifndeMIZmMzqyhQx36XL20fOyCujVW0NxPwMxOdyNDtG2mYfDRjPgoKh6Bjz0nsXCUFZCY2isXVgwltusVE+pFiIo0Xt0GZAFAyaWtxPJg+iUZXhcsRYUN1bfW5hl7gv1GGUIXRmETmVhVYcAgEegMsnCCbAZiJUyDbid2Je6+dSIetRenZBYg9FsBbXOZUhjymcBkzZy27d8vqyf6lsFqvkjb3fsHWyXSXL1+16kbJfyA4MROAUKg9DM3k5nf59TWD0oODAclTuAcc/rFro+vsSZH6Doju9uNy+RZe/JUefUEsBAhQDFAAAAAgA74I8XZ3FiiryAAAAuQEAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACADvgjxd1P2h1rUAAAA3AQAACwAAAAAAAAAAAAAAgAEjAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACADvgjxd4xF6/x4BAAChAgAAEQAAAAAAAAAAAAAAgAEBAgAAd29yZC9kb2N1bWVudC54bWxQSwUGAAAAAAMAAwC5AAAATgMAAAAA"
                )
            )

        let first =
            try DOCXImporter
                .importedDocument(
                    from:
                        fixture
                )

        XCTAssertTrue(
            first.text.string
                .contains(
                    "Before 77 after."
                )
        )

        let firstField =
            try XCTUnwrap(
                fields(
                    in:
                        first.text
                )
                .first {
                    $0.0.instruction
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )
                        .uppercased()
                        .hasPrefix(
                            "NUMPAGES"
                        )
                }
            )

        XCTAssertEqual(
            firstField.0.kind,
            .complex
        )

        XCTAssertEqual(
            firstField.0.instruction
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                ),
            "NUMPAGES \\* MERGEFORMAT"
        )

        XCTAssertEqual(
            (
                first.text.string
                    as NSString
            )
            .substring(
                with:
                    firstField.1
            ),
            "77"
        )

        let firstExport =
            try DOCXExporter.data(
                from:
                    first.text,
                title:
                    "NUMPAGES Round Trip 1",
                settings:
                    first.page,
                sections:
                    first.sections
            )

        let second =
            try DOCXImporter
                .importedDocument(
                    from:
                        firstExport
                )

        let secondField =
            try XCTUnwrap(
                fields(
                    in:
                        second.text
                )
                .first {
                    $0.0.instruction
                        .uppercased()
                        .contains(
                            "NUMPAGES"
                        )
                }
            )

        XCTAssertEqual(
            secondField.0.instruction,
            firstField.0.instruction
        )

        XCTAssertEqual(
            (
                second.text.string
                    as NSString
            )
            .substring(
                with:
                    secondField.1
            ),
            "77"
        )

        let secondExport =
            try DOCXExporter.data(
                from:
                    second.text,
                title:
                    "NUMPAGES Round Trip 2",
                settings:
                    second.page,
                sections:
                    second.sections
            )

        let third =
            try DOCXImporter
                .importedDocument(
                    from:
                        secondExport
                )

        let thirdField =
            try XCTUnwrap(
                fields(
                    in:
                        third.text
                )
                .first {
                    $0.0.instruction
                        .uppercased()
                        .contains(
                            "NUMPAGES"
                        )
                }
            )

        XCTAssertEqual(
            thirdField.0.instruction,
            firstField.0.instruction
        )

        XCTAssertEqual(
            (
                third.text.string
                    as NSString
            )
            .substring(
                with:
                    thirdField.1
            ),
            "77"
        )

        print(
            "NUMPAGES_DOCX_ROUNDTRIP "
            + "visible=\(third.text.string) "
            + "instruction=\(thirdField.0.instruction)"
        )
    }
}
