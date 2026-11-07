import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

@main
enum BOLDCoverProofCLI {
    static func main() {
        exit(
            run(
                Array(
                    CommandLine.arguments.dropFirst()
                )
            )
        )
    }

    static func run(
        _ arguments: [String]
    ) -> Int32 {
        if arguments == ["--help"] ||
           arguments == ["-h"] {
            print(
                "Usage: Scripts/bold cover-proof --pages N --trim WIDTHxHEIGHT --caliper-mils N --bleed INCHES --output PROOF.pdf [--safe-inset INCHES] [--spine-allowance INCHES] [--json]"
            )
            return 0
        }

        var options: [String: String] = [:]
        var json = false
        var position = 0

        let names = Set([
            "--pages",
            "--trim",
            "--caliper-mils",
            "--bleed",
            "--output",
            "--safe-inset",
            "--spine-allowance"
        ])

        while position < arguments.count {
            let name = arguments[position]

            if name == "--json" && !json {
                json = true
                position += 1
                continue
            }

            guard names.contains(name),
                  options[name] == nil,
                  position + 1 < arguments.count else {
                fputs(
                    "COVER_PROOF_ERROR=Invalid or duplicate argument: \(name)\n",
                    stderr
                )
                return 2
            }

            options[name] = arguments[
                position + 1
            ]

            position += 2
        }

        guard let rawPages = options["--pages"],
              let pages = Int(rawPages),
              let trim = options["--trim"],
              let rawCaliper = options["--caliper-mils"],
              let caliper = Double(rawCaliper),
              let rawBleed = options["--bleed"],
              let bleed = Double(rawBleed),
              let output = options["--output"],
              !output.isEmpty,
              let safe = Double(
                  options["--safe-inset"] ?? "0.25"
              ),
              let allowance = Double(
                  options["--spine-allowance"] ?? "0"
              ) else {
            fputs(
                "COVER_PROOF_ERROR=Missing or invalid arguments\n",
                stderr
            )
            return 2
        }

        let parts = trim.lowercased().split(
            separator: "x",
            omittingEmptySubsequences: false
        )

        guard parts.count == 2,
              let width = Double(parts[0]),
              let height = Double(parts[1]) else {
            fputs(
                "COVER_PROOF_ERROR=Trim must be WIDTHxHEIGHT\n",
                stderr
            )
            return 2
        }

        let destination = URL(
            fileURLWithPath: output
        ).standardizedFileURL

        guard destination.pathExtension.lowercased() == "pdf" else {
            fputs(
                "COVER_PROOF_ERROR=Output must end in .pdf\n",
                stderr
            )
            return 2
        }

        do {
            let geometry = try BOLDPrintCoverGeometry.calculate(
                pageCount: pages,
                trimWidthInches: width,
                trimHeightInches: height,
                sheetCaliperMils: caliper,
                bleedInches: bleed,
                spineAllowanceInches: allowance
            )

            try BOLDPrintCoverProofPDF.create(
                geometry: geometry,
                safeInsetInches: safe,
                at: destination
            )

            if json {
                struct Report: Encodable {
                    let schemaVersion: Int
                    let outputPDF: String
                    let guideOnly: Bool
                    let safeInsetInches: Double
                    let geometry: BOLDPrintCoverGeometry.Result
                }

                let report = Report(
                    schemaVersion: 1,
                    outputPDF: destination.path,
                    guideOnly: true,
                    safeInsetInches: safe,
                    geometry: geometry
                )

                let encoder = JSONEncoder()

                encoder.outputFormatting = [
                    .prettyPrinted,
                    .sortedKeys
                ]

                let data = try encoder.encode(
                    report
                )

                guard let text = String(
                    data: data,
                    encoding: .utf8
                ) else {
                    fputs(
                        "COVER_PROOF_ERROR=JSON encoding failed\n",
                        stderr
                    )
                    return 3
                }

                print(text)
            } else {
                print("COVER_PROOF_RESULT=PASS")
                print(
                    "COVER_PROOF_FILE=\(destination.path)"
                )
                print(
                    "COVER_PROOF_GUIDE_ONLY=YES"
                )
                print(
                    "COVER_PROOF_SPINE_INCHES=\(geometry.spineWidthInches)"
                )
            }

            return 0
        } catch {
            fputs(
                "COVER_PROOF_ERROR=\(error)\n",
                stderr
            )
            return 3
        }
    }
}
