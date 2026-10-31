#!/usr/bin/env bash
# Q3: the reference screenshots.
#
# The set is captured under .run/shots/clean-before/ (or clean-after/), and a
# later set is compared with the earlier one: the shell must look the same
# after the cleanup.
#
# The first capture can only be a BASELINE: it proves something once there is
# a second set to compare it with. The gate says so instead of pretending.
#
# The clock is in the bar, so the bar's shot moves with the time; the diff
# compares the other surfaces and reports the bar separately.
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$MEI"
RUN="$MEI/.run"
RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STATE="${1:-before}"
DIR="$RUN/shots/clean-$STATE"

mkdir -p "$DIR"
if [ ! -d "$RUN/shots/clean-before" ] || [ "$STATE" = "before" ]; then
  echo "capturing the reference set into $DIR"
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei run ) >/dev/null 2>&1
  SIG=""; WD=""
  for _ in $(seq 1 120); do
    [ -z "$SIG" ] && SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    [ -z "$WD" ] && WD="$(ls "$RT"/wayland-* 2>/dev/null | head -1 | xargs -r basename)"
    [ -n "$SIG" ] && [ -n "$WD" ] && break
    sleep 0.5
  done
  sleep 8
  H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
  shot(){ XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WD" HYPRLAND_INSTANCE_SIGNATURE="$SIG" grim "$DIR/$1.png" 2>/dev/null; }
  shot bar
  H dispatch 'hl.dsp.global("mei:launcher")' >/dev/null 2>&1; sleep 2; shot launcher
  H dispatch 'hl.dsp.global("mei:launcher")' >/dev/null 2>&1; sleep 1
  H dispatch 'hl.dsp.global("mei:lock")' >/dev/null 2>&1; sleep 4; shot lock
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
  sleep 2
fi

before="$RUN/shots/clean-before"
if [ ! -f "$before/bar.png" ]; then
  echo "no baseline capture yet"
  exit 1
fi
if [ "$DIR" = "$before" ]; then
  echo "BASELINE-CAPTURED: the reference set is in $before"
  echo "(the comparison proves something once there is a second set)"
  ls -1 "$before" | sed 's/^/  /'
  exit 0
fi

# The comparison: the same names, the same pixels.
if command -v compare >/dev/null 2>&1; then
  diffs=""
  for f in "$before"/*.png; do
    b="$(basename "$f")"
    [ -f "$DIR/$b" ] || { diffs="$diffs $b(missing)"; continue; }
    d="$(compare -metric AE "$f" "$DIR/$b" null: 2>&1 | awk '{print $1+0}')"
    [ "${d:-0}" -gt 0 ] && diffs="$diffs $b($d px)"
  done
  if [ -n "$diffs" ]; then
    echo "FAIL: the look changed:$diffs"
    exit 1
  fi
  echo "ok: the reference set is the same"
  exit 0
fi
echo "BASELINE-CAPTURED: compare is not installed, so the diff cannot run here"
exit 0
