#!/usr/bin/env python3
"""Disposable end-to-end tests for native PDF preflight."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile

REPO = Path(__file__).resolve().parents[2]
BINARY = Path(sys.argv[1]) if len(sys.argv) > 1 else None
RUNNER = REPO / "Scripts/bold"
COUNT = 0

def make_pdf(path, pages):
    objects = [b"<< /Type /Catalog /Pages 2 0 R >>"]
    kids = " ".join(str(3 + 2*i) + " 0 R" for i in range(len(pages)))
    objects.append(f"<< /Type /Pages /Kids [{kids}] /Count {len(pages)} >>".encode())

    for definition in pages:
        media = definition.get("media", (0, 0, 432, 648))
        trim = definition.get("trim")
        rotation = definition.get("rotation", 0)
        page_id = len(objects) + 1
        contents_id = page_id + 1
        extra = ""

        if trim is not None:
            extra += " /TrimBox [" + " ".join(map(str, trim)) + "]"
        if rotation:
            extra += f" /Rotate {rotation}"

        objects.append((
            f"<< /Type /Page /Parent 2 0 R /MediaBox ["
            + " ".join(map(str, media))
            + f"]{extra} /Resources << >> /Contents {contents_id} 0 R >>"
        ).encode())
        objects.append(b"<< /Length 0 >>\nstream\n\nendstream")

    result = bytearray(b"%PDF-1.4\n%\xe2\xe3\xcf\xd3\n")
    positions = [0]

    for index, item in enumerate(objects, 1):
        positions.append(len(result))
        result.extend(f"{index} 0 obj\n".encode() + item + b"\nendobj\n")

    start_xref = len(result)
    result.extend(f"xref\n0 {len(positions)}\n0000000000 65535 f \n".encode())

    for position in positions[1:]:
        result.extend(f"{position:010d} 00000 n \n".encode())

    result.extend(
        f"trailer\n<< /Root 1 0 R /Size {len(positions)} >>\nstartxref\n{start_xref}\n%%EOF\n".encode()
    )
    path.write_bytes(result)

def case(name, args, expected_code, marker=None, json_status=None, issue=None, via_router=False):
    global COUNT
    invocation = (
        [str(RUNNER), "pdf-preflight"] if via_router else [str(BINARY)]
    ) + [str(arg) for arg in args]

    result = subprocess.run(
        invocation,
        cwd=REPO,
        text=True,
        capture_output=True,
        errors="replace",
        timeout=150
    )

    output = result.stdout + "\n" + result.stderr

    if result.returncode != expected_code or (
        marker is not None and marker not in output
    ):
        print(f"SMOKE_FAIL={name}: expected={expected_code}, observed={result.returncode}")
        print(output[-3000:])
        raise SystemExit(1)

    if json_status is not None:
        try:
            report = json.loads(result.stdout)
        except Exception as error:
            raise SystemExit(f"SMOKE_FAIL={name}: invalid JSON: {error}\n{output[-2000:]}")

        if report.get("status") != json_status or report.get("schemaVersion") != 2:
            raise SystemExit(f"SMOKE_FAIL={name}: unexpected report fields {report!r}")

        if issue and not any(
            item.get("code") == issue for item in report.get("issues", [])
        ):
            raise SystemExit(f"SMOKE_FAIL={name}: issue {issue} absent: {report!r}")

    COUNT += 1
    print("SMOKE_PASS=" + name)

if BINARY is None or not BINARY.is_file():
    raise SystemExit("PDF_PREFLIGHT_TEST_BINARY_MISSING")

with tempfile.TemporaryDirectory(prefix="bold-production-pdf-") as directory:
    home = Path(directory)
    good = home / "Interior résumé.pdf"
    odd = home / "Odd.pdf"
    mixed = home / "Mixed media.pdf"
    with_bleed = home / "Bleed.pdf"
    tiny_bleed = home / "Tiny bleed.pdf"
    trim_mixed = home / "Mixed trim.pdf"
    rotated = home / "Rotated.pdf"
    broken = home / "Broken.pdf"

    make_pdf(good, [{}, {}])
    make_pdf(odd, [{}])
    make_pdf(mixed, [{}, {"media": (0,0,360,576)}])
    make_pdf(with_bleed, [{"media": (0,0,450,666), "trim": (9,9,441,657)}])
    make_pdf(tiny_bleed, [{"media": (0,0,444,660), "trim": (6,6,438,654)}])
    make_pdf(
        trim_mixed,
        [
            {"media": (0,0,450,666), "trim": (9,9,441,657)},
            {"media": (0,0,450,666), "trim": (9,9,441,648)}
        ]
    )
    make_pdf(rotated, [{"rotation": 90}])
    broken.write_bytes(b"this is not a PDF")

    case("help", ["--help"], 0, "Usage:")
    case("classic_valid", [good, "--trim", "6x9", "--min-pages", "2"], 0, "PREFLIGHT_RESULT=PASS")
    case("wrong_trim", [good, "--trim", "5x8"], 3, "TRIM_MISMATCH")
    case("mixed_media", [mixed], 3, "MIXED_MEDIA_SIZE")
    case("odd_even_required", [odd, "--require-even-pages"], 3, "ODD_PAGE_COUNT")
    case("invalid_pdf", [broken], 2, "UNREADABLE_PDF")
    case("missing_pdf", [home / "Missing.pdf"], 2, "UNREADABLE_PDF")
    case("invalid_trim", [good, "--trim", "not-a-size"], 2, "INVALID_ARGUMENTS")
    case("json_valid", [good, "--trim", "6x9", "--json"], 0, json_status="PASS")
    case("json_wrong_trim", [good, "--trim", "4x7", "--json"], 3, json_status="FAIL", issue="TRIM_MISMATCH")
    case("json_unreadable", [broken, "--json"], 2, json_status="UNREADABLE_PDF", issue="UNREADABLE_PDF")
    case("json_invalid_args", [good, "--bleed", "bad", "--json"], 2, json_status="INVALID_ARGUMENTS", issue="ARGUMENTS")
    case("bleed_success", [with_bleed, "--trim", "6x9", "--bleed", "0.125"], 0, "PREFLIGHT_RESULT=PASS")
    case("bleed_missing", [good, "--bleed", "0.125"], 3, "BLEED_INSUFFICIENT")
    case("bleed_short", [tiny_bleed, "--bleed", "0.125", "--json"], 3, json_status="FAIL", issue="BLEED_INSUFFICIENT")
    case("bleed_invalid_zero", [good, "--bleed", "0"], 2, "INVALID_ARGUMENTS")
    case("bleed_invalid_nonfinite", [good, "--bleed", "inf"], 2, "INVALID_ARGUMENTS")
    case("max_pages_pass", [good, "--max-pages", "2"], 0, "PREFLIGHT_RESULT=PASS")
    case("max_pages_fail", [good, "--max-pages", "1", "--json"], 3, json_status="FAIL", issue="PAGE_COUNT_ABOVE_MAX")
    case("min_above_max", [good, "--min-pages", "3", "--max-pages", "2"], 2, "INVALID_ARGUMENTS")
    case("mixed_trim", [trim_mixed, "--json"], 3, json_status="FAIL", issue="MIXED_TRIM_SIZE")
    case("rotated_warning", [rotated], 0, "ROTATED_PAGE")
    case("unicode_cli_route", [good, "--json"], 0, json_status="PASS", via_router=True)
    case("min_page_constraint", [odd, "--min-pages", "2"], 3, "PAGE_COUNT_BELOW_MIN")
    case("invalid_max_zero", [good, "--max-pages", "0"], 2, "INVALID_ARGUMENTS")

print(f"PDF_PREFLIGHT_SMOKE={COUNT}_CASES_PASSED")
