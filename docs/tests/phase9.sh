#!/usr/bin/env bash
# Phase 9: the full acceptance pass, cold start, one run.
#
#   docs/tests/phase9.sh        -> cold start, core + step4/5/6/7/8, restore, table
#   docs/tests/phase9.sh KEEP   -> leave the last session up (debug)
#
# Every sub-harness starts and stops its own nested session and runs
# verify-untouched itself. The cold start moves (never deletes)
# .run/state, .run/cache, .run/config/mei and the fake-HOME cache/state to
# .run/backup-<stamp>, and restores them on exit.
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="$RUN/logs/phase9-$STAMP.log"
BK="$RUN/backup-$STAMP"
mkdir -p "$RUN/logs" "$RUN/shots" "$BK"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

# ── cold start ──────────────────────────────────────────────────────────────
echo "=== cold start (backup $BK) ==="
if pgrep -f "^qs -p $MEI/src/ryoku/shell|^$RUN/bin/mei-shell daemon" >/dev/null 2>&1; then
  bad "a nested session is already running; refusing to cold-start over it"
  echo "RESULT: FAIL"; exit 1
fi
for d in state cache config/mei home/.cache/mei home/.local/state/mei; do
  if [ -e "$RUN/$d" ]; then
    mkdir -p "$BK/$(dirname "$d")"
    mv "$RUN/$d" "$BK/$d"
    note "moved .run/$d -> $BK/$d"
  fi
done

restore() {
  [ "${KEEP:-0}" = 1 ] && return
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
  sleep 2
  for d in state cache config/mei home/.cache/mei home/.local/state/mei; do
    rm -rf "$RUN/$d"
    if [ -e "$BK/$d" ]; then
      mkdir -p "$RUN/$(dirname "$d")"
      mv "$BK/$d" "$RUN/$d"
    fi
  done
  echo "  restored the pre-cold-start state"
}
trap restore EXIT

# ── item 13/14/15 snapshots (before) ────────────────────────────────────────
REAL_DIRS=(.config/kitty .config/btop .config/qt6ct .config/gtk-3.0 .config/gtk-4.0 .config/ryoku .config/matugen .cache/ryoku .cache/matugen)
hash_real() {
  for d in "${REAL_DIRS[@]}"; do
    if [ -e "$HOME/$d" ]; then
      printf '%s ' "$d"
      find "$HOME/$d" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'
    else
      echo "$d absent"
    fi
  done
}
hash_hypr() { find "$HOME/.config/hypr" -type f -print0 2>/dev/null | sort -z | xargs -0 sha256sum 2>/dev/null | sha256sum | awk '{print $1}'; }
live_owners() { busctl --user list --no-legend 2>/dev/null | awk '$1=="org.freedesktop.Notifications"||$1=="org.kde.StatusNotifierWatcher"{print $1"="$2}' | sort; }
home_names() { find "$HOME" -xdev -mindepth 1 \( -iname '*mei*' -o -iname '*ryoku*' -o -iname '*ryogami*' \) -not -path "$MEI*" 2>/dev/null | sort; }

hash_real > "$BK/real-before.txt"
hash_hypr > "$BK/hypr-before.txt"
live_owners > "$BK/owners-before.txt"
home_names > "$BK/home-names-before.txt"
note "real paths: $(wc -l < "$BK/real-before.txt") entries hashed"
note "live D-Bus owners: $(tr '\n' ' ' < "$BK/owners-before.txt")"

# ── the pass ────────────────────────────────────────────────────────────────
declare -A SRC RC EVID
run_one() { # $1 = item key, $2 = label, $3 = command...
  local key="$1" label="$2"; shift 2
  local out="$RUN/logs/phase9-${key}-$STAMP.log"
  echo; echo "================ $label ================"
  "$@" > "$out" 2>&1
  RC[$key]=$?
  SRC[$key]="$out"
  tail -3 "$out" | sed 's/^/  | /'
  if [ "${RC[$key]}" = 0 ] && ! grep -q '^FAIL' "$out"; then
    ok "$label"
  else
    bad "$label (rc=${RC[$key]}, see $out)"
    grep '^FAIL' "$out" | head -5 | sed 's/^/  | /'
  fi
}

run_one core  "items 1,2,3,4,10,11,12: launch, bar, launcher, sidebar, dependency, shutdown, idle" \
  bash "$MEI/docs/tests/phase9-core.sh"
if [ "${ONLY:-all}" = core ]; then
  echo; echo "ONLY=core: stopping before the item harnesses"
else
run_one item8 "item 8: Settings (5 pages, persistence across restart, reset)" \
  bash "$MEI/docs/tests/step4.sh"
