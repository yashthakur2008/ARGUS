#!/bin/bash
# Development artifact only. Never installs, launches, notarizes or publishes.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
APP="$ROOT/build/ARGUS.app"
mkdir -p "$ROOT/build"
LOCK="$ROOT/build/.ARGUS-packaging.lock"
LOCK_HELD=false
STAGE=""
BACKUP=""
PUBLISHED=false
cleanup() {
  local status=$?
  trap - EXIT
  if [[ -n "$BACKUP" && ( -e "$BACKUP/ARGUS.app" || -L "$BACKUP/ARGUS.app" ) && "$PUBLISHED" == false ]]; then
    if [[ ! -e "$APP" && ! -L "$APP" ]] && mv "$BACKUP/ARGUS.app" "$APP"; then
      : # A failed publication restores the previous complete bundle.
    else
      printf 'Previous bundle preserved for recovery at: %s\n' "$BACKUP/ARGUS.app" >&2
      status=1
    fi
  fi
  if [[ -n "$STAGE" ]]; then rm -rf "$STAGE"; fi
  if [[ -n "$BACKUP" && ( "$PUBLISHED" == true || ( ! -e "$BACKUP/ARGUS.app" && ! -L "$BACKUP/ARGUS.app" ) ) ]]; then
    rm -rf "$BACKUP"
  fi
  if [[ "$LOCK_HELD" == true ]] && ! rmdir "$LOCK"; then
    printf 'Could not remove owned packaging lock: %s\n' "$LOCK" >&2
    status=1
  fi
  exit "$status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM
# Never break a lock automatically: an interrupted run may need manual recovery.
if ! mkdir "$LOCK"; then
  printf 'Cannot acquire packaging lock: %s\nConfirm no packager is active and inspect .ARGUS-backup.* before removing a stale lock manually.\n' "$LOCK" >&2
  exit 1
fi
LOCK_HELD=true
SWIFT="${ARGUS_SWIFT:-swift}"
"$SWIFT" build -c release --product ARGUS
BIN_DIR="$("$SWIFT" build -c release --show-bin-path)"
STAGE="$(mktemp -d "$ROOT/build/.ARGUS-stage.XXXXXX")"
STAGED_APP="$STAGE/ARGUS.app"
mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
bash "$ROOT/scripts/build-icon.sh"
cp "$ROOT/build/ARGUS.icns" "$STAGED_APP/Contents/Resources/ARGUS.icns"
# A fresh bundle prevents obsolete resources/code from surviving a rebuild, and
# uses a new executable inode rather than truncating a potentially running binary.
STAGED_EXECUTABLE="$STAGED_APP/Contents/MacOS/ARGUS"
cp "$BIN_DIR/ARGUS" "$STAGED_EXECUTABLE"
chmod 755 "$STAGED_EXECUTABLE"
# Capture inspection first: process-substitution failures would otherwise be lost.
LOAD_COMMANDS="$(/usr/bin/otool -l "$STAGED_EXECUTABLE")"
# Keep system/relative rpaths; strip build-machine paths before signing.
while IFS= read -r rpath; do
  case "$rpath" in
    /usr/lib/*|/System/Library/*) ;;
    /*) /usr/bin/install_name_tool -delete_rpath "$rpath" "$STAGED_EXECUTABLE" ;;
  esac
done < <(printf '%s\n' "$LOAD_COMMANDS" | /usr/bin/awk '/cmd LC_RPATH/{found=1; next} found && /path /{sub(/^ *path /, ""); sub(/ \(offset.*$/, ""); print; found=0}')
cp "$ROOT/Config/Info.plist" "$STAGED_APP/Contents/Info.plist"
/usr/bin/plutil -lint "$STAGED_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$STAGED_APP"
/usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGED_APP"
# Nothing touches the previous output until the entire new bundle is validated.
# Same-filesystem renames preserve the old bundle for rollback if publication fails.
# This is not a power-loss-atomic exchange. SIGKILL between renames can leave the
# previous bundle in .ARGUS-backup.*/ARGUS.app and the lock in place. Inspect and
# restore that backup manually before clearing the lock; never discard it blindly.
if [[ -e "$APP" || -L "$APP" ]]; then
  BACKUP="$(mktemp -d "$ROOT/build/.ARGUS-backup.XXXXXX")"
  mv "$APP" "$BACKUP/ARGUS.app"
fi
mv "$STAGED_APP" "$APP"
PUBLISHED=true
printf 'Development-only ad-hoc bundle: %s\nNot installed, launched, sandbox-verified, or App Store-ready.\n' "$APP"
