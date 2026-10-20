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

    // lock asks the daemon first whether the PAM setup can be used at all. If
    // it cannot, the lock does NOT engage: a lock that cannot be opened would
    // be a way to lose the session, so a broken setup shows a notification
    // instead.
    function lock() {
        if (root.locked || root.busy)
            return;
        root.error = "";
        root.busy = true;
        send("lock-selfcheck\n");
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
        send("lock-verify\n" + password + "\n");
    }

    // The daemon closes the connection after every command, so a request must
    // go out on a FRESH connection: writing into a socket the daemon has
    // already closed is silently lost, and the lock would look like a
    // password that never arrived.
    function send(line) {
        sock.queued = line;
        sock.connected = false;
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
                if (reply && reply.selfcheck) {
                    // The readiness answer: lock only if the setup works.
                    if (reply.ok) {
                        root.locked = true;
                        root.error = "";
                    } else {
                        root.locked = false;
                        root.error = (reply && reply.reason) ? reply.reason
                            : "the PAM setup is not usable";
                        Quickshell.execDetached([
                            "notify-send", "-a", "Mei",
                            "The lock is not available: " + root.error
                        ]);
                    }
                    return;
                }
                if (reply && reply.ok) {
                    root.locked = false;
                    root.error = "";
                } else {
                    root.error = (reply && reply.reason) ? reply.reason
                        : "the password was refused";
                }
            }
        }

        // The daemon closes the connection after every command. The socket
        // therefore reconnects on demand: the next request sets connected
        // again and the queued line is flushed when the connection is up.
        onConnectionStateChanged: if (connected) flushQueued()
    }
}
