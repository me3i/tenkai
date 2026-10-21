#!/usr/bin/env bash
# Mei's acceptance gate.
#
# Every machine-checkable criterion in docs/CRITERIA.md, one table: the gate
# id, the name, PASS / FAIL / UNVERIFIED and the evidence (a log path).
#
# Everything runs from a cold start in the nested session: the fake HOME, the
# private bus, the nested compositor. Nothing here can reach the owner's live
# session, and every synthetic keystroke goes through the guarded input tool.
#
#   usage: ./mei accept            the whole gate
#          ./mei accept --list     the gates and their commands, nothing run
#          ./mei accept --prove    show that the static gates can fail
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$MEI/.run"
LOGDIR="$RUN/logs/accept"
mkdir -p "$LOGDIR"
STAMP="$(date +%H%M%S)"
OUT="$LOGDIR/accept-$STAMP.log"
exec > >(tee -a "$OUT") 2>&1

cd "$MEI"

# ---------------------------------------------------------------- the gates
# id | name | the command to run | the evidence
GATES=(
"S1|the live session is untouched|bash $MEI/docs/tests/accept-safety.sh s1|$OUT"
"S2|no personal values in the tracked tree|bash $MEI/docs/tests/accept-safety.sh s2|$OUT"
"S3|no Mei process holds the live runtime or the live display|bash $MEI/docs/tests/accept-safety.sh s3|$OUT"
"S4|no process is ever signalled by name|bash $MEI/docs/tests/accept-safety.sh s4|$OUT"
"S5|the guarded input tool refuses the live display|bash $MEI/docs/tests/accept-safety.sh s5|$OUT"
"S6|Mei makes no outbound connection and listens on nothing|bash $MEI/docs/tests/accept-safety.sh s6|$OUT"
"S7|a clean stop leaves nothing behind|bash $MEI/docs/tests/accept-safety.sh s7|$OUT"
"S8|nothing is written outside the project|bash $MEI/docs/tests/accept-safety.sh s8|$OUT"
"F1|the bar and the workspaces|bash $MEI/docs/tests/workspaces.sh|$OUT"
"F2|the launcher|bash $MEI/docs/tests/launcher-check.sh|$OUT"
"F3|the control centre, and the audio and brightness steps|bash $MEI/docs/tests/control-center-matrix.sh|$OUT"
"F4|the notifications|bash $MEI/docs/tests/step6.sh|$OUT"
"F5|the system tray|bash $MEI/docs/tests/step7.sh|$OUT"
"F6|the wallpaper and the palette|bash $MEI/docs/tests/step5.sh|$OUT"
"F7|the settings app|bash $MEI/docs/tests/step4.sh|$OUT"
"F8|the session lock|bash $MEI/docs/tests/lock-module.sh; bash $MEI/docs/tests/session-lock-module.sh; bash $MEI/docs/tests/lock-ui-outbound.sh|$OUT"
"F9|the idle module and the ScreenSaver service|bash $MEI/docs/tests/idle-module.sh|$OUT"
"F10|the power menu|bash $MEI/docs/tests/power-menu.sh|$OUT"
"F11|the OSD, the clipboard, the screenshots, the polkit agent|bash $MEI/docs/tests/restored-modules.sh|$OUT"
"F13|mei start, the fallback and the preflight|bash $MEI/docs/tests/start-fallback.sh|$OUT"
"Q1|the code is clean (qmllint, go vet, go build, go test, shellcheck)|bash $MEI/docs/tests/accept-safety.sh q1|$OUT"
"Q2|no dead code, no personal strings, no ryoku names outside the allowed ones|bash $MEI/docs/tests/accept-safety.sh q2|$OUT"
"F12|the module matrix (every module off, three at once)|bash $MEI/docs/tests/phase8.sh|$OUT"
"Q3|the reference screenshots|bash $MEI/docs/tests/accept-q3.sh before|$OUT"
"Q4|the idle measurement table|bash $MEI/docs/tests/accept-q4.sh|$OUT"
"Q5|the documents are there and say what is true|bash $MEI/docs/tests/accept-safety.sh q5|$OUT"
)

# The gates that only the owner can close. They are UNVERIFIED on purpose.
HUMAN=(
"H1|the lock's accept path with the owner's real password"
"H2|the lock on the owner's second output"
"H3|the compositor's inhibitors with a real video playing"
"H4|the idle with the owner's real panel"
"H5|the feel at 144 Hz"
"H6|the horizon line's smoothness"
"H7|the real tray apps"
"H8|notifications from real apps"
"H9|the real audio hardware"
"H10|Wi-Fi and Bluetooth through the terminal tools"
)

# The gates the owner's criteria list but that have no runnable check yet.
# They are listed with what they would need, and they are NOT counted as
# passed.
TODO=(
)

