#!/bin/zsh

set -euo pipefail

project_dir="${0:A:h:h}"
output_dir="$project_dir/dist"
app_dir="$output_dir/AspaceI.app"

swift build --package-path "$project_dir" -c release

release_dir="$project_dir/.build/release"
# resource bundle 的位置取決於用哪個建置系統：Xcode 的放在 .build/out/Products/Release，
# 純 SwiftPM 的放在 .build/release。只掃存在的目錄——find 吃到不存在的路徑會回非零，
# 加上 set -e 會讓腳本就地結束在這一行（CI 上一直是這樣失敗的）。
resource_bundle=""
for candidate_dir in "$project_dir/.build/out/Products/Release" "$release_dir"; do
    [[ -d "$candidate_dir" ]] || continue
    resource_bundle=$(find "$candidate_dir" -maxdepth 1 -iname "*_AspaceI.bundle" -print -quit 2>/dev/null || true)
    [[ -n "$resource_bundle" ]] && break
done
if [[ -z "$resource_bundle" ]]; then
    # 少了它，平台彩色圖示在 App 裡會全部載不到，而且不會有任何錯誤。
    print -u2 "找不到 AspaceI 的 resource bundle"
    exit 1
fi

find "$app_dir" -depth -delete 2>/dev/null || true
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$release_dir/AspaceI" "$app_dir/Contents/MacOS/AspaceI"
cp "$project_dir/Support/Info.plist" "$app_dir/Contents/Info.plist"
cp -R "$resource_bundle" "$app_dir/Contents/Resources/"
xcrun actool "$project_dir/Support/AppIcon.icon" \
    --compile "$app_dir/Contents/Resources" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$output_dir/AppIcon-partial.plist"
rm -f "$output_dir/AppIcon-partial.plist"
chmod 755 "$app_dir/Contents/MacOS/AspaceI"
# Keychain 以簽章判斷是不是同一個 App；ad-hoc 簽章每次建置都不同，會一直重新要求授權。
# 沒有可用憑證時退回 ad-hoc。`|| true` 不能省：CI runner 上 find-identity 回非零，
# 加上 set -o pipefail 會讓整個腳本在這一行結束。
signing_identity=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}' || true)
codesign --force --deep --sign "${signing_identity:--}" "$app_dir"

echo "$app_dir"
