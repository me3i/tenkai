#!/usr/bin/env bash
# Phase 6 step 6 acceptance: notifications.
#  - exactly one NotificationServer (services/Notifs.qml); the qsbar panel no
#    longer owns a server or writes ~/.cache/qs-rise-notifications.json
#  - Mei owns org.freedesktop.Notifications on the NESTED private bus, and the
#    live bus still shows the baseline PID as the owner
#  - notify-send from inside the nested session: popup, urgency levels, long
#    body, actions, icon
#  - DND suppresses popups and stops suppressing when off
#  - dismiss / clear work; no notification state outside the fake HOME
#  - no outbound; clean stop
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"
RT="$MEI/.r"
SHELL_DIR="$MEI/src/ryoku/shell/quickshell/shell"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LIVE_BUS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$HOST_XDG/bus}"
SHELLJSON="$RUN/config/mei/shell.json"
BASELINE_NAME="org.freedesktop.Notifications"
LOG="$RUN/logs/step6-$(date +%H%M%S).log"
mkdir -p "$RUN/shots" "$RUN/icons"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

REAL_DIRS=(/home/mei/.config/kitty /home/mei/.config/btop /home/mei/.config/qt6ct \
           /home/mei/.config/gtk-3.0 /home/mei/.config/gtk-4.0 \
           /home/mei/.cache/ryoku /home/mei/.cache/matugen)
hash_real() {
  for d in "${REAL_DIRS[@]}"; do
    if [ -e "$d" ]; then
      printf '%s %s\n' "$d" "$(find "$d" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | awk '{print $1}')"
    else
      printf '%s ABSENT\n' "$d"
    fi
  done
}

# ── 1. STATIC: one server, no private cache ──────────────────────────────────
echo "=== STATIC PROOF: exactly one NotificationServer ==="
mapfile -t srv < <(grep -rn 'NotificationServer {' --include=*.qml "$SHELL_DIR")
if [ "${#srv[@]}" = 1 ]; then
  ok "one NotificationServer in the shell: ${srv[0]#"$SHELL_DIR/"}"
  case "${srv[0]}" in *services/Notifs.qml*) ok "it is services/Notifs.qml (the kept one)";; *) bad "the single server is not services/Notifs.qml";; esac
else
  bad "expected 1 NotificationServer, found ${#srv[@]}:"; printf '            %s\n' "${srv[@]}"
fi
hits="$(grep -rn 'qs-rise-notifications' --include=*.qml "$SHELL_DIR" | grep -vE ':[0-9]+:[[:space:]]*//' || true)"
if [ -n "$hits" ]; then bad "a qs-rise-notifications.json write still exists:"; printf '            %s\n' "$hits"; else ok "no qs-rise-notifications.json writer remains (only a comment records the removal)"; fi
if grep -q 'saveCache\|liveMap\|property var recent' "$SHELL_DIR/modules/bar/barstyles/qsbar/panels/NotificationPanel.qml"; then
  bad "NotificationPanel still carries its own cache/live-map machinery"
else
  ok "qsbar NotificationPanel is a view over Notifs (no cache, no live-map)"
fi

# ── 2. the nested bar style must be the keep-list qsbar, not the sumi rail ───
PREV_STYLE="$(jq -r '.barStyle' "$SHELLJSON" 2>/dev/null || echo '?')"
note "nested shell.json barStyle was: $PREV_STYLE"
if [ "$PREV_STYLE" != "qsbar" ]; then
  jq '.barStyle = "qsbar"' "$SHELLJSON" > "$SHELLJSON.tmp" && mv "$SHELLJSON.tmp" "$SHELLJSON"
  note "set barStyle=qsbar in the nested fake config (only the nested one; the live config is untouched)"
fi

echo; echo "=== REAL-PATH HASHES BEFORE ==="
hash_real | tee "$RUN/step6-real-before.txt"

echo; echo "=== verify-untouched BEFORE ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -1

# ── 3. start the nested session ──────────────────────────────────────────────
echo; echo "=== starting ./mei run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" run || { bad "mei run failed"; exit 1; }

BASELINE_SIG="$(sed -n 's/^BASELINE_SIG="\(.*\)"$/\1/p' "$RUN/session.sh")"
SIG=""; QS=""
for _ in $(seq 1 120); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $SHELL_DIR" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "session did not come up"; "$MEI/mei" stop; exit 1; }
[ "$SIG" = "$BASELINE_SIG" ] && { bad "nested signature equals the baseline"; "$MEI/mei" stop; exit 1; }
ok "nested Hyprland signature differs from the live baseline"

