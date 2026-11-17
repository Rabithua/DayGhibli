#!/bin/bash
# Regenerate the committed icon assets:
#   Resources/AppIcon.icns    - irregular-shape app icon (transparent margins, no mask)
#   Resources/MenuBarIcon.png - 64 px-high transparent menu bar template icon
#
# Usage: scripts/make-icons.sh
#
# Inputs (already committed): Resources/AppIconSource.png, Resources/MenuBarIcon.svg
# Requires: swift, sips, iconutil (stock macOS toolchain).
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT

# 1. Compose the 1024x1024 transparent master: content scaled so its longest
#    side is <= 1000 px, centered, >= 12 px transparent margin, silhouette intact.
master_png="$scratch/AppIcon.master.png"
swift "$repo_root/scripts/compose-icon-master.swift" \
    "$repo_root/Resources/AppIconSource.png" "$master_png"

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

# 3. Pack the iconset into the committed icns.
iconutil -c icns "$iconset" -o "$repo_root/Resources/AppIcon.icns"

# 4. Render the menu bar icon from the SVG.
swift "$repo_root/scripts/render-menubar-icon.swift" \
    "$repo_root/Resources/MenuBarIcon.svg" "$repo_root/Resources/MenuBarIcon.png"

printf 'Icons written to %s/Resources\n' "$repo_root"
