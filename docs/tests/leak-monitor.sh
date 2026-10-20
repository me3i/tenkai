#!/usr/bin/env bash
# Whole-run live-session leak monitor.
#
#   usage: leak-monitor.sh <pidfile> <stopfile> <logfile>
#   env:   NESTED_RT, LIVE_RT, LIVE_WL, LEAK_LIVE_PIDS (optional override)
#
# Reads only recorded Mei PIDs (the pidfile written by `mei run`) and only
# /proc/<pid>/environ, /proc/<pid>/stat. It never calls hyprctl and never
# connects to the live compositor. A process is a violation when:
#   - its XDG_RUNTIME_DIR is the live runtime (the old b915e0a leak), or
#   - its runtime is unset/unexpected (fail closed), or
#   - it names a WAYLAND_DISPLAY that has no socket under the nested runtime, or
#   - its direct parent is a live session process (live shell / live Hyprland).
#
# Exit 0 only if the stop file appears with no violation; exit 1 otherwise.
set -uo pipefail

PIDFILE="${1:?pidfile}"; STOP="${2:?stopfile}"; LOG="${3:?logfile}"
NESTED_RT="${NESTED_RT:-/home/mei/projects/mei/.r}"
LIVE_RT="${LIVE_RT:-/run/user/$(id -u)}"
LIVE_WL="${LIVE_WL:-wayland-1}"
: > "$LOG"

live_shell="$(busctl --user list --no-legend 2>/dev/null | awk '$1=="org.freedesktop.Notifications"{print $2; exit}')"
live_hypr="$(ps -eo pid=,args= 2>/dev/null | awk '$2=="Hyprland" && $0 !~ /-c /{print $1; exit}')"
LIVE_PIDS="${LEAK_LIVE_PIDS:-$live_shell $live_hypr}"

printf 'monitor: pidfile=%s nested=%s live=%s live_wl=%s live_pids=%s\n' \
  "$PIDFILE" "$NESTED_RT" "$LIVE_RT" "$LIVE_WL" "$LIVE_PIDS" >> "$LOG"

declare -A seen=()
viol=0
checks=0
v() { # $1 pid, $2 name, $3 reason
  local key="$1:$3"
  [ -n "${seen[$key]:-}" ] && return
  seen[$key]=1
  viol=$((viol+1))
  printf 'LEAK %s pid=%s name=%s %s\n' "$(date +%H:%M:%S)" "$1" "${2:-?}" "$3" | tee -a "$LOG"
}

while [ ! -e "$STOP" ]; do
  if [ -r "$PIDFILE" ]; then
    while IFS=$'\t' read -r pid pgid name; do
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      [ -d "/proc/$pid" ] || continue
      checks=$((checks+1))
      rt="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)"
      wl="$(tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)"
      ppid="$(awk '{print $4}' "/proc/$pid/stat" 2>/dev/null)"
      if [ "$rt" = "$LIVE_RT" ]; then
        v "$pid" "$name" "uses the live XDG_RUNTIME_DIR ($rt)"
      elif [ -z "$rt" ]; then
        v "$pid" "$name" "has no XDG_RUNTIME_DIR (could default to the live runtime)"
      elif [ "$rt" != "$NESTED_RT" ]; then
        v "$pid" "$name" "unexpected XDG_RUNTIME_DIR ($rt)"
      fi
      if [ -n "$wl" ] && [ "$rt" = "$NESTED_RT" ] && [ ! -e "$NESTED_RT/$wl" ]; then
        v "$pid" "$name" "WAYLAND_DISPLAY=$wl has no socket under the nested runtime"
      fi
      for lp in $LIVE_PIDS; do
        [ -n "$lp" ] && [ "$ppid" = "$lp" ] && v "$pid" "$name" "is a child of live PID $lp"
      done
    done < "$PIDFILE"
  fi
  sleep 0.25
done

if [ "$viol" -gt 0 ]; then
  printf 'LEAK: %d violation(s) across %d checks\n' "$viol" "$checks" | tee -a "$LOG"
  exit 1
fi
printf 'OK: no live-runtime or live-parent process in %d checks\n' "$checks" | tee -a "$LOG"
exit 0
