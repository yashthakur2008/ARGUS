#!/bin/bash
# Exercise the verification orchestrator with synthetic tools and bundle files only.
# No Swift compilation, native signing, application launch or network operation occurs.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${JCODE_SCRATCH_DIR:-${TMPDIR:-/tmp}}/argus-verification-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scripts" "$WORK/bin" "$WORK/build/ARGUS.app/Contents/Resources"
cp "$ROOT/scripts/verify.sh" "$WORK/scripts/verify.sh"
# The copied orchestrator must not recurse into this harness or perform real packaging.
for script in test-build-dev-app.sh test-verify.sh build-dev-app.sh; do
  printf '#!/bin/bash\nexit 0\n' > "$WORK/scripts/$script"
done
printf 'synthetic icon\n' > "$WORK/build/ARGUS.icns"
cp "$WORK/build/ARGUS.icns" "$WORK/build/ARGUS.app/Contents/Resources/ARGUS.icns"
printf 'synthetic plist\n' > "$WORK/build/ARGUS.app/Contents/Info.plist"
cat > "$WORK/bin/swift" <<'SWIFT'
#!/bin/bash
[[ "${FAIL_AT:-}" != swift ]] || exit 42
exit 0
SWIFT
cat > "$WORK/bin/plutil" <<'PLUTIL'
#!/bin/bash
[[ "${FAIL_AT:-}" != plist ]] || exit 42
if [[ "${1:-}" == -extract ]]; then
  case "$2" in
    CFBundleIconFile) echo ARGUS.icns ;;
    NSMicrophoneUsageDescription|NSSpeechRecognitionUsageDescription)
      [[ "${FAIL_AT:-}" == disclosure ]] || echo 'Synthetic nonempty usage description' ;;
    *) exit 43 ;;
  esac
fi
exit 0
PLUTIL
cat > "$WORK/bin/codesign" <<'CODESIGN'
#!/bin/bash
[[ "${FAIL_AT:-}" != signature ]] || exit 42
exit 0
CODESIGN
cat > "$WORK/bin/otool" <<'OTOOL'
#!/bin/bash
case "$1" in
  -L)
    [[ "${FAIL_AT:-}" != dependencies ]] || exit 42
    printf 'synthetic executable:\n'
    if [[ "${FAIL_AT:-}" == private_dependency ]]; then
      printf '\t/Users/synthetic/libPrivate.dylib (compatibility version 1.0.0)\n'
    else
      printf '\t/usr/lib/libSystem.B.dylib (compatibility version 1.0.0)\n'
    fi ;;
  -l)
    [[ "${FAIL_AT:-}" != load_commands ]] || { echo 'synthetic inspection failure' >&2; exit 42; }
    printf 'Load command 0\n          cmd LC_RPATH\n      cmdsize 40\n'
    if [[ "${FAIL_AT:-}" == private_rpath ]]; then
      printf '         path /Users/synthetic/toolchain/lib (offset 12)\n'
    else
      printf '         path /usr/lib/swift (offset 12)\n'
    fi ;;
  *) exit 43 ;;
esac
OTOOL
chmod +x "$WORK/bin/"*
failures=0
cases=0
for scenario in success swift plist disclosure signature dependencies load_commands private_dependency private_rpath; do
  cases=$((cases + 1))
  status=0
  PATH="$WORK/bin:$PATH" ARGUS_SWIFT="$WORK/bin/swift" FAIL_AT="$scenario" \
    /bin/bash "$WORK/scripts/verify.sh" > "$WORK/$scenario.log" 2>&1 || status=$?
  if [[ "$scenario" == success ]]; then
    if [[ "$status" == 0 ]] && grep -q 'Local checks passed' "$WORK/$scenario.log"; then
      echo "PASS $scenario"
    else
      echo "FAIL $scenario: expected successful synthetic verification"; cat "$WORK/$scenario.log"
      failures=$((failures + 1))
    fi
  elif [[ "$status" != 0 ]] && ! grep -q 'Local checks passed' "$WORK/$scenario.log"; then
    echo "PASS rejects_$scenario"
  else
    echo "FAIL rejects_$scenario: exit=$status, verification must fail closed"; cat "$WORK/$scenario.log"
    failures=$((failures + 1))
  fi
done
[[ "$failures" == 0 ]] || exit 1
echo "$cases synthetic verification regressions passed. No real compilation or signing was used."
