#!/usr/bin/env bash
# Whole-run live-session leak monitor.
#
#   usage: leak-monitor.sh <pidfile> <stopfile> <logfile>
#   env:   NESTED_RT, LIVE_RT, LIVE_WL, LEAK_LIVE_PIDS (optional override)
#
# Reads the recorded Mei PIDs (the pidfile written by `mei run`) and walks
# /proc/<pid>/stat parent links to include every descendant of the recorded
# nested launcher and nested compositor. It reads only /proc/<pid>/environ,
# /proc/<pid>/stat and /proc/<pid>/cmdline. It never calls hyprctl and never
# connects to the live compositor. A process is a violation when:
#   - its XDG_RUNTIME_DIR is the live runtime (the old b915e0a leak), or
#   - its runtime is unset/unexpected (fail closed), or
#   - it names an absolute WAYLAND_DISPLAY inside the live runtime, or
#   - its direct parent is a live session process (live shell / live Hyprland).
#
# The recorded launcher and compositor are the only recorded top-level
# exemptions: the launcher is the setsid/dbus-run-session parent that inherits
# the live environment only to start the nested session, and the nested
# compositor opens the live display as a Wayland client by design. The
# launcher's own dbus-daemon and session.sh wrapper are launch infrastructure
# (not Mei UI/daemon processes) and are logged as INFRA; their runtime is not
# treated as a leak because they carry the host environment into the session.
# Every other descendant, including qs, mei-shell, ryogami, mei-hub and
# mei-wm-hyprland, is checked strictly on every scan.
#
# Exit 0 only if the stop file appears with no violation; exit 1 otherwise.
set -uo pipefail

PIDFILE="${1:?pidfile}"; STOP="${2:?stopfile}"; LOG="${3:?logfile}"
NESTED_RT="${NESTED_RT:-/home/mei/projects/mei/.r}"
LIVE_RT="${LIVE_RT:-/run/user/$(id -u)}"
LIVE_WL="${LIVE_WL:-wayland-1}"
RUN_DIR="${NESTED_RT%/*}/.run"
: > "$LOG"

live_shell="$(busctl --user list --no-legend 2>/dev/null | awk '$1=="org.freedesktop.Notifications"{print $2; exit}')"
live_hypr="$(ps -eo pid=,args= 2>/dev/null | awk '$2=="Hyprland" && $0 !~ /-c /{print $1; exit}')"
LIVE_PIDS="${LEAK_LIVE_PIDS:-$live_shell $live_hypr}"

printf 'monitor: pidfile=%s nested=%s live=%s live_wl=%s live_pids=%s\n' \
  "$PIDFILE" "$NESTED_RT" "$LIVE_RT" "$LIVE_WL" "$LIVE_PIDS" >> "$LOG"

declare -A seen=()
declare -A PARENT_OF=()
declare -A COMM_OF=()
declare -A CHECK=()
declare -A ROOT_KIND=()
declare -A announced=()
declare -A seen_infra=()
LAUNCHER_ROOTS=""
COMPOSITOR_ROOTS=""
viol=0
checks=0
scope_logged=0

v() { # $1 pid, $2 name, $3 reason
  local key="$1:$3"
  [ -n "${seen[$key]:-}" ] && return
  seen[$key]=1
  viol=$((viol+1))
  printf 'LEAK %s pid=%s name=%s %s\n' "$(date +%H:%M:%S)" "$1" "${2:-?}" "$3" | tee -a "$LOG"
}

proc_stat() { # $1 pid; sets PSTATE and PARENT
  local line rest
  line="$(cat "/proc/$1/stat" 2>/dev/null)" || return 1
  rest="${line##*) }"
  PSTATE="${rest%% *}"
  rest="${rest#* }"
  PARENT="${rest%% *}"
  [ -n "$PSTATE" ] && [ -n "$PARENT" ]
}

read_env() { # $1 pid; sets ERT, EWL, EEMPTY
  local raw
  raw="$(tr '\0' '\n' < "/proc/$1/environ" 2>/dev/null)" || return 1
  EEMPTY=0
  [ -z "$raw" ] && EEMPTY=1
  ERT="$(printf '%s\n' "$raw" | sed -n 's/^XDG_RUNTIME_DIR=//p' | head -1)"
  EWL="$(printf '%s\n' "$raw" | sed -n 's/^WAYLAND_DISPLAY=//p' | head -1)"
}

load_table() { # current /proc process tree, parent links only
  local d pid
  PARENT_OF=(); COMM_OF=()
  for d in /proc/[0-9]*; do
    pid="${d##*/}"
    proc_stat "$pid" || continue
    [ "$PSTATE" = "Z" ] && continue
    PARENT_OF[$pid]="$PARENT"
    COMM_OF[$pid]="$(cat "$d/comm" 2>/dev/null)"
  done
}

is_descendant() { # $1 pid, $2 root; true if root is an ancestor
  local p="$1" depth=0
  while [ "$depth" -lt 64 ]; do
    p="${PARENT_OF[$p]:-}"
    [ -z "$p" ] && return 1
    [ "$p" = "$2" ] && return 0
    if [ "$p" = 0 ] || [ "$p" = 1 ]; then return 1; fi
    depth=$((depth+1))
  done
  return 1
}

