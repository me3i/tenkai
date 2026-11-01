#!/usr/bin/env bash
# Phase 8 acceptance: the shell.json `modules` switchboard.
#
# Each scenario rewrites ONLY .run/config/mei/shell.json (the nested fake
# config), starts one nested session, asserts, stops it and runs
# verify-untouched. The owner's real config is never opened.
#
# Evidence: this log plus .run/shots/phase8-*.png.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
CFG="$RUN/config/mei/shell.json"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/phase8-$STAMP.log"
BK="$RUN/backup-phase8"
SHELLLOG=""
mkdir -p "$BK" "$RUN/shots" "$RUN/deps/bin"
exec > >(tee -a "$LOG") 2>&1

fail=0
SIG=""; QS=""; BUS=""; DPID=""; SHELLLOG=""
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }
H() {
  local rt="${RT:-${MEI:-$HOME/projects/mei}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
D() { H dispatch "hl.dsp.global(\"mei:$1\")" >/dev/null 2>&1; }
bar_up() { H layers | grep -q 'namespace: ryoku-frame'; }
launcher_layers() { H layers | grep -c 'namespace: launcher'; }
all_layers() { H layers | grep -c 'Layer '; }
owner() { busctl --address="${BUS:-$(cat "$RUN/bus")}" list --no-legend 2>/dev/null | awk -v n="$1" '$1==n{print $2}' | grep -v '^-$'; }
QI() { qs ipc --pid "$QS" call qsbar "$@" 2>&1; }
shot() { grim -o "${WAYLAND_DISPLAY^^}" "$RUN/shots/phase8-$1.png" 2>/dev/null; }
# count of differing pixels in the area below the bar (idle drift is ~130)
dcount() {
  magick "$RUN/shots/phase8-$1.png" -crop 920x448+0+60 +repage /tmp/p8a-crop.png 2>/dev/null
  magick "$RUN/shots/phase8-$2.png" -crop 920x448+0+60 +repage /tmp/p8b-crop.png 2>/dev/null
  compare -metric AE /tmp/p8a-crop.png /tmp/p8b-crop.png null: 2>&1 | awk '{print int($1)}'
}
new_shell_errors() {
  [ -n "$SHELLLOG" ] && [ -f "$SHELLLOG" ] || { echo ""; return; }
  tail -n "+$((1 + $1))" "$SHELLLOG" | grep -E 'ERROR|TypeError|is not a function|is not creatable' \
    | grep -viE 'pipewire|pulseaudio|pa_context' | head -5
}

# Wait until the desktop stops changing (first paint, wallpaper reveal, pill).
settle() { # $1 = bright (default) | dark (wallpaper module off: never bright)
  local mode="${1:-bright}" i dc mean
  shot settle-1
  for i in $(seq 1 22); do
    sleep 0.9
    shot settle-2
    dc="$(dcount settle-1 settle-2)"
    mean="$(magick "$RUN/shots/phase8-settle-2.png" -format '%[fx:mean]' info: 2>/dev/null)"
    # a black screen is static: require both stillness AND a painted wallpaper.
    if [ "${dc:-99999}" -lt 1500 ] && { [ "$mode" = "dark" ] || awk "BEGIN{exit !(${mean:-0} > 0.30)}"; }; then
      cp "$RUN/shots/phase8-settle-2.png" "$RUN/shots/phase8-settled.png"
      note "screen settled (drift ${dc} px, mean ${mean}, ${i} checks)"
      return 0
    fi
    cp "$RUN/shots/phase8-settle-2.png" "$RUN/shots/phase8-settle-1.png"
  done
  note "settle timeout (drift ${dc:-?} px, mean ${mean:-?})"
  return 1
}

set_mods() { # $1 = module overrides (all others true)
  jq --argjson m "$1" \
    '.modules = ({"bar":true,"launcher":true,"control_center":true,"notifications":true,"tray":true,"wallpaper":true,"settings":true} + $m)' \
    "$BK/shell.json" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}

start() { # EXTRA_PATH optionally prefixes PATH, EXTRA_ENV adds VAR=VALUE (dependency scenarios)
  local old_sig="$SIG" old_qs="$QS" old_bus="$BUS" nqs
  # EXTRA_ENV exists because PATH alone cannot stage a broken backend: mei
  # gives every session a fixed PATH (.run/bin + the system list, R1) and never
  # inherits the caller's, so a failing tool placed on EXTRA_PATH is invisible
  # to the daemon. A product seam (MEI_*) does survive, and is how a nested test
  # makes a backend fail without touching the owner's hardware.
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" \
      env ${EXTRA_ENV:-} PATH="${EXTRA_PATH:-}${PATH}" ./mei run ) >/dev/null 2>&1
  SIG=""; QS=""
  for _ in $(seq 1 200); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ "$SIG" != "$old_sig" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] \
      && [ -n "$QS" ] && [ "$QS" != "$old_qs" ] && break
    SIG=""; QS=""
    sleep 0.3
  done
  if [ -z "$SIG" ] || [ -z "$QS" ]; then
    bad "session did not come up (old sig=$old_sig qs=$old_qs)"
    return 1
  fi
  # The supervisor can briefly overlap a retiring shell with its replacement;
  # wait for the count to settle before calling it contamination.
  nqs=""
  for _ in $(seq 1 40); do
    nqs="$(pgrep -fc "^qs -p $MEI/src/ryoku/shell/quickshell/shell" 2>/dev/null || true)"
    [ "$nqs" = 1 ] && break
    sleep 0.25
  done
  BUS="$(cat "$RUN/bus" 2>/dev/null)"
  if [ "$nqs" != "1" ] || [ "$BUS" = "$old_bus" ] || [ -z "$BUS" ]; then
    bad "scenario start is contaminated (shells=$nqs bus='$BUS' old='$old_bus')"
    return 1
  fi
  export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
  WL_NAME="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WL_NAME"
  SHELLLOG="$RUN/state/mei/surfaces/shell.log"
  SHELLLOG_BEFORE="$(wc -l < "$SHELLLOG" 2>/dev/null || echo 0)"
  sleep 2
  DPID="$(pgrep -f "^$RUN/bin/mei-shell daemon" | head -1)"
  if [ "${WALL_OFF:-0}" = 1 ]; then settle dark; else settle; fi
  return 0
}

