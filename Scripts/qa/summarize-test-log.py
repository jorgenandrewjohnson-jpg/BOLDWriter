#!/usr/bin/env python3
"""Extract complete XCTest case/suite results from a SwiftPM test log."""
import argparse
import datetime
import json
import pathlib
import re
import subprocess


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("log", type=pathlib.Path)
    parser.add_argument("--output", type=pathlib.Path)
    parser.add_argument("--coordination-log", type=pathlib.Path)
    parser.add_argument("--exit-status", type=int, required=True)
    parser.add_argument("--source-revision")
    args = parser.parse_args()
    raw = args.log.read_text(errors="replace")
    coordination_path = args.coordination_log or args.log.with_name(args.log.name + ".concurrency.log")
    coordination = coordination_path.read_text(errors="replace") if coordination_path.exists() else ""
    started = re.findall(r"^Test Case '(.+)' started\.$", raw, re.M)
    passed = re.findall(r"^Test Case '(.+)' passed \(([^)]+)\)", raw, re.M)
    skipped = re.findall(r"^Test Case '(.+)' skipped \(([^)]+)\)", raw, re.M)
    failed = re.findall(r"^Test Case '(.+)' failed \(([^)]+)\)", raw, re.M)
    suite_started = re.findall(r"^Test Suite '(.+)' started at ", raw, re.M)
    suite_passed = re.findall(r"^Test Suite '(.+)' passed at ", raw, re.M)
    suite_failed = re.findall(r"^Test Suite '(.+)' failed at ", raw, re.M)
    summaries = re.findall(r"Executed (\d+) tests?, with (?:(\d+) tests? skipped and )?(\d+) failures? \(\d+ unexpected\) in ([0-9.]+) \(([0-9.]+)\) seconds", raw)
    final = summaries[-1] if summaries else None
    completed = bool(final and args.exit_status == 0 and len(started) == len(passed) + len(skipped) + len(failed)
                     and int(final[0]) == len(passed) + len(skipped) + len(failed)
                     and int(final[1] or 0) == len(skipped)
                     and int(final[2]) == len(failed))
    revision = args.source_revision or subprocess.run(
        ["git", "rev-parse", "HEAD"], check=False, capture_output=True, text=True
    ).stdout.strip()
    report = {
        "schemaVersion": 1,
        "sourceRevision": revision,
        "logPath": str(args.log.resolve()),
        "childExitStatus": args.exit_status,
        "complete": completed,
        "status": "PASS" if completed and not failed else ("FAIL" if args.exit_status != 0 or failed else "INCOMPLETE"),
        "tests": {"started": len(started), "passed": len(passed), "skipped": len(skipped), "failed": len(failed)},
        "suites": {"started": len(suite_started), "passed": len(suite_passed), "failed": len(suite_failed)},
        "xctestDurationSeconds": float(final[3]) if final else None,
        "xctestDurationIncludingOverheadSeconds": float(final[4]) if final else None,
        "benchmarkTimingContaminated": (
            "Timing benchmarks in this run are contaminated." in coordination
            or "External BOLD Writer build/test already active at start:" in coordination
        ),
        "failures": failed,
        "skippedCases": skipped,
        "externalBuildObservations": len(re.findall(r"^(?:Advisory: external build/test observed|External BOLD Writer build/test already active at start:)", coordination, re.M)),
        "coordinationLogPath": str(coordination_path.resolve()) if coordination else None,
        "generatedUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    rendered = json.dumps(report, indent=2) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered)
    print(rendered, end="")
    return 0 if report["status"] == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