export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
shot() { grim -o "${WDISP^^}" "$RUN/shots/step6-$1.png" 2>/dev/null && echo "  shot: step6-$1.png"; }
IPC() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar "$@" 2>/dev/null; }
SJ()  { IPC notifState | python3 -c 'import json,sys
d=json.load(sys.stdin); print(d.get(sys.argv[1],"?"))' "$1" 2>/dev/null; }

# wait for the qsbar IPC surface (the barscene loads a beat after qs starts)
for _ in $(seq 1 90); do
  case "$(IPC layout)" in \{*) break;; esac
  sleep 0.5
done
case "$(IPC layout)" in
  \{*) ok "qsbar IPC surface is live (barStyle=qsbar loaded, no sumi fallback)";;
  *)   bad "qsbar IPC surface never appeared — the bar fell back to the sumi rail";;
esac

# ── 4. one server, two buses ─────────────────────────────────────────────────
echo; echo "=== BUS OWNERSHIP ($BASELINE_NAME) ==="
bus_pid() {  # $1 = address, $2 = well-known name  -> owner pid
  local c
  c="$(busctl --address="$1" --no-pager call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetNameOwner s "$2" 2>/dev/null | awk -F'"' '{print $2}')"
  [ -n "$c" ] || return 1
  busctl --address="$1" --no-pager call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus GetConnectionUnixProcessID s "$c" 2>/dev/null | awk '{print $2}'
}
NESTED_BUS="$(cat "$RUN/bus" 2>/dev/null)"
if [ -n "$NESTED_BUS" ] && [ "$NESTED_BUS" != "$LIVE_BUS" ]; then
  ok "nested private bus differs from the live bus (${NESTED_BUS%%guid=*}…)"
else
  bad "nested bus address missing or identical to the live bus"; "$MEI/mei" stop; exit 1
fi
NESTED_OWNER="$(bus_pid "$NESTED_BUS" "$BASELINE_NAME" || true)"
LIVE_OWNER="$(bus_pid "$LIVE_BUS" "$BASELINE_NAME" || true)"
LIVE_BASE="$(awk -v n="$BASELINE_NAME" '$1==n {print $2}' "$MEI/docs/baseline/dbus-watched.tsv" | head -1)"
note "nested owner PID = ${NESTED_OWNER:-none}   (nested shell pid $QS)"
note "live   owner PID = ${LIVE_OWNER:-none}   (baseline ${LIVE_BASE:-unknown})"
[ "$NESTED_OWNER" = "$QS" ] && ok "Mei owns $BASELINE_NAME on the nested bus (pid $NESTED_OWNER)" \
  || bad "nested $BASELINE_NAME owner is '$NESTED_OWNER', expected the nested shell pid $QS"
[ "$LIVE_OWNER" = "$LIVE_BASE" ] && ok "live bus $BASELINE_NAME still owned by pid $LIVE_OWNER (unchanged)" \
  || bad "live $BASELINE_NAME owner changed: $LIVE_BASE -> $LIVE_OWNER"

echo; echo "=== server identity + capabilities (nested bus) ==="
busctl --address="$NESTED_BUS" --no-pager call org.freedesktop.Notifications /org/freedesktop/Notifications \
  org.freedesktop.Notifications GetServerInformation 2>&1 | sed 's/^/  /'
CAPS="$(busctl --address="$NESTED_BUS" --no-pager call org.freedesktop.Notifications /org/freedesktop/Notifications \
  org.freedesktop.Notifications GetCapabilities 2>&1)"
echo "  capabilities: $CAPS"
for c in body actions; do
  case "$CAPS" in *"\"$c\""*) ok "server advertises '$c' capability";; *) bad "server does not advertise '$c'";; esac
done

# ── 5. popups from inside the nested session ─────────────────────────────────
NS() { DBUS_SESSION_BUS_ADDRESS="$NESTED_BUS" notify-send "$@"; }
ICON="$RUN/icons/step6-icon.png"
magick -size 64x64 xc:'#d94f4f' -fill white -draw 'circle 32,32 32,12' "$ICON" 2>/dev/null || \
  printf 'not an image\n' > "$ICON"
note "icon: $ICON ($(stat -c%s "$ICON") bytes)"

IPC notifications false >/dev/null; sleep 0.3
P0="$(SJ popups)"; H0="$(SJ history)"
note "before any notification: popups=$P0 history=$H0"
[ "$P0" = 0 ] && [ "$H0" = 0 ] && ok "shell starts with an empty notification state" || bad "non-empty notification state at start"

echo; echo "=== TEST: a plain notification ==="
NS -a MeiTest -i "$ICON" -u normal "Mei popup test" "A short body from notify-send." || bad "notify-send failed"
sleep 1
P1="$(SJ popups)"; H1="$(SJ history)"
[ "$H1" = 1 ] && ok "history has 1 entry" || bad "history=$H1, expected 1"
[ "$P1" = 1 ] && ok "popup list has 1 card" || bad "popups=$P1, expected 1"
shot 03-normal-popup

