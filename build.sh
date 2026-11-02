#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_scratch="${BUILD_DIR:-$task_root/.build}"
app_path="${APP_OUTPUT:-$task_root/../每日吉卜力.app}"
signing_identity="${SIGNING_IDENTITY:--}"

swift build --package-path "$task_root" --scratch-path "$task_scratch" -c release
binary_dir="$(swift build --package-path "$task_root" --scratch-path "$task_scratch" -c release --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$app_path/Contents/Frameworks"
cp "$binary_dir/DayGhibli" "$app_path/Contents/MacOS/DayGhibli"
cp "$task_root/Resources/catalog.json" "$task_root/Resources/SourceNotice.txt" \
    "$task_root/Resources/Sparkle-LICENSE.txt" "$app_path/Contents/Resources/"
sparkle_framework="$task_scratch/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$sparkle_framework" ]]; then
    printf 'Sparkle framework not found: %s\n' "$sparkle_framework" >&2
    exit 1
fi
rm -rf "$app_path/Contents/Frameworks/Sparkle.framework"
ditto "$sparkle_framework" "$app_path/Contents/Frameworks/Sparkle.framework"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>me.dayghibli.mac</string>
    <key>CFBundleName</key><string>每日吉卜力</string>
    <key>CFBundleDisplayName</key><string>每日吉卜力</string>
    <key>CFBundleExecutable</key><string>DayGhibli</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.5.0</string>
    <key>CFBundleVersion</key><string>10</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>SUFeedURL</key><string>https://raw.githubusercontent.com/Rabithua/DayGhibli/main/appcast.xml</string>
    <key>SUPublicEDKey</key><string>Ay6nb+J34D2BM5qKkwcnmViJH+5MKxW3xoeIvzGqTXE=</string>
    <key>SUEnableAutomaticChecks</key><true/>
    <key>SUAutomaticallyUpdate</key><true/>
    <key>SUScheduledCheckInterval</key><integer>86400</integer>
    <key>SUEnableSystemProfiling</key><false/>
    <key>SUVerifyUpdateBeforeExtraction</key><true/>
    <key>SURequireSignedFeed</key><true/>
    <key>NSHumanReadableCopyright</key><string>Images © respective rights holders. See SourceNotice.txt.</string>
</dict></plist>
PLIST
sign_args=(--force --sign "$signing_identity")
if [[ "$signing_identity" != "-" ]]; then
    sign_args+=(--options runtime --timestamp)
fi
sparkle_version="$app_path/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign "${sign_args[@]}" "$sparkle_version/XPCServices/Installer.xpc"
codesign "${sign_args[@]}" --preserve-metadata=entitlements "$sparkle_version/XPCServices/Downloader.xpc"
codesign "${sign_args[@]}" "$sparkle_version/Autoupdate"
codesign "${sign_args[@]}" "$sparkle_version/Updater.app"
codesign "${sign_args[@]}" "$app_path/Contents/Frameworks/Sparkle.framework"
codesign "${sign_args[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf 'Built: %s\n' "$app_path"
