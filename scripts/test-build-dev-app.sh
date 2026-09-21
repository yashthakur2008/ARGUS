#!/bin/bash
# Synthetic packaging regression only: no Swift compilation, signing, Keychain or network.
# Copy the production script unchanged except rebinding four absolute native tool paths.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${JCODE_SCRATCH_DIR:-${TMPDIR:-/tmp}}/argus-packaging-tests.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
# The packager resolves its root with cd/pwd. Match that path spelling before
# comparing mv arguments, even when TMPDIR has a trailing slash or symlink.
WORK="$(cd "$WORK" && pwd -P)"
failures=0

make_fixture() {
  CASE="$WORK/$1"
  mkdir -p "$CASE/scripts" "$CASE/Config" "$CASE/bin" "$CASE/products" \
    "$CASE/build/ARGUS.app/Contents/MacOS" "$CASE/build/ARGUS.app/Contents/Resources"
  cp "$ROOT/scripts/build-dev-app.sh" "$CASE/scripts/build-dev-app.sh"
  for tool in codesign plutil otool install_name_tool; do
    sed "s|/usr/bin/$tool|\"\$FIXTURE/bin/$tool\"|g" "$CASE/scripts/build-dev-app.sh" > "$CASE/script.next"
    mv "$CASE/script.next" "$CASE/scripts/build-dev-app.sh"
  done
  printf 'new synthetic executable\n' > "$CASE/products/ARGUS"
  printf 'new synthetic plist\n' > "$CASE/Config/Info.plist"
  printf '# Changelog\n\n## v9.9.9 - synthetic\n\n- Synthetic note.\n' > "$CASE/CHANGELOG.md"
  printf 'old synthetic executable\n' > "$CASE/build/ARGUS.app/Contents/MacOS/ARGUS"
  printf 'obsolete executable\n' > "$CASE/build/ARGUS.app/Contents/MacOS/obsolete-tool"
  printf 'obsolete resource\n' > "$CASE/build/ARGUS.app/Contents/Resources/obsolete.txt"
  printf 'old synthetic plist\n' > "$CASE/build/ARGUS.app/Contents/Info.plist"
  cp -R "$CASE/build/ARGUS.app" "$CASE/previous.app"
  # A hard link models an existing mapped executable inode surviving publication.
  ln "$CASE/build/ARGUS.app/Contents/MacOS/ARGUS" "$CASE/old-executable-inode"
  cat > "$CASE/scripts/build-icon.sh" <<'ICON'
#!/bin/bash
set -eu
[[ "${FAIL_AT:-}" != icon ]] || exit 42
printf 'new synthetic icon\n' > "$FIXTURE/build/ARGUS.icns"
ICON
  cat > "$CASE/bin/swift" <<'SWIFT'
#!/bin/bash
set -eu
[[ "${FAIL_AT:-}" != build ]] || exit 42
if [[ "$*" == *--show-bin-path* ]]; then printf '%s\n' "$FIXTURE/products"; fi
SWIFT
  cat > "$CASE/bin/otool" <<'OTOOL'
#!/bin/bash
set -eu
[[ "${FAIL_AT:-}" != inspect ]] || exit 42
printf 'cmd LC_RPATH\npath /synthetic/private/toolchain (offset 12)\n'
OTOOL
  cat > "$CASE/bin/install_name_tool" <<'INSTALL'
#!/bin/bash
set -eu
[[ "${FAIL_AT:-}" != rpath ]] || exit 42
printf 'rpath removed\n' >> "$FIXTURE/tool-calls"
INSTALL
  cat > "$CASE/bin/plutil" <<'PLUTIL'
#!/bin/bash
set -eu
[[ "${FAIL_AT:-}" != plist ]] || exit 42
PLUTIL
  cat > "$CASE/bin/codesign" <<'SIGN'
#!/bin/bash
set -eu
if [[ "$*" == *--verify* ]]; then phase=verify; else phase=sign; fi
bundle="${!#}"
cmp "$FIXTURE/products/ARGUS" "$bundle/Contents/MacOS/ARGUS"
cmp "$FIXTURE/Config/Info.plist" "$bundle/Contents/Info.plist"
cmp "$FIXTURE/build/ARGUS.icns" "$bundle/Contents/Resources/ARGUS.icns"
cmp "$FIXTURE/CHANGELOG.md" "$bundle/Contents/Resources/CHANGELOG.md"
grep -Eq '^[0-9a-f]{7,}|^unavailable$' "$bundle/Contents/Resources/ARGUSCommit.txt"
if [[ -d "$FIXTURE/previous.app" ]]; then
  diff -r "$FIXTURE/previous.app" "$FIXTURE/build/ARGUS.app" >/dev/null
fi
[[ "${FAIL_AT:-}" != "$phase" ]] || exit 42
if [[ "${FAIL_AT:-}" == interrupt && "$phase" == verify ]]; then kill -TERM "$PPID"; fi
printf '%s\n' "$phase" >> "$FIXTURE/tool-calls"
SIGN
  cat > "$CASE/bin/mv" <<'MOVE'
#!/bin/bash
set -eu
if [[ ( "${FAIL_AT:-}" == publish || "${FAIL_AT:-}" == rollback ) && "$1" == *'/.ARGUS-stage.'*'/ARGUS.app' ]]; then exit 42; fi
if [[ "${FAIL_AT:-}" == backup && "$1" == "$FIXTURE/build/ARGUS.app" ]]; then exit 42; fi
if [[ "${FAIL_AT:-}" == rollback && "$1" == *'/.ARGUS-backup.'*'/ARGUS.app' ]]; then exit 42; fi
exec /bin/mv "$@"
MOVE
  chmod +x "$CASE/bin/"*
}

