# BOLD Writer — Paperback Flat-Wrap Cover Geometry

The shared `BOLDPrintCoverGeometry` Swift model calculates physical paperback cover artwork dimensions and panel positions.

The same model powers the command-line interface and can be used by the Cover Creator, 3D artwork mapper, and Publishing workspace.

## Example

    Scripts/bold cover-geometry --pages 300 --trim 6x9 --caliper-mils 4 --bleed 0.125 --json

## Inputs

- `--pages`: Final PDF interior page count.
- `--trim`: Finished page width and height in inches.
- `--caliper-mils`: Physical paper sheet thickness in thousandths of an inch.
- `--bleed`: Outside bleed in inches.
- `--spine-allowance`: Optional printer-specified spine allowance in inches.
- `--json`: Emit structured JSON suitable for other BOLD Writer components.

The operator must supply the actual paper caliper, bleed, and binding allowance. No universal printer-specific formula or paper stock is assumed.

One physical sheet contains two printed pages. Odd page counts require rounding upward to another sheet.

The flat artwork arrangement is:

    BACK | SPINE | FRONT

Coordinates are measured from the lower-left corner of the entire flat artwork, in inches. Panel coordinates exclude outside bleed.

The JSON preserves unrounded numeric values.

## Restrictions

This model is designed for paperback flat-wrap covers.

Hardcover cases, dust jackets, hinges, boards, and turn-ins require additional geometry and should not use this formula without adaptation.

This calculation does not independently certify print readiness.

Validate the interior PDF using:

    Scripts/bold pdf-preflight

Confirm the finished specifications with the intended printer.

## Automated verification

- `Tests/BOLDWriterTests/PrintCoverGeometryTests.swift`
- `Scripts/tests/test-cover-geometry.py`
