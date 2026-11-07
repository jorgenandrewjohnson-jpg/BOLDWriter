#!/usr/bin/env python3
"""Run QA work independently and record, but never stop for, other builds.

Each worktree gets its own SwiftPM scratch path / DerivedData. Concurrent builds
can affect timing measurements, but they do not invalidate functional test
results. Shared GUI input and benchmark coordination are handled by the caller.
"""
import os
import pathlib
import subprocess
import sys
import time
from typing import Optional

ROOT = pathlib.Path(__file__).resolve().parents[2]
OTHER_ROOTS = [ROOT.parent / name for name in (
    "BOLDWriter", "BOLDWriter-Performance", "BOLDWriter-PhotoEditor", "BOLDWriter-Integration"
)]
BUILD_NAMES = {"swift", "swift-test", "swift-build", "swift-frontend", "xcodebuild", "xctest"}


def command_mentions_root(command: str, root: pathlib.Path) -> bool:
    needle = str(root)
    offset = command.find(needle)
    return offset >= 0 and (offset + len(needle) == len(command) or command[offset + len(needle)] == "/")


def competing_builds(ignored_pgids: Optional[set[int]] = None) -> list[str]:
    output = subprocess.run(
        ["ps", "-ax", "-o", "pid=,ucomm=,args="],
        check=False, capture_output=True, text=True,
    ).stdout
    ignored_pgids = ignored_pgids or {os.getpgrp()}
    matches = []
    for line in output.splitlines():
        fields = line.strip().split(None, 2)
        if len(fields) < 3:
            continue
        try:
            pid = int(fields[0])
            if os.getpgid(pid) in ignored_pgids:
                continue
        except (OSError, ValueError):
            continue
        executable = fields[1]
        command = fields[2]
        if executable not in BUILD_NAMES:
            continue
        roots = [root for root in OTHER_ROOTS if command_mentions_root(command, root)]
        # Swift test invocations often omit their working directory from argv.
        # Resolve cwd only for those build processes so independent builds in
        # the primary checkout or sibling worktrees are visible to the report.
        if not roots and executable in {"swift", "swift-test", "swift-build", "xctest"}:
            cwd = subprocess.run(
                ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"],
                check=False, capture_output=True, text=True,
            ).stdout
            path = next((item[1:] for item in cwd.splitlines() if item.startswith("n/")), "")
            roots = [root for root in OTHER_ROOTS if path == str(root) or path.startswith(str(root) + "/")]
        if roots:
            worktree = str(roots[0])
            matches.append(f"pid={pid} executable={executable} worktree={worktree} argv={command[:160]}")
    return matches


def main() -> int:
    args = sys.argv[1:]
    if "--" not in args:
        print("usage: run-guarded.py LOG -- COMMAND [ARG ...]", file=sys.stderr)
        return 64
    divider = args.index("--")
    if divider != 1 or len(args) <= 2:
        print("usage: run-guarded.py LOG -- COMMAND [ARG ...]", file=sys.stderr)
        return 64
    log_path = pathlib.Path(args[0])
    command = args[2:]
    log_path.parent.mkdir(parents=True, exist_ok=True)
    concurrency_path = log_path.with_name(log_path.name + ".concurrency.log")
    with concurrency_path.open("w", encoding="utf-8") as coordination:
        coordination.write("Concurrency policy: independent build/test is allowed; external builds are advisory and may contaminate timings only.\n")
    with log_path.open("w", encoding="utf-8") as log:
        existing = competing_builds({os.getpgrp()})
        if existing:
            with concurrency_path.open("a", encoding="utf-8") as coordination:
                coordination.write("External BOLD Writer build/test already active at start:\n" + "\n".join(existing) + "\n")
        process = subprocess.Popen(
            command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
        seen = set(existing)
        try:
            while process.poll() is None:
                # swift/Xcode workers inherit the dedicated child process group
                # created above; exclude every process in that group.
                competing = competing_builds({os.getpgrp(), process.pid})
                new = [item for item in competing if item not in seen]
                if new:
                    seen.update(new)
                    with concurrency_path.open("a", encoding="utf-8") as coordination:
                        coordination.write("Advisory: external build/test observed during QA run; continuing. Timing benchmarks in this run are contaminated.\n")
                        coordination.write("\n".join(new) + "\n")
                time.sleep(2)
        except KeyboardInterrupt:
            log.write("\nQA monitor interrupted by its owner. Forwarding SIGINT to its isolated child process group.\n")
            log.flush()
            try:
                os.killpg(process.pid, 2)
            except ProcessLookupError:
                pass
            try:
                code = process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, 15)
                code = process.wait()
            return 130 if code < 0 else code
        code = process.returncode
        return code if code >= 0 else 128 - code


if __name__ == "__main__":
    sys.exit(main())
