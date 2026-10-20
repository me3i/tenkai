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
    property int dimSteps: 0
    property int screensaverInhibits: 0
    property string lastAction: ""

    // The config, re-read when it changes.
    FileView {
        id: cfgFile
        path: root.cfgDir + "/idle.json"
        watchChanges: true
        printErrors: false
        atomicWrites: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text);
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
        enabled: root.cfg.enabled === true
        respectInhibitors: true
        timeout: 1000
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

    // The inhibit the shell holds while an app asked through the D-Bus
    // interface to keep the machine awake. It needs a window to hang on, so a
    // one pixel transparent surface carries it.
    PanelWindow {
        id: inhWindow
        visible: root.screensaverInhibits > 0
        width: 1
        height: 1
        color: "transparent"
        anchors { top: true; left: true }
    }
    IdleInhibitor {
        id: inh
        enabled: root.screensaverInhibits > 0
        window: inhWindow
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

    function second() {
        if (root.cfg.enabled !== true)
            return;
        if (!mon.isIdle) {
            root.idleSeconds = 0;
            root.undim();
            root.wake();
            return;
        }
        root.idleSeconds++;
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

    // dim steps the panel down to the configured level and remembers how many
    // steps it took, so the restore puts it back exactly where it was.
    function dim() {
        if (root.dimmed)
            return;
        const pct = Math.round((OsdFeed.brightness || 0) * 100);
        const target = root.cfg.dimPercent || 40;
        const steps = Math.ceil((pct - target) / 5);
        if (steps <= 0) {
            root.dimmed = true;
            return;
        }
        for (let i = 0; i < steps; i++)
            root.command("brightness down");
        root.dimSteps = steps;
        root.dimmed = true;
        root.lastAction = "dim " + steps + " steps";
    }

    function undim() {
        if (!root.dimmed)
            return;
        for (let i = 0; i < root.dimSteps; i++)
            root.command("brightness up");
        root.dimSteps = 0;
        root.dimmed = false;
        root.lastAction = "restore";
    }

    function lockNow() {
        if (root.locked)
            return;
        root.locked = true;
        root.lastAction = "lock";
        Lock.lock();
    }

    function dpmsOff() {
        root.lastAction = "dpms off";
        root.call("wm.act", { "action": "output.power", "args": ["off"] });
    }

    function wake() {
        root.call("wm.act", { "action": "output.power", "args": ["on"] });
    }

    function suspend() {
        root.lastAction = "suspend";
        root.call("session.suspend", {});
    }
}
