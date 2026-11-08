#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -n "$(git -C "$project_root" status --porcelain)" ]]; then
    echo "Refusing to package a dirty repository; commit the intended source first." >&2
    exit 1
fi
required_release_files=(
    LICENSE VERSION.txt INSTALL.txt ReleaseNotes.md
    Docs/ThirdPartyAttribution.md
    Docs/ThirdParty/WordCraft-LICENSE-MIT.txt
    Docs/ThirdParty/FabricJS-LICENSE.txt
    Sources/BOLDWriter/AudioProduction/LAME/COPYING
    Sources/BOLDWriter/AudioProduction/LAME/LICENSE.upstream
    Sources/BOLDWriter/AudioProduction/LAME/PROVENANCE.md
)
missing_release_files=()
for relative_path in "${required_release_files[@]}"; do
    [[ -f "$project_root/$relative_path" ]] || missing_release_files+=("$relative_path")
done
if (( ${#missing_release_files[@]} )); then
    printf 'Release packaging prerequisites are missing; no build was started:\n' >&2
    printf '  %s\n' "${missing_release_files[@]}" >&2
    exit 66
fi
release_dir="$project_root/Releases/BOLD-Writer-1.0"
build_dir="$project_root/DerivedDataRelease"
staging_dir="$(mktemp -d /private/tmp/boldwriter-dmg.XXXXXX)"
source_staging="$(mktemp -d /private/tmp/boldwriter-source.XXXXXX)"
trap 'rm -rf "$staging_dir" "$source_staging"' EXIT

[[ -f "$project_root/Resources/AppIcon.icns" ]] || {
    echo "The tracked app icon is missing; generate and review it separately before packaging." >&2
    exit 1
}
xcodebuild -project "$project_root/BOLDWriter.xcodeproj" -scheme "BOLD Writer" -configuration Release -destination "generic/platform=macOS" -derivedDataPath "$build_dir" CODE_SIGNING_ALLOWED=NO ONLY_ACTIVE_ARCH=NO clean build
mkdir -p "$release_dir"
ditto "$build_dir/Build/Products/Release/BOLD Writer.app" "$release_dir/BOLD Writer.app"
cp "$project_root/LICENSE" "$release_dir/BOLD Writer.app/Contents/Resources/LICENSE.txt"
third_party_dir="$release_dir/BOLD Writer.app/Contents/Resources/ThirdPartyNotices"
mkdir -p "$third_party_dir"
cp "$project_root/Docs/ThirdPartyAttribution.md" "$third_party_dir/ThirdPartyAttribution.md"
cp "$project_root/Docs/ThirdParty/WordCraft-LICENSE-MIT.txt" "$third_party_dir/WordCraft-LICENSE-MIT.txt"
cp "$project_root/Docs/ThirdParty/FabricJS-LICENSE.txt" "$third_party_dir/FabricJS-LICENSE.txt"
cp "$project_root/Sources/BOLDWriter/AudioProduction/LAME/COPYING" "$third_party_dir/LAME-COPYING.txt"
cp "$project_root/Sources/BOLDWriter/AudioProduction/LAME/LICENSE.upstream" "$third_party_dir/LAME-LICENSE.upstream"
cp "$project_root/Sources/BOLDWriter/AudioProduction/LAME/PROVENANCE.md" "$third_party_dir/LAME-PROVENANCE.md"
xattr -dr com.apple.FinderInfo "$release_dir/BOLD Writer.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$release_dir/BOLD Writer.app" 2>/dev/null || true
codesign --force --deep --sign - "$release_dir/BOLD Writer.app"
codesign --verify --deep --strict "$release_dir/BOLD Writer.app"
lipo -archs "$release_dir/BOLD Writer.app/Contents/MacOS/BOLD Writer"
cp "$project_root/INSTALL.txt" "$project_root/VERSION.txt" "$project_root/ReleaseNotes.md" "$release_dir/"
"$release_dir/BOLD Writer.app/Contents/MacOS/BOLD Writer" --generate-sample "$release_dir/BOLD-Writer-Sample.boldwriter"

ditto "$release_dir/BOLD Writer.app" "$staging_dir/BOLD Writer.app"
# File-provider-managed folders can reattach Finder metadata after signing.
# Clean only forbidden signing metadata on this generated staging copy;
# preserve quarantine and all other security attributes.
xattr -dr com.apple.FinderInfo "$staging_dir/BOLD Writer.app" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$staging_dir/BOLD Writer.app" 2>/dev/null || true
codesign --verify --deep --strict "$staging_dir/BOLD Writer.app"
cp "$release_dir/INSTALL.txt" "$staging_dir/INSTALL.txt"
ln -s /Applications "$staging_dir/Applications"
hdiutil create -volname "BOLD Writer" -srcfolder "$staging_dir" -ov -format UDZO "$release_dir/BOLD-Writer.dmg"
ditto -c -k --sequesterRsrc --keepParent "$staging_dir/BOLD Writer.app" "$release_dir/BOLD-Writer.zip"

mkdir -p "$source_staging/BOLDWriter"
git -C "$project_root" archive --format=tar HEAD | tar -xf - -C "$source_staging/BOLDWriter"
ditto -c -k --norsrc --noextattr --keepParent "$source_staging/BOLDWriter" "$release_dir/BOLD-Writer-Source.zip"
(cd "$release_dir" && shasum -a 256 BOLD-Writer.dmg BOLD-Writer.zip BOLD-Writer-Source.zip > SHA256SUMS.txt)
echo "Release packaged in $release_dir"