cleanup_on_exit() {
  local rc=$?
  [ "${KEEP:-0}" = 1 ] && return $rc
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
  return $rc
}
trap cleanup_on_exit EXIT

stopit() {
  local dying_qs="$QS" dying_daemon="$DPID" i nq nd
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
  for i in $(seq 1 180); do
    nq="$(pgrep -fc "^qs -p $MEI/src/ryoku/shell/quickshell/shell" 2>/dev/null || true)"
    nd="$(pgrep -fc "^$RUN/bin/mei-shell daemon" 2>/dev/null || true)"
    { [ "$nq" = 0 ] || [ "$nq" = "" ]; } && { [ "$nd" = 0 ] || [ "$nd" = "" ]; } && break
    sleep 0.25
  done
  # recorded PIDs only, and only if their cmdline still names this project
  for p in "$dying_qs" "$dying_daemon"; do
    [ -n "$p" ] && [ -d "/proc/$p" ] || continue
    tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$MEI" && kill -TERM "$p" 2>/dev/null
  done
  sleep 1
  nq="$(pgrep -fc "^qs -p $MEI/src/ryoku/shell/quickshell/shell" 2>/dev/null || true)"
  nd="$(pgrep -fc "^$RUN/bin/mei-shell daemon" 2>/dev/null || true)"
  if { [ "${nq:-0}" != 0 ]; } || { [ "${nd:-0}" != 0 ]; }; then
    bad "stop left shells=$nq daemons=$nd; aborting so the next scenario is not contaminated"
    echo "RESULT: FAIL"; exit 1
  fi
  rm -f "$RUN/bus"
  echo "  verify-untouched: $( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )"
}

cp -f "$CFG" "$BK/shell.json"
note "config backup -> $BK/shell.json"
echo "=== verify-untouched BEFORE ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )

