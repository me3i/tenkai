#!/usr/bin/env python3
"""Own the two shell D-Bus names on the private nested bus, then wait.

Test-only stand-in for the Phase 8 handover test: it plays the role of the old
shell (or a tray host) that is about to be replaced by Tenkai. It never touches the
live bus -- the caller hands it the nested bus address.

Prints "owned <name>" per name, then "READY" once both are held. SIGTERM/SIGINT
release them and exit 0.
"""
import signal
import sys

import gi

gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NAMES = ["org.freedesktop.Notifications", "org.kde.StatusNotifierWatcher"]

conn = Gio.bus_get_sync(Gio.BusType.SESSION, None)
loop = GLib.MainLoop()
held = set()


def on_acquired(_conn, name, _data=None):
    held.add(name)
    print("owned %s" % name, flush=True)
    if len(held) == len(NAMES):
        print("READY", flush=True)


def on_lost(_conn, name, _data=None):
    print("lost %s" % name, flush=True)


for n in NAMES:
    Gio.bus_own_name_on_connection(
        conn, n, Gio.BusNameOwnerFlags.NONE, on_acquired, on_lost
    )


def quit_loop(*_args):
    loop.quit()
    return True


for sig in (signal.SIGTERM, signal.SIGINT):
    GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, sig, quit_loop)

loop.run()
conn.close_sync(None)
print("released", flush=True)
sys.exit(0)
