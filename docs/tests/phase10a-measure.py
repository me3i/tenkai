#!/usr/bin/env python3
"""Phase 10A: measure only. No product changes, no installs, no live signalling.

One nested session is started by ./mei run. After 120 s of idle it measures:
  idle, launcher open, quick settings open, Settings hub open, one wallpaper set.
Each window is 60 s. Per-process RSS/PSS/threads/CPU/context switches come from
/proc only. The live Quickshell (PID 949) is read-only via /proc; it is never
signalled or queried over IPC. The nested Hyprland is measured separately and is
never included in the Mei total.

Output: .run/logs/phase10a-<stamp>.log and .run/logs/phase10a-<stamp>.json
"""

import json
import os
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime

MEI = "/home/mei/projects/mei"
RUN = os.path.join(MEI, ".run")
RT = os.path.join(MEI, ".r")
HOST_XDG = os.environ.get("XDG_RUNTIME_DIR", "/run/user/%d" % os.getuid())
HOST_WL = os.environ.get("WAYLAND_DISPLAY", "wayland-1")
LIVE_QS = 949
DURATION = 60
IDLE_SECONDS = 120
STAMP = datetime.now().strftime("%Y%m%d-%H%M%S")
LOG_PATH = os.path.join(RUN, "logs", "phase10a-%s.log" % STAMP)
JSON_PATH = os.path.join(RUN, "logs", "phase10a-%s.json" % STAMP)
WALL = os.path.join(RUN, "wall", "wall-1-warm.jpg")
HZ = os.sysconf("SC_CLK_TCK")

os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
DATA = {"stamp": STAMP, "duration_s": DURATION, "idle_s": IDLE_SECONDS, "states": {}}
STARTED = False
SIG = ""
BUS = ""
NESTED_ENV = {}
MESH_ENV = {}
HOST_ENV = {}
RESULTS = []


def log(*parts):
    text = " ".join(str(p) for p in parts)
    print(text, flush=True)
    with open(LOG_PATH, "a", encoding="utf-8") as fh:
        fh.write(text + "\n")


def run(argv, env, timeout=60):
    return subprocess.run(argv, env=env, text=True, capture_output=True, timeout=timeout)


def read_cmdline(pid):
    try:
        raw = open("/proc/%d/cmdline" % pid, "rb").read()
    except OSError:
        return []
    return [x.decode("utf-8", "replace") for x in raw.split(b"\0") if x]


def read_comm(pid):
    try:
        return open("/proc/%d/comm" % pid).read().strip()
    except OSError:
        return ""


def read_environ(pid):
    out = {}
    try:
        raw = open("/proc/%d/environ" % pid, "rb").read()
    except OSError:
        return out
    for item in raw.split(b"\0"):
        if b"=" not in item:
            continue
        key, value = item.split(b"=", 1)
        out[key.decode("utf-8", "replace")] = value.decode("utf-8", "replace")
    return out


def belongs_to_current_session(label, pid):
    """Reject a test process left behind by a previous nested session.

    All Mei processes should carry the fake HOME and the nested runtime. Shell
    and hub qs additionally carry the current nested Hyprland signature. This is
    deliberately a guard for this measurement harness, not a product check.
    """
    env = read_environ(pid)
    if env.get("XDG_RUNTIME_DIR") != RT:
        return False
    if env.get("HOME") != os.path.join(RUN, "home"):
        return False
    if SIG and label in ("qs", "hub-qs"):
        return env.get("HYPRLAND_INSTANCE_SIGNATURE") == SIG
    return True


