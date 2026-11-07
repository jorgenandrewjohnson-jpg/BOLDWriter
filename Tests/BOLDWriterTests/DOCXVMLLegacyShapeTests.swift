import AppKit
import XCTest
@testable import BOLDWriter

final class DOCXVMLLegacyShapeTests:
    XCTestCase
{
    private struct Fixture {
        let kind: String
        let text: String
        let shapeID: String
        let style: String
        let fill: String
        let stroke: String
        let weight: String
        let inset: String
        let dataBase64: String
    }

    private func fixtures()
        -> [Fixture]
    {
        [
            Fixture(
                kind: "rect",
                text: "VML-RECT-TEXT-92817",
                shapeID: "Rect92817",
                style: "width:144pt;height:72pt",
                fill: "#00FF00",
                stroke: "#FF0000",
                weight: "2pt",
                inset: "4pt,4pt,4pt,4pt",
                dataBase64: "UEsDBBQAAAAIAJyTPF2yT4cB8gAAALgBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQzU7DMBCE73kKa68oceCAEErSAz9H4FAeYGVvEqv+k9ct7dvjtJADUg8crflmZj3d5uisOFBiE3wPt00LgrwK2viph8/ta/0AgjN6jTZ46uFEDJuh6ranSCyK2XMPc87xUUpWMznkJkTyRRlDcpjLM00yotrhRPKube+lCj6Tz3VeMmCoRPdMI+5tFi/HIlxOSWQZxNMFXdp6wBitUZiLLg9e/+mpfzqa4jwzPJvINwUAeaVj0a5XrM73sk8ymsQHpvyGrnDyKyQtdVB7V7zNglbiX9eGcTSK1oQlL6agiLlM72yzKg6N//1FJ8+7D9U3UEsDBBQAAAAIAJyTPF32DOmVtQAAADIBAAALAAAAX3JlbHMvLnJlbHONz8sKwjAQBdB9viLM3qZ1ISKm3YjQrdQPCMk0LTYPkvjo3xvEhRUXLoc7c4a7bx5mojcMcXSWQ1WUQNFKp0arOZy742oLNCZhlZicRQ4zRmhqsj/hJFK+icPoI82IjRyGlPyOsSgHNCIWzqPNSe+CESmPQTMv5EVoZOuy3LDwaUBN6EKlreIQWlUBobSbPf7ju74fJR6cvBq06cebr42XLYLGxOHugmLqHRQZBpaLskXTmjwBUEsDBBQAAAAIAJyTPF2p6ViHZwEAAKACAAARAAAAd29yZC9kb2N1bWVudC54bWx9UlFPgzAQft+vIPVVVrYsTutg0QWeNBqCxldWymikPdJ2wP69LY65uGQPHB8f333Xu+tq3Yvaa5nSHGSIZtMAeUxSKLjchegjS/x75GmTyyKvQbIQHZhG62iy6kgBdC+YNBPPWkhNuhBVxjQEY00rJnI9hYZJ+68EJXJjP9UOd6CKRgFlWtsKosbzILjDIucSjT5tiPZKkqOJLzhVoKE0PgVBWlGfhHBNCGXJKTu+UDTx7Im3UBwscrCJbFAumOg5Tt7S2E/jTbbCjnBRDbG5kDecWkFLFKPG40WIUgse5vezpZvTobYj6nhhKjJbLBrzWDG+qwxZzhuDvJLXNYUaVIhugiBJgsDlKPhmI+u4P7YbkkPkkl1Nw3qzhd7jUjNLW//bswcN3fTbfgPS2L1E/9r8fH0ZevSz+CvzhyNftjsw5x74VHbAru1fKafXB2WipySL06tj1dbtXWG3HTyux6HxakWTH1BLAwQUAAAACACckzxd1eog13kAAACOAAAAHAAAAHdvcmQvX3JlbHMvZG9jdW1lbnQueG1sLnJlbHNNjEEOwiAQAO99Bdm7BT0YY0p76wOMPmBDV2iEhbDE6O/l6HEymZmWT4rqTVX2zBaOowFF7PK2s7fwuK+HCyhpyBvGzGThSwLLPEw3ith6I2EvovqExUJorVy1FhcooYy5EHfzzDVh61i9Luhe6EmfjDnr+v8APQ8/UEsBAhQDFAAAAAgAnJM8XbJPhwHyAAAAuAEAABMAAAAAAAAAAAAAAIABAAAAAFtDb250ZW50X1R5cGVzXS54bWxQSwECFAMUAAAACACckzxd9gzplbUAAAAyAQAACwAAAAAAAAAAAAAAgAEjAQAAX3JlbHMvLnJlbHNQSwECFAMUAAAACACckzxdqelYh2cBAACgAgAAEQAAAAAAAAAAAAAAgAEBAgAAd29yZC9kb2N1bWVudC54bWxQSwECFAMUAAAACACckzxd1eog13kAAACOAAAAHAAAAAAAAAAAAAAAgAGXAwAAd29yZC9fcmVscy9kb2N1bWVudC54bWwucmVsc1BLBQYAAAAABAAEAAMBAABKBAAAAAA="
            ),
            Fixture(
                kind: "roundrect",
                text: "VML-ROUNDRECT-TEXT-92818",
                shapeID: "Round92818",
                style: "width:180pt;height:90pt",
                fill: "#112233",
                stroke: "#445566",
                weight: "3pt",
                inset: "5pt,6pt,7pt,8pt",
                dataBase64: "UEsDBBQAAAAIAJyTPF2yT4cB8gAAALgBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQzU7DMBCE73kKa68oceCAEErSAz9H4FAeYGVvEqv+k9ct7dvjtJADUg8crflmZj3d5uisOFBiE3wPt00LgrwK2viph8/ta/0AgjN6jTZ46uFEDJuh6ranSCyK2XMPc87xUUpWMznkJkTyRRlDcpjLM00yotrhRPKube+lCj6Tz3VeMmCoRPdMI+5tFi/HIlxOSWQZxNMFXdp6wBitUZiLLg9e/+mpfzqa4jwzPJvINwUAeaVj0a5XrM73sk8ymsQHpvyGrnDyKyQtdVB7V7zNglbiX9eGcTSK1oQlL6agiLlM72yzKg6N//1FJ8+7D9U3UEsDBBQAAAAIAJyTPF32DOmVtQAAADIBAAALAAAAX3JlbHMvLnJlbHONz8sKwjAQBdB9viLM3qZ1ISKm3YjQrdQPCMk0LTYPkvjo3xvEhRUXLoc7c4a7bx5mojcMcXSWQ1WUQNFKp0arOZy742oLNCZhlZicRQ4zRmhqsj/hJFK+icPoI82IjRyGlPyOsSgHNCIWzqPNSe+CESmPQTMv5EVoZOuy3LDwaUBN6EKlreIQWlUBobSbPf7ju74fJR6cvBq06cebr42XLYLGxOHugmLqHRQZBpaLskXTmjwBUEsDBBQAAAAIAJyTPF3SENuDewEAALoCAAARAAAAd29yZC9kb2N1bWVudC54bWyFUk1PwzAMve9XVOFKybqxMcpaxEd34ktVQVy7NF0jmrhKsrX79ziFDgQSHOK8vDzbsZ3lZSdrb8e1EaAiEpyMiccVg0KoTUSes5W/IJ6xuSryGhSPyJ4bchmPlm1YANtKruzIwxDKhG1EKmubkFLDKi5zcwINV3hXgpa5xaPe0BZ00Whg3BjMIGs6GY/nVOZCkSHOLiJbrcLPIL4UTIOB0voMZLiT9UEIfwmhLAXjnxuJRx6+eA3FHpGDTYxGO2Pj62T1mCZ++vj8cJsmN9mSOtZZ3dvml08jGAp2oYatKjRn1hNFRFJ3Op8sgr5l+xq71YrCVmGwGDf2ouJiU9nwHDHxSlHXDGrQETkKgslkOnU+Gt74wJ6ezmbz+cC2vXNEpujsMlve2TV0nlCGIz1r7PEc1xmuRS/BErp1dwPK4ojiHxW/3N99letnyWvm9+/+XXnPfA9ED7l7fOjAh16wvxtn46tVlqT/99pgyCdN3dzoMDiHhk8Xj94BUEsDBBQAAAAIAJyTPF3V6iDXeQAAAI4AAAAcAAAAd29yZC9fcmVscy9kb2N1bWVudC54bWwucmVsc02MQQ7CIBAA730F2bsFPRhjSnvrA4w+YENXaISFsMTo7+XocTKZmZZPiupNVfbMFo6jAUXs8razt/C4r4cLKGnIG8bMZOFLAss8TDeK2HojYS+i+oTFQmitXLUWFyihjLkQd/PMNWHrWL0u6F7oSZ+MOev6/wA9Dz9QSwECFAMUAAAACACckzxdsk+HAfIAAAC4AQAAEwAAAAAAAAAAAAAAgAEAAAAAW0NvbnRlbnRfVHlwZXNdLnhtbFBLAQIUAxQAAAAIAJyTPF32DOmVtQAAADIBAAALAAAAAAAAAAAAAACAASMBAABfcmVscy8ucmVsc1BLAQIUAxQAAAAIAJyTPF3SENuDewEAALoCAAARAAAAAAAAAAAAAACAAQECAAB3b3JkL2RvY3VtZW50LnhtbFBLAQIUAxQAAAAIAJyTPF3V6iDXeQAAAI4AAAAcAAAAAAAAAAAAAACAAasDAAB3b3JkL19yZWxzL2RvY3VtZW50LnhtbC5yZWxzUEsFBgAAAAAEAAQAAwEAAF4EAAAAAA=="
            ),
            Fixture(
                kind: "oval",
                text: "VML-OVAL-TEXT-92819",
                shapeID: "Oval92819",
                style: "width:120pt;height:120pt",
                fill: "#ABCDEF",
                stroke: "#123456",
                weight: "1.5pt",
                inset: "3pt,3pt,3pt,3pt",
                dataBase64: "UEsDBBQAAAAIAJyTPF2yT4cB8gAAALgBAAATAAAAW0NvbnRlbnRfVHlwZXNdLnhtbJWQzU7DMBCE73kKa68oceCAEErSAz9H4FAeYGVvEqv+k9ct7dvjtJADUg8crflmZj3d5uisOFBiE3wPt00LgrwK2viph8/ta/0AgjN6jTZ46uFEDJuh6ranSCyK2XMPc87xUUpWMznkJkTyRRlDcpjLM00yotrhRPKube+lCj6Tz3VeMmCoRPdMI+5tFi/HIlxOSWQZxNMFXdp6wBitUZiLLg9e/+mpfzqa4jwzPJvINwUAeaVj0a5XrM73sk8ymsQHpvyGrnDyKyQtdVB7V7zNglbiX9eGcTSK1oQlL6agiLlM72yzKg6N//1FJ8+7D9U3UEsDBBQAAAAIAJyTPF32DOmVtQAAADIBAAALAAAAX3JlbHMvLnJlbHONz8sKwjAQBdB9viLM3qZ1ISKm3YjQrdQPCMk0LTYPkvjo3xvEhRUXLoc7c4a7bx5mojcMcXSWQ1WUQNFKp0arOZy742oLNCZhlZicRQ4zRmhqsj/hJFK+icPoI82IjRyGlPyOsSgHNCIWzqPNSe+CESmPQTMv5EVoZOuy3LDwaUBN6EKlreIQWlUBobSbPf7ju74fJR6cvBq06cebr42XLYLGxOHugmLqHRQZBpaLskXTmjwBUEsDBBQAAAAIAJyTPF1rN48LbgEAAKMCAAARAAAAd29yZC9kb2N1bWVudC54bWx9UlFPwyAQft+vaPDVjq3qstW1Zmr7NDNjpvG1o3QlAkcA2+7fC926GE32wPFxfHfHd8fyoRM8aKg2DGSCpuMJCqgkUDK5T9D7Ng/nKDC2kGXBQdIEHahBD+lo2cYlkG9BpR0FLoU0cZug2loVY2xITUVhxqCodHcVaFFYd9R73IIulQZCjXEVBMfRZDLDomASDXmaBH1rGZ+ShIIRDQYqGxIQcSP4mQiXiFBVjNDThtJR4F68g/LgkIcqdUZ7Y9PHLN+8ZeHmY7VeYu/wVvdW/aMrRhyhiaEpeMDKBG0cWETz6cL36cBdi1pW2jqeRhNl72vK9rU9HlBQMc4JcNAJulo9Pj1nuQ/S8EUH7zS6ub2bDd62j/ZjuXPhvqylnd1BFzBpqLu4Ufb610K9oG7XPYG0bjTpH6UfL+teZrjNPrdh/+r/invP7xz4XLbHXvmR2rfiQq9susq32dvFzhpK7KvGfkB4mJBHw+9KRz9QSwMEFAAAAAgAnJM8XdXqINd5AAAAjgAAABwAAAB3b3JkL19yZWxzL2RvY3VtZW50LnhtbC5yZWxzTYxBDsIgEADvfQXZuwU9GGNKe+sDjD5gQ1dohIWwxOjv5ehxMpmZlk+K6k1V9swWjqMBRezytrO38Livhwsoacgbxsxk4UsCyzxMN4rYeiNhL6L6hMVCaK1ctRYXKKGMuRB388w1YetYvS7oXuhJn4w56/r/AD0PP1BLAQIUAxQAAAAIAJyTPF2yT4cB8gAAALgBAAATAAAAAAAAAAAAAACAAQAAAABbQ29udGVudF9UeXBlc10ueG1sUEsBAhQDFAAAAAgAnJM8XfYM6ZW1AAAAMgEAAAsAAAAAAAAAAAAAAIABIwEAAF9yZWxzLy5yZWxzUEsBAhQDFAAAAAgAnJM8XWs3jwtuAQAAowIAABEAAAAAAAAAAAAAAIABAQIAAHdvcmQvZG9jdW1lbnQueG1sUEsBAhQDFAAAAAgAnJM8XdXqINd5AAAAjgAAABwAAAAAAAAAAAAAAIABngMAAHdvcmQvX3JlbHMvZG9jdW1lbnQueG1sLnJlbHNQSwUGAAAAAAQABAADAQAAUQQAAAAA"
            )
        ]
    }

    private func documentXML(
        _ data: Data
    ) throws -> String {
        let directory =
            FileManager.default
                .temporaryDirectory
                .appendingPathComponent(
                    UUID().uuidString,
                    isDirectory: true
                )

        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )

        defer {
            try? FileManager.default.removeItem(
                at: directory
            )
        }

        let file =
            directory.appendingPathComponent(
                "vml-shape.docx"
            )

        try data.write(to: file)

        let process = Process()

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

        let output = Pipe()
        process.standardOutput = output

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
            encoding: .utf8
        )
        ?? ""
    }

    private func shape(
        in text: NSAttributedString,
        containing needle: String
    ) throws -> WordVMLShape {
        let range =
            (
                text.string
                as NSString
            )
            .range(of: needle)

        XCTAssertNotEqual(
            range.location,
            NSNotFound
        )

        return try XCTUnwrap(
            text.attribute(
                .boldWriterWordVMLShape,
                at: range.location,
                effectiveRange: nil
            )
            as? WordVMLShape
        )
    }

    private func assertShape(
        _ shape: WordVMLShape,
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(
            shape.shapeKind.lowercased(),
            fixture.kind,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.shapeID,
            fixture.shapeID,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.style,
            fixture.style,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.fillColor,
            fixture.fill,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.strokeColor,
            fixture.stroke,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.strokeWeight,
            fixture.weight,
            file: file,
            line: line
        )

        XCTAssertEqual(
            shape.textBoxInset,
            fixture.inset,
            file: file,
            line: line
        )
    }

    private func assertXML(
        _ xml: String,
        fixture: Fixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            xml.contains("<w:pict"),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(
                "<v:\(fixture.kind)"
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains("<v:textbox"),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains("<w:txbxContent>"),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(fixture.text),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(
                "id=\"\(fixture.shapeID)\""
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(
                "style=\"\(fixture.style)\""
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.localizedCaseInsensitiveContains(
                "fillcolor=\"\(fixture.fill)\""
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.localizedCaseInsensitiveContains(
                "strokecolor=\"\(fixture.stroke)\""
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(
                "strokeweight=\"\(fixture.weight)\""
            ),
            file: file,
            line: line
        )

        XCTAssertTrue(
            xml.contains(
                "inset=\"\(fixture.inset)\""
            ),
            file: file,
            line: line
        )
    }

    func testVMLTextShapesRoundTripTwice()
        throws
    {
        for fixture in fixtures() {
            let source =
                try XCTUnwrap(
                    Data(
                        base64Encoded:
                            fixture.dataBase64
                    )
                )

            let firstImport =
                try DOCXImporter
                    .importedDocument(
                        from: source
                    )

            XCTAssertTrue(
                firstImport.text.string.contains(
                    "BEFORE-"
                    + fixture.kind.uppercased()
                )
            )

            XCTAssertTrue(
                firstImport.text.string.contains(
                    fixture.text
                )
            )

            XCTAssertTrue(
                firstImport.text.string.contains(
                    "AFTER-"
                    + fixture.kind.uppercased()
                )
            )

            let firstShape =
                try shape(
                    in: firstImport.text,
                    containing: fixture.text
                )

            assertShape(
                firstShape,
                fixture: fixture
            )

            let firstExport =
                try DOCXExporter.data(
                    from: firstImport.text,
                    title:
                        "VML \(fixture.kind)",
                    settings:
                        firstImport.page,
                    sections:
                        firstImport.sections
                )

            let firstXML =
                try documentXML(firstExport)

            assertXML(
                firstXML,
                fixture: fixture
            )

            let secondImport =
                try DOCXImporter
                    .importedDocument(
                        from: firstExport
                    )

            let secondShape =
                try shape(
                    in: secondImport.text,
                    containing: fixture.text
                )

            assertShape(
                secondShape,
                fixture: fixture
            )

            let secondExport =
                try DOCXExporter.data(
                    from: secondImport.text,
                    title:
                        "VML \(fixture.kind) cycle 2",
                    settings:
                        secondImport.page,
                    sections:
                        secondImport.sections
                )

            let secondXML =
                try documentXML(secondExport)

            assertXML(
                secondXML,
                fixture: fixture
            )

            print(
                "VML_SHAPE_ROUNDTRIP"
                + "|kind=\(fixture.kind)"
                + "|id=\(secondShape.shapeID ?? "")"
                + "|style=\(secondShape.style ?? "")"
                + "|fill=\(secondShape.fillColor ?? "")"
                + "|stroke=\(secondShape.strokeColor ?? "")"
                + "|weight=\(secondShape.strokeWeight ?? "")"
                + "|inset=\(secondShape.textBoxInset ?? "")"
            )
        }
    }

    func testVMLShapeMetadataSurvivesNativeBOLDPackage()
        throws
    {
        let fixture =
            try XCTUnwrap(
                fixtures()
                    .first {
                        $0.kind == "roundrect"
                    }
            )

        let source =
            try XCTUnwrap(
                Data(
                    base64Encoded:
                        fixture.dataBase64
                )
            )

        let imported =
            try DOCXImporter
                .importedDocument(
                    from: source
                )

        let package =
            try BOLDWriterDocument
                .packageWrapper(
                    text: imported.text,
                    metadata:
                        DocumentMetadata(
                            title:
                                "VML Native Round Trip"
                        )
                )

        let reopened =
            try BOLDWriterDocument(
                fileWrapper: package,
                contentType:
                    .boldWriterDocument
            )

        let restoredShape =
            try shape(
                in: reopened.text,
                containing: fixture.text
            )

        assertShape(
            restoredShape,
            fixture: fixture
        )

        let exported =
            try DOCXExporter.data(
                from: reopened.text,
                title:
                    "VML Native Export",
                settings:
                    reopened.metadata.page,
                sections:
                    reopened.metadata.sections
            )

        let xml =
            try documentXML(exported)

        assertXML(
            xml,
            fixture: fixture
        )

        print(
            "VML_SHAPE_NATIVE"
            + "|kind=\(restoredShape.shapeKind)"
            + "|id=\(restoredShape.shapeID ?? "")"
            + "|text=\(fixture.text)"
        )
    }
}
