#!/usr/bin/env python3
"""Create deterministic, synthetic rich-text import fixtures and a SHA-256 manifest."""
from __future__ import annotations

import hashlib
import json
import pathlib
import re
import struct
import subprocess
import sys
import zipfile
import zlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
FIXTURES = ROOT / "Audit" / "QA" / "fixtures"
PAGE_COUNTS = (1, 10, 50, 100, 391, 500, 1000)


def page_text(page: int, total: int) -> str:
    return (
        f"Chapter {((page - 1) % 12) + 1}: The Glass Harbor\n"
        f"Page marker {page} of {total}. “Mara’s notebook” — Unicode: café, naïve, 東京, and Ω.\n"
        "A long paragraph follows: at dawn the harbor lamps faded one by one, while the tide carried "
        "small silver reflections under the old bridge. The keeper checked the brass clock, marked the "
        "weather in the ledger, and listened for the ferry beyond the breakwater. Each sentence is "
        "original fixture text so searches, paragraph boundaries, and save/reopen hashes are useful.\n"
        "A short paragraph closes this page.\n"
        f"• Field note {page}: verify the compass, the tide table, and the marked passage.\n"
    )


def rtf_escape(value: str) -> str:
    out: list[str] = []
    for char in value:
        code = ord(char)
        if char in "\\{}":
            out.append("\\" + char)
        elif char == "\n":
            out.append("\\par\n")
        elif code < 128:
            out.append(char)
        else:
            signed = code if code < 32768 else code - 65536
            out.append(f"\\u{signed}?")
    return "".join(out)


def png_chunk(kind: bytes, data: bytes) -> bytes:
    body = kind + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xFFFFFFFF)


def synthetic_png() -> bytes:
    signature = b"\x89PNG\r\n\x1a\n"
    header = struct.pack(">IIBBBBB", 8, 4, 8, 6, 0, 0, 0)
    rows = b"".join(
        b"\x00" + bytes(channel for x in range(4) for channel in ((245, 55, 75, 255) if x < 2 else (30, 120, 235, 255)))
        for _ in range(8)
    )
    return signature + png_chunk(b"IHDR", header) + png_chunk(b"IDAT", zlib.compress(rows, 9)) + png_chunk(b"IEND", b"")