run_case() {
  local name="$1" failure="$2" fresh="${3:-false}"
  make_fixture "$name"
  if [[ "$fresh" == true ]]; then
    rm -rf "$CASE/build/ARGUS.app" "$CASE/previous.app"
  fi
  if [[ "$failure" == contention ]]; then
    mkdir "$CASE/build/.ARGUS-packaging.lock"
    printf 'other packager owns this lock\n' > "$CASE/build/.ARGUS-packaging.lock/owner"
  fi
  local result=0
  FIXTURE="$CASE" FAIL_AT="$failure" ARGUS_SWIFT="$CASE/bin/swift" \
    PATH="$CASE/bin:$PATH" bash "$CASE/scripts/build-dev-app.sh" > "$CASE/output" 2>&1 || result=$?
  local problem=""
  if [[ -n "$failure" ]]; then
    if [[ "$result" == 0 ]]; then problem="failure injection unexpectedly succeeded";
    elif [[ "$failure" == rollback ]]; then
      backup="$(find "$CASE/build" -maxdepth 1 -name '.ARGUS-backup.*')"
      if [[ -z "$backup" ]] || ! diff -r "$CASE/previous.app" "$backup/ARGUS.app" >/dev/null 2>&1 \
        || ! grep -q 'Previous bundle preserved for recovery' "$CASE/output"; then
        problem="rollback failure lost recoverable previous bundle"
      fi
    elif ! diff -r "$CASE/previous.app" "$CASE/build/ARGUS.app" >/dev/null 2>&1; then
      problem="failed packaging changed previous bundle"
    fi
  elif [[ "$result" != 0 ]]; then
    problem="packaging failed ($result)"
  elif [[ -e "$CASE/build/ARGUS.app/Contents/MacOS/obsolete-tool" || \
          -e "$CASE/build/ARGUS.app/Contents/Resources/obsolete.txt" ]]; then
    problem="obsolete content carried into new bundle"
  elif ! cmp "$CASE/products/ARGUS" "$CASE/build/ARGUS.app/Contents/MacOS/ARGUS" >/dev/null; then
    problem="wrong executable published"
  elif [[ ! -x "$CASE/build/ARGUS.app/Contents/MacOS/ARGUS" ]]; then
    problem="published executable is not executable"
  elif ! grep -q '^verify$' "$CASE/tool-calls"; then
    problem="published bundle was not verified"
  fi
  if [[ "$failure" == contention ]]; then
    if ! grep -q 'packaging lock' "$CASE/output" \
      || ! grep -q '^other packager owns this lock$' "$CASE/build/.ARGUS-packaging.lock/owner"; then
      problem="contended lock was changed or error was not actionable"
    fi
  elif [[ -e "$CASE/build/.ARGUS-packaging.lock" ]]; then
    problem="owned packaging lock leaked"
  fi
  if ! grep -q '^old synthetic executable$' "$CASE/old-executable-inode"; then
    problem="previous executable inode was overwritten"
  fi
  if [[ "$failure" != rollback ]] && find "$CASE/build" -maxdepth 1 \( -name '.ARGUS-stage.*' -o -name '.ARGUS-backup.*' \) | grep -q .; then
    problem="temporary stage/backup leaked"
  fi
  if [[ -n "$problem" ]]; then
    printf 'FAIL %s: %s\n' "$name" "$problem"
    cat "$CASE/output"
    failures=$((failures + 1))
  else
    printf 'PASS %s\n' "$name"
  fi
}

run_case replaces_whole_bundle ""
run_case creates_initial_bundle "" true
for phase in build icon inspect rpath plist sign verify backup publish rollback interrupt contention; do
  run_case "preserves_previous_on_$phase" "$phase"
done
[[ "$failures" == 0 ]] || { printf '%s packaging regression(s) failed\n' "$failures"; exit 1; }
printf '14 synthetic packaging regressions passed. No real toolchain or signing was used.\n'
