#!/bin/bash
# Regenerate the icon assets:
#   Resources/AppIcon.icns    - full-bleed 1024x1024 app icon (fallback only)
#   Resources/MenuBarIcon.png - 64 px-high transparent menu bar template icon
#
# The icon macOS actually ships is built at ./build.sh time from
# Resources/AppIcon.icon (a layered .icon directory compiled with actool into
# Assets.car). This script exists to regenerate the committed-looking
# AppIcon.icns fallback and the menu bar icon; the icns it produces is NOT
# copied into the app bundle unless you re-add that copy to build.sh.
#
# Usage: scripts/make-icons.sh
#
# Inputs (already committed): Resources/AppIconSource.png, Resources/MenuBarIcon.svg
# Requires: swift, sips, iconutil, xcrun actool (stock macOS toolchain).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# 1. The app-icon source is a 1024x1024 fully opaque, full-bleed square: the
#    black plate IS the icon body. Use it verbatim as the master - no scaling,
#    no margins, no mask; the system applies the rounded-corner shape.
master_png="$repo_root/Resources/AppIconSource.png"

# 2. Scribe the full iconset from the master with sips.
iconset="$scratch/AppIcon.iconset"
mkdir "$iconset"
while IFS='|' read -r size name; do
    sips -z "$size" "$size" "$master_png" --out "$iconset/$name" >/dev/null
done <<'SIZES'
16|icon_16x16.png
32|icon_16x16@2x.png
32|icon_32x32.png
64|icon_32x32@2x.png
128|icon_128x128.png
256|icon_128x128@2x.png
256|icon_256x256.png
512|icon_256x256@2x.png
512|icon_512x512.png
1024|icon_512x512@2x.png
SIZES

# 3. Pack the iconset into the fallback icns.
iconutil -c icns "$iconset" -o "$repo_root/Resources/AppIcon.icns"

# 4. Render the menu bar icon from the SVG.
swift "$repo_root/scripts/render-menubar-icon.swift" \
    "$repo_root/Resources/MenuBarIcon.svg" "$repo_root/Resources/MenuBarIcon.png"

printf 'Icons written to %s/Resources\n' "$repo_root"
