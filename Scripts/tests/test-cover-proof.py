#!/usr/bin/env python3

import json
from pathlib import Path
import subprocess
import sys
import tempfile

binary = Path(sys.argv[1])
router = Path(sys.argv[2])

count = 0

base = [
    "--pages", "300",
    "--trim", "6x9",
    "--caliper-mils", "4",
    "--bleed", "0.125"
]

def case(
    name,
    args,
    expected=0,
    marker=None,
    routed=False
):
    global count

    command = (
        [str(router), "cover-proof"]
        if routed
        else [str(binary)]
    ) + args

    result = subprocess.run(
        command,
        text=True,
        capture_output=True,
        timeout=180
    )

    output = result.stdout + result.stderr

    if (
        result.returncode != expected
        or (
            marker is not None
            and marker not in output
        )
    ):
        raise AssertionError(
            f"{name}: exit {result.returncode} "
            f"expected {expected}\n{output[-1500:]}"
        )

    count += 1

    print(
        f"COVER_PROOF_CASE={name}:PASS",
        flush=True
    )

    return result

with tempfile.TemporaryDirectory(
    prefix="bold-cover-proof-"
) as temporary:
    folder = Path(temporary)

    proof = folder / "Book proof résumé.pdf"

    case(
        "valid",
        base + [
            "--output",
            str(proof)
        ],
        marker="COVER_PROOF_RESULT=PASS"
    )

    assert proof.read_bytes().startswith(
        b"%PDF-"
    )

    assert proof.stat().st_size > 500

    preserved = proof.read_bytes()

    case(
        "overwrite_refused",
        base + [
            "--output",
            str(proof)
        ],
        3,
        "Destination already exists"
    )

    assert proof.read_bytes() == preserved

    data = folder / "JSON proof.pdf"

    result = case(
        "json",
        base + [
            "--output",
            str(data),
            "--json"
        ]
    )

    record = json.loads(result.stdout)

    assert record["schemaVersion"] == 1
    assert record["guideOnly"] is True
    assert record["outputPDF"] == str(data)

    assert abs(
        record["geometry"][
            "totalCoverWidthInches"
        ] - 12.85
    ) < 0.00001

    assert data.read_bytes().startswith(
        b"%PDF-"
    )

    routed = folder / "Routed.pdf"

    case(
        "router",
        base + [
            "--output",
            str(routed)
        ],
        marker="COVER_PROOF_RESULT=PASS",
        routed=True
    )

    assert routed.exists()

    case(
        "help",
        ["--help"],
        marker="Usage:"
    )

    case(
        "missing",
        [],
        2
    )

    case(
        "missing_output",
        base,
        2
    )

    case(
        "duplicate_output",
        base + [
            "--output",
            "a.pdf",
            "--output",
            "b.pdf"
        ],
        2
    )

    case(
        "duplicate_json",
        base + [
            "--output",
            "a.pdf",
            "--json",
            "--json"
        ],
        2
    )

    case(
        "unknown_flag",
        base + [
            "--output",
            "a.pdf",
            "--hardcover",
            "yes"
        ],
        2
    )

    case(
        "wrong_extension",
        base + [
            "--output",
            str(folder / "no.svg")
        ],
        2
    )

    case(
        "zero_pages",
        [
            "--pages",
            "0"
        ] + base[2:] + [
            "--output",
            str(folder / "zero.pdf")
        ],
        3
    )

    case(
        "negative_caliper",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "-1",
            "--bleed", ".125",
            "--output",
            str(folder / "caliper.pdf")
        ],
        3
    )

    case(
        "nan_trim",
        [
            "--pages", "300",
            "--trim", "nanx9",
            "--caliper-mils", "4",
            "--bleed", ".125",
            "--output",
            str(folder / "nan.pdf")
        ],
        3
    )

    case(
        "infinite_caliper",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "inf",
            "--bleed", ".125",
            "--output",
            str(folder / "inf.pdf")
        ],
        3
    )

    case(
        "negative_bleed",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "4",
            "--bleed", "-1",
            "--output",
            str(folder / "bleed.pdf")
        ],
        3
    )

    case(
        "negative_safe",
        base + [
            "--safe-inset",
            "-1",
            "--output",
            str(folder / "negative-safe.pdf")
        ],
        3
    )

    case(
        "nonfinite_safe",
        base + [
            "--safe-inset",
            "inf",
            "--output",
            str(folder / "nonfinite-safe.pdf")
        ],
        3
    )

    case(
        "oversize_safe",
        base + [
            "--safe-inset",
            "3",
            "--output",
            str(folder / "too-safe.pdf")
        ],
        3
    )

    case(
        "missing_directory",
        base + [
            "--output",
            str(
                folder / "absent" / "proof.pdf"
            )
        ],
        3
    )

    odd = folder / "odd.pdf"

    case(
        "odd_pages",
        [
            "--pages",
            "301"
        ] + base[2:] + [
            "--output",
            str(odd)
        ]
    )

    assert odd.exists()

    allowance = folder / "allowance.pdf"

    case(
        "spine_allowance",
        base + [
            "--spine-allowance",
            "0.02",
            "--output",
            str(allowance)
        ]
    )

    assert allowance.exists()

    zero_bleed = folder / "zero-bleed.pdf"

    case(
        "zero_bleed",
        [
            "--pages", "300",
            "--trim", "6x9",
            "--caliper-mils", "4",
            "--bleed", "0",
            "--output",
            str(zero_bleed)
        ]
    )

    assert zero_bleed.exists()

print(
    f"COVER_PROOF_SMOKE={count}_CASES_PASSED",
    flush=True
)
