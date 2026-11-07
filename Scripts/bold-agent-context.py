#!/usr/bin/env python3
"""Read-only JSON map for terminal agents working on the current checkout."""

import csv
import json
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent


def git(*arguments):
    return subprocess.check_output(
        ["git", *arguments], cwd=ROOT, text=True
    ).strip()


with (ROOT / "Docs/RepositoryMap.tsv").open(newline="", encoding="utf-8") as source:
    subsystem_rows = list(csv.DictReader(source, delimiter="\t"))

subsystems = [
    {
        "name": row["subsystem"],
        "sources": row["production path(s)"].split(";"),
        "tests": row["test path(s)"].split(";"),
    }
    for row in subsystem_rows
]

changes = [
    {"status": line[:2], "path": line[3:]}
    for line in git("status", "--short").splitlines()
]

context = {
    "schema_version": 1,
    "repository": str(ROOT),
    "branch": git("branch", "--show-current"),
    "head": git("rev-parse", "HEAD"),
    "working_tree_changes": changes,
    "subsystems": subsystems,
    "terminal_commands": {
        "environment": "Scripts/bold doctor",
        "status": "Scripts/bold status",
        "agent_context": "Scripts/bold agent-context",
        "repository_checks": "Scripts/bold verify-repo",
        "dependency_resolution": "Scripts/bold resolve",
        "debug_build": "Scripts/bold build",
        "release_build": "Scripts/bold build-release",
        "focused_tests": "Scripts/bold test FILTER",
        "full_tests": "Scripts/bold test",
        "native_app_build": "Scripts/bold xcode-build",
        "native_app_tests": "Scripts/bold xcode-test",
        "generated_build_cleanup": "Scripts/bold clean",
        "full_verification": "Scripts/bold verify",
        "sign_generated_app": "Scripts/bold sign",
        "verify_local_install": "Scripts/bold verify-install",
        "local_install": "Scripts/bold install",
        "local_launch": "Scripts/bold launch",
        "release_package": "Scripts/bold package",
        "explicit_pdf_acceptance": "Scripts/bold acceptance-pdf PATH",
        "explicit_docx_acceptance": "Scripts/bold acceptance-docx PATH",
    },
}

print(json.dumps(context, indent=2, ensure_ascii=False))
