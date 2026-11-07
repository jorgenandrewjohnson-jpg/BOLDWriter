#!/usr/bin/env python3
"""End-to-end BOLD Writer paperback cover geometry acceptance tests."""

import json
import math
from pathlib import Path
import subprocess
import sys

binary = Path(sys.argv[1])
router = Path(sys.argv[2])
count = 0

base = [
    "--pages", "300",
    "--trim", "6x9",
    "--caliper-mils", "4",
    "--bleed", "0.125",
]

def check(name, args, expected, key=None, via_router=False):
    global count

    command = (
        [str(router), "cover-geometry"]
        if via_router
        else [str(binary)]
    ) + args

    result = subprocess.run(
        command,
        capture_output=True,
        text=True,
        timeout=180,
    )

    output = result.stdout + result.stderr

    if result.returncode != expected or (
        key is not None and key not in output
    ):
        raise AssertionError(
            f"{name}: exit={result.returncode} "
            f"expected={expected}, output={output[-2000:]}"
        )

    count += 1
    print("COVER_GEOMETRY_CASE=" + name + ":PASS")

    return result.stdout

check("help", ["--help"], 0, "Usage:")

check(
    "valid_text",
    base,
    0,
    "FULL_COVER_WIDTH_INCHES=12.85000",
)

raw = check(
    "valid_json",
    base + ["--json"],
    0,
)

report = json.loads(raw)

assert report["schemaVersion"] == 1
assert report["sheetCount"] == 150
assert math.isclose(report["spineWidthInches"], 0.6)
assert math.isclose(report["totalCoverHeightInches"], 9.25)
assert math.isclose(report["back"]["xInches"], 0.125)
assert math.isclose(report["spine"]["xInches"], 6.125)
assert math.isclose(report["front"]["xInches"], 6.725)

raw = check(
    "odd_page_roundup",
    [
        "--pages", "301",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "0.125",
        "--json",
    ],
    0,
)

assert json.loads(raw)["sheetCount"] == 151

raw = check(
    "explicit_allowance",
    base + [
        "--spine-allowance", "0.02",
        "--json",
    ],
    0,
)

assert math.isclose(
    json.loads(raw)["spineWidthInches"],
    0.62,
)

raw = check(
    "bleed_zero",
    [
        "--pages", "300",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "0",
        "--json",
    ],
    0,
)

assert math.isclose(
    json.loads(raw)["totalCoverWidthInches"],
    12.6,
)

check(
    "zero_pages",
    [
        "--pages", "0",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "0.125",
    ],
    2,
    "COVER_GEOMETRY_ERROR=",
)

check(
    "negative_caliper",
    [
        "--pages", "300",
        "--trim", "6x9",
        "--caliper-mils", "-4",
        "--bleed", "0.125",
    ],
    2,
)

check(
    "infinite_caliper",
    [
        "--pages", "300",
        "--trim", "6x9",
        "--caliper-mils", "inf",
        "--bleed", "0.125",
    ],
    2,
)

check(
    "nan_trim",
    [
        "--pages", "300",
        "--trim", "nanx9",
        "--caliper-mils", "4",
        "--bleed", "0.125",
    ],
    2,
)

check(
    "negative_bleed",
    [
        "--pages", "300",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "-0.1",
    ],
    2,
)

check(
    "huge_bleed",
    [
        "--pages", "300",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "5",
    ],
    2,
)

check(
    "invalid_allowance",
    base + [
        "--spine-allowance", "-0.1",
    ],
    2,
)

check(
    "duplicate_flag",
    base + [
        "--pages", "301",
    ],
    2,
)

check(
    "unknown_flag",
    base + [
        "--binding", "hardcover",
    ],
    2,
)

check(
    "missing_value",
    ["--pages"],
    2,
)

check(
    "invalid_trim",
    [
        "--pages", "300",
        "--trim", "6-9",
        "--caliper-mils", "4",
        "--bleed", "0.125",
    ],
    2,
)

check(
    "negative_page",
    [
        "--pages", "-10",
        "--trim", "6x9",
        "--caliper-mils", "4",
        "--bleed", "0.125",
    ],
    2,
)

check(
    "router_entrypoint",
    base + ["--json"],
    0,
    '"schemaVersion" : 1',
    via_router=True,
)

print(f"COVER_GEOMETRY_SMOKE={count}_CASES_PASSED")
