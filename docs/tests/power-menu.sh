#!/usr/bin/env bash
# The power menu: the daemon's session verbs exist, the actions are stubbed in
# a test session, and the confirmation flow reaches the stub.
#
# No real power action is ever executed: MEI_TEST=1 (the nested session) and
# MEI_STUB_POWER=1 (the first live trial) both suppress every action, and the
# test asserts that no systemctl power command ran.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/power-menu-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

SIG=""; QS=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
call(){ printf 'call %s %s\n' "$1" "$2" | socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1; }
dlg_layers(){ H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="ryoku-dialog")] | length' 2>/dev/null; }

start(){ # $1 = extra env assignments for the session (MEI_STUB_POWER=1 ...)
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" \
      env "$@" ./mei run ) >/dev/null 2>&1
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

echo "power menu: $(date -Is)"

echo; echo "=== A: the session verbs exist and the actions are stubbed (MEI_TEST) ==="
start || exit 1
for verb in session.logout session.reboot session.suspend session.shutdown; do
  ans="$(call "$verb" '{}')"
  case "$ans" in
    *unknown\ method*) bad "A: $verb is not registered ($ans)" ;;
    *) ok "A: $verb answered: $ans" ;;
  esac
done
for a in logout reboot suspend shutdown; do
  if grep -q "suppressed session $a (MEI_TEST=1)" "$RUN/logs/daemon.log" 2>/dev/null; then
    ok "A: session.$a was suppressed by MEI_TEST"
  else
    bad "A: session.$a was not suppressed by MEI_TEST"
  fi
done
if grep -qE "systemctl (reboot|poweroff|suspend)" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "A: a real systemctl power command ran"
else
  ok "A: no real systemctl power command ran"
fi
stop

echo; echo "=== B: the same with MEI_STUB_POWER=1 (the first live trial) ==="
# MEI_TEST is emptied on purpose: the nested session always stubs the power
# actions (MEI_STUB_POWER=1 is exported by the session template), so this
# session can only ever log a stub, never run a power command.
start "MEI_TEST=" "MEI_STUB_POWER=1" || exit 1
call session.reboot '{}' >/dev/null
call session.suspend '{}' >/dev/null
call session.shutdown '{}' >/dev/null
call session.logout '{}' >/dev/null
for a in reboot suspend shutdown logout; do
  if grep -q "suppressed session $a (MEI_STUB_POWER=1)" "$RUN/logs/daemon.log" 2>/dev/null; then
    ok "B: session.$a was suppressed by MEI_STUB_POWER"
  else
    bad "B: session.$a was not suppressed by MEI_STUB_POWER"
  fi
done
if grep -qE "systemctl (reboot|poweroff|suspend)" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "B: a real systemctl power command ran"
else
  ok "B: no real systemctl power command ran"
fi

echo; echo "=== C: the confirmation flow opens the dialog ==="
XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call shell sessionConfirm "" reboot >/dev/null 2>&1
sleep 2
n="$(dlg_layers)"; [ "${n:-0}" -ge 1 ] && ok "C: the confirmation dialog opened (ryoku-dialog layers=$n)" || bad "C: the confirmation dialog did not open (layers=$n)"
XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call shell clearSurfaceTrace >/dev/null 2>&1
stop

echo; echo "=== D: the QML action path is stubbed (the real singleton, in a Quickshell instance) ==="
cat > /tmp/mei-power-stubtest/shell.qml 2>/dev/null || mkdir -p /tmp/mei-power-stubtest
cat > /tmp/mei-power-stubtest/shell.qml <<'EOF'
import QtQuick
import Quickshell
import shell.services as Svc

ShellRoot {
    Component.onCompleted: {
        console.log("[power-stubtest] MEI_STUB_POWER=" + Quickshell.env("MEI_STUB_POWER")
            + " powerStubbed=" + Svc.SessionActions.powerStubbed);
        Svc.SessionActions.run("reboot");
        Svc.SessionActions.run("suspend");
        console.log("[power-stubtest] run() returned");
    }
}
EOF
out=$(env MEI_STUB_POWER=1 QML2_IMPORT_PATH="$MEI/src/ryoku/shell/quickshell:$RUN/qml" \
      XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY=wayland-1 HYPRLAND_INSTANCE_SIGNATURE="$SIG" \
      timeout 25 qs -p /tmp/mei-power-stubtest 2>&1 | grep -E "power-stubtest|mei-stub" | sed 's/^/   /')
printf '%s\n' "$out"
if printf '%s' "$out" | grep -q "suppressed session.reboot (MEI_STUB_POWER=1)"; then
  ok "D: the QML path suppressed the action with MEI_STUB_POWER"
else
  bad "D: the QML path did not suppress the action"
fi

echo
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "POWER MENU: PASS" || echo "POWER MENU: FAIL"
echo "log: $LOG"
exit $fail
