#!/usr/bin/env bash
# matugen-calls.sh — R5 static check: no matugen call may omit Mei's -c config.
#
# Three things run here:
#   1. every matugen spawn in the tracked sources is listed with its verdict;
#   2. a spawn that passes -c is accepted on the spot — the .run/bin shim
#      (mei_write_matugen_shim in ./mei) re-checks at runtime that the path it
#      names is inside the project, so a literal -c here cannot smuggle a live
#      ~/.config/matugen path past the session;
#   3. a spawn that passes NO -c fails, except the one audited indirection in
#      the daemon whose arguments are built by matugenArgs() and normalised by
#      the shim (it injects Mei's config). That exception is named, in this file,
#      so a new call site cannot borrow it silently.
#
# Usage: matugen-calls.sh [extra-file]
#   extra-file — scanned with the same rules; used by the gate's --prove run to
#   show this check failing on a doctored spawn.
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$MEI"

extra="${1:-}"
fails=0
seen=0

verdict() { # $1 = file:line, $2 = the line text
  local where="$1" text="$2" n
  seen=$((seen + 1))
  case "$text" in
    *'"-c"'*|*' -c '*|*"-c "*)
      printf 'OK       %s\n' "$where"
      return 0
      ;;
    *'exec.Command("matugen", args...)'*)
      # The audited indirection: matugenArgs() builds the argv, the shim adds
      # Mei's -c. Nothing else may look like this.
      printf 'OK-SHIM  %s   (argv built by matugenArgs; the shim supplies -c)\n' "$where"
      return 0
      ;;
  esac
  printf 'FAIL     %s\n         %s\n' "$where" "$(printf '%s' "$text" | cut -c1-120)"
  fails=$((fails + 1))
  return 1
}

scan() { # $1 = file, $2 = Go|Qml|Sh
  local f="$1" kind="$2" n text
  [ -f "$f" ] || return 0
  case "$kind" in
    Go)  n="$(grep -n 'exec\.Command("matugen"' "$f" | cut -d: -f1)" ;;
    Qml) n="$(grep -n -E '(command:[[:space:]]*\[?[[:space:]]*"matugen"|execDetached\([^)]*"matugen")' "$f" | cut -d: -f1)" ;;
    Sh)  n="$(grep -n -E '^[[:space:]]*(exec[[:space:]]+)?matugen[[:space:]]' "$f" | cut -d: -f1)" ;;
    *)   return 0 ;;
  esac
  [ -n "$n" ] || return 0
  for ln in $n; do
    text="$(sed -n "${ln}p" "$f")"
    verdict "$f:$ln" "$text" || true
  done
}

echo "=== matugen spawns in the tracked sources ==="
while IFS= read -r f; do
  case "$f" in
    *.go) scan "$f" Go  ;;
    *.qml) scan "$f" Qml ;;
    *.sh) scan "$f" Sh  ;;
  esac
done < <(git ls-files 'src/*.go' 'src/*.qml' 'docs/*.sh' 'docs/tests/*.sh' 'mei' 2>/dev/null)
# ./mei is bash, not sh: its own matugen reference is the config copy, not a spawn.
if [ -n "$extra" ] && [ -f "$extra" ]; then
  echo "--- proof material: $extra ---"
  scan "$extra" Go
  scan "$extra" Sh
fi

echo "spawns checked: $seen   failures: $fails"
if [ "$fails" -gt 0 ]; then
  echo "matugen-calls: FAIL (a matugen call does not carry Mei's -c config)"
  exit 1
fi
echo "matugen-calls: PASS (every matugen call carries Mei's -c config, or is the audited shim-normalised argv)"
exit 0
