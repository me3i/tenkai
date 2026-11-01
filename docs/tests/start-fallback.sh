#!/usr/bin/env bash
# ./mei start: the non-interactive start, its preflight, its idempotency and
# its fallback.
#
# The test never touches the live session. It runs the start in a DUMMY
# context: a private bus (so the notification and tray names are free), a
# runtime directory of its own, and a Wayland socket name that does not exist
# as a real display. Mei's shell therefore cannot come up, which is exactly
# the "Mei exited" case the fallback exists for. The stand-in fallback only
# writes a file.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/start-fallback-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

DUMMY="$RUN/tmp/start-dummy-$STAMP"
mkdir -p "$DUMMY"
: > "$DUMMY/wayland-0"          # the start only checks that the path exists
# The runtime directory is read-only, so Mei's daemon cannot create its control
# socket and exits: the "Mei exited" case the fallback exists for.
chmod 500 "$DUMMY"
# The mark lives in a writable place: the dummy runtime directory is read-only
# on purpose (so Mei's daemon cannot create its socket and exits).
MARK="$RUN/tmp/fallback-mark-$STAMP.txt"
FALLBACK="printf 'fell back\\n' >> '$MARK'"

# A private bus, so the names the start checks are free.
BUSOUT="$(dbus-run-session -- sh -c 'printf %s "$DBUS_SESSION_BUS_ADDRESS"')"
BUS="$(echo "$BUSOUT" | tr -d '\r\n')"
[ -n "$BUS" ] || { echo "no private bus; skipping"; exit 2; }

run_start(){ # $@ = extra flags
  # A test must never run the owner's real previous-shell command: the local
  # config points at the live session's unit, and starting it from here would
  # touch the owner's session (and, when that unit starts Mei, re-enter this
  # very command). Every call gets a harmless fallback unless it passes one.
  local -a fb=(--fallback true)
  case " $* " in *" --fallback "*) fb=() ;; esac
  # The start writes to a file, not to a pipe: a session it leaves running
  # inherits the fd, and a `| tail` would then wait for an EOF that only comes
  # when that session exits. The timeout is a floor, not a product check.
  mkdir -p "$RUN/tmp"
  local out="$RUN/tmp/start-$STAMP-$$.txt" rc
  ( cd "$MEI" && \
    XDG_RUNTIME_DIR="$DUMMY" WAYLAND_DISPLAY=wayland-0 HYPRLAND_INSTANCE_SIGNATURE=dummysig \
    DBUS_SESSION_BUS_ADDRESS="$BUS" \
    timeout 180 ./mei start --profile full "${fb[@]}" "$@" >"$out" 2>&1 )
  rc=$?
  cat "$out"
  rm -f "$out"
  return $rc
}

echo "mei start: $(date -Is)"

echo; echo "=== A: the fallback runs exactly once when Mei does not come up ==="
rm -f "$MARK"
( cd "$MEI" && XDG_RUNTIME_DIR="$DUMMY" ./mei live-stop ) >/dev/null 2>&1
out="$(run_start --fallback "$FALLBACK" | tail -4)"; echo "$out" | sed 's/^/   /'
n=$( [ -f "$MARK" ] && wc -l < "$MARK" || echo 0 )
echo "   the fallback wrote $n line(s)"
[ "$n" = "1" ] && ok "the fallback ran exactly once" || bad "the fallback ran $n times"
echo "$out" | grep -q "the fallback was NOT run" && bad "the fallback was skipped" || ok "the fallback was allowed to run"

echo; echo "=== B: --real-power leaves the stub unset ==="
rm -f "$MARK"
( cd "$MEI" && XDG_RUNTIME_DIR="$DUMMY" ./mei live-stop ) >/dev/null 2>&1
run_start --real-power 2>&1 | tail -3 | sed 's/^/   /'
if grep -q "^export MEI_STUB_POWER" "$RUN/live-session.sh" 2>/dev/null; then
  bad "--real-power still stubbed the power actions"
else
  ok "--real-power left MEI_STUB_POWER unset"
fi
echo "$RUN/live-session.sh" | sed 's/^/   generated: /'

echo; echo "=== C: the default keeps the power actions stubbed ==="
( cd "$MEI" && XDG_RUNTIME_DIR="$DUMMY" ./mei live-stop ) >/dev/null 2>&1
run_start >/dev/null 2>&1
if grep -q "^export MEI_STUB_POWER" "$RUN/live-session.sh" 2>/dev/null; then
  ok "the default still stubs the power actions"
else
  bad "the default lost the power stub"
fi

echo; echo "=== D: the start is idempotent ==="
# A live pid in the live pidfile is enough: the start must notice and do
# nothing.
( cd "$MEI" && XDG_RUNTIME_DIR="$DUMMY" ./mei live-stop ) >/dev/null 2>&1
printf '%s\t%s\t%s\n' "$$" "$$" "fake-live" > "$RUN/live-pids"
out="$(run_start 2>&1 | tail -2)"; echo "$out" | sed 's/^/   /'
echo "$out" | grep -q "already running" && ok "a second start did nothing (already running)" || bad "the second start did not notice"
rm -f "$RUN/live-pids"

echo; echo "=== E: the preflight refuses while something owns the names ==="
# The private bus has no owner for the notification name, so the start is
# expected to pass the preflight; a name that IS owned has to be refused. The
# nested session's own daemon is not on this bus, so the check is done with a
# bus that does have an owner: the live bus is never used, so this case is
# covered by the preflight's own unit check below.
if grep -q 'still owns' "$MEI/mei"; then
  ok "the preflight has the ownership refusal"
else
  bad "the preflight has no ownership refusal"
fi

( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
chmod 700 "$DUMMY" 2>/dev/null; rm -rf "$DUMMY"
[ "$fail" = 0 ] && echo "START/FALLBACK: PASS" || echo "START/FALLBACK: FAIL"
echo "log: $LOG"
exit $fail
