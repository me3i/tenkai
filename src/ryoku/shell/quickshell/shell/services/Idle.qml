pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Mei's idle: dim, lock, DPMS off and suspend, with the inhibitors honoured.
//
// The idle source is the compositor's own idle-notify, so a video player that
// holds an idle-inhibit keeps the desktop awake exactly as it should. The
// ScreenSaver service the daemon offers (for the apps that use the D-Bus
// interface instead) feeds the same inhibitor logic.
//
// The thresholds live in Mei's own config (idle.json), so they are the user's
// to set and not baked into the code. Defaults: dim after 120 s, lock after
// 300 s, DPMS off after 360 s, suspend after 600 s.
Singleton {
    id: root

    readonly property string cfgDir: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/mei"
    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mei-shell.sock"

    property var cfg: ({ "enabled": true, "dim": 120, "lock": 300, "dpms": 360, "suspend": 600, "dimPercent": 40 })

    property int idleSeconds: 0
    property bool dimmed: false
    property int screensaverInhibits: 0
    property string lastAction: ""
    property bool locked: false
    property bool dpmsOff_: false
    property bool suspended: false

    // The config, re-read when it changes.
    FileView {
        id: cfgFile
        path: root.cfgDir + "/idle.json"
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            // FileView.text is a method in this Quickshell, not a property.
            try {
                const d = JSON.parse(text() || "{}");
                for (const k in d)
                    root.cfg[k] = d[k];
            } catch (e) {
            }
        }
    }

    // The compositor's idle state. respectInhibitors keeps the desktop awake
    // while anything holds an idle-inhibit.
    IdleMonitor {
        id: mon
        enabled: root.on
        respectInhibitors: true
        // Quickshell's idle timeout is in SECONDS (measured against the
        // compositor: a timeout of 2 flips the idle state after about two
        // seconds). The module counts the idle seconds itself, so the monitor
        // only has to notice the idle quickly.
        timeout: 1
        onIsIdleChanged: root.idleChanged()
    }

    // The ScreenSaver service the daemon offers (the full live profile only)
    // publishes how many apps asked to hold the idle off.
    Socket {
        id: sub
        path: root.sockPath
        parser: SplitParser {
            onRead: line => {
                try {
                    const f = JSON.parse(line);
                    if (f && typeof f.count === "number")
                        root.screensaverInhibits = f.count;
                } catch (e) {
                }
            }
        }
        Component.onCompleted: connected = true
        onConnectionStateChanged: if (connected) { write("subscribe screensaver\n"); flush(); }
    }

    Timer {
        id: tick
        interval: 1000
        repeat: true
        running: true
        onTriggered: root.second()
    }

    // A registered call: "call <method> <json>".
    function call(method, payload) {
        const s = sock2
        s.queued = "call " + method + " " + JSON.stringify(payload || {}) + "\n";
        if (s.connected)
            s.flushQueued();
        else
            s.connected = true;
    }

    // A bare command, for the verbs that take a word ("brightness down").
    function command(text) {
        const s = sock2
        s.queued = text + "\n";
        if (s.connected)
            s.flushQueued();
        else
            s.connected = true;
    }

    // The daemon closes the connection after every command, so every request
    // goes out on a fresh one.
    Socket {
        id: sock2
        path: root.sockPath
        property string queued: ""
        function flushQueued() {
            if (queued.length === 0)
                return;
            write(queued);
            flush();
            queued = "";
        }
        onConnectionStateChanged: if (connected) flushQueued()
    }

    function idleChanged() {
        if (!mon.isIdle) {
            root.idleSeconds = 0;
            root.undim();
            root.wake();
        }
    }

    readonly property bool on: root.cfg.enabled === true && Config.moduleOn("idle")

    function second() {
        if (!root.on)
            return;
        if (!mon.isIdle) {
            root.idleSeconds = 0;
            root.undim();
            root.wake();
            root.suspended = false;
            return;
        }
        // An app that asked through the D-Bus interface to keep the machine
        // awake (a video, a call) holds the idle off: the idle time does not
        // count, and nothing is dimmed, locked or suspended. When it is
        // released, the idle starts counting again from zero.
        if (root.screensaverInhibits > 0) {
            root.idleSeconds = 0;
            root.checkLockState();
            return;
        }
        root.idleSeconds++;
        root.checkLockState();
        const s = root.idleSeconds;
        if (root.cfg.dim && s >= root.cfg.dim)
            root.dim();
        if (root.cfg.lock && s >= root.cfg.lock)
            root.lockNow();
        if (root.cfg.dpms && s >= root.cfg.dpms)
            root.dpmsOff();
        if (root.cfg.suspend && s >= root.cfg.suspend)
            root.suspend();
    }

    // dim asks the daemon to step the panel down to the configured level. The
    // daemon remembers how many steps it took, so the restore is exact.
    function dim() {
        if (root.dimmed)
            return;
        root.dimmed = true;
        root.lastAction = "dim";
        root.command("brightness.dim " + (root.cfg.dimPercent || 40));
    }

    function undim() {
        if (!root.dimmed)
            return;
        root.dimmed = false;
        root.lastAction = "restore";
        root.command("brightness.restore");
    }

    function lockNow() {
        if (root.locked)
            return;
        root.locked = true;
        root.lastAction = "lock";
        Lock.lock();
    }

    // A lock that was dismissed (the right password) must not stop the next
    // idle from locking again.
    function checkLockState() {
        if (root.locked && !Lock.locked)
            root.locked = false;
    }

    function dpmsOff() {
        if (root.dpmsOff_)
            return;
        root.dpmsOff_ = true;
        root.lastAction = "dpms off";
        root.call("wm.act", { "action": "output.power", "args": ["off"] });
    }

    // The display only wakes if it was put to sleep: an "on" every second
    // would be a dispatcher call per second for nothing.
    function wake() {
        if (!root.dpmsOff_)
            return;
        root.dpmsOff_ = false;
        root.lastAction = "dpms on";
        root.call("wm.act", { "action": "output.power", "args": ["on"] });
    }

    function suspend() {
        if (root.suspended)
            return;
        root.suspended = true;
        root.lastAction = "suspend";
        root.call("session.suspend", {});
    }
}
