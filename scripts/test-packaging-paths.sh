#!/bin/bash
# Exercise the existing synthetic packaging suite under portable temp-path layouts.
# No real compilation, signing, app launch, credentials or network operations occur.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d "${JCODE_SCRATCH_DIR:-${TMPDIR:-/tmp}}/argus-packaging-paths.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
WORK="$(cd "$WORK" && pwd -P)"
mkdir "$WORK/plain" "$WORK/with spaces" "$WORK/real"
ln -s "$WORK/real" "$WORK/link with spaces"

for variant in trailing_slash whitespace symlink; do
  case "$variant" in
    trailing_slash) scratch="$WORK/plain/" ;;
    whitespace) scratch="$WORK/with spaces" ;;
    symlink) scratch="$WORK/link with spaces/" ;;
  esac
  printf 'Checking packaging fixture layout: %s\n' "$variant"
  JCODE_SCRATCH_DIR="$scratch" /bin/bash "$ROOT/scripts/test-build-dev-app.sh"
done
printf '3 packaging temporary-path variants passed using the existing synthetic suite.\n'
