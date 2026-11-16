#!/usr/bin/env bash
# dev/linux-build.sh, showing only the errors (and the last line).
cd "$(dirname "$0")/.."
log=$(mktemp)
dev/linux-build.sh "$@" >"$log" 2>&1
# Each error once: the compiler repeats them per file it emits.
grep -E 'error:' -A4 "$log" | grep -v '^\[' | awk '!seen[$0]++' | head -${LINES_MAX:-120}
tail -2 "$log"
rm -f "$log"