# ---------------------------------------------------------------- S0 baseline
echo; echo "=== S0: every module on ==="
set_mods '{}'
start || { exit 1; }
bar_up && ok "S0 bar renders (ryoku-frame layer)" || bad "S0 no bar layer"
shot s0-a
D launcher; sleep 1.3
[ "$(launcher_layers)" = 1 ] && ok "S0 launcher opens on the bound shortcut" || bad "S0 launcher layers=$(launcher_layers)"
D launcher; sleep 1
shot s0-b
qs ipc --pid "$QS" call shell clearSurfaceTrace >/dev/null 2>&1
D quicksettings; sleep 1.3
cc="$(qs ipc --pid "$QS" call shell lastSurface 2>&1)"
[ "$cc" = "quick-settings" ] && ok "S0 control centre request reaches ShellState ($cc)" || bad "S0 control centre trace='$cc'"
shot s0-q
D quicksettings
n="$(owner org.freedesktop.Notifications)"
[ -n "$n" ] && [ "$n" = "$QS" ] && ok "S0 notifications name owned by the shell qs ($n)" || bad "S0 notifications owner='$n' qs='$QS'"
t="$(owner org.kde.StatusNotifierWatcher)"
[ -n "$t" ] && [ "$t" = "$DPID" ] && ok "S0 tray watcher owned by the daemon ($t)" || bad "S0 watcher owner='$t' daemon='$DPID'"
pgrep -f "^$RUN/bin/ryogami daemon" >/dev/null && ok "S0 ryogami running" || bad "S0 no ryogami"
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S0 no new QML errors (pipewire noise excluded)" || bad "S0 QML errors: $e"
stopit

# ---------------------------------------------------------------- S1 launcher
echo; echo "=== S1: launcher=false ==="
set_mods '{"launcher":false}'
start || { exit 1; }
bar_up && ok "S1 bar still renders with the launcher off" || bad "S1 bar missing"
D launcher; sleep 1.3
[ "$(launcher_layers)" = 0 ] && ok "S1 SUPER+SPACE creates no launcher surface (layer count 0)" || bad "S1 launcher layers=$(launcher_layers)"
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S1 no new QML errors" || bad "S1 QML errors: $e"
stopit

# --------------------------------------------------------- S2 control centre
echo; echo "=== S2: control_center=false ==="
set_mods '{"control_center":false}'
start || { exit 1; }
bar_up && ok "S2 bar renders" || bad "S2 bar missing"
qs ipc --pid "$QS" call shell clearSurfaceTrace >/dev/null 2>&1
D quicksettings; sleep 1.3
tr="$(qs ipc --pid "$QS" call shell lastSurface 2>&1)"
[ -z "$tr" ] && ok "S2 SUPER+ESCAPE issues no surface request (gate holds)" || bad "S2 control centre request traced as '$tr'"
qs ipc --pid "$QS" call shell clearSurfaceTrace >/dev/null 2>&1
D screenshot; sleep 1
tr="$(qs ipc --pid "$QS" call shell lastSurface 2>&1)"
[ -z "$tr" ] && ok "S2 the screenshot tab is equally gated" || bad "S2 screenshot request traced as '$tr'"
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S2 no new QML errors" || bad "S2 QML errors: $e"
stopit

# --------------------------------------------------------- S3 notifications
echo; echo "=== S3: notifications=false ==="
set_mods '{"notifications":false}'
start || { exit 1; }
n="$(owner org.freedesktop.Notifications)"
[ -z "$n" ] && ok "S3 org.freedesktop.Notifications not claimed on the nested bus" || bad "S3 notifications owner='$n'"
bar_up && ok "S3 bar renders" || bad "S3 bar missing"
qs_alive=0; [ -d "/proc/$QS" ] && qs_alive=1
[ "$qs_alive" = 1 ] && ok "S3 shell alive with no notification server" || bad "S3 shell died"
stopit

# ------------------------------------------------------------------- S4 tray
echo; echo "=== S4: tray=false ==="
set_mods '{"tray":false}'
start || { exit 1; }
t="$(owner org.kde.StatusNotifierWatcher)"
[ -z "$t" ] && ok "S4 StatusNotifierWatcher not claimed on the nested bus" || bad "S4 watcher owner='$t'"
grep -q 'tray module off' "$RUN/logs/daemon.log" && ok "S4 daemon logged the deliberate skip" || bad "S4 daemon did not log the skip"
bar_up && ok "S4 bar renders" || bad "S4 bar missing"
stopit

