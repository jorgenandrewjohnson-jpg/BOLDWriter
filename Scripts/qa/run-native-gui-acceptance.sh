#!/bin/bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

usage() {
  cat >&2 <<'USAGE'
Usage: run-native-gui-acceptance.sh \
  --app APP_BUNDLE --bundle-id BUNDLE_ID --revision SOURCE_REVISION \
  --input DISPOSABLE.boldwriter --output NEW_EVIDENCE_DIRECTORY [harness options]

The input filename must contain TEST-COPY-DO-NOT-USE-AS-ORIGINAL.
The output directory must not exist. This command does not install or terminate apps.
USAGE
}

args=("$@")
for required in --app --bundle-id --revision --input --output; do
  found=0
  for arg in "${args[@]}"; do [[ "$arg" == "$required" ]] && found=1; done
  if [[ "$found" == 0 ]]; then usage; exit 64; fi
done

input_path=""
output_path=""
for ((i=0; i<${#args[@]}; i++)); do
  case "${args[$i]}" in
    --input) input_path="${args[$((i+1))]}" ;;
    --output) output_path="${args[$((i+1))]}" ;;
  esac
done
if [[ ! -f "$input_path" && ! -d "$input_path" ]]; then
  echo "Input does not exist: $input_path" >&2; exit 66
fi
case "$input_path" in
  "$HOME/Desktop"|"$HOME/Desktop"/*) echo "Refusing test input on Desktop: $input_path" >&2; exit 65 ;;
esac
case "$output_path" in
  "$HOME/Desktop"|"$HOME/Desktop"/*) echo "Refusing evidence output on Desktop: $output_path" >&2; exit 65 ;;
esac
if [[ "$(basename "$input_path")" != *TEST-COPY-DO-NOT-USE-AS-ORIGINAL* ]]; then
  echo "Refusing GUI mutation of an input not explicitly named as a disposable test copy." >&2; exit 65
fi
if [[ -e "$output_path" ]]; then
  echo "Evidence output already exists; choose a new path: $output_path" >&2; exit 73
fi

build_dir="$(mktemp -d "${TMPDIR:-/tmp}/boldwriter-gui-harness.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
harness="$build_dir/native-gui-acceptance"
xcrun swiftc -swift-version 5 "$repo_root/Scripts/tests/native-gui-acceptance.swift" -o "$harness"
"$harness" "$@"
