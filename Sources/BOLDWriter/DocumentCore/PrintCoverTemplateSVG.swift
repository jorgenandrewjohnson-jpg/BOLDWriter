import Foundation

/// Generates an editable paperback flat-wrap cover guide from
/// BOLD Writer's shared physical print-cover geometry.
enum BOLDPrintCoverTemplateSVG {
    enum TemplateError: Error, CustomStringConvertible {
        case invalidSafeInset

        var description: String {
            switch self {
            case .invalidSafeInset:
                return "Safe inset must be finite, nonnegative, and less than half of each panel dimension"
            }
        }
    }

    static func render(
        geometry: BOLDPrintCoverGeometry.Result,
        safeInsetInches: Double = 0.25
    ) throws -> String {
        guard safeInsetInches.isFinite,
              safeInsetInches >= 0,
              safeInsetInches * 2 < geometry.trimWidthInches,
              safeInsetInches * 2 < geometry.trimHeightInches else {
            throw TemplateError.invalidSafeInset
        }

        func number(_ value: Double) -> String {
            String(
                format: "%.6f",
                locale: Locale(identifier: "en_US_POSIX"),
                value
            )
        }

        func rectangle(
            _ panel: BOLDPrintCoverGeometry.Panel
        ) -> (Double, Double, Double, Double) {
            let x = panel.xInches * 72
            let y = (
                geometry.totalCoverHeightInches
                - panel.yInches
                - panel.heightInches
            ) * 72

            return (
                x,
                y,
                panel.widthInches * 72,
                panel.heightInches * 72
            )
        }

        let pageWidth = geometry.totalCoverWidthInches * 72
        let pageHeight = geometry.totalCoverHeightInches * 72
        let bleed = geometry.bleedInches * 72
        let safe = safeInsetInches * 72

        var lines: [String] = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(geometry.totalCoverWidthInches))in\" height=\"\(number(geometry.totalCoverHeightInches))in\" viewBox=\"0 0 \(number(pageWidth)) \(number(pageHeight))\" role=\"img\" aria-label=\"Paperback wrap template, back, spine and front\">",
            "<title>BOLD Writer — Paperback cover layout guide</title>",
            "<desc>Vector guide only. Remove guide graphics before printing; supplied paper caliper and binding specifications must be confirmed with the printer.</desc>",
            "<rect id=\"bleed-sheet\" x=\"0\" y=\"0\" width=\"\(number(pageWidth))\" height=\"\(number(pageHeight))\" fill=\"#f5f5f5\"/>",
            "<rect id=\"trim-outline\" x=\"\(number(bleed))\" y=\"\(number(bleed))\" width=\"\(number(pageWidth - 2 * bleed))\" height=\"\(number(pageHeight - 2 * bleed))\" fill=\"#ffffff\" stroke=\"#555555\" stroke-width=\"0.6\" stroke-dasharray=\"6 3\"/>"
        ]

        for (name, panel, color) in [
            ("back", geometry.back, "#2066ad"),
            ("spine", geometry.spine, "#a147a3"),
            ("front", geometry.front, "#227b51")
        ] {
            let (x, y, width, height) = rectangle(panel)

            lines.append(
                "<rect id=\"\(name)-panel\" x=\"\(number(x))\" y=\"\(number(y))\" width=\"\(number(width))\" height=\"\(number(height))\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"0.9\"/>"
            )

            if name != "spine" {
                lines.append(
                    "<rect id=\"\(name)-safe\" x=\"\(number(x + safe))\" y=\"\(number(y + safe))\" width=\"\(number(width - 2 * safe))\" height=\"\(number(height - 2 * safe))\" fill=\"none\" stroke=\"\(color)\" stroke-width=\"0.45\" stroke-dasharray=\"3 3\"/>"
                )
            }

            if width >= 48 {
                lines.append(
                    "<text x=\"\(number(x + width / 2))\" y=\"\(number(y + height / 2))\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"14\" font-weight=\"bold\" text-anchor=\"middle\" fill=\"\(color)\">\(name.uppercased())</text>"
                )
            }
        }

        lines.append(
            "<text id=\"remove-before-print\" x=\"\(number(pageWidth / 2))\" y=\"\(number(pageHeight - 3))\" font-family=\"Helvetica,Arial,sans-serif\" font-size=\"6\" text-anchor=\"middle\" fill=\"#9b2525\">GUIDE ONLY — REMOVE BEFORE PRINTING</text>"
        )

        lines.append("</svg>")

        return lines.joined(separator: "\n") + "\n"
    }
}
