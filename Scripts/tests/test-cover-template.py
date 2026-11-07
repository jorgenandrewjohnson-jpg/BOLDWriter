#!/usr/bin/env python3

import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

binary = Path(sys.argv[1])
router = Path(sys.argv[2])

count = 0

base = [
    "--pages", "300",
    "--trim", "6x9",
    "--caliper-mils", "4",
    "--bleed", "0.125"
]

def case(name, args, expected=0, marker=None, routed=False):
    global count

    command = (
        [str(router), "cover-template"]
        if routed
        else [str(binary)]
    ) + args

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=180
    )

    combined = result.stdout + result.stderr

    if (
        result.returncode != expected
        or (marker and marker not in combined)
    ):
        raise AssertionError(
            f"{name}: exit={result.returncode}, "
            f"expected={expected}, output={combined[-1500:]}"
        )

    count += 1
    print("TEMPLATE_CASE=" + name + ":PASS", flush=True)

    return result

with tempfile.TemporaryDirectory(
    prefix="bold-cover-template-"
) as temporary:
    folder = Path(temporary)

    primary = folder / "Cover résumé.svg"

    result = case(
        "physical_6x9_template",
        base + ["--output", str(primary)],
        marker="COVER_TEMPLATE_RESULT=PASS"
    )

    original = primary.read_bytes()
    root = ET.fromstring(original)

    assert root.attrib["width"] == "12.850000in"
    assert root.attrib["height"] == "9.250000in"
    assert root.attrib["viewBox"] == (
        "0 0 925.200000 666.000000"
    )

    namespace = "{http://www.w3.org/2000/svg}"

    identifiers = {
        node.attrib.get("id"): node
        for node in root.iter()
        if node.attrib.get("id")
    }

    assert identifiers["back-panel"].attrib["x"] == "9.000000"
    assert identifiers["spine-panel"].attrib["x"] == "441.000000"
    assert identifiers["front-panel"].attrib["x"] == "484.200000"
    assert identifiers["front-safe"].attrib["x"] == "502.200000"

    assert root.find(namespace + "desc") is not None

    case(
        "existing_artwork_not_overwritten",
        base + ["--output", str(primary)],
        expected=3,
        marker="Could not create SVG"
    )

    assert primary.read_bytes() == original

    detailed = folder / "With safe inset.svg"

    result = case(
        "json_and_svg",
        base + [
            "--output", str(detailed),
            "--safe-inset", "0.375",
            "--json"
        ]
    )

    record = json.loads(result.stdout)

    assert record["schemaVersion"] == 1
    assert record["outputSVG"] == str(detailed)

    assert math.isclose(
        record["safeInsetInches"], 0.375
    )

    assert math.isclose(
        record["geometry"]["spineWidthInches"], 0.6
    )

    assert detailed.is_file()
    ET.parse(detailed)

    odd = folder / "Odd pages.svg"

    case(
        "odd_page_spine",
        ["--pages", "301"] + base[2:] + [
            "--output", str(odd)
        ]
    )

    assert 'width="43.488000"' in odd.read_text()

    allowance = folder / "Spine allowance.svg"

    case(
        "printer_spine_allowance",
        base + [
            "--spine-allowance", ".02",
            "--output", str(allowance)
        ]
    )

    assert 'width="44.640000"' in allowance.read_text()

    no_bleed = folder / "Zero bleed.svg"

    case(
        "zero_bleed",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "4",
            "--bleed", "0",
            "--output", str(no_bleed)
        ]
    )

    assert 'width="12.600000in"' in no_bleed.read_text()

    routed = folder / "Routed.svg"

    case(
        "real_command_router",
        base + ["--output", str(routed)],
        marker="COVER_TEMPLATE_RESULT=PASS",
        routed=True
    )

    assert routed.is_file()

    case("help", ["--help"], marker="Usage:")

    case(
        "missing_arguments",
        [],
        expected=2,
        marker="COVER_TEMPLATE_ERROR="
    )

    case(
        "duplicate_output",
        base + [
            "--output", str(folder / "first.svg"),
            "--output", str(folder / "second.svg")
        ],
        expected=2
    )

    case(
        "duplicate_json",
        base + [
            "--output", str(folder / "duplicate.svg"),
            "--json",
            "--json"
        ],
        expected=2
    )

    case(
        "unknown_option",
        base + [
            "--output", str(folder / "unknown.svg"),
            "--invalid", "1"
        ],
        expected=2
    )

    case("missing_output", base, expected=2)

    case(
        "invalid_extension",
        base + [
            "--output", str(folder / "wrong.pdf")
        ],
        expected=2
    )

    for label, value in [
        ("negative_safe", "-1"),
        ("nan_safe", "nan"),
        ("infinite_safe", "inf"),
        ("oversized_safe", "3")
    ]:
        case(
            label,
            base + [
                "--output", str(folder / (label + ".svg")),
                "--safe-inset", value
            ],
            expected=2
        )

    case(
        "zero_page_count",
        ["--pages", "0"] + base[2:] + [
            "--output", str(folder / "zero.svg")
        ],
        expected=2
    )

    case(
        "infinite_caliper",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "inf",
            "--bleed", ".125",
            "--output", str(folder / "infinite.svg")
        ],
        expected=2
    )

    case(
        "nonfinite_trim",
        [
            "--pages", "300",
            "--trim", "nanx9",
            "--caliper-mils", "4",
            "--bleed", ".125",
            "--output", str(folder / "nan.svg")
        ],
        expected=2
    )

    case(
        "negative_bleed",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "4",
            "--bleed", "-1",
            "--output", str(folder / "bleed.svg")
        ],
        expected=2
    )

    case(
        "missing_trim",
        [
            "--pages", "300",
            "--caliper-mils", "4",
            "--bleed", ".125",
            "--output", str(folder / "missing-trim.svg")
        ],
        expected=2
    )

    case(
        "missing_destination_directory",
        base + [
            "--output",
            str(folder / "not-created" / "guide.svg")
        ],
        expected=3
    )

    assert not (folder / "not-created").exists()

print(
    f"COVER_TEMPLATE_SMOKE={count}_CASES_PASSED",
    flush=True
)
