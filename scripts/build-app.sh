#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="$project_dir/dist"
app_dir="$output_dir/AspaceI.app"

swift build --package-path "$project_dir" -c release

find "$app_dir" -depth -delete 2>/dev/null || true
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$project_dir/.build/release/AspaceI" "$app_dir/Contents/MacOS/AspaceI"
cp "$project_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
chmod 755 "$app_dir/Contents/MacOS/AspaceI"
codesign --force --deep --sign - "$app_dir"

echo "$app_dir"
