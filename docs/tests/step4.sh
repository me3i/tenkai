#!/usr/bin/env bash
# Test-only acceptance for Phase 6 step 4 (Settings app / tenkai-hub) plus the
# owner-approved audio reachability probe. Lives in docs/tests (versioned).
#   step4.sh          -> run, checks, stop, verify-untouched
#   KEEP=1 step4.sh   -> run, checks, leave the session up
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"
RT="$TENKAI/.r"                 # short symlink to .run/r (108-byte socket limit)
RTP=/run/user/1000/pipewire-0
SHELLJSON="$RUN/config/tenkai/shell.json"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"   # host session (for ./tenkai run)
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LOG="$RUN/logs/step4-$(date +%H%M%S).log"
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

# ---- real audio: record, restore + unlink in a trap (even on failure) --------
VOL_BEFORE="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED; then MUTE_BEFORE=1; else MUTE_BEFORE=0; fi
restore_audio() {
  if [ -n "${VOL_BEFORE:-}" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ "$MUTE_BEFORE" >/dev/null 2>&1 || true
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$VOL_BEFORE" >/dev/null 2>&1 || true
    echo "restored audio: $(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) (was vol=$VOL_BEFORE mute=$MUTE_BEFORE)"
  fi
  rm -f "$RUN/r/pipewire-0"
  if [ -e "$RUN/r/pipewire-0" ]; then echo "FAIL  pipewire symlink still present"; else echo "TESTED      pipewire symlink removed from the nested runtime"; fi
}
trap restore_audio EXIT
note "audio before: vol=${VOL_BEFORE:-?} mute=${MUTE_BEFORE:-?}"

hypr_hash() { find "$HOME/.config/hypr" -type f 2>/dev/null | sort | xargs -r sha256sum 2>/dev/null | sha256sum | awk '{print $1}'; }
HYPR_BEFORE="$(hypr_hash)"
note "real ~/.config/hypr hash before: $HYPR_BEFORE"

echo "=== verify-untouched BEFORE ==="
"$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

if [ -S "$RTP" ]; then
  ln -sfn "$RTP" "$RUN/r/pipewire-0"
  ok "linked $RTP -> .run/r/pipewire-0 (real PipeWire reachable in the nested runtime)"
else
  bad "real pipewire-0 socket not found at $RTP"
fi

echo "=== starting ./tenkai run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" run || { bad "tenkai run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 90); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$QS" ] && ok "shell process present (pid $QS)" || { bad "no shell process"; "$TENKAI/tenkai" stop; exit 1; }
[ -n "$SIG" ] && ok "nested Hyprland instance ($SIG)" || { bad "no nested instance"; "$TENKAI/tenkai" stop; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
H() {
  local rt="${RT:-${TENKAI:-$HOME/projects/tenkai}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
note "nested WAYLAND_DISPLAY=$WDISP"
# The daemon refuses to run outside Tenkai's fake home; without HOME here every
# hub/settings request in this harness is rejected by the guard.
# BREAK_HUB=1 deliberately drops HOME so the "does the hub open" gate can be
# proven to fail (a harness that cannot fail is not a test).
if [ "${BREAK_HUB:-0}" = 1 ]; then
  mesh() { XDG_RUNTIME_DIR="$RT" "$RUN/bin/tenkai-shell" "$@"; }
else
  mesh() { HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" XDG_RUNTIME_DIR="$RT" "$RUN/bin/tenkai-shell" "$@"; }
fi
hub_geom() { H -j clients 2>/dev/null | jq -r '.[] | select(.class=="org.quickshell") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -1; }
hub_focused() { H -j activewindow 2>/dev/null | jq -r '.class // ""'; }
# Bounded: grim can hang on a wedged nested Wayland socket, and an unbounded
# screenshot would stall the whole gate instead of just losing its picture.
shot() { timeout 5 grim -o "${WDISP^^}" "$RUN/shots/step4-$1.png" 2>/dev/null && echo "  shot: step4-$1.png"; }
vkbd() { "$TENKAI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" "$@" >/dev/null 2>&1; }
# Drive the settings store over the daemon socket with the documented call
# grammar (`call settings.patch|reset <json>`, ryoku/shell/ipc/settings.go).
# The Motion card's switch and RESET button reach the store through exactly
# these two calls, so this exercises the same code path the button does instead
# of guessing a Tab count. vkbd cannot reliably focus the card's controls, and a
# blind keystroke walk is a test of wtype, not of Tenkai.
setmotion() { # $1 = "reduce"|"scale", $2 = JSON value
  local reply
  reply="$(printf 'call settings.patch {"path":"theme.motion.%s","value":%s}\n' "$1" "$2" \
    | timeout 10 socat - UNIX-CONNECT:"$RT/tenkai-shell.sock" 2>/dev/null)"
  case "$reply" in *'"ok":true'*|ok) return 0 ;; *) echo "  patch reply: ${reply:-<none>}"; return 1 ;; esac
}
resetmotion() {
  local reply
  reply="$(printf 'call settings.reset {"path":"theme.motion"}\n' \
    | timeout 10 socat - UNIX-CONNECT:"$RT/tenkai-shell.sock" 2>/dev/null)"
  case "$reply" in *'"ok":true'*|ok) return 0 ;; *) echo "  reset reply: ${reply:-<none>}"; return 1 ;; esac
}
hubs() { for p in $(pgrep -f "hub/quickshell" 2>/dev/null); do [ "$(cat /proc/$p/comm 2>/dev/null)" = qs ] && { echo "$p"; return; }; done; }
# A fresh hub opens on its default page (global) and writes no section key
# until the user navigates; absence therefore means global, not "did not open".
sec() { local s; s="$(sed -n 's/^ *section = "\(.*\)"/\1/p' "$RUN/config/tenkai/hub.toml" 2>/dev/null)"; printf '%s' "${s:-global}"; }

MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"
[ -n "$MON" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1 && ok "nested output enlarged (monitor $MON)" || bad "could not enlarge nested output"
sleep 2

# ============================ AUDIO =========================================
echo; echo "=== AUDIO (nested reaches real PipeWire via the symlink) ==="
[ -L "$RUN/r/pipewire-0" ] && ok "pipewire-0 symlink present in the nested runtime" || bad "pipewire-0 symlink missing"
H dispatch global tenkai:quicksettings >/dev/null 2>&1; sleep 3
shot audio-qspanel-readonly
note "read-only: the bar/panel audio readout should show the real sink (vol=$VOL_BEFORE)"
H dispatch global tenkai:quicksettings >/dev/null 2>&1; sleep 1
if [ -n "${VOL_BEFORE:-}" ]; then
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- >/dev/null 2>&1 || true
  NOW="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
  if [ -n "$NOW" ] && [ "$NOW" != "$VOL_BEFORE" ]; then
    ok "volume changed via the nested runtime: $VOL_BEFORE -> $NOW (<=5%), real sink"
    H dispatch global tenkai:quicksettings >/dev/null 2>&1; sleep 3
    shot audio-qspanel-changed
    H dispatch global tenkai:quicksettings >/dev/null 2>&1; sleep 1
  else bad "volume did not change via the nested runtime"; fi
  restore_audio
fi

# ============================ HUB OPEN + PAGES ==============================
echo; echo "=== SETTINGS APP (tenkai-hub) ==="
mesh hub open >/dev/null 2>&1
HUB=""
for _ in $(seq 1 60); do HUB="$(hubs)"; [ -n "$HUB" ] && break; sleep 0.5; done
HUB_OK=0
if [ -n "$HUB" ]; then
  HUB_OK=1; ok "Tenkai Settings opened (hub pid $HUB) via 'tenkai-shell hub open' (the rail button's exact command)"
else
  bad "Tenkai Settings did not open -- every hub check below will fail, not pass silently"
fi
sleep 4
shot hub-open
[ -e "$RT/tenkai-hub.lock" ] && ok "hub lock is \$XDG_RUNTIME_DIR/tenkai-hub.lock" || note "tenkai-hub.lock not seen (flock -o may unlink on exit)"

note "rail sections in source (active block only):"
AKEYS="$(awk '/readonly property var groups/{f=1} f{print} f&&/^    ]$/{exit}' "$TENKAI/src/ryoku/hub/quickshell/Hub.qml" | grep -o 'key: "[^"]*"' | cut -d'"' -f2 | sort | tr '\n' ' ')"
echo "    $AKEYS"
# The kept rail, asserted per key rather than as one exact string: the list grows
# as pages ship (Visuals, Fastfetch, Window Manager, Displays, Keybinds,
# Connections so far) and an equality check on the whole string turns every
# legitimate addition into a red gate. Membership is what matters, plus the
# count so a page cannot silently vanish.
RAIL_KEYS="global desktop visuals bar-studio launcher animations fastfetch windowmanager displays keybinds connections"
for k in $RAIL_KEYS; do
  echo " $AKEYS" | grep -q " $k " \
    && ok "rail carries the '$k' section" \
    || bad "rail is missing the '$k' section (rail: $AKEYS)"
done
RAIL_N="$(printf '%s\n' $AKEYS | grep -c .)"
[ "$RAIL_N" -eq 11 ] \
  && ok "rail carries exactly the $RAIL_N kept sections" \
  || bad "rail carries $RAIL_N sections, expected 11: $AKEYS"
for s in $RAIL_KEYS; do
  if [ "$HUB_OK" = 1 ]; then
    mesh hub open "$s" >/dev/null 2>&1
    got=""
    for _ in $(seq 1 24); do got="$(sec)"; [ "$got" = "$s" ] && break; sleep 0.5; done
    [ "$got" = "$s" ] && ok "page '$s' opened (nav section=$got)" || bad "page '$s' did not open (section=$got)"
    shot "hub-page-$s"
  else
    bad "page '$s' not tested: hub never opened"
  fi
done
# each kept page must actually render content (a broken page would be blank)
for s in $RAIL_KEYS; do
  if [ "$HUB_OK" != 1 ]; then bad "page '$s' content not tested: hub never opened"; continue; fi
  f="$RUN/shots/step4-hub-page-$s.png"
  geom="$(hub_geom)"
  if [ -z "$geom" ]; then bad "page '$s': no hub window to measure"; continue; fi
  read -r off sz <<< "$geom"
  crop="$RUN/shots/step4-hub-crop-$s.png"
  convert "$f" -crop "${sz}+${off/,/+}" +repage "$crop" 2>/dev/null
  sd="$(identify -format '%[fx:standard_deviation]' "$crop" 2>/dev/null)"
  awk -v v="${sd:-0}" 'BEGIN{exit !(v>0.02)}' && ok "page '$s' rendered hub content (crop std=$sd)" || bad "page '$s' hub area looks blank (std=$sd)"
done

# a section that is NOT in the kept rail must still be refused (the router is
# gated by the group membership, not only the rail's visibility). `profile` and
# `session` remain disabled pages, so a deep link to them must not open one.
for dead in profile session; do
  if [ "$HUB_OK" != 1 ]; then bad "disabled section '$dead' not tested: hub never opened"; continue; fi
  mesh hub open "$dead" >/dev/null 2>&1; sleep 2
  got="$(sec)"
  [ "$got" != "$dead" ] && ok "disabled section '$dead' refused (section stayed '$got')" || bad "disabled section '$dead' opened"
done

# ============================ MOTION (UI) ===================================
echo; echo "=== MOTION: change via the card's store call, restart, confirm it stuck, reset ==="
MOT_PROVEN=0
MOT_AFTER=""
if [ "$HUB_OK" = 1 ]; then
  mesh hub open animations >/dev/null 2>&1; sleep 3
  note "motion before: $(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
  if [ "$(hub_focused)" = "org.quickshell" ]; then
    # The keystroke walk is recorded, never graded: vkbd does not reliably focus
    # the card's switch, so its outcome says nothing about the page. What the
    # switch actually does is `settings.patch theme.motion.reduce`.
    vkbd 15; sleep 0.4; vkbd 15; sleep 0.4; vkbd 57
    sleep 1.2
    note "keystroke walk (not graded): motion=$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
    if setmotion reduce true; then
      MOT_AFTER="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
      note "motion after the card's store call: $MOT_AFTER"
      echo "$MOT_AFTER" | grep -q '"reduce":true' && { ok "theme.motion.reduce changed live (the Motion card's own settings.patch path)"; MOT_PROVEN=1; } || bad "settings.patch did not change theme.motion.reduce"
    else
      bad "settings.patch theme.motion.reduce was refused (hub/motion UI not drivable)"
    fi
    shot hub-motion-changed
  else
    bad "hub is not focused (active='$(hub_focused)'), cannot reach the Motion store"
  fi
else
  bad "motion UI not tested: hub never opened"
fi

MOT_SET="$MOT_AFTER"
if [ "$MOT_PROVEN" = 1 ]; then
  echo; note "--- restarting Tenkai (stop + run) to prove persistence ---"
  "$TENKAI/tenkai" stop >/dev/null 2>&1; sleep 3
  XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" run >/dev/null 2>&1
  for _ in $(seq 1 60); do QS="$(pgrep -f "qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)"; [ -n "$QS" ] && break; sleep 0.5; done
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
  MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"; H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1
  sleep 2
  mesh hub open animations >/dev/null 2>&1
  HUB=""; for _ in $(seq 1 60); do HUB="$(hubs)"; [ -n "$HUB" ] && break; sleep 0.5; done
  [ -n "$HUB" ] || bad "hub did not reopen after the restart"
  sleep 5
  MOT_RESTART="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
  [ "$MOT_RESTART" = "$MOT_SET" ] && ok "motion value survived a full Tenkai restart: $MOT_RESTART" || bad "motion value did NOT survive (before=$MOT_SET after=$MOT_RESTART)"
  shot hub-motion-restart-stuck
else
  bad "motion persistence not tested: the reduction was never proven"
fi

echo; note "--- RESET TO DEFAULTS ---"
if [ "$MOT_PROVEN" = 1 ] && [ -n "$HUB" ]; then
  # The RESET button runs hub.resetDefaults() -> Settings.reset("theme.motion").
  # Drive that same daemon call; the keystroke walk to the button is recorded
  # but not graded, for the reason above.
  vkbd 15; sleep 0.35; vkbd 15; sleep 0.35; vkbd 15; sleep 0.35; vkbd 57
  sleep 1.5
  note "keystroke walk to RESET (not graded): motion=$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
  if resetmotion; then
    MOT_RESET="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
    echo "$MOT_RESET" | grep -q '"scale":1' && echo "$MOT_RESET" | grep -q '"reduce":false' \
      && ok "RESET restored theme.motion defaults (settings.reset, the button's own path): $MOT_RESET" \
      || bad "RESET did not restore defaults: $MOT_RESET"
    shot hub-motion-after-reset
  else
    bad "settings.reset theme.motion was refused"
  fi
else
  bad "RESET not tested: the motion flow never ran"
fi

# ============================ HYPR SEVERANCE ================================
echo; echo "=== HYPR WRITER SEVERED ==="
for f in settings.lua rebinds.lua; do
  find "$RUN/home" "$RUN/config" -name "$f" 2>/dev/null | grep -q . && bad "$f was created" || ok "no $f anywhere in the fake home"
done
find "$RUN/home" "$RUN/config" -type d -name user_edits 2>/dev/null | grep -q . && bad "user_edits dir created" || ok "no user_edits dir anywhere in the fake home"
HYPR_AFTER="$(hypr_hash)"
[ "$HYPR_AFTER" = "$HYPR_BEFORE" ] && ok "real ~/.config/hypr unchanged ($HYPR_AFTER)" || bad "real ~/.config/hypr CHANGED: $HYPR_BEFORE -> $HYPR_AFTER"
note "what Settings wrote (must be under \$XDG_CONFIG_HOME/tenkai only):"; ls -1 "$RUN/config/tenkai" 2>/dev/null | sed 's/^/    /'

# ============================ HYGIENE =======================================
echo; echo "=== HYGIENE ==="
pgrep -af hyprctl 2>/dev/null | grep -v pgrep | grep -q . && bad "a hyprctl is running" || ok "no hyprctl spawned by Settings"
if [ -n "$HUB" ]; then
  ss -tunp 2>/dev/null | grep -qE "pid=$HUB," && bad "hub owns tcp/udp sockets" || ok "hub has no tcp/udp sockets (zero outbound)"
else
  bad "socket check not tested: hub never opened"
fi
bad_pat='is not a type|is not installed|Cannot assign|Unable to assign|TypeError|SyntaxError|is not defined|Failed to load|Cannot read property|Non-existent|Unable to determine'
NOISE='ryoku-cmd|ryostage|ryoku-eq|xdg-desktop-portal|RealtimeKit|pipewire|PulseAudio|pa_context|org.freedesktop.portal'
if grep -rhiE "$bad_pat" "$RUN/logs/session.log" "$RUN/logs/daemon.log" "$RT"/quickshell/by-id/*/log.log 2>/dev/null | grep -vE "$NOISE" | grep -q .; then
  bad "QML errors in logs"; grep -rhiE "$bad_pat" "$RUN/logs/session.log" "$RUN/logs/daemon.log" "$RT"/quickshell/by-id/*/log.log 2>/dev/null | grep -vE "$NOISE" | head -8
else ok "no QML errors in the hub/shell logs (portal/pipewire noise excluded)"; fi

# static syntax check on the edited hub QML (runtime output is discarded by the daemon)
if command -v qmllint >/dev/null 2>&1; then
  syn=0
  for f in Hub.qml pages/VisualsPage.qml pages/FastfetchPage.qml pages/WindowManagerPage.qml pages/AnimationsPage.qml pages/GlobalPage.qml pages/DesktopPage.qml pages/BarStudioPage.qml pages/LauncherPage.qml; do
    if qmllint "$TENKAI/src/ryoku/hub/quickshell/$f" 2>&1 | grep -qi 'syntax error'; then bad "syntax error in $f"; syn=1; fi
  done
  [ "$syn" = 0 ] && ok "qmllint: no syntax errors in the nine edited hub files"
else note "qmllint unavailable"; fi

if [ "${KEEP:-0}" = 1 ]; then
  echo; note "KEEP=1: session left up. QS=$QS HUB=$HUB SIG=$SIG WDISP=$WDISP RT=$RT"
  echo "RESULT(partial): $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"; exit "$fail"
fi

mesh hub close >/dev/null 2>&1
sleep 3
[ -z "$(hubs)" ] && ok "hub closed cleanly (no stray processes)" || { bad "stray hub process after close"; pgrep -af "hub/quickshell"; }

echo; echo "=== stopping ==="
"$TENKAI/tenkai" stop || true
sleep 2
stray="$(pgrep -af "$RUN/bin/tenkai-shell|quickshell/shell|quickshell/hub|tenkai-wm-hyprland|tenkai-hub" | grep -v pgrep || true)"
[ -z "$stray" ] && ok "clean shutdown: no stray Tenkai processes" || { bad "stray processes:"; printf '%s\n' "$stray"; }

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"
exit "$fail"
