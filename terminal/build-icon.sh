#!/bin/zsh
set -euo pipefail
cd -- "${0:A:h}"
stage=$(mktemp -d "${TMPDIR:-/tmp}/boterm-icon.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT
mkdir "$stage/Boterm.iconset"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" ../assets/boterm/icon-grid.png --out "$stage/Boterm.iconset/icon_${size}x${size}.png" >/dev/null
    retina=$((size * 2))
    sips -z "$retina" "$retina" ../assets/boterm/icon-grid.png --out "$stage/Boterm.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$stage/Boterm.iconset" -o Boterm.icns
sips -s format png Boterm.icns --out "$stage/decoded.png" >/dev/null
[[ -s "$stage/decoded.png" ]]
print "Built: $PWD/Boterm.icns"
