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
# Runtime dependencies must not resolve from a developer's home or extracted toolchain.
if printf '%s\n' "$DEPENDENCIES" | tail -n +2 | grep -E '^[[:space:]]+(/Users/|/private/|/var/|/tmp/)' >/dev/null; then
  printf '%s\n' 'ERROR: development-only absolute runtime dependency found.' >&2
  exit 1
fi
# Capture outside the conditional so inspection failure is not mistaken for
# "no forbidden paths". Bash deliberately suppresses errexit in if conditions.
LOAD_COMMANDS="$(otool -l "$APP/Contents/MacOS/ARGUS")"
RPATHS="$(printf '%s\n' "$LOAD_COMMANDS" | awk '/cmd LC_RPATH/{r=1;next} r && /path /{print $2;r=0}')"
if printf '%s\n' "$RPATHS" | grep -E '^(/Users/|/private/|/var/|/tmp/)' >/dev/null; then
  printf '%s\n' 'ERROR: development-only absolute runtime search path found.' >&2
  exit 1
fi
printf '%s\n' 'Local checks passed. Ad-hoc development bundle only. Notification delivery, sandbox confinement, release signing, and App Store review require separate verification.'
