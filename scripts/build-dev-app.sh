#!/bin/bash
# Development artifact only. Never installs, launches, notarizes or publishes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
SWIFT="${ARGUS_SWIFT:-swift}"
"$SWIFT" build -c release --product ARGUS
BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"
APP="$ROOT/build/ARGUS.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
bash "$ROOT/scripts/build-icon.sh"
cp "$ROOT/build/ARGUS.icns" "$APP/Contents/Resources/ARGUS.icns"
# Replace the executable inode, never truncate a potentially running mapped binary.
STAGED_EXECUTABLE="$(mktemp "$APP/Contents/MacOS/.ARGUS.XXXXXX")"
trap 'if [[ -n "${STAGED_EXECUTABLE:-}" ]]; then rm -f "$STAGED_EXECUTABLE"; fi' EXIT
cp "$BIN_DIR/ARGUS" "$STAGED_EXECUTABLE"
chmod 755 "$STAGED_EXECUTABLE"
# Swift toolchains may inject absolute testing-library search paths even into
# release binaries. System Swift libraries have absolute /usr/lib install names.
# Keep relative bundle rpaths, remove build-machine absolute rpaths before signing.
while IFS= read -r rpath; do
  case "$rpath" in
    /usr/lib/*|/System/Library/*) ;;
    /*) /usr/bin/install_name_tool -delete_rpath "$rpath" "$STAGED_EXECUTABLE" ;;
  esac
done < <(/usr/bin/otool -l "$STAGED_EXECUTABLE" | /usr/bin/awk '/cmd LC_RPATH/{found=1; next} found && /path /{sub(/^ *path /, ""); sub(/ \(offset.*$/, ""); print; found=0}')
mv -f "$STAGED_EXECUTABLE" "$APP/Contents/MacOS/ARGUS"
STAGED_EXECUTABLE=""
cp "$ROOT/Config/Info.plist" "$APP/Contents/Info.plist"
/usr/bin/plutil -lint "$APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$APP"
printf 'Development-only ad-hoc bundle: %s\nNot installed, launched, sandbox-verified, or App Store-ready.\n' "$APP"
