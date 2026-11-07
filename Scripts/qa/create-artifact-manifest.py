#!/usr/bin/env python3
"""Write SHA-256 and size inventory for the QA evidence tree."""
import hashlib
import json
import pathlib

root = pathlib.Path(__file__).resolve().parents[2] / "Audit" / "QA"
output = root / "artifact-manifest.json"
entries = []
for path in sorted(root.rglob("*")):
    if not path.is_file() or path == output or "__pycache__" in path.parts:
        continue
    data = path.read_bytes()
    entries.append({
        "path": str(path.relative_to(root)),
        "bytes": len(data),
        "sha256": hashlib.sha256(data).hexdigest(),
    })
output.write_text(json.dumps({"schemaVersion": 1, "files": entries}, indent=2) + "\n", encoding="utf-8")
print(f"{len(entries)} files hashed into {output}")
