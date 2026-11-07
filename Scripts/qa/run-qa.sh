#!/bin/bash
set -uo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repo_root="$(cd "$script_dir/../.." && pwd -P)"
cd "$repo_root"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_dir="${BOLD_QA_RUN_DIR:-$repo_root/Audit/QA/runs/$timestamp}"
scratch_dir="${BOLD_QA_SCRATCH_DIR:-${TMPDIR:-/tmp}/boldwriter-qa-build/$timestamp}"
mkdir -p "$run_dir" "$scratch_dir"

developer_dir="$(xcode-select -p 2>/dev/null || true)"
if [[ -x /Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild ]]; then developer_dir="/Applications/Xcode.app/Contents/Developer"; fi
if [[ -x "$developer_dir/usr/bin/xcodebuild" ]]; then
  export DEVELOPER_DIR="$developer_dir"
fi

revision="$(git rev-parse HEAD)"
branch="$(git branch --show-current)"
status="$(git status --porcelain=v1)"
overall=0
blocked=0
results=()

record() {
  local id="$1" status="$2" detail="$3"
  results+=("$id|$status|$detail")
  printf '[%s] %s — %s\n' "$status" "$id" "$detail"
}

if [[ "$branch" != "codex/boldwriter-qa" ]]; then
  record source_identity FAIL "Expected QA branch; found $branch"
  overall=1
else
  record source_identity PASS "branch=$branch revision=$revision"
fi

if [[ -n "$status" ]]; then
  printf '%s\n' "$status" > "$run_dir/git-status.txt"
  if [[ "${BOLD_QA_ALLOW_DIRTY:-0}" == 1 ]]; then
    record git_state PASS "Working tree changes captured in git-status.txt"
  else
    record git_state FAIL "Working tree is dirty; set BOLD_QA_ALLOW_DIRTY=1 after reviewing status"
    overall=1
  fi
else
  record git_state PASS "clean"
fi

if python3 "$script_dir/generate-fixtures.py" > "$run_dir/fixture-generation.json" 2> "$run_dir/fixture-generation.stderr"; then
  if python3 "$script_dir/verify-fixtures.py" > "$run_dir/fixture-integrity.txt" 2>&1; then
    record fixture_integrity PASS "Generated seven rich-text RTF fixtures and one DrawingML DOCX; SHA-256, Unicode, page/section markers and package relationships verified"
  else
    record fixture_integrity FAIL "Fixture SHA-256 verification failed"
    overall=1
  fi
else
  record fixture_integrity FAIL "Fixture generation failed"
  overall=1
fi

if python3 "$script_dir/test_run_guarded.py" > "$run_dir/concurrency-harness-tests.log" 2>&1; then
  record concurrency_harness PASS "Worktree path matching and sibling-prefix regression checks passed"
else
  record concurrency_harness FAIL "Concurrency monitor unit checks failed; see concurrency-harness-tests.log"
  overall=1
fi

swift_log="$run_dir/swift-test.log"
BOLD_QA_PDF_OUTPUT="$run_dir/BOLDWriter-production-interior.pdf" \
BOLD_QA_DOCX_FIXTURE="$repo_root/Audit/QA/fixtures/independent-floating-drawingml.docx" \
BOLD_QA_DOCX_REPORT="$run_dir/DOCX-floating-anchor-inspection.json" \
BOLD_QA_LONG_FIXTURE_ROOT="$repo_root/Audit/QA/fixtures" \
BOLD_QA_LONG_OUTPUT_ROOT="$run_dir/native-long-documents" \
BOLD_QA_SOURCE_REVISION="$revision" \
  python3 "$script_dir/run-guarded.py" "$swift_log" -- swift test --scratch-path "$scratch_dir/swiftpm"
test_status=$?
summary_status=1
if python3 "$script_dir/summarize-test-log.py" "$swift_log" --exit-status "$test_status" --source-revision "$revision" --output "$run_dir/test-summary.json" > "$run_dir/test-summary.txt"; then
  summary_status=0
fi
if [[ "$test_status" == 0 ]]; then
  summary="$(rg 'Executed [0-9]+ tests?' "$swift_log" | tail -1 || true)"
  if [[ "$summary_status" == 0 ]]; then
    record swiftpm_tests PASS "${summary:-swift test succeeded}; test-summary.json confirms complete case accounting; log=swift-test.log"
  else
    record swiftpm_tests FAIL "swift test exited zero but its log could not be reconciled with XCTest's final summary; inspect test-summary.txt"
    overall=1
  fi
elif [[ "$test_status" == 75 || "$test_status" == 130 ]]; then
  partial_summary="$(python3 - "$swift_log" <<'PY'
import pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text(errors="replace").splitlines()
count = lambda phrase: sum(line.startswith("Test Case ") and phrase in line for line in lines)
suites = sum(line.startswith("Test Suite '") and " passed at " in line for line in lines)
print(f"partial: {count(' passed (')} passed, {count(' skipped (')} skipped, {count(' failed (')} failed across {suites} completed suites")
PY
)"
  record swiftpm_tests BLOCKED "$partial_summary; test process was explicitly interrupted or returned coordination code 75; see swift-test.log"
  blocked=1
else
  record swiftpm_tests FAIL "swift test failed; log=swift-test.log"
  overall=1
