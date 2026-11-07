import Foundation
import PDFKit
import CoreGraphics

/// Read-only inspection of an interior PDF before calculating a print cover.
/// Verifies consistent physical trim dimensions across every page.
enum BOLDInteriorPDFInspection {
    struct Result: Equatable {
        let pageCount: Int
        let trimWidthInches: Double
        let trimHeightInches: Double
    }

    enum InspectionError: LocalizedError {
        case notPDF
        case unreadable
        case invalidPage(Int)
        case inconsistentTrim(Int)
        case rotatedPage(Int)
        case trimOutsideMedia(Int)
        case unsupportedPageCount

        var errorDescription: String? {
            switch self {
            case .notPDF:
                return "Select a PDF interior document."
            case .unreadable:
                return "The selected PDF could not be opened or is locked."
            case .invalidPage(let number):
                return "Page \(number) has invalid physical dimensions."
            case .inconsistentTrim(let number):
                return "Page \(number) has a different trim size. Use a consistent interior PDF."
            case .rotatedPage(let number):
                return "Page \(number) is rotated by 90 or 270 degrees. Normalize the interior before calculating the cover."
            case .trimOutsideMedia(let number):
                return "Page \(number) has a TrimBox outside its MediaBox."
            case .unsupportedPageCount:
                return "The interior must contain between 1 and 1000000 pages."
            }
        }
    }

    static func inspect(url: URL) throws -> Result {
        let fileURL = url.standardizedFileURL

        guard fileURL.isFileURL,
              fileURL.pathExtension.lowercased() == "pdf" else {
            throw InspectionError.notPDF
        }

        let accessible = fileURL.startAccessingSecurityScopedResource()

        defer {
            if accessible {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let document = PDFDocument(url: fileURL),
              !document.isLocked else {
            throw InspectionError.unreadable
        }

        guard (1...1_000_000).contains(document.pageCount) else {
            throw InspectionError.unsupportedPageCount
        }

        let rawDocument = CGPDFDocument(fileURL as CFURL)
        let tolerance = 0.5
        var first: (width: Double, height: Double)?

        for index in 0..<document.pageCount {
            let number = index + 1

            guard let page = document.page(at: index) else {
                throw InspectionError.invalidPage(number)
            }

            if abs(page.rotation % 180) == 90 {
                throw InspectionError.rotatedPage(number)
            }

            let media = page.bounds(for: .mediaBox)
            let trim = page.bounds(for: .trimBox)
            // PDF_RAW_TRIM_GUARD_V2
            // PDFKit may normalize an invalid TrimBox.
            // Examine the original PDF dictionary before trusting it.
            if let originalPDF = rawDocument,
               let rawPage = originalPDF.page(at: number),
               let dictionary = rawPage.dictionary {
                var rawTrim: CGPDFArrayRef?

                if CGPDFDictionaryGetArray(
                    dictionary,
                    "TrimBox",
                    &rawTrim
                ), let rawTrim {
                    guard CGPDFArrayGetCount(rawTrim) == 4 else {
                        throw InspectionError.invalidPage(number)
                    }

                    var coordinates: [Double] = []

                    for item in 0..<4 {
                        var coordinate: CGPDFReal = 0

                        guard CGPDFArrayGetNumber(
                            rawTrim,
                            item,
                            &coordinate
                        ) else {
                            throw InspectionError.invalidPage(number)
                        }

                        coordinates.append(Double(coordinate))
                    }

                    guard coordinates.allSatisfy({ $0.isFinite }),
                          coordinates[2] > coordinates[0],
                          coordinates[3] > coordinates[1] else {
                        throw InspectionError.invalidPage(number)
                    }

                    if coordinates[0] < Double(media.minX) - tolerance ||
                       coordinates[1] < Double(media.minY) - tolerance ||
                       coordinates[2] > Double(media.maxX) + tolerance ||
                       coordinates[3] > Double(media.maxY) + tolerance {
                        throw InspectionError.trimOutsideMedia(number)
                    }
                }
            }

            let values = [
                Double(media.minX),
                Double(media.minY),
                Double(media.maxX),
                Double(media.maxY),
                Double(trim.minX),
                Double(trim.minY),
                Double(trim.maxX),
                Double(trim.maxY)
            ]

            guard values.allSatisfy({ $0.isFinite }),
                  media.width > 0,
                  media.height > 0,
                  trim.width > 0,
                  trim.height > 0 else {
                throw InspectionError.invalidPage(number)
            }

            guard trim.minX >= media.minX - tolerance,
                  trim.minY >= media.minY - tolerance,
                  trim.maxX <= media.maxX + tolerance,
                  trim.maxY <= media.maxY + tolerance else {
                throw InspectionError.trimOutsideMedia(number)
            }

            let width = Double(trim.width)
            let height = Double(trim.height)

            if let initial = first {
                guard abs(width - initial.width) <= tolerance,
                      abs(height - initial.height) <= tolerance else {
                    throw InspectionError.inconsistentTrim(number)
                }
            } else {
                first = (width, height)
            }
        }

        guard let dimensions = first else {
            throw InspectionError.unreadable
        }

        return Result(
            pageCount: document.pageCount,
            trimWidthInches: dimensions.width / 72,
            trimHeightInches: dimensions.height / 72
        )
    }
}
