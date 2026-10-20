#!/usr/bin/env bash
# The screenshot helper: a local capture into the user's Pictures folder, with
# no upload and no network call.
#
# The test runs it in the nested session, so the capture lands in Mei's fake
# home and never in the owner's Pictures. The clipboard and the notification
# are switched off for the test (the clipboard is the host's, and a
# notification would be the owner's), and both are on the live checklist.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/screenshot-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""
start(){
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei run ) >/dev/null 2>&1
  SIG=""; QS=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ -n "$QS" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 7
}
stop(){ ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1; sleep 2; }

echo "screenshot module: $(date -Is)"
start || exit 1
[ -L "$RUN/bin/mei-screenshot" ] && ok "the helper is linked into .run/bin" || bad "the helper is not linked into .run/bin"

before_owner="$(ls "$HOME/Pictures" 2>/dev/null | wc -l)"
out="$(env HOME="$RUN/home" XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=wayland-1 \
       HYPRLAND_INSTANCE_SIGNATURE="$SIG" PATH="$RUN/bin:$PATH" \
       "$RUN/bin/mei-screenshot" full --no-clipboard --no-notify 2>&1 | tail -1)"
echo "  the helper said: $out"
if [ -s "$out" ] && [ -f "$out" ]; then
  ok "the capture landed: $out ($(stat -c %s "$out") bytes)"
else
  bad "no capture was produced ($out)"
fi
case "$out" in
"$RUN/home/Pictures"/*) ok "the file landed in Mei's own (fake) Pictures folder" ;;
*) bad "the file landed outside Mei's fake home: $out" ;;
esac
if [ -f "$out" ]; then
  magic="$(head -c 4 "$out" | od -An -tx1 | tr -d ' \n')"
  [ "$magic" = "89504e47" ] && ok "the file is a PNG" || bad "the file is not a PNG (magic $magic)"
fi
after_owner="$(ls "$HOME/Pictures" 2>/dev/null | wc -l)"
[ "$before_owner" = "$after_owner" ] && ok "nothing landed in the owner's Pictures ($after_owner files)" || bad "the owner's Pictures changed"

# the helper must refuse what it does not know
if "$RUN/bin/mei-screenshot" bogus >/dev/null 2>&1; then
  bad "the helper accepted an unknown mode"
else
  ok "the helper refuses an unknown mode"
fi
if grep -qE "^[^#]*(curl|wget|http://|https://)" src/ryoku/shell/scripts/mei-screenshot 2>/dev/null; then
  bad "the helper runs a network command"
else
  ok "the helper runs no network command (no curl/wget/http outside comments)"
fi

stop
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "SCREENSHOT MODULE: PASS" || echo "SCREENSHOT MODULE: FAIL"
echo "log: $LOG"
exit $fail
