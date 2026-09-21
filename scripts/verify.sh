#!/bin/bash
# Reproducible local checks. This does not prove OS delivery or App Store eligibility.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
SWIFT="${ARGUS_SWIFT:-swift}"
"$SWIFT" --version
bash scripts/test-build-dev-app.sh
bash scripts/test-verify.sh
TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/argus-swift-test.XXXXXX")"
cleanup_test_log() { rm -f "$TEST_LOG"; }
trap cleanup_test_log EXIT
set +e
"$SWIFT" test --disable-xctest --enable-swift-testing 2>&1 | tee "$TEST_LOG"
TEST_CODES=("${PIPESTATUS[@]}")
set -e
if [ "${TEST_CODES[0]}" -ne 0 ]; then
  if [ "${TEST_CODES[0]}" -eq 134 ] || grep -E 'Symbol not found|swift-package|llbuild' "$TEST_LOG" >/dev/null; then
    cat >&2 <<EOF
ERROR: Swift test execution failed in a way that often indicates a mismatched
Command Line Tools SwiftPM/llbuild installation.

Select a complete Xcode toolchain or pass an explicit Swift executable, for example:
  export DEVELOPER_DIR=/Applications/Xcode_16.4.app/Contents/Developer
  export ARGUS_SWIFT=/Applications/Xcode_16.4.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift
  bash scripts/verify.sh

If you installed a standalone Swift toolchain, set ARGUS_SWIFT to that toolchain's
swift executable. The failing executable was: $SWIFT
EOF
  fi
  exit "${TEST_CODES[0]}"
fi
if [ "${TEST_CODES[1]}" -ne 0 ]; then
  echo 'ERROR: could not write Swift test output log.' >&2
  exit "${TEST_CODES[1]}"
fi
cleanup_test_log
trap - EXIT
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
