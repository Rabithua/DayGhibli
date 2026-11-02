#!/bin/bash
set -euo pipefail
task_root="$(cd "$(dirname "$0")" && pwd)"
task_scratch="${BUILD_DIR:-$task_root/.build}"
app_path="${APP_OUTPUT:-$task_root/../每日吉卜力.app}"

swift build --package-path "$task_root" --scratch-path "$task_scratch" -c release
binary_dir="$(swift build --package-path "$task_root" --scratch-path "$task_scratch" -c release --show-bin-path)"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources"
cp "$binary_dir/DayGhibli" "$app_path/Contents/MacOS/DayGhibli"
cp "$task_root/Resources/catalog.json" "$task_root/Resources/SourceNotice.txt" "$app_path/Contents/Resources/"
cat > "$app_path/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
    <key>CFBundleIdentifier</key><string>me.dayghibli.mac</string>
    <key>CFBundleName</key><string>每日吉卜力</string>
    <key>CFBundleDisplayName</key><string>每日吉卜力</string>
    <key>CFBundleExecutable</key><string>DayGhibli</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.4.3</string>
    <key>CFBundleVersion</key><string>9</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSHumanReadableCopyright</key><string>Images © respective rights holders. See SourceNotice.txt.</string>
</dict></plist>
PLIST
codesign --force --sign - "$app_path"
printf 'Built: %s\n' "$app_path"