# ---------------------------------------------------------------- the runners
# mei_alive asks whether a Mei shell is still running, by reading /proc (no
# process is looked up by name, and nothing is signalled).
mei_alive(){
  local p
  for p in /proc/[0-9]*; do
    [ -r "$p/cmdline" ] || continue
    if tr '\0' ' ' < "$p/cmdline" 2>/dev/null | grep -q "quickshell/shell/shell.qml"; then
      return 0
    fi
  done
  return 1
}

# settle waits for the previous gate's session to be gone: a leftover session
# makes the next gate fail for the wrong reason.
settle(){
  local i=0
  while [ $i -lt 45 ]; do
    mei_alive || return 0
    sleep 1
    i=$((i+1))
  done
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
      WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei stop ) >/dev/null 2>&1
  sleep 3
}

run_gate(){ # id, name, command
  local id="$1" name="$2" cmd="$3"
  local log="$LOGDIR/$id-$STAMP.log"
  settle
  printf '\n--- %s: %s ---\n' "$id" "$name"
  if bash -c "$cmd" > "$log" 2>&1; then
    if grep -q "BASELINE-CAPTURED" "$log"; then
      printf '%-4s %-62s BASELINE\n' "$id" "$name"
      RESULT_BASELINE=$((RESULT_BASELINE+1))
    else
      printf '%-4s %-62s PASS\n' "$id" "$name"
      RESULT_PASS=$((RESULT_PASS+1))
    fi
  else
    printf '%-4s %-62s FAIL\n' "$id" "$name"
    printf '     evidence: %s\n' "$log"
    tail -12 "$log" | sed 's/^/     /'
    RESULT_FAIL=$((RESULT_FAIL+1))
    FAILED_IDS="$FAILED_IDS $id"
  fi
  printf '%-4s %-62s %s\n' "$id" "$name" "$log"
}

list_only(){
  printf '%-4s %-62s %s\n' "id" "gate" "command"
  for g in "${GATES[@]}"; do
    IFS='|' read -r id name cmd evidence <<< "$g"
    printf '%-4s %-62s %s\n' "$id" "$name" "$cmd"
  done
  printf '\n(human gates, UNVERIFIED by design)\n'
  for h in "${HUMAN[@]}"; do printf '%-4s %-62s UNVERIFIED\n' "${h%%|*}" "${h#*|}"; done
  printf '\n(gates with no runnable check yet)\n'
  for t in "${TODO[@]}"; do printf '%-4s %-62s TODO: %s\n' "${t%%|*}" "${t#*|}" "${t#*|}"; done
}

# ---------------------------------------------------------------- the proof
prove_static(){
  printf 'the static gates can fail:\n'
  local tmp="$RUN/accept-prove.txt"
  printf 'pkill -f quickshell\n' > "$tmp"
  if bash "$MEI/docs/tests/accept-safety.sh" s4 "$tmp" 2>&1 | grep -q "FAIL"; then
    printf '  S4  a file with pkill in it is caught            OK\n'
  else
    printf '  S4  a file with pkill in it is caught            NOT PROVEN\n'
  fi
  printf 'https://example.invalid/secret\n' > "$tmp"
  if bash "$MEI/docs/tests/accept-safety.sh" q2 "$tmp" 2>&1 | grep -q "FAIL"; then
    printf '  Q2  a file with an outbound URL is caught        OK\n'
  else
    printf '  Q2  a file with an outbound URL is caught        NOT PROVEN\n'
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------- the run
RESULT_PASS=0
RESULT_FAIL=0
RESULT_BASELINE=0
FAILED_IDS=""
case "${1:-}" in
--list) list_only; exit 0 ;;
--prove) prove_static; exit 0 ;;
esac

printf 'Mei acceptance gate: %s\n' "$(date -Is)"
printf 'the log of this run: %s\n' "$OUT"
printf '\n'

for g in "${GATES[@]}"; do
  IFS='|' read -r id name cmd evidence <<< "$g"
  run_gate "$id" "$name" "$cmd"
done

printf '\n================ the table ================\n'
printf '%-4s %-62s %s\n' "id" "gate" "state"
for g in "${GATES[@]}"; do
  IFS='|' read -r id name cmd evidence <<< "$g"
  case " $FAILED_IDS " in *" $id "*) printf '%-4s %-62s FAIL\n' "$id" "$name" ;; *) printf '%-4s %-62s PASS\n' "$id" "$name" ;; esac
done
for h in "${HUMAN[@]}"; do printf '%-4s %-62s UNVERIFIED\n' "${h%%|*}" "${h#*|}"; done
for t in "${TODO[@]}"; do printf '%-4s %-62s TODO\n' "${t%%|*}" "${t#*|}"; done
printf '\nPASS %d   FAIL %d   BASELINE %d   UNVERIFIED %d   TODO %d\n' \
  "$RESULT_PASS" "$RESULT_FAIL" "$RESULT_BASELINE" "${#HUMAN[@]}" "${#TODO[@]}"
[ -n "$FAILED_IDS" ] && printf 'failed:%s\n' "$FAILED_IDS"
printf 'the evidence is in %s\n' "$LOGDIR"
[ "$RESULT_FAIL" = 0 ] || exit 1
exit 0