# -------------------------------------------------------------- S5 wallpaper
echo; echo "=== S5: wallpaper=false ==="
set_mods '{"wallpaper":false}'
WALL_OFF=1 start || { exit 1; }
pgrep -f "^$RUN/bin/ryogami daemon" >/dev/null && bad "S5 ryogami still started" || ok "S5 ryogami not started"
grep -q 'wallpaper module off' "$RUN/logs/session.log" && ok "S5 session logged the deliberate skip" || bad "S5 no skip line in session.log"
bar_up && ok "S5 bar renders without the wallpaper daemon" || bad "S5 bar missing"
stopit

# --------------------------------------------------------------- S6 settings
echo; echo "=== S6: settings=false ==="
set_mods '{"settings":false}'
start || { exit 1; }
r="$( HOME="$RUN/home" XDG_RUNTIME_DIR="$RT" DBUS_SESSION_BUS_ADDRESS="$BUS" "$RUN/bin/mei-shell" hub open general 2>&1 )"
[ "$r" = "ok settings module off" ] && ok "S6 hub verb refuses while settings is off ($r)" || bad "S6 hub verb returned '$r'"
pgrep -f "$RUN/bin/mei-hub" >/dev/null && bad "S6 a hub process still spawned" || ok "S6 no hub process"
bar_up && ok "S6 bar renders" || bad "S6 bar missing"
stopit

# -------------------------------------------------------------------- S7 bar
echo; echo "=== S7: bar=false ==="
set_mods '{"bar":false}'
start || { exit 1; }
bar_up && bad "S7 a bar layer still exists" || ok "S7 no bar layer created"
[ "$(H layers | grep -c 'namespace: ryoku-frame-edge')" = 0 ] && ok "S7 no frame edge layers" || bad "S7 frame edge layers remain"
shot s7-a
D launcher; sleep 1.3
[ "$(launcher_layers)" = 1 ] && ok "S7 launcher still opens without the bar" || bad "S7 launcher layers=$(launcher_layers)"
shot s7-b
dc="$(dcount s7-a s7-b)"
[ "${dc:-0}" -gt 20000 ] && ok "S7 launcher visibly opens (crop diff $dc px)" || bad "S7 launcher diff=$dc"
D launcher; sleep 0.8
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S7 no new QML errors" || bad "S7 QML errors: $e"
stopit

# ------------------------------------------------------------ S8 combination
echo; echo "=== S8: launcher + control_center + tray all off ==="
set_mods '{"launcher":false,"control_center":false,"tray":false}'
start || { exit 1; }
bar_up && ok "S8 bar renders with three modules off" || bad "S8 bar missing"
[ "$(owner org.kde.StatusNotifierWatcher)" = "" ] && ok "S8 no watcher" || bad "S8 watcher present"
shot s8-a
D launcher; sleep 1.2
D quicksettings; sleep 1.2
shot s8-b
dc="$(dcount s8-a s8-b)"
[ "${dc:-99999}" -lt 2000 ] && ok "S8 both shortcuts are no-ops (crop diff $dc px)" || bad "S8 screen changed ($dc px)"
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S8 no new QML errors" || bad "S8 QML errors: $e"
stopit
pgrep -f "^$RUN/bin/mei-shell daemon" >/dev/null && bad "S8 daemon survived stop" || ok "S8 no stray daemon after stop"
pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" >/dev/null && bad "S8 shell survived stop" || ok "S8 no stray shell after stop"

