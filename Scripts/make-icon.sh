#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
icon_work="$(mktemp -d /private/tmp/boldwriter-icon.XXXXXX)"
trap 'rm -rf "$icon_work"' EXIT
mkdir -p "$icon_work/AppIcon.iconset"
CLANG_MODULE_CACHE_PATH="$icon_work/cache" swift "$project_root/Scripts/make-icon.swift" "$icon_work/icon.png"
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" "$icon_work/icon.png" --out "$icon_work/AppIcon.iconset/icon_${size}x${size}.png" >/dev/null
done
for size in 16 32 128 256 512; do
  doubled="$((size * 2))"
  sips -z "$doubled" "$doubled" "$icon_work/icon.png" --out "$icon_work/AppIcon.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$icon_work/AppIcon.iconset" -o "$project_root/Resources/AppIcon.icns"
echo "Created original BOLD Writer icon."