def write_docx(path: pathlib.Path) -> bytes:
    image = synthetic_png()
    files = {
        "[Content_Types].xml": """<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>""".encode(),
        "_rels/.rels": """<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>""".encode(),
        "word/_rels/document.xml.rels": """<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rIdImage1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/floating.png"/></Relationships>""".encode(),
        "word/document.xml": """<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"><w:body><w:p><w:r><w:t>Before anchor</w:t></w:r><w:r><w:drawing><wp:anchor distT="0" distB="0" distL="0" distR="0" simplePos="0" relativeHeight="251658240" behindDoc="0" locked="0" layoutInCell="1" allowOverlap="1"><wp:simplePos x="0" y="0"/><wp:positionH relativeFrom="column"><wp:posOffset>127000</wp:posOffset></wp:positionH><wp:positionV relativeFrom="paragraph"><wp:posOffset>254000</wp:posOffset></wp:positionV><wp:extent cx="1270000" cy="635000"/><wp:effectExtent l="0" t="0" r="0" b="0"/><wp:wrapSquare wrapText="bothSides"/><wp:docPr id="1" name="QA floating picture"/><wp:cNvGraphicFramePr><a:graphicFrameLocks noChangeAspect="1"/></wp:cNvGraphicFramePr><a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic><pic:nvPicPr><pic:cNvPr id="1" name="floating.png"/><pic:cNvPicPr/></pic:nvPicPr><pic:blipFill><a:blip r:embed="rIdImage1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill><pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1270000" cy="635000"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr></pic:pic></a:graphicData></a:graphic></wp:anchor></w:drawing></w:r><w:r><w:t>After anchor</w:t></w:r></w:p><w:sectPr><w:pgSz w:w="12240" w:h="15840"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="720" w:footer="720" w:gutter="0"/></w:sectPr></w:body></w:document>""".encode(),
        "word/media/floating.png": image,
    }
    path.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, data in files.items():
            info = zipfile.ZipInfo(name, date_time=(2020, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return image


def main() -> int:
    FIXTURES.mkdir(parents=True, exist_ok=True)
    records = []
    for count in PAGE_COUNTS:
        parts = [page_text(i, count) for i in range(1, count + 1)]
        text = "\n".join(parts)
        filename = f"synthetic-{count:04d}-page-import.rtf"
        body = [r"{\rtf1\ansi\deff0", r"{\fonttbl{\f0 Times New Roman;}{\f1 Arial;}}", r"\viewkind4\uc1"]
        for index, part in enumerate(parts):
            lines = part.rstrip("\n").split("\n")
            for line_index, line in enumerate(lines):
                if line_index == 0:
                    style, suffix = r"\f1\fs30\b ", r"\b0\par "
                elif line_index == 1:
                    style, suffix = r"\f0\fs20\i ", r"\i0\par "
                elif line_index == 2:
                    style, suffix = r"\f0\fs22 ", r"\par "
                elif line_index == 3:
                    style, suffix = r"\f1\fs22\ul ", r"\ulnone\par "
                else:
                    style, suffix = r"\f0\fs20 ", r"\par "
                body.append(style + rtf_escape(line) + suffix)
            if index + 1 < count:
                body.append(r"\page")
            if (index + 1) % 10 == 0 and index + 1 < count:
                body.append(r"\sect\sectd\sbkpage")
        body.append("}")
        path = FIXTURES / filename
        payload = "".join(body).encode("ascii")
        path.write_bytes(payload)
        records.append({
            "id": f"synthetic-{count:04d}-page-import",
            "path": str(path.relative_to(ROOT)),
            "nominalPageBreaks": count,
            "expectedPhysicalPages": None,
            "characterCount": len(text),
            "utf16Length": len(text.encode("utf-16-le")) // 2,
            "paragraphCount": len(re.findall(r"\n", text)),
            "expectedSections": 1 + max(0, (count - 1) // 10),
            "textSHA256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
            "fixtureSHA256": hashlib.sha256(payload).hexdigest(),
            "attributes": ["Arial 15pt bold headings", "Times New Roman 10pt italic markers", "Times New Roman 11pt body", "Arial 11pt underlined closing paragraphs", "bullet field notes", "explicit page breaks", "section breaks every ten pages", "Unicode", "long paragraphs", "short paragraphs"],
            "notes": "Nominal page count comes from explicit RTF page breaks; actual rendered pagination must be measured independently.",
        })
    docx_path = FIXTURES / "independent-floating-drawingml.docx"
    image_data = write_docx(docx_path)
    docx_data = docx_path.read_bytes()
    manifest = {
        "schemaVersion": 1,
        "sourceRevision": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
        "generator": "Scripts/qa/generate-fixtures.py",
        "fixtures": records,
        "docxRegressionFixtures": [{
            "id": "independent-floating-drawingml",
            "path": str(docx_path.relative_to(ROOT)),
            "fixtureSHA256": hashlib.sha256(docx_data).hexdigest(),
            "imageSHA256": hashlib.sha256(image_data).hexdigest(),
            "paragraphText": ["Before anchor", "After anchor"],
            "drawingType": "wp:anchor",
            "wrapping": "wp:wrapSquare",
            "sizeEMU": {"cx": 1270000, "cy": 635000},
            "expectedLimitation": "Importer converts floating position/wrapping to inline placement and must issue an explicit warning.",
        }],
    }
    (FIXTURES / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({"fixtureDirectory": str(FIXTURES), "fixtureCount": len(records), "manifest": str(FIXTURES / "manifest.json")}, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
