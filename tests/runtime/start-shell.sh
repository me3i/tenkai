#!/usr/bin/env bash
# start-shell.sh — locate the running nested/live Tenkai shell and capture its
# log. It does NOT invent a launcher: ./tenkai run owns starting a nested
# session, and the daemon supervises `qs -p .../shell`. If nothing is running,
# this prints the exact command to start one and exits 3 (UNVERIFIED).
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TS="${1:-$(date +%Y%m%d-%H%M%S)}"
OUT="$ROOT/tests/evidence/$TS"
mkdir -p "$OUT"

pid=$(pgrep -f '^qs -p .*/tenkai_core/shell/quickshell/shell$' | head -1)
if [ -z "$pid" ]; then
  printf 'no running Tenkai shell; start one with:\n  ./tenkai run\n' >&2
  exit 3
fi
log="$ROOT/.run/state/tenkai/surfaces/shell.log"
[ -f "$log" ] || log="/proc/$pid/fd/2"
printf 'pid=%s\nlog=%s\n' "$pid" "$log" > "$OUT/shell-meta.txt"
cp -a "$log" "$OUT/shell.log" 2>/dev/null || true
printf '%s\n' "$pid"