fi

if [[ -n "${DEVELOPER_DIR:-}" && -x "$DEVELOPER_DIR/usr/bin/xcodebuild" ]] && xcodebuild -version > "$run_dir/xcode-version.txt" 2>&1; then
  python3 "$script_dir/run-guarded.py" "$run_dir/xcode-release.log" -- xcodebuild -project "$repo_root/BOLDWriter.xcodeproj" -scheme 'BOLD Writer' -configuration Release -destination 'generic/platform=macOS' -derivedDataPath "$scratch_dir/DerivedDataRelease" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO build
  xcode_status=$?
  if [[ "$xcode_status" == 75 || "$xcode_status" == 130 ]]; then
    record xcode_universal_release BLOCKED "Build process returned coordination code 75 or was interrupted; see xcode-release.log"
    blocked=1
  elif [[ "$xcode_status" == 0 ]]; then
    candidate_app="$scratch_dir/DerivedDataRelease/Build/Products/Release/BOLD Writer.app"
    if [[ ! -f "$candidate_app/Contents/Info.plist" || ! -x "$candidate_app/Contents/MacOS/BOLD Writer" ]]; then
      record xcode_universal_release FAIL "Build succeeded but candidate app bundle is incomplete"
      overall=1
    else
      bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_app/Contents/Info.plist")"
      if [[ "$bundle_id" != "com.boldwriter.app" ]]; then
        record xcode_universal_release FAIL "Unexpected candidate bundle identifier: $bundle_id"
        overall=1
      else
        /usr/libexec/PlistBuddy -c 'Delete :BOLDWriterSourceRevision' "$candidate_app/Contents/Info.plist" >/dev/null 2>&1 || true
        /usr/libexec/PlistBuddy -c "Add :BOLDWriterSourceRevision string $revision" "$candidate_app/Contents/Info.plist"
        printf '%s\n' "$candidate_app" > "$run_dir/CANDIDATE_APP_PATH.txt"
        {
          printf 'Bundle ID: %s\nRevision: %s\n' "$bundle_id" "$revision"
          /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate_app/Contents/Info.plist"
          lipo -info "$candidate_app/Contents/MacOS/BOLD Writer"
          shasum -a 256 "$candidate_app/Contents/MacOS/BOLD Writer"
        } > "$run_dir/CANDIDATE_IDENTITY.txt" 2>&1
        record xcode_universal_release PASS "Native Release candidate built and stamped at $candidate_app"
      fi
    fi
  else
    record xcode_universal_release FAIL "Native Release build failed; log=xcode-release.log"
    overall=1
  fi
else
  printf '%s\n' "xcodebuild requires full Xcode; current developer directory: $(xcode-select -p 2>&1)" > "$run_dir/xcode-release.blocked.txt"
  record xcode_universal_release BLOCKED "Full Xcode unavailable; CLT-only toolchain"
  blocked=1
fi

active_gui="$(pgrep -fl 'BOLD Writer.app/Contents/MacOS/BOLD Writer|native-gui-acceptance|System Events' || true)"
if [[ -n "$active_gui" || "${BOLD_QA_ALLOW_GUI:-0}" != 1 ]]; then
  printf '%s\n' "${active_gui:-GUI consent flag absent}" > "$run_dir/gui.blocked.txt"
  record native_gui_acceptance BLOCKED "Shared GUI/input availability not established; no focus or input sent"
  blocked=1
else
  record native_gui_acceptance NOT_RUN "Harness is available at Scripts/tests/native-gui-acceptance.swift; invoke in a dedicated GUI window after verifying permissions and session ownership"
  blocked=1
fi

exit_code="$overall"
if [[ "$overall" == 0 && "$blocked" == 1 ]]; then exit_code=2; fi
python3 - "$run_dir" "$revision" "$branch" "$exit_code" "${results[@]}" <<'PY'
import datetime, json, pathlib, sys
run_dir = pathlib.Path(sys.argv[1])
revision, branch, exit_code = sys.argv[2], sys.argv[3], int(sys.argv[4])
rows = []
for item in sys.argv[5:]:
    case, status, detail = item.split('|', 2)
    rows.append({"id": case, "status": status, "detail": detail})
report = {
    "schemaVersion": 1,
    "runUTC": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "sourceRevision": revision,
    "branch": branch,
    "overallStatus": "PASS" if exit_code == 0 else ("FAIL" if exit_code == 1 else "BLOCKED"),
    "exitCode": exit_code,
    "results": rows,
    "evidenceDirectory": str(run_dir),
}
(run_dir / "REPORT.json").write_text(json.dumps(report, indent=2) + "\n")
lines = ["# BOLD Writer QA Run", "", f"- Status: **{report['overallStatus']}**", f"- Source: `{branch}` at `{revision}`", f"- Run (UTC): `{report['runUTC']}`", f"- Evidence: `{run_dir}`", "", "| Check | Status | Detail |", "|---|---|---|"]
lines += [f"| {x['id']} | {x['status']} | {x['detail']} |" for x in rows]
(run_dir / "REPORT.md").write_text("\n".join(lines) + "\n")
PY

printf 'QA evidence: %s\n' "$run_dir"
exit "$exit_code"
