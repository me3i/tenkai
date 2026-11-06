#!/usr/bin/env python3
"""Live-trial self-monitor: Tenkai's CPU and RSS every 5 s, into .run/logs.

Reads .run/live-pids (the pids ./tenkai live recorded) and walks their descendants
through /proc parent links, so it sees the daemon, the shell, the WM provider
and ryogami without knowing their names. The numbers are the live counterpart
of the nested Phase 10A table, so the two can be compared directly.

usage: live-monitor.py [interval-seconds]
"""
import os
import sys
import time
from datetime import datetime

TENKAI = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
RUN = os.path.join(TENKAI, ".run")
PIDFILE = os.path.join(RUN, "live-pids")
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
LOG = os.path.join(RUN, "logs", "live-monitor-%s.log" % STAMP)
CSV = os.path.join(RUN, "logs", "live-monitor-%s.csv" % STAMP)
HZ = os.sysconf("SC_CLK_TCK")
INTERVAL = float(sys.argv[1]) if len(sys.argv) > 1 else 5.0


def read_cmdline(pid):
    try:
        raw = open("/proc/%d/cmdline" % pid, "rb").read()
    except OSError:
        return []
    return [x.decode("utf-8", "replace") for x in raw.split(b"\0") if x]


def ppid_of(pid):
    try:
        raw = open("/proc/%d/stat" % pid, encoding="utf-8").read()
    except OSError:
        return None
    try:
        rest = raw[raw.rfind(")") + 2:].split()
        return int(rest[1])
    except (IndexError, ValueError):
        return None


def cpu_ticks(pid):
    try:
        raw = open("/proc/%d/stat" % pid, encoding="utf-8").read()
    except OSError:
        return None
    try:
        rest = raw[raw.rfind(")") + 2:].split()
        return int(rest[11]) + int(rest[12])
    except (IndexError, ValueError):
        return None


def metrics(pid):
    out = {"rss": None, "pss": None, "threads": None, "cpu": None}
    try:
        for line in open("/proc/%d/smaps_rollup" % pid, encoding="utf-8"):
            if line.startswith("Rss:"):
                out["rss"] = int(line.split()[1])
            elif line.startswith("Pss:"):
                out["pss"] = int(line.split()[1])
    except OSError:
        pass
    try:
        for line in open("/proc/%d/status" % pid, encoding="utf-8"):
            if line.startswith("Threads:"):
                out["threads"] = int(line.split()[1])
            elif line.startswith("VmRSS:") and out["rss"] is None:
                out["rss"] = int(line.split()[1])
    except OSError:
        pass
    out["cpu"] = cpu_ticks(pid)
    return out


def label_for(pid):
    argv = read_cmdline(pid)
    if not argv:
        return "?"
    exe = os.path.basename(argv[0])
    if exe == "qs":
        for a in argv:
            if "/hub/quickshell" in a:
                return "hub-qs"
        return "qs"
    if exe == "tenkai-shell":
        return "tenkai-shell"
    if exe == "tenkai-wm-hyprland":
        return "tenkai-wm"
    if exe == "ryogami":
        return "ryogami"
    return exe


def roots():
    out = []
    try:
        for line in open(PIDFILE, encoding="utf-8"):
            parts = line.rstrip("\n").split("\t")
            if parts and parts[0].isdigit():
                out.append(int(parts[0]))
    except OSError:
        pass
    return out


def descendants(roots):
    children = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        ppid = ppid_of(pid)
        if ppid is not None:
            children.setdefault(ppid, []).append(pid)
    seen = set()
    out = []
    stack = list(roots)
    while stack:
        pid = stack.pop()
        for child in children.get(pid, []):
            if child in seen:
                continue
            seen.add(child)
            out.append(child)
            stack.append(child)
    return out


def main():
    os.makedirs(os.path.dirname(LOG), exist_ok=True)
    with open(CSV, "w", encoding="utf-8") as fh:
        fh.write("time,label,pid,cpu_percent,rss_kb,pss_kb,threads\n")
    with open(LOG, "w", encoding="utf-8") as fh:
        fh.write("# Tenkai live self-monitor, every %.0f s\n" % INTERVAL)
        fh.write("# time label pid cpu%% rss_kB pss_kB threads\n")
    print("live-monitor: %s" % LOG, flush=True)
    prev = {}
    while True:
        rs = roots()
        if not rs:
            break
        pids = sorted(set(rs) | set(descendants(rs)))
        now = time.monotonic()
        stamp = datetime.now().strftime("%H:%M:%S")
        rows = []
        for pid in pids:
            if not os.path.exists("/proc/%d" % pid):
                prev.pop(pid, None)
                continue
            m = metrics(pid)
            if m["cpu"] is None:
                continue
            pct = 0.0
            if pid in prev and now > prev[pid][0]:
                pct = (m["cpu"] - prev[pid][1]) / float(HZ) / (now - prev[pid][0]) * 100.0
            prev[pid] = (now, m["cpu"])
            rows.append((label_for(pid), pid, pct, m["rss"], m["pss"], m["threads"]))
        tot_rss = sum(r[3] or 0 for r in rows)
        tot_pss = sum(r[4] or 0 for r in rows if r[4] is not None)
        tot_cpu = sum(r[2] for r in rows)
        tot_thr = sum(r[5] or 0 for r in rows)
        line = "%s  TOTAL rss=%d kB pss=%d kB cpu=%.2f%% threads=%d" % (
            stamp, tot_rss, tot_pss, tot_cpu, tot_thr)
        with open(LOG, "a", encoding="utf-8") as fh:
            fh.write(line + "\n")
            for r in rows:
                fh.write("   %-10s pid=%-7d cpu=%6.2f%% rss=%-8s pss=%-8s threads=%s\n" % r)
        with open(CSV, "a", encoding="utf-8") as fh:
            for r in rows:
                fh.write("%s,%s,%d,%.2f,%s,%s,%s\n" % (
                    stamp, r[0], r[1], r[2], r[3], r[4], r[5]))
        print(line, flush=True)
        time.sleep(INTERVAL)
    print("live-monitor: the live session ended, monitor stopped", flush=True)


if __name__ == "__main__":
    main()