def classify(strict=False):
    """Return {label: pid} for every persistent Mei process, no name-wide pgrep."""
    found = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        argv = read_cmdline(pid)
        if not argv:
            continue
        exe = os.path.basename(argv[0])
        label = None
        if exe == "qs":
            project = ""
            for i, arg in enumerate(argv[:-1]):
                if arg == "-p":
                    project = argv[i + 1]
                    break
            if "/src/ryoku/shell/quickshell/shell" in project:
                label = "qs"
            elif "/src/ryoku/hub/quickshell" in project:
                label = "hub-qs"
        elif exe == "mei-shell" and "daemon" in argv:
            label = "mei-shell"
        elif exe == "ryogami" and "daemon" in argv:
            label = "ryogami"
        elif exe == "mei-hub":
            label = "mei-hub"
        elif exe == "mei-wm-hyprland":
            label = "mei-wm-hyprland"
        if not label:
            continue
        if strict and not belongs_to_current_session(label, pid):
            log("EXCLUDED stale/foreign process %s pid=%d (not this nested session)" % (label, pid))
            continue
        found[label] = pid
    return found


def project_hubs():
    """Find any Mei Settings-hub qs, including a stale one from an earlier run."""
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        argv = read_cmdline(pid)
        if not argv or os.path.basename(argv[0]) != "qs":
            continue
        project = ""
        for i, arg in enumerate(argv[:-1]):
            if arg == "-p":
                project = argv[i + 1]
                break
        if project.startswith(MEI + "/") and "/src/ryoku/hub/quickshell" in project:
            found.append((pid, project))
    return found