run_one item7 "item 7: wallpaper set, reveal, recolour" \
  bash "$MEI/docs/tests/step5.sh"
run_one item5 "item 5: notifications (popup, DND, actions, dismiss, clear)" \
  bash "$MEI/docs/tests/step6.sh"
run_one item6 "item 6: tray (add, click, menu, remove)" \
  bash "$MEI/docs/tests/step7.sh"
run_one item9 "item 9: every module off, and the 3-off combo" \
  bash "$MEI/docs/tests/phase8.sh"
fi

# ── items 13/14/15 (after) ──────────────────────────────────────────────────
echo; echo "================ items 13,14,15 ================"
hash_real > "$BK/real-after.txt"
hash_hypr > "$BK/hypr-after.txt"
live_owners > "$BK/owners-after.txt"
home_names > "$BK/home-names-after.txt"
if diff -u "$BK/real-before.txt" "$BK/real-after.txt" >/dev/null; then
  ok "13 real ~/.config and ~/.cache paths unchanged"
else
  bad "13 a real path changed"; diff -u "$BK/real-before.txt" "$BK/real-after.txt" | sed 's/^/  /'
fi
if diff -u "$BK/hypr-before.txt" "$BK/hypr-after.txt" >/dev/null; then
  ok "14 Hyprland config byte-identical"
else
  bad "14 ~/.config/hypr changed"; diff -u "$BK/hypr-before.txt" "$BK/hypr-after.txt" | sed 's/^/  /'
fi
if diff -u "$BK/owners-before.txt" "$BK/owners-after.txt" >/dev/null; then
  ok "14 live D-Bus owners unchanged ($(tr '\n' ' ' < "$BK/owners-after.txt"))"
else
  bad "14 live D-Bus owners changed"; diff -u "$BK/owners-before.txt" "$BK/owners-after.txt" | sed 's/^/  /'
fi
if diff -u "$BK/home-names-before.txt" "$BK/home-names-after.txt" >/dev/null; then
  ok "15 no new mei/ryoku/ryogami name under the real HOME"
else
  bad "15 new names under the real HOME"; diff -u "$BK/home-names-before.txt" "$BK/home-names-after.txt" | sed 's/^/  /'
fi
echo "  verify-untouched: $( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )"

# ── table ────────────────────────────────────────────────────────────────────
echo; echo "================ PHASE 9 TABLE ================"
row() { printf '%-3s %-46s %-9s %s\n' "$1" "$2" "$3" "$4"; }
row "#" "item" "status" "evidence"
row "1"  "launch, no QML errors"                     "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "2"  "bar + workspaces match Hyprland"            "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "3"  "launcher open/search/launch/close"          "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "4"  "sidebar (clock, battery, net, audio, bright)" "PARTIAL" "panel+clock+read-only audio TESTED; brightness control UNVERIFIED (${SRC[core]:-})"
row "5"  "notifications"                              "$([ ${RC[item5]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[item5]:-}"
row "6"  "tray"                                       "$([ ${RC[item6]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[item6]:-}"
row "7"  "wallpaper + recolour"                       "$([ ${RC[item7]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[item7]:-}"
row "8"  "Settings 5 pages, persistence, reset"       "$([ ${RC[item8]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[item8]:-}"
row "9"  "modules off + 3-off combo"                  "$([ ${RC[item9]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[item9]:-}"
row "10" "missing optional dependency"                "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "11" "clean shutdown"                             "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "12" "5-minute idle, no outbound"                 "$([ ${RC[core]:-1} = 0 ] && echo TESTED || echo FAIL)" "${SRC[core]:-}"
row "13" "real config/cache hashes unchanged"         "$(diff -q "$BK/real-before.txt" "$BK/real-after.txt" >/dev/null && echo TESTED || echo FAIL)" "$BK/real-before.txt"
row "14" "Hyprland + live owners unchanged"           "$(diff -q "$BK/hypr-before.txt" "$BK/hypr-after.txt" >/dev/null && diff -q "$BK/owners-before.txt" "$BK/owners-after.txt" >/dev/null && echo TESTED || echo FAIL)" "$BK/owners-before.txt"
row "15" "no new names under real HOME"               "$(diff -q "$BK/home-names-before.txt" "$BK/home-names-after.txt" >/dev/null && echo TESTED || echo FAIL)" "$BK/home-names-before.txt"
term="$(grep -o 'TERMINAL-CHECK: [A-Z]*' "${SRC[core]:-}" 2>/dev/null | tail -1 | awk '{print $2}')"
[ "$term" = PASS ] && term=TESTED
row "16" "terminal role for Terminal=true apps"       "${term:-UNVERIFIED}" "${SRC[core]:-}"

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
echo "log: $LOG"
echo "backup: $BK"
exit "$fail"
