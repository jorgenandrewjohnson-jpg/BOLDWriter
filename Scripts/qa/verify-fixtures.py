#!/usr/bin/env python3
"""Verify fixture files against their deterministic manifest."""
import hashlib
import json
import pathlib
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
import zipfile

root = pathlib.Path(__file__).resolve().parents[2]
manifest_path = root / "Audit" / "QA" / "fixtures" / "manifest.json"
manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
failed = False
for fixture in manifest["fixtures"]:
    path = root / fixture["path"]
    data = path.read_bytes()
    actual = hashlib.sha256(data).hexdigest()
    checks = [actual == fixture["fixtureSHA256"]]
    converted = subprocess.run(
        ["/usr/bin/textutil", "-convert", "txt", "-stdout", str(path)],
        check=False, capture_output=True, text=True,
    )
    text = converted.stdout
    count = fixture["nominalPageBreaks"]
    checks.extend([
        converted.returncode == 0,
        len(re.findall(r"Page marker \d+ of \d+\.", text)) == count,
        f"Page marker 1 of {count}." in text,
        f"Page marker {count} of {count}." in text,
        "東京" in text and "Ω" in text and "Mara’s notebook”" in text,
        len(re.findall(r"\\page\b", data.decode("ascii"))) == count - 1,
        len(re.findall(r"\\sect\b", data.decode("ascii"))) == fixture["expectedSections"] - 1,
        all(token in data.decode("ascii") for token in (r"\b ", r"\i ", r"\ul ", "Times New Roman", "Arial")),
    ])
    observed_markers = len(re.findall(r"Page marker \d+ of \d+\.", text))
    status = "PASS" if all(checks) else "FAIL"
    print(f"{status} {fixture['id']} sha256={actual} convertedPageMarkers={observed_markers}/{count} sections={fixture['expectedSections']}")
    if status == "FAIL":
        print(f"  checks={checks}; converterError={converted.stderr[-500:]}")
        failed = True
for fixture in manifest.get("docxRegressionFixtures", []):
    path = root / fixture["path"]
    data = path.read_bytes()
    checks = [hashlib.sha256(data).hexdigest() == fixture["fixtureSHA256"]]
    converted_docx = subprocess.run(
        ["/usr/bin/textutil", "-convert", "txt", "-stdout", str(path)],
        check=False, capture_output=True, text=True,
    )
    checks.extend([
        converted_docx.returncode == 0,
        "Before anchor" in converted_docx.stdout,
        "After anchor" in converted_docx.stdout,
    ])
    try:
        with zipfile.ZipFile(path) as archive:
            checks.append(archive.testzip() is None)
            document = ET.fromstring(archive.read("word/document.xml"))
            rels = ET.fromstring(archive.read("word/_rels/document.xml.rels"))
            image = archive.read("word/media/floating.png")
            checks.extend([
                any(node.tag.endswith("}anchor") for node in document.iter()),
                any(node.tag.endswith("}wrapSquare") for node in document.iter()),
                any(node.attrib.get("Id") == "rIdImage1" for node in rels),
                hashlib.sha256(image).hexdigest() == fixture["imageSHA256"],
            ])
    except (OSError, KeyError, zipfile.BadZipFile, ET.ParseError):
        checks.append(False)
    status = "PASS" if all(checks) else "FAIL"
    print(f"{status} {fixture['id']} sha256={hashlib.sha256(data).hexdigest()} checks={checks}")
    failed |= status == "FAIL"
sys.exit(1 if failed else 0)
