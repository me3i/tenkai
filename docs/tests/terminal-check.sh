#!/usr/bin/env bash
# Terminal role (Ryoku's ryoku-app, ported as mei-app). Assumes ./mei run is up.
#
#  - mei-app is on the session PATH
#  - `mei-app terminal -- <prog>` opens a kitty window on the nested display and
#    runs <prog> inside it (the marker file proves the inner command ran)
#  - desktop.json's desktop.apps.terminal is honoured (title probe)
#  - a Terminal=true launcher entry (htop) launches through the same chain
#  - an unknown role fails cleanly
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/terminal-check-$STAMP.log"
mkdir -p "$RUN/logs" "$RUN/shots" "$RUN/state/mei"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }
H() {
  local rt="${RT:-${MEI:-$HOME/projects/mei}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
VK="$MEI/docs/tests/tools/nested-input.sh $RUN/tools/vkbd/vkbd"

SIG=""; QS=""
for _ in $(seq 1 120); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] && [ -n "$QS" ] && break
  sleep 0.3
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "no nested session"; echo "RESULT: FAIL"; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
export WAYLAND_DISPLAY="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
BUS="$(cat "$RUN/bus" 2>/dev/null)"
APP="$RUN/bin/mei-app"

env_app() {
  env HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" \
      XDG_CACHE_HOME="$RUN/home/.cache" XDG_STATE_HOME="$RUN/state" \
      XDG_DATA_HOME="$RUN/data" XDG_RUNTIME_DIR="$RT" \
      WAYLAND_DISPLAY="$WAYLAND_DISPLAY" "$APP" "$@"
}
kitty_count() { local n; n="$(H -j clients 2>/dev/null | jq '[.[] | select(.class=="kitty")] | length' 2>/dev/null)"; echo "${n:-0}"; }
layers_launcher() {
  H -j layers 2>/dev/null | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="launcher")] | length' 2>/dev/null
}
wait_kitty() { local i; for i in $(seq 1 40); do [ "$(kitty_count)" -ge 1 ] && return 0; sleep 0.25; done; return 1; }
# A compositor close makes kitty ask "Close OS window" and keep the window, so
# close the client itself -- but only after proving it is a nested, fake-HOME
# process (never the owner's kitty on the live session).
close_kitty() {
  local p e
  for p in $(H -j clients 2>/dev/null | jq -r '.[] | select(.class=="kitty") | .pid' 2>/dev/null); do
    e="$(tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null)"
    if printf '%s\n' "$e" | grep -qx "HOME=$RUN/home" &&
       printf '%s\n' "$e" | grep -qx "XDG_RUNTIME_DIR=$RT"; then
      kill -TERM "$p" 2>/dev/null || true
    else
      bad "refusing to signal kitty pid $p (not a nested fake-home process)"
    fi
  done
  for _ in $(seq 1 24); do [ "$(kitty_count)" = 0 ] && return 0; sleep 0.25; done
}

echo "=== the role launcher is installed ==="
if [ -x "$APP" ]; then ok "mei-app on the session PATH ($APP -> $(readlink -f "$APP"))"; else bad "mei-app missing at $APP"; fi

echo; echo "=== 1. direct: mei-app terminal -- <prog> ==="
M1="$RUN/state/mei/terminal-direct-$STAMP.txt"; rm -f "$M1"
env_app terminal -- sh -c "printf 'direct-ok %s\\n' \"\$(id -un)\" > '$M1'; sleep 30" \
  > "$RUN/logs/terminal-direct-$STAMP.out" 2>&1 &
DPID1=$!
for _ in $(seq 1 40); do [ -s "$M1" ] && break; sleep 0.25; done
[ -s "$M1" ] && ok "the inner command ran inside the terminal: $(head -1 "$M1")" || bad "marker never written"
wait_kitty && ok "a kitty window appeared on the nested display" || bad "no kitty window"
KPID="$(H -j clients | jq -r '.[] | select(.class=="kitty") | .pid' | head -1)"
if [ -n "$KPID" ]; then
  ENVS="$(tr '\0' '\n' < "/proc/$KPID/environ" 2>/dev/null)"
  echo "$ENVS" | grep -qx "HOME=$RUN/home" && ok "terminal HOME = fake home" || bad "terminal HOME wrong"
  echo "$ENVS" | grep -qx "WAYLAND_DISPLAY=$WAYLAND_DISPLAY" && ok "terminal on the nested display" || bad "terminal display wrong"
  echo "$ENVS" | grep -q "^__QUICKSHELL_CRASH" && bad "crash handle leaked into the terminal" || ok "no Quickshell crash handle in the terminal env"
