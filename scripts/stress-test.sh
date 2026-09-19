#!/usr/bin/env bash
# Repeated full Swift Testing suites. No live hardware coverage is implied.
set -euo pipefail

refuse() { printf 'stress-test: %s\n' "$*" >&2; exit 2; }
[ "$#" -eq 1 ] || refuse 'usage: bash scripts/stress-test.sh OUTPUT_DIR'
runs=${ARGUS_STRESS_RUNS-3}
configuration=${ARGUS_STRESS_CONFIGURATION-debug}
swift=${ARGUS_SWIFT-swift}
case "$runs" in [1-5]) ;; *) refuse 'ARGUS_STRESS_RUNS must be an integer 1..5' ;; esac
case "$configuration" in debug|release) ;; *) refuse 'ARGUS_STRESS_CONFIGURATION must be debug or release' ;; esac
[ -n "$swift" ] || refuse 'ARGUS_SWIFT must not be empty'
swift=$(command -v "$swift") || refuse 'Swift executable not found'
[ -f "$swift" ] && [ -x "$swift" ] || refuse 'Swift must be an executable file'
case "$swift" in /*) ;; *) swift="$PWD/$swift" ;; esac
[ -n "$1" ] || refuse 'OUTPUT_DIR must not be empty'
case "$1" in /*) output=$1 ;; *) output="$PWD/$1" ;; esac
[ ! -e "$output" ] && [ ! -L "$output" ] || refuse 'OUTPUT_DIR must be new (not an existing path or symlink)'
[ -d "$(dirname "$output")" ] || refuse 'OUTPUT_DIR parent must exist'

repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo"
commit=$(git rev-parse HEAD)
status=$(git status --porcelain)
dirty=clean
[ -z "$status" ] || dirty=dirty
# mkdir without -p also refuses a path created between validation and creation.
mkdir "$output"
summary="$output/summary.md"
complete=0
finish() {
    code=$?
    if [ "$complete" -ne 1 ]; then
        [ "$code" -ne 0 ] || code=1
        printf '\nOutcome: FAILED / INCOMPLETE (exit %s). Evidence retained.\n' "$code" >> "$summary"
    fi
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '# Stress test evidence\n\nOutcome: IN PROGRESS\n\nNo live hardware acceptance is claimed by this runner.\nConfiguration: %s\nPlanned runs: %s\n' "$configuration" "$runs" > "$summary"
printf 'Commit: %s\nWorking tree: %s\nConfiguration: %s\nRuns: %s\n' "$commit" "$dirty" "$configuration" "$runs" > "$output/metadata.txt"
python3 - "$repo/Config/Info.plist" >> "$output/metadata.txt" <<'PY'
import plistlib
import sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
print('App version: ' + info['CFBundleShortVersionString'])
print('App build: ' + info['CFBundleVersion'])
PY
printf 'Toolchain:\n' >> "$output/metadata.txt"

# Prefer the tool's exact failure code even if tee also fails. A logging failure
# must never result in a success label. PIPESTATUS arrays work on Bash 3.
run_logged() {
    log=$1
    shift
    set +e
    "$@" 2>&1 | tee -a "$log"
    codes=("${PIPESTATUS[@]}")
    set -e
    [ "${codes[0]}" -eq 0 ] || return "${codes[0]}"
    return "${codes[1]}"
}
run_logged "$output/metadata.txt" "$swift" --version
args=(test -c "$configuration" --disable-xctest --enable-swift-testing)
i=1
while [ "$i" -le "$runs" ]; do
    printf '\nRun %s: IN PROGRESS\n' "$i" >> "$summary"
    if run_logged "$output/run-$i.log" "$swift" "${args[@]}"; then
        printf 'Run %s: PASS\n' "$i" >> "$summary"
    else
        code=$?
        printf 'Run %s: FAIL (exit %s)\n' "$i" "$code" >> "$summary"
        exit "$code"
    fi
    if [ "$i" -eq 1 ]; then args+=(--skip-build); fi
    i=$((i + 1))
done
printf '\nOutcome: SUCCESS (all %s default-enabled suite runs passed).\n' "$runs" >> "$summary"
complete=1
