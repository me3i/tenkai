pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The lock: its state and the password check.
//
// The state lives here so the surface only renders; the daemon does the PAM
// check. The password is written to the control socket on a line of its own,
// so it never reaches a command line (and thus a world-readable
// /proc/<pid>/cmdline) and is never logged.
Singleton {
    id: root

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mei-shell.sock"

    // locked is the whole state: while it is true, the other surfaces refuse
    // to open and the lock surface covers the screen.
    property bool locked: false
    property string error: ""
    property bool busy: false

    function lock() {
        root.error = "";
        root.locked = true;
    }

    function unlock() {
        root.locked = false;
        root.error = "";
    }

    // verify asks the daemon to check the password against PAM.
    function verify(password) {
        if (root.busy || password === "")
            return;
        root.busy = true;
        root.error = "";
        sock.queued = "lock-verify\n" + password + "\n";
        if (sock.connected)
            sock.flushQueued();
        else
            sock.connected = true;
    }

    Socket {
        id: sock
        path: root.sockPath
        property string queued: ""

        function flushQueued() {
            if (queued.length === 0)
                return;
            write(queued);
            flush();
            queued = "";
        }

        parser: SplitParser {
            onRead: line => {
                const t = (line || "").trim();
                if (t === "")
                    return;
                let reply = null;
                try {
                    reply = JSON.parse(t);
                } catch (e) {
                    reply = null;
                }
                root.busy = false;
                if (reply && reply.ok) {
                    root.locked = false;
                    root.error = "";
                } else {
                    root.error = (reply && reply.reason) ? reply.reason
                        : "the password was refused";
                }
            }
        }

        onConnectionStateChanged: if (connected) flushQueued()
    }
}
