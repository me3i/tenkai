#!/usr/bin/env bash
# Q4: the idle measurement, and it must not be more than 5 % over the last
# recorded table (docs/STATUS.md: idle 602,584 kB RSS / 328,937 kB PSS / 88
# threads / 1.2 s CPU per 60 s).
#
# The Phase 10A harness measures; this gate compares.
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$MEI"
RUN="$MEI/.run"
mkdir -p "$RUN/logs"

# The recorded table, in kB and seconds.
REC_RSS=602584
REC_PSS=328937
REC_THREADS=88
REC_CPU=1.2
LIMIT=1.05

log="$RUN/logs/accept-q4.log"
python3 docs/tests/phase10a-measure.py > "$log" 2>&1 || { echo "the 10A harness failed, see $log"; tail -20 "$log"; exit 1; }
json="$(ls -t "$RUN"/logs/phase10a-*.json 2>/dev/null | head -1)"
[ -n "$json" ] || { echo "the 10A harness wrote no json"; exit 1; }

python3 - "$json" "$REC_RSS" "$REC_PSS" "$REC_THREADS" "$REC_CPU" "$LIMIT" <<'PY'
import json, sys
path, rec_rss, rec_pss, rec_thr, rec_cpu, limit = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), float(sys.argv[6])
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
    print("the json has no idle state")
    sys.exit(1)

procs = idle.get("procs") or idle.get("processes") or []
if not procs and "rss_kb" in idle:
    procs = [idle]
rss = sum(p.get("rss_kb") or 0 for p in procs)
pss = sum(p.get("pss_kb") or 0 for p in procs)
thr = sum(p.get("threads") or 0 for p in procs)
cpu = sum(p.get("cpu_s") or 0 for p in procs)

print("idle now:      %d kB RSS / %d kB PSS / %d threads / %.2f s CPU per 60 s" % (rss, pss, thr, cpu))
print("idle recorded: %d kB RSS / %d kB PSS / %d threads / %.2f s CPU per 60 s" % (rec_rss, rec_pss, rec_thr, rec_cpu))
bad = []
for name, now, was in (("rss", rss, rec_rss), ("pss", pss, rec_pss), ("threads", thr, rec_thr), ("cpu", cpu, rec_cpu)):
    if was and now > was * limit:
        bad.append("%s %d over the recorded %d (more than 5 %%)" % (name, now, was))
if bad:
    print("FAIL: " + "; ".join(bad))
    sys.exit(1)
print("ok: the idle measurement is within 5 % of the recorded table")
PY