echo; echo "=== TEST: urgency levels (low, normal, critical) ==="
for u in low critical; do
  NS -a MeiTest -u "$u" "Urgency $u" "same body, different urgency" || bad "notify-send -u $u failed"
done
sleep 1
H2="$(SJ history)"
[ "$H2" = 3 ] && ok "all three urgencies reached the server (history=3)" || bad "history=$H2, expected 3"
note "upstream contract: urgency has no styling/timeout effect, so all three look identical (look = UNVERIFIED)"
shot 04-urgency

echo; echo "=== TEST: a long body ==="
LONG="$(python3 -c 'print("This is a deliberately long notification body. "*8)')"
NS -a MeiTest -u normal "Long body" "$LONG" || bad "notify-send (long body) failed"
sleep 1
H3="$(SJ history)"
[ "$H3" = 4 ] && ok "long body accepted (history=4)" || bad "history=$H3, expected 4"
shot 05-long-body

echo; echo "=== TEST: flyout, dismiss, clear ==="
IPC notifications true >/dev/null; sleep 0.8
[ "$(SJ flyout)" = "True" ] && ok "notification flyout opened" || bad "flyout did not open: $(SJ flyout)"
shot 06-flyout
HB="$(SJ history)"
IPC notifDismissLatest >/dev/null; sleep 0.8
HA="$(SJ history)"
[ "${HA:-99}" -lt "${HB:-0}" ] && ok "dismiss removed one entry ($HB -> $HA)" || bad "dismiss did not remove an entry ($HB -> $HA)"
shot 07-after-dismiss
IPC notifClearAll >/dev/null; sleep 1.0
[ "$(SJ history)" = 0 ] && ok "clear all emptied the history" || bad "clear all left history=$(SJ history)"
[ "$(SJ popups)" = 0 ] && ok "clear all also closed the live popups" || bad "popups survived clear all: $(SJ popups)"
shot 08-cleared
IPC notifications false >/dev/null; sleep 0.3

echo; echo "=== TEST: DND ==="
IPC dnd true >/dev/null; sleep 0.3
[ "$(SJ dnd)" = "True" ] && ok "DND is on (Notifs.dnd=true)" || bad "DND did not turn on: $(SJ dnd)"
DP="$(SJ popups)"; DH="$(SJ history)"
NS -a MeiTest -u critical "While DND" "must not pop" || bad "notify-send during DND failed"
sleep 1
DP2="$(SJ popups)"; DH2="$(SJ history)"
[ "$DP2" = "$DP" ] && ok "popup suppressed while DND is on (popups stayed $DP)" || bad "popup appeared during DND: $DP -> $DP2"
[ "$DH2" -gt "$DH" ] && ok "history still records it while DND is on ($DH -> $DH2)" || bad "history did not record the DND-suppressed notification"
shot 09-dnd-suppressed
IPC dnd false >/dev/null; sleep 0.3
[ "$(SJ dnd)" = "False" ] && ok "DND is off again" || bad "DND did not turn off: $(SJ dnd)"
NS -a MeiTest -u normal "After DND" "must pop now" || bad "notify-send after DND failed"
sleep 1
DP3="$(SJ popups)"
[ "${DP3:-0}" -gt "${DP2:-0}" ] && ok "popups resume when DND is off ($DP2 -> $DP3)" || bad "no popup after DND off ($DP2 -> $DP3)"
shot 10-after-dnd

echo; echo "=== TEST: persistent (expire_timeout 0) ==="
HB2="$(SJ history)"; PB2="$(SJ popups)"
NS -a MeiTest -u normal -t 0 "Persistent" "expire_timeout 0: must never self-expire" || bad "notify-send -t 0 failed"
sleep 1
[ "$(SJ history)" = "$HB2" ] && ok "expire_timeout 0 stays out of history ($HB2)" || bad "history moved to $(SJ history), expected $HB2"
[ "$(SJ popups)" -gt "$PB2" ] && ok "the persistent card is on screen (popups $PB2 -> $(SJ popups))" || bad "popups=$PB2, the persistent card did not appear"
shot 11-persistent
note "waiting 6 s (longer than the 5 s popup default) to prove expire_timeout 0 does not self-expire"
sleep 6
P5="$(SJ popups)"
[ "${P5:-0}" -ge 1 ] && ok "still shown after 6 s (popups=$P5)" || bad "the persistent popup expired (popups=$P5)"