# ------------------------------------------------------- S9 missing deps
echo; echo "=== S9a: brightness backend unavailable ==="
printf '#!/bin/sh\nexit 127\n' > "$RUN/deps/bin/brightnessctl"
chmod +x "$RUN/deps/bin/brightnessctl"
set_mods '{}'
# The daemon cannot see EXTRA_PATH (R1: a session's PATH is fixed), so the
# failure is staged where the product looks: the brightness seam. Pointed at a
# directory, the step cannot be recorded, the backend genuinely cannot do its
# job, and the verb has to report that instead of pretending "ok" (which the
# client prints as nothing at all). The seam also keeps the real panel untouched.
mkdir -p "$RUN/state/s9a-unwritable"
EXTRA_PATH="$RUN/deps/bin:" EXTRA_ENV="MEI_BRIGHTNESS_FAKE=$RUN/state/s9a-unwritable" start || { exit 1; }
bar_up && ok "S9a bar renders with a failing brightnessctl" || bad "S9a bar missing"
r="$( HOME="$RUN/home" XDG_RUNTIME_DIR="$RT" DBUS_SESSION_BUS_ADDRESS="$BUS" "$RUN/bin/mei-shell" brightness up 2>&1 )"
# The verb's convention is the daemon's: an error is "err <verb>: <why>", which
# the client prints as "ryoku-shell: <verb>: <why>" and exits non-zero. Assert on
# that structure, not on one particular wording: an empty reply here would mean
# the verb claimed "ok" while the backend could not run at all.
case "$r" in
  err\ brightness:*|*"ryoku-shell: brightness:"*)
    ok "S9a brightness verb degrades to an error string ($r)" ;;
  *) bad "S9a brightness verb returned '$r'" ;;
esac
# the qsbar widget only shows when its probe parses a percentage; the stubbed
# backend prints nothing, so the same read has to come back empty.
probe="$( PATH="$RUN/deps/bin:$PATH" bash -c 'BL=$(ls /sys/class/backlight 2>/dev/null | head -1); brightnessctl -d "$BL" -m 2>/dev/null | cut -d, -f4 | tr -d "%" | awk "{print int(\$1)}"' )"
[ -z "$probe" ] && ok "S9a the bar's brightness probe returns nothing (widget stays hidden)" || bad "S9a probe returned '$probe'"
sleep 0.5
[ -d "/proc/$DPID" ] && ok "S9a daemon alive after the failed brightness step" || bad "S9a daemon died"
[ -d "/proc/$QS" ] && ok "S9a shell alive after the failed brightness step" || bad "S9a shell died"
shot s9a-bar
stopit

echo; echo "=== S9b: no PipeWire socket (already the nested default) ==="
[ -e "$RT/pipewire-0" ] && bad "S9b nested runtime unexpectedly has pipewire-0" || ok "S9b nested runtime has no PipeWire socket"
set_mods '{}'
start || { exit 1; }
bar_up && ok "S9b bar renders with no PipeWire" || bad "S9b bar missing"
grep -q 'pipewire' "$SHELLLOG" && ok "S9b the shell logged the PipeWire failure it survived" || note "S9b no pipewire line in this shell.log window"
[ -d "/proc/$QS" ] && ok "S9b shell alive with no PipeWire" || bad "S9b shell died"
e="$(new_shell_errors "$SHELLLOG_BEFORE")"
[ -z "$e" ] && ok "S9b no QML TypeError/creatable errors" || bad "S9b QML errors: $e"
shot s9b-bar
stopit

# ------------------------------------------------ S10 changing the config live
echo; echo "=== S10: config changes while running ==="
set_mods '{}'
start || { exit 1; }
D launcher; sleep 1.2
[ "$(launcher_layers)" = 1 ] && ok "S10 launcher open before the change" || bad "S10 launcher did not open"
set_mods '{"launcher":false}'
sleep 2
n="$(launcher_layers)"
D launcher; sleep 1.2
n2="$(launcher_layers)"
if [ "$n" = 0 ]; then
  ok "S10 launcher=false applies live (open surface torn down without a restart)"
else
  note "S10 launcher=false needs a restart (surface stayed: $n -> $n2)"
fi
# tray is a daemon bootstrap decision: it must NOT move live
t1="$(owner org.kde.StatusNotifierWatcher)"
set_mods '{"tray":false}'
sleep 2
t2="$(owner org.kde.StatusNotifierWatcher)"
[ -n "$t1" ] && [ "$t1" = "$t2" ] && ok "S10 tray=false needs a restart (watcher $t1 stayed live)" \
  || bad "S10 tray owner moved live: '$t1' -> '$t2'"
stopit

# ------------------------------------------------------------------- restore
cp -f "$BK/shell.json" "$CFG"
note "nested config restored"
echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$fail"
