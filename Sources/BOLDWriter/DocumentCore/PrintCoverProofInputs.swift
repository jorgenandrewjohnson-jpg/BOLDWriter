import Foundation

/// Editable printer-specified values for a physical paperback cover guide.
/// Defaults are illustrative; actual interior page count must be entered.
struct BOLDPrintCoverProofInputs: Equatable {
    var pageCount = ""
    var trimWidth = "6"
    var trimHeight = "9"
    var caliperMils = "4"
    var bleedInches = "0.125"
    var safeInsetInches = "0.25"
    var spineAllowanceInches = "0"

    enum InputError: Error, LocalizedError {
        case invalid(String)

        var errorDescription: String? {
            switch self {
            case .invalid(let field):
                return "Enter a valid \(field) before exporting."
            }
        }
    }

    struct Validated {
        let geometry: BOLDPrintCoverGeometry.Result
        let safeInsetInches: Double
    }

    /// Populate only dimensions learned from the selected PDF.
    /// Printer-specific settings stay unchanged.
    mutating func apply(_ inspection: BOLDInteriorPDFInspection.Result) {
        pageCount = String(inspection.pageCount)

        trimWidth = String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            inspection.trimWidthInches
        )

        trimHeight = String(
            format: "%.4f",
            locale: Locale(identifier: "en_US_POSIX"),
            inspection.trimHeightInches
        )
    }

    func validate() throws -> Validated {
        func decimal(_ text: String, field: String) throws -> Double {
            guard let value = Double(
                text.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            ), value.isFinite else {
                throw InputError.invalid(field)
            }

            return value
        }

        guard let pages = Int(
            pageCount.trimmingCharacters(
                in: .whitespacesAndNewlines
            )
        ) else {
            throw InputError.invalid(
                "interior page count"
            )
        }

        let width = try decimal(
            trimWidth,
            field: "trim width"
        )

        let height = try decimal(
            trimHeight,
            field: "trim height"
        )

        let caliper = try decimal(
            caliperMils,
            field: "paper caliper"
        )

        let bleed = try decimal(
            bleedInches,
            field: "bleed"
        )

        let safe = try decimal(
            safeInsetInches,
            field: "safe inset"
        )

        let allowance = try decimal(
            spineAllowanceInches,
            field: "spine allowance"
        )

        let geometry = try BOLDPrintCoverGeometry.calculate(
            pageCount: pages,
            trimWidthInches: width,
            trimHeightInches: height,
            sheetCaliperMils: caliper,
            bleedInches: bleed,
            spineAllowanceInches: allowance
        )

        guard safe >= 0,
              safe * 2 < geometry.trimWidthInches,
              safe * 2 < geometry.trimHeightInches else {
            throw InputError.invalid(
                "safe inset"
            )
        }

        return Validated(
            geometry: geometry,
            safeInsetInches: safe
        )
    }
}