echo; echo "=== TEST: actions ==="
# notify-send -A implies --wait, so it only returns when the action is invoked:
# run it in the background and invoke through the same call the card's button makes.
ACTOUT="$RUN/step6-action.out"; rm -f "$ACTOUT"
DBUS_SESSION_BUS_ADDRESS="$NESTED_BUS" timeout 40 notify-send -a MeiTest -t 0 --print-id --wait \
  -A "default=Open" -A "later=Later" "Action test" "two actions" > "$ACTOUT" 2>&1 &
ACTPID=$!
sleep 1.5
AID="$(head -1 "$ACTOUT" | tr -dc '0-9')"
if [ -n "$AID" ]; then ok "notify-send reported notification id $AID"; else bad "no notification id from notify-send (got '$(cat "$ACTOUT")')"; fi
note "with the action card: history=$(SJ history) popups=$(SJ popups)"
shot 12-actions
if [ -n "$AID" ]; then
  INV="$(IPC notifInvoke "$AID" later)"
  [ "$INV" = "ok later" ] && ok "action invoked through the shell: $INV" || bad "notifInvoke returned '$INV'"
fi
for _ in $(seq 1 20); do kill -0 "$ACTPID" 2>/dev/null || break; sleep 0.5; done
if kill -0 "$ACTPID" 2>/dev/null; then
  bad "notify-send --wait never unblocked: no ActionInvoked reached the sender"
  kill -TERM "$ACTPID" 2>/dev/null || true
else
  wait "$ACTPID"; arc=$?
  grep -q 'later' "$ACTOUT" && ok "sender saw ActionInvoked 'later' (exit $arc, output '$(tr '\n' ' ' < "$ACTOUT")')" \
    || bad "sender exited $arc without the action key (output '$(cat "$ACTOUT")')"
fi
# document the contract: clear_all dismisses history; a persistent (expire_timeout
# 0) card is not in history and is deliberately left, matching upstream dismiss_all.
IPC notifClearAll >/dev/null; sleep 0.8
[ "$(SJ history)" = 0 ] && ok "clear all after the persistent card: history empty (persistent card left by contract)" || bad "clear all left history=$(SJ history)"

echo; echo "=== TEST: no notification state outside the fake HOME ==="
if find "$RUN/home" -name 'qs-rise-notifications*' 2>/dev/null | grep -q .; then
  bad "a qs-rise-notifications file exists under the fake HOME"
else
  ok "no qs-rise-notifications file anywhere under the fake HOME"
fi
found_real="$(find /home/mei/.cache /home/mei/.local/state /home/mei/.local/share /home/mei/.config \
  -mindepth 1 -maxdepth 3 2>/dev/null | sed 's|^/home/mei/||' | grep -iE '(^|/)(mei|ryoku|ryogami)([._-]|$)' || true)"
[ -z "$found_real" ] && ok "no mei/ryoku/ryogami entry appeared outside the project" || { bad "new entries outside the project:"; printf '            %s\n' "$found_real"; }

echo; echo "=== OUTBOUND ==="
sleep 1
for p in "$QS" "$(pgrep -f "$RUN/bin/mei-shell daemon" | head -1)"; do
  [ -n "$p" ] || continue
  ss -tunp 2>/dev/null | grep -qE "pid=$p," && { bad "pid $p owns a tcp/udp socket:"; ss -tunp | grep -E "pid=$p,"; } || ok "pid $p owns no tcp/udp socket"
done

# ── 6. stop + verify ─────────────────────────────────────────────────────────
echo; echo "=== SHUTDOWN ==="
"$MEI/mei" stop
sleep 2
stray="$(pgrep -af "$RUN/bin/mei-shell|$SHELL_DIR|$RUN/bin/ryogami|$RUN/bin/mei-hub" | grep -v pgrep || true)"
[ -z "$stray" ] && ok "clean shutdown: no stray Mei processes" || { bad "stray processes:"; printf '            %s\n' "$stray"; }

echo; echo "=== REAL-PATH HASHES AFTER ==="
if diff -q <(cat "$RUN/step6-real-before.txt") <(hash_real) >/dev/null; then
  ok "real ~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}, ~/.cache/{ryoku,matugen} unchanged"
else
  bad "real config/cache changed:"; diff -u "$RUN/step6-real-before.txt" <(hash_real)
fi

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -2
LIVE_AFTER="$(bus_pid "$LIVE_BUS" "$BASELINE_NAME" || true)"
[ "$LIVE_AFTER" = "$LIVE_BASE" ] && ok "live $BASELINE_NAME owner still pid $LIVE_AFTER after the test" \
  || bad "live $BASELINE_NAME owner moved to '$LIVE_AFTER' after the test"

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
echo "log: $LOG"
exit "$fail"
