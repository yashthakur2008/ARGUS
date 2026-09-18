#!/bin/bash
# Reproducible local checks. This does not prove OS delivery or App Store eligibility.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SWIFT="${ARGUS_SWIFT:-swift}"
"$SWIFT" --version
bash scripts/test-build-dev-app.sh
bash scripts/test-verify.sh
"$SWIFT" test --disable-xctest --enable-swift-testing
ARGUS_SWIFT="$SWIFT" bash scripts/build-dev-app.sh
APP="$ROOT/build/ARGUS.app"
plutil -lint "$APP/Contents/Info.plist"
test "$(plutil -extract CFBundleIconFile raw "$APP/Contents/Info.plist")" = "ARGUS.icns"
test -s "$APP/Contents/Resources/ARGUS.icns"
test -n "$(plutil -extract NSMicrophoneUsageDescription raw "$APP/Contents/Info.plist")"
test -n "$(plutil -extract NSSpeechRecognitionUsageDescription raw "$APP/Contents/Info.plist")"
cmp "$ROOT/build/ARGUS.icns" "$APP/Contents/Resources/ARGUS.icns"
codesign --verify --deep --strict --verbose=2 "$APP"
DEPENDENCIES="$(otool -L "$APP/Contents/MacOS/ARGUS")"
printf '%s\n' "$DEPENDENCIES"
# Only macOS system locations may be absolute. Homebrew, local frameworks,
# mounted build volumes and toolchains are not portable runtime dependencies.
# Bundle-relative install names are allowed here; this is not a dyld resolution audit.
if printf '%s\n' "$DEPENDENCIES" | tail -n +2 | grep -E '^[[:space:]]+/' | grep -E '/\.\.(/|[[:space:]]+\(|$)' >/dev/null; then
  printf '%s\n' 'ERROR: parent traversal in absolute runtime dependency found.' >&2
  exit 1
fi
if printf '%s\n' "$DEPENDENCIES" | tail -n +2 | grep -E '^[[:space:]]+/' | grep -Ev '^[[:space:]]+(/System/Library/|/usr/lib/)' >/dev/null; then
  printf '%s\n' 'ERROR: non-system absolute runtime dependency found.' >&2
  exit 1
fi
# Capture outside the conditional so inspection failure is not mistaken for
# "no forbidden paths". Bash deliberately suppresses errexit in if conditions.
LOAD_COMMANDS="$(otool -l "$APP/Contents/MacOS/ARGUS")"
RPATHS="$(printf '%s\n' "$LOAD_COMMANDS" | awk '
  /cmd LC_RPATH/{r=1;next}
  r && /^[[:space:]]*path[[:space:]]/{
    sub(/^[[:space:]]*path[[:space:]]+/, "")
    sub(/[[:space:]]+\(offset [0-9]+\)[[:space:]]*$/, "")
    print; r=0
  }')"
if printf '%s\n' "$RPATHS" | grep -E '^/' | grep -E '/\.\.(/|$)' >/dev/null; then
  printf '%s\n' 'ERROR: parent traversal in absolute runtime search path found.' >&2
  exit 1
fi
if printf '%s\n' "$RPATHS" | grep -E '^/' | grep -Ev '^(/System/Library|/usr/lib)(/|$)' >/dev/null; then
  printf '%s\n' 'ERROR: non-system absolute runtime search path found.' >&2
  exit 1
fi
printf '%s\n' 'Local checks passed. Ad-hoc development bundle only. Notification delivery, sandbox confinement, release signing, and App Store review require separate verification.'