fi
close_kitty
kill -TERM "$DPID1" 2>/dev/null || true

echo; echo "=== 2. desktop.json's terminal choice is honoured ==="
STORE="$RUN/config/mei/desktop.json"
STORE_BAK="$RUN/state/mei/desktop.json.terminal-bak"
[ -f "$STORE" ] && cp -f "$STORE" "$STORE_BAK"
mkdir -p "$(dirname "$STORE")"
printf '%s\n' '{"desktop":{"apps":{"terminal":"kitty --title MEI_STORE_PROBE"}}}' > "$STORE"
M2="$RUN/state/mei/terminal-store-$STAMP.txt"; rm -f "$M2"
env_app terminal -- sh -c "printf 'store-ok\\n' > '$M2'; sleep 30" \
  > "$RUN/logs/terminal-store-$STAMP.out" 2>&1 &
DPID2=$!
for _ in $(seq 1 40); do [ -s "$M2" ] && break; sleep 0.25; done
sleep 1
SKPID="$(H -j clients 2>/dev/null | jq -r '.[] | select(.class=="kitty") | .pid' | head -1)"
SCMD="$(tr '\0' ' ' < "/proc/${SKPID:-0}/cmdline" 2>/dev/null)"
case "$SCMD" in
  *MEI_STORE_PROBE*) ok "the configured command ran (cmdline: $SCMD)" ;;
  *) bad "store command not in the kitty cmdline: '$SCMD'" ;;
esac
[ -s "$M2" ] && ok "the configured terminal still ran the inner command" || bad "store inner command did not run"
close_kitty
kill -TERM "$DPID2" 2>/dev/null || true
if [ -f "$STORE_BAK" ]; then mv -f "$STORE_BAK" "$STORE"; else rm -f "$STORE"; fi

echo; echo "=== 3. launcher: a Terminal=true entry (Htop) ==="
m1="$(kitty_count)"
if [ "$(layers_launcher)" != "0" ]; then
  "$VK" 1 >/dev/null 2>&1
  for _ in $(seq 1 20); do [ "$(layers_launcher)" = "0" ] && break; sleep 0.25; done
fi
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1
ln=0
for _ in $(seq 1 40); do ln="$(layers_launcher)"; [ "$ln" = "1" ] && break; sleep 0.3; done
if [ "$ln" != "1" ]; then
  bad "launcher did not open (layers=$ln)"
else
  ok "launcher opened for the Terminal=true entry"
  sleep 2   # the layer needs keyboard focus before vkbd keys land
  "$VK" 35 20 24 25 >/dev/null 2>&1   # h t o p
  sleep 1.2
  "$VK" 28 >/dev/null 2>&1            # Enter
  m2="$m1"
  for _ in $(seq 1 40); do
    m2="$(kitty_count)"
    [ "$m2" -gt "$m1" ] && break
    sleep 0.25
  done
  [ "${m2:-0}" -gt "${m1:-0}" ] && ok "the launcher opened a terminal for htop ($m1 -> $m2 kitty)" || bad "no terminal from the launcher ($m1 -> $m2)"
  HPID=""
  for _ in $(seq 1 20); do
    for p in $(pgrep -x htop 2>/dev/null || true); do
      tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "HOME=$RUN/home" && { HPID=$p; break; }
    done
    [ -n "$HPID" ] && break
    sleep 0.25
  done
  [ -n "$HPID" ] && ok "htop is running inside that terminal (pid $HPID, fake HOME)" || bad "no htop process with the fake HOME"
fi
close_kitty

echo; echo "=== 4. unknown role fails cleanly ==="
OUT="$(env_app files 2>&1)"; RC=$?
[ "$RC" = 1 ] && ok "unknown role exited 1" || bad "unknown role rc=$RC"
echo "$OUT" | grep -q 'no default for role' && ok "clear error message: $OUT" || bad "unclear error: $OUT"
[ "$(kitty_count)" = 0 ] && ok "no stray terminal window" || bad "kitty count $(kitty_count) after cleanup"

echo; echo "=== shell log clean for this feature ==="
if tail -80 "$RUN/state/mei/surfaces/shell.log" 2>/dev/null | grep -qiE 'mei-app.*(not found|error)|AppLaunch.*(Cannot|undefined)'; then
  bad "shell log mentions a mei-app/AppLaunch error"
else
  ok "no mei-app/AppLaunch errors in the shell log"
fi

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
echo "log: $LOG"
exit "$fail"