def wait_hub_ready(seconds=30):
    """Wait for the Settings hub's QML to finish loading, not just its process."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        procs = classify(strict=True)
        pid = procs.get("hub-qs")
        if pid:
            m = read_metric(pid)
            if m and (m["threads"] or 0) >= 5 and (m["rss_kb"] or 0) >= 50000:
                return True
        time.sleep(0.5)
    return False


def hypr_pid():
    pidfile = os.path.join(RUN, "pids")
    try:
        for line in open(pidfile):
            fields = line.rstrip("\n").split("\t")
            if len(fields) >= 3 and fields[2] == "hyprland-nested":
                return int(fields[0])
    except (OSError, ValueError):
        pass
    return None


def read_metric(pid):
    """Read RSS/PSS/threads/ctxt/CPU from /proc only; None if the PID vanished."""
    if not pid or not os.path.exists("/proc/%d" % pid):
        return None
    out = {"pid": pid, "rss_kb": None, "pss_kb": None, "threads": None,
           "vol": 0, "nonvol": 0, "utime": 0, "stime": 0, "state": "?", "gone": False}
    try:
        smaps = open("/proc/%d/smaps_rollup" % pid, encoding="utf-8").read()
        for line in smaps.splitlines():
            if line.startswith("Rss:"):
                out["rss_kb"] = int(line.split()[1])
            elif line.startswith("Pss:"):
                out["pss_kb"] = int(line.split()[1])
    except OSError:
        pass
    try:
        status = open("/proc/%d/status" % pid, encoding="utf-8").read()
        for line in status.splitlines():
            if line.startswith("Threads:"):
                out["threads"] = int(line.split()[1])
            elif line.startswith("voluntary_ctxt_switches:"):
                out["vol"] = int(line.split()[1])
            elif line.startswith("nonvoluntary_ctxt_switches:"):
                out["nonvol"] = int(line.split()[1])
            elif line.startswith("VmRSS:") and out["rss_kb"] is None:
                out["rss_kb"] = int(line.split()[1])
    except OSError:
        return None
    try:
        raw = open("/proc/%d/stat" % pid, encoding="utf-8").read()
        rest = raw[raw.rfind(")") + 2:].split()
        out["state"] = rest[0]
        out["utime"] = int(rest[11])
        out["stime"] = int(rest[12])
    except (OSError, IndexError, ValueError):
        return None
    return out


def metric_row(label, start, end, elapsed):
    if start is None and end is None:
        return None
    a = start or end
    b = end or start
    ticks = max(0, (b["utime"] + b["stime"]) - (a["utime"] + a["stime"]))
    cpu_s = ticks / float(HZ)
    cpu_pct = cpu_s / elapsed * 100.0 if elapsed > 0 else 0.0
    vol = max(0, b["vol"] - a["vol"])
    nonvol = max(0, b["nonvol"] - a["nonvol"])
    return {
        "label": label,
        "pid": b["pid"],
        "rss_kb": b["rss_kb"],
        "pss_kb": b["pss_kb"],
        "threads": b["threads"],
        "cpu_s": round(cpu_s, 3),
        "cpu_pct": round(cpu_pct, 3),
        "vol_s": round(vol / elapsed, 2) if elapsed > 0 else 0,
        "nonvol_s": round(nonvol / elapsed, 2) if elapsed > 0 else 0,
        "gone": b["gone"],
    }


def fmt(v, suffix=""):
    return "n/a" if v is None else "%s%s" % (v, suffix)


def measure(state, note, duration=DURATION):
    procs = classify(strict=True)
    hypr = hypr_pid()
    live_ok = os.path.exists("/proc/%d" % LIVE_QS) and "quickshell" in read_comm(LIVE_QS)
    log("")
    log("=== %s — %s ===" % (state, note))
    log("nested-only: %s  (live PID 949 reference is host read-only)" % state)
    if not procs:
        log("FAIL no Mei processes found")
    start = {label: read_metric(pid) for label, pid in procs.items()}
    start_hypr = read_metric(hypr)
    start_live = read_metric(LIVE_QS) if live_ok else None
    t0 = time.monotonic()
    time.sleep(duration)
    elapsed = time.monotonic() - t0
    end = {label: read_metric(pid) for label, pid in procs.items()}
    end_hypr = read_metric(hypr)
    end_live = read_metric(LIVE_QS) if live_ok else None

    rows = []
    for label in ("qs", "mei-shell", "mei-wm-hyprland", "ryogami", "mei-hub", "hub-qs"):
        if label in procs:
            row = metric_row(label, start.get(label), end.get(label), elapsed)
            if row:
                rows.append(row)
    total = {
        "label": "MEI TOTAL (no compositor)",
        "rss_kb": sum(r["rss_kb"] or 0 for r in rows) if rows else 0,
        "pss_kb": sum(r["pss_kb"] or 0 for r in rows) if rows and all(r["pss_kb"] is not None for r in rows) else None,
        "threads": sum(r["threads"] or 0 for r in rows) if rows else 0,
        "cpu_s": round(sum(r["cpu_s"] for r in rows), 3),
        "cpu_pct": round(sum(r["cpu_pct"] for r in rows), 3),
        "vol_s": round(sum(r["vol_s"] for r in rows), 2),
        "nonvol_s": round(sum(r["nonvol_s"] for r in rows), 2),
        "pid": "-",
        "gone": False,
    }
    hypr_row = metric_row("nested Hyprland (excluded from Mei total)", start_hypr, end_hypr, elapsed)
    live_row = metric_row("live Quickshell 949 (host read-only reference)", start_live, end_live, elapsed)
    if live_row:
        live_row["live_reference"] = True

    log("| process | PID | RSS kB | PSS kB | threads | CPU s/60s | CPU % | vol ctxt/s | nonvol ctxt/s |")
    log("|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    for row in rows + [total] + ([hypr_row] if hypr_row else []) + ([live_row] if live_row else []):
        if not row:
            continue
        log("| %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
            row["label"], row["pid"], fmt(row["rss_kb"]), fmt(row["pss_kb"]),
            fmt(row["threads"]), fmt(row["cpu_s"]), fmt(row["cpu_pct"]),
            fmt(row["vol_s"]), fmt(row["nonvol_s"])))
    if "mei-hub" not in procs:
        log("NOTE no persistent `mei-hub` process was observed in this state.")
    if "hub-qs" not in procs and state == "settings-hub":
        log("NOTE no Settings hub qs process was observed in this state.")
    if not live_ok:
        log("NOTE live PID 949 is not a quickshell process; reference skipped.")

    rec = {
        "state": state,
        "note": note,
        "duration_s": round(elapsed, 3),
        "processes": rows,
        "total": total,
        "hyprland": hypr_row,
        "live_qs": live_row,
    }
    DATA["states"][state] = rec
    RESULTS.append(rec)
    return rec


def child_rows(parents):
    pids = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        pid = int(entry)
        try:
            raw = open("/proc/%d/stat" % pid).read()
            rest = raw[raw.rfind(")") + 2:].split()
            pids[pid] = int(rest[1])
        except (OSError, IndexError, ValueError):
            pass
    out = []
    for child, ppid in sorted(pids.items()):
        if ppid not in parents:
            continue
        cmd = read_cmdline(child)
        m = read_metric(child)
        out.append({
            "pid": child,
            "parent": parents[ppid],
            "comm": read_comm(child),
            "rss_kb": m["rss_kb"] if m else None,
            "cmdline": " ".join(cmd)[:240],
        })
    return out


def nested_h(*args):
    if not SIG or not os.path.exists(os.path.join(RT, "hypr", SIG, ".socket.sock")):
        raise RuntimeError("nested Hyprland socket absent; refusing live fallback")
    return run(["hyprctl", *args], NESTED_ENV, timeout=15)


def dispatch_global(name):
    r = nested_h("dispatch", 'hl.dsp.global("ryoku:%s")' % name)
    log("dispatch ryoku:%s rc=%s %s" % (name, r.returncode, (r.stdout + r.stderr).strip()))
    time.sleep(2.0)


def layer_namespaces():
    r = nested_h("-j", "layers")
    try:
        obj = json.loads(r.stdout)
        names = set()
        for level in obj.values():
            for item in level:
                if isinstance(item, dict) and item.get("namespace"):
                    names.add(item["namespace"])
        return ",".join(sorted(names))
    except Exception:
        return "?"


def wait_session():
    global SIG, BUS, NESTED_ENV, MESH_ENV
    for _ in range(300):
        dirs = []
        try:
            dirs = [d for d in os.listdir(os.path.join(RT, "hypr")) if os.path.isdir(os.path.join(RT, "hypr", d))]
        except OSError:
            pass
        if dirs:
            sig = dirs[0]
            if os.path.exists(os.path.join(RT, "hypr", sig, ".socket.sock")):
                procs = classify()
                if "qs" in procs:
                    SIG = sig
                    try:
                        BUS = open(os.path.join(RUN, "bus")).read().strip()
                    except OSError:
                        BUS = ""
                    wl = ""
                    try:
                        for name in os.listdir(RT):
                            if name.startswith("wayland-"):
                                wl = name
                                break
                    except OSError:
                        pass
                    NESTED_ENV = os.environ.copy()
                    NESTED_ENV.update({
                        "XDG_RUNTIME_DIR": RT,
                        "HYPRLAND_INSTANCE_SIGNATURE": SIG,
                        "WAYLAND_DISPLAY": wl,
                    })
                    MESH_ENV = os.environ.copy()
                    MESH_ENV.update({
                        "HOME": os.path.join(RUN, "home"),
                        "XDG_CONFIG_HOME": os.path.join(RUN, "config"),
                        "XDG_CACHE_HOME": os.path.join(RUN, "home", ".cache"),
                        "XDG_STATE_HOME": os.path.join(RUN, "state"),
                        "XDG_DATA_HOME": os.path.join(RUN, "data"),
                        "XDG_RUNTIME_DIR": RT,
                        "DBUS_SESSION_BUS_ADDRESS": BUS,
                    })
                    return
        time.sleep(0.3)
    raise RuntimeError("nested session did not come up")


def main():
    global STARTED, HOST_ENV
    HOST_ENV = os.environ.copy()
    HOST_ENV["XDG_RUNTIME_DIR"] = HOST_XDG
    HOST_ENV["WAYLAND_DISPLAY"] = HOST_WL

    log("Phase 10A measure-only; nested-only numbers; no product changes")
    log("start %s" % datetime.now().isoformat(timespec="seconds"))
    log("live reference: PID %d (read-only /proc)" % LIVE_QS)
    stale_hubs = project_hubs()
    if stale_hubs:
        for pid, project in stale_hubs:
            log("REFUSING: stale Settings hub pid=%d (%s); stop it before measuring" % (pid, project))
        return 2
    if os.path.exists(os.path.join(RUN, "pids")):
        log("REFUSING: .run/pids exists; a session may already be running")
        return 2
    before = run([os.path.join(MEI, "mei"), "verify-untouched"], HOST_ENV, timeout=120)
    log("verify-untouched BEFORE: %s" % before.stdout.strip().splitlines()[-1])
    if before.returncode != 0:
        return 2

    r = run([os.path.join(MEI, "mei"), "run"], HOST_ENV, timeout=90)
    if r.returncode != 0:
        log("FAIL ./mei run rc=%s\n%s\n%s" % (r.returncode, r.stdout, r.stderr))
        return 2
    STARTED = True
    wait_session()
    ready = classify(strict=True)
    log("nested ready: sig=%s shell=%s daemon=%s ryogami=%s" % (
        SIG, ready.get("qs"), ready.get("mei-shell"), ready.get("ryogami")))
    if "hub-qs" in ready:
        log("REFUSING: a Settings hub is already open before the idle measurement")
        return 2

    log("idle wait: %d s" % IDLE_SECONDS)
    time.sleep(IDLE_SECONDS)
    parents = classify(strict=True)
    kids = child_rows(parents)
    log("")
    log("=== idle child processes (direct children of Mei processes) ===")
    if not kids:
        log("none")
    for row in kids:
        log("| parent=%s pid=%s comm=%s rss_kB=%s | %s |" % (
            row["parent"], row["pid"], row["comm"], fmt(row["rss_kb"]), row["cmdline"]))
    DATA["idle_children"] = kids

    measure("idle", "after 120 s idle, no surfaced opened")
    dispatch_global("launcher")
    log("layers after launcher: %s" % layer_namespaces())
    measure("launcher", "launcher surface open")
    dispatch_global("launcher")
    time.sleep(2)

    dispatch_global("quicksettings")
    log("layers after quick settings: %s" % layer_namespaces())
    measure("quick-settings", "quick settings surface open")
    dispatch_global("quicksettings")
    time.sleep(2)

    r = run([os.path.join(RUN, "bin", "mei-shell"), "hub", "open"], MESH_ENV, timeout=45)
    log("hub open rc=%s %s" % (r.returncode, (r.stdout + r.stderr).strip()))
    hub_ready = wait_hub_ready()
    log("Settings hub QML ready: %s" % ("yes" if hub_ready else "NO (measured as-is)"))
    log("layers after Settings hub: %s" % layer_namespaces())
    measure("settings-hub", "Settings hub open via mei-shell hub open")
    r = run([os.path.join(RUN, "bin", "mei-shell"), "hub", "close"], MESH_ENV, timeout=30)
    log("hub close rc=%s %s" % (r.returncode, (r.stdout + r.stderr).strip()))
    for _ in range(30):
        if "hub-qs" not in classify(strict=True):
            break
        time.sleep(0.5)
    log("Settings hub closed: %s" % ("yes" if "hub-qs" not in classify(strict=True) else "NO"))
    time.sleep(2)

    r = run([os.path.join(MEI, "mei"), "wallpaper", WALL], HOST_ENV, timeout=120)
    log("wallpaper set rc=%s %s" % (r.returncode, (r.stdout + r.stderr).strip()))
    time.sleep(3)
    measure("wallpaper", "one still wallpaper set via ./mei wallpaper")

    with open(JSON_PATH, "w", encoding="utf-8") as fh:
        json.dump(DATA, fh, indent=2)
    log("json: %s" % JSON_PATH)
    log("log:  %s" % LOG_PATH)
    return 0


if __name__ == "__main__":
    rc = 3
    try:
        rc = main()
    finally:
        if STARTED:
            r = run([os.path.join(MEI, "mei"), "stop"], HOST_ENV, timeout=60)
            log("nested stop rc=%s" % r.returncode)
        if HOST_ENV:
            after = run([os.path.join(MEI, "mei"), "verify-untouched"], HOST_ENV, timeout=120)
            log("verify-untouched AFTER: %s" % after.stdout.strip().splitlines()[-1])
    sys.exit(rc)
