#!/usr/bin/env bash
# Q4: the idle measurement.
#
#   accept-q4.sh --reference   measure the idle state now and record the number
#                              this run will be gated against
#   accept-q4.sh               measure now and compare against that reference
#
# Why a per-run reference: the idle figure follows whatever the machine is
# doing. A number recorded on an idle box, compared at the end of a 30-minute
# acceptance run that exercises the whole shell, reports the run's own load as
# a regression. accept therefore measures a fresh reference before it starts
# any gate, and the recorded figures below stay what they always were — a
# trend record, not a threshold.
#
# The Phase 10A harness measures; this gate compares.
set -uo pipefail
TENKAI="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$TENKAI" || exit 1
RUN="$TENKAI/.run"
mkdir -p "$RUN/logs"

REF="$RUN/logs/q4-reference.txt"
LIMIT=1.05
MODE="${1:-compare}"

# measure writes the harness log to $1 and prints "rss pss threads cpu".
measure() { # $1 = log path
  python3 docs/tests/phase10a-measure.py > "$1" 2>&1 || return 1
  local json
  json="$(ls -t "$RUN"/logs/phase10a-*.json 2>/dev/null | head -1)"
  [ -n "$json" ] || return 1
  python3 - "$json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path))

def find_idle(obj):
    """The idle state, wherever the harness put it."""
    if isinstance(obj, dict):
        if "idle" in obj and isinstance(obj["idle"], dict):
            return obj["idle"]
        for v in obj.values():
            got = find_idle(v)
            if got:
                return got
    if isinstance(obj, list):
        for v in obj:
            got = find_idle(v)
            if got:
                return got
    return None

idle = find_idle(data)
if not idle:
    print("the json has no idle state", file=sys.stderr)
    sys.exit(1)

procs = idle.get("procs") or idle.get("processes") or []
if not procs and "rss_kb" in idle:
    procs = [idle]
rss = sum(p.get("rss_kb") or 0 for p in procs)
pss = sum(p.get("pss_kb") or 0 for p in procs)
thr = sum(p.get("threads") or 0 for p in procs)
cpu = sum(p.get("cpu_s") or 0 for p in procs)
print("%d %d %d %.2f" % (rss, pss, thr, cpu))
PY
}

case "$MODE" in
--reference)
  log="$RUN/logs/accept-q4-reference.log"
  if ! now="$(measure "$log")"; then
    echo "the 10A reference measurement failed, see $log"
    tail -20 "$log"
    exit 1
  fi
  printf '%s\n' "$now" > "$REF"
  echo "idle reference (this run): $now  (rss_kb pss_kb threads cpu_s)"
  exit 0
  ;;
esac

# The committed trend record (Phase 10A final, post-Blobs, idle on an idle
# box; it used to live in docs/STATUS.md, since removed):
REC_RSS=657260
REC_PSS=311253
REC_THREADS=98
REC_CPU=0.73
SOURCE="recorded table (Phase 10A figures; trend only)"

if [ -s "$REF" ]; then
  read -r REC_RSS REC_PSS REC_THREADS REC_CPU < "$REF"
  SOURCE="reference measured at the start of this run ($REF)"
fi

log="$RUN/logs/accept-q4.log"
if ! now="$(measure "$log")"; then
  echo "the 10A harness failed, see $log"
  tail -20 "$log"
  exit 1
fi
read -r now_rss now_pss now_thr now_cpu <<< "$now"

python3 - "$REC_RSS" "$REC_PSS" "$REC_THREADS" "$REC_CPU" "$LIMIT" \
  "$now_rss" "$now_pss" "$now_thr" "$now_cpu" "$SOURCE" <<'PY'
import sys
rec_rss, rec_pss, rec_thr, rec_cpu, limit = (
    int(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3]), float(sys.argv[4]), float(sys.argv[5]))
rss, pss, thr, cpu = (
    int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8]), float(sys.argv[9]))
source = sys.argv[10]

print("idle now:      %d kB RSS / %d kB PSS / %d threads / %.2f s CPU per 60 s" % (rss, pss, thr, cpu))
print("idle compared: %d kB RSS / %d kB PSS / %d threads / %.2f s CPU per 60 s" % (rec_rss, rec_pss, rec_thr, rec_cpu))
print("against:       %s" % source)

bad = []
for name, now, was in (("rss", rss, rec_rss), ("pss", pss, rec_pss),
                       ("threads", thr, rec_thr), ("cpu", cpu, rec_cpu)):
    if was and now > was * limit:
        bad.append("%s %d over the reference %d (more than 5 %%)" % (name, now, was))
if bad:
    print("FAIL: " + "; ".join(bad))
    sys.exit(1)
print("ok: the idle measurement is within 5 % of this run's reference")
PY