is_launch_infra() { # $1 pid: launcher's D-Bus/session wrapper, not Mei UI
  local pid="$1" cmd
  case "${COMM_OF[$pid]:-}" in
    dbus-daemon) return 0 ;;
  esac
  cmd="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null)"
  case "$cmd" in
    *"$RUN_DIR/session.sh"*) return 0 ;;
  esac
  return 1
}

build_scope() {
  local pid name
  CHECK=(); ROOT_KIND=(); LAUNCHER_ROOTS=""; COMPOSITOR_ROOTS=""
  if [ -r "$PIDFILE" ]; then
    while IFS=$'\t' read -r pid pgid name; do
      case "$pid" in ''|*[!0-9]*) continue ;; esac
      [ -d "/proc/$pid" ] || continue
      CHECK[$pid]="${name:-?}"
      case "$name" in
        nested-launcher) LAUNCHER_ROOTS="$LAUNCHER_ROOTS $pid"; ROOT_KIND[$pid]=launcher ;;
        hyprland-nested) COMPOSITOR_ROOTS="$COMPOSITOR_ROOTS $pid"; ROOT_KIND[$pid]=compositor ;;
      esac
    done < "$PIDFILE"
  fi
  load_table
  for pid in "${!PARENT_OF[@]}"; do
    for name in $LAUNCHER_ROOTS $COMPOSITOR_ROOTS; do
      if is_descendant "$pid" "$name"; then
        CHECK[$pid]="${COMM_OF[$pid]:-?}"
        break
      fi
    done
  done
  if [ "$scope_logged" = 0 ]; then
    printf 'scope: launcher=%s compositor=%s descendants+recorded=%d\n' \
      "${LAUNCHER_ROOTS:-none}" "${COMPOSITOR_ROOTS:-none}" "${#CHECK[@]}" >> "$LOG"
    scope_logged=1
  fi
  for pid in "${!CHECK[@]}"; do
    if [ -z "${announced[$pid]:-}" ]; then
      printf 'track pid=%s name=%s\n' "$pid" "${CHECK[$pid]}" >> "$LOG"
      announced[$pid]=1
    fi
  done
}

check_pid() { # $1 pid, $2 name
  local pid="$1" name="$2" kind ppid
  [ -d "/proc/$pid" ] || return
  kind="${ROOT_KIND[$pid]:-}"
  if [ "$name" = "nested-launcher" ] || [ "$kind" = "launcher" ]; then return; fi
  [ -n "$kind" ] || { if is_launch_infra "$pid"; then kind=infra; fi; }

  read_env "$pid" || return
  # A daemon recorded at the instant it is exec'd can briefly expose an
  # empty environ. Retry twice; then fail closed (it could default live).
  if [ "$EEMPTY" = 1 ]; then
    for _ in 1 2; do
      [ -d "/proc/$pid" ] || return
      sleep 0.1
      read_env "$pid" || return
      [ "$EEMPTY" = 0 ] && break
    done
  fi
  [ -d "/proc/$pid" ] || return
  proc_stat "$pid" || return
  [ "$PSTATE" = "Z" ] && return
  ppid="$PARENT"
  checks=$((checks+1))

  if [ "$kind" = "infra" ]; then
    if [ -z "${seen_infra[$pid]:-}" ]; then
      printf 'INFRA pid=%s name=%s runtime=%s (launcher D-Bus/session wrapper; not a Mei UI process)\n' \
        "$pid" "$name" "${ERT:-unset}" >> "$LOG"
      seen_infra[$pid]=1
    fi
  else
    if [ "$ERT" = "$LIVE_RT" ]; then
      v "$pid" "$name" "uses the live XDG_RUNTIME_DIR ($ERT)"
    elif [ -z "$ERT" ]; then
      v "$pid" "$name" "has no XDG_RUNTIME_DIR (could default to the live runtime)"
    elif [ "$ERT" != "$NESTED_RT" ]; then
      v "$pid" "$name" "unexpected XDG_RUNTIME_DIR ($ERT)"
    fi
  fi

  # A relative WAYLAND_DISPLAY is resolved under XDG_RUNTIME_DIR, which is
  # already required to be nested above; it can be briefly absent while the
  # nested compositor starts/stops. Only an absolute path into the live
  # runtime is evidence of the live display. The nested compositor is the one
  # process allowed that path: it opens the live display as a client.
  case "$EWL" in
    "$LIVE_RT"/*)
      [ "$kind" = "compositor" ] || \
        v "$pid" "$name" "WAYLAND_DISPLAY points into the live runtime ($EWL)"
      ;;
  esac
  for lp in $LIVE_PIDS; do
    [ -n "$lp" ] && [ "$ppid" = "$lp" ] && v "$pid" "$name" "is a child of live PID $lp"
  done
}

while [ ! -e "$STOP" ]; do
  build_scope
  for pid in "${!CHECK[@]}"; do
    check_pid "$pid" "${CHECK[$pid]}"
  done
  sleep 0.25
done

if [ "$viol" -gt 0 ]; then
  printf 'LEAK: %d violation(s) across %d checks (%d tracked PIDs)\n' \
    "$viol" "$checks" "${#announced[@]}" | tee -a "$LOG"
  exit 1
fi
printf 'OK: no live-runtime or live-parent process in %d checks (%d tracked PIDs, including descendants)\n' \
  "$checks" "${#announced[@]}" | tee -a "$LOG"
exit 0
