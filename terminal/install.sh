#!/bin/zsh
# Installs terminal/Boterm.app into /Applications without quitting a running Boterm, and makes sure macOS
# only knows that one copy. Any other bundle with the same id (old builds, test copies, the old VozTTY.app)
# can make the Dock and Finder show its old icon, so each one is unregistered and old builds are kept
# under a name that is not a bundle (".app-old"), which LaunchServices never registers again.
set -euo pipefail
cd "${0:A:h}/.."
ID=com.danyalgil.voztty.terminal
LS=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
NEW=terminal/Boterm.app
[[ -d $NEW ]] || { echo "Build first: terminal/build.sh" >&2; exit 1; }

mkdir -p work/old-builds
rm -rf /Applications/Boterm-new.app
ditto "$NEW" /Applications/Boterm-new.app
if [[ -d /Applications/Boterm.app ]]; then
  old=$(defaults read /Applications/Boterm.app/Contents/Info CFBundleVersion 2>/dev/null || echo unknown)
  $LS -u /Applications/Boterm.app
  mv /Applications/Boterm.app "work/old-builds/Boterm-build$old-$(date +%Y%m%d%H%M%S).app-old"
fi
mv /Applications/Boterm-new.app /Applications/Boterm.app

# Unregister every other registered copy with our bundle id.
$LS -dump 2>/dev/null | awk -v id="$ID" '
  /^path:/ { sub(/^path: */, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); path = $0 }
  /^identifier:/ && $2 == id && path != "/Applications/Boterm.app" { print path }
' | sort -u | while IFS= read -r stale; do
  $LS -u "$stale" 2>/dev/null || true
  # Old copies kept as bundles get registered again by Spotlight/Finder; keep them, but not as bundles.
  if [[ -d $stale && $stale == *.app && $stale != */terminal/Boterm.app ]]; then mv "$stale" "${stale}-old"; fi
  echo "unregistered: $stale"
done

touch /Applications/Boterm.app
$LS -f /Applications/Boterm.app
# The Dock keeps its own icon cache, which can hold the old icon even after LaunchServices is fixed.
rm -f "$(getconf DARWIN_USER_CACHE_DIR)com.apple.dock.iconcache"
killall Dock 2>/dev/null || true
echo "Installed build $(defaults read /Applications/Boterm.app/Contents/Info CFBundleVersion)"
