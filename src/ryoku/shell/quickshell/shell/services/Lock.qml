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

    // What the lock is waiting for: "selfcheck", "verify", or nothing. The
    // daemon answers on the same socket for other commands too (the protocol
    // report, for one), and an answer the lock did not ask for must not be
    // read as a refused password.
    property string waiting: ""

    // The compositor's own lock state (ext-session-lock-v1): whether the
    // session is locked, and whether the compositor calls the lock secure.
    // They are the compositor's answer, not Mei's wish.
    property bool protocolLocked: false
    property bool protocolSecure: false

    // Emitted when the shell releases the lock, so the protocol object can
    // tell the compositor the session may be used again.
    signal unlocked

    // reportProtocol tells the daemon what the compositor answered, so the
    // state of the session lock can be read without looking at a screen.
    function reportProtocol(isLocked, isSecure) {
        root.protocolLocked = isLocked === true;
        root.protocolSecure = isSecure === true;
        send("lock-protocol " + (root.protocolLocked ? "active" : "released")
            + " " + (root.protocolSecure ? "secure" : "plain") + "\n");
    }

    // lock asks the daemon first whether the PAM setup can be used at all. If
    // it cannot, the lock does NOT engage: a lock that cannot be opened would
    // be a way to lose the session, so a broken setup shows a notification
    // instead.
    function lock() {
        if (root.locked || root.busy)
            return;
        root.error = "";
        root.busy = true;
        root.waiting = "selfcheck";
        send("lock-selfcheck\n");
    }

    function unlock() {
        root.locked = false;
        root.error = "";
        root.unlocked();
    }

    // verify asks the daemon to check the password against PAM.
    function verify(password) {
        if (root.busy || password === "")
            return;
        root.busy = true;
        root.error = "";
        root.waiting = "verify";
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
                if (root.waiting === "") {
                    // An answer nobody asked for: the daemon's own commands
                    // (the protocol report) come back on this socket too.
                    return;
                }
                const asked = root.waiting;
                root.waiting = "";
                if (asked === "selfcheck" && reply && reply.selfcheck) {
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
                if (asked === "verify" && reply && reply.ok) {
                    root.locked = false;
                    root.error = "";
                } else if (asked === "verify") {
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
