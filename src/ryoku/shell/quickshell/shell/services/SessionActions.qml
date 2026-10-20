pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Fires the session power actions the confirmation dialog confirms. The daemon
// (session.go) runs the documented systemctl command; QML never spawns systemctl
// itself, keeping the shell's state-in-daemon / render-in-QML split. Calls are
// fire-and-forget: reboot and shutdown tear the session down, so no reply is
// awaited. Contract 13 sec 8.
Singleton {
    id: root

    readonly property string sockPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/mei-shell.sock"

    // Mei test-mode stub (AGENTS.md rule 7): the nested test session exports
    // MEI_TEST=1, and every power path routes through here, so nothing executes --
    // it only logs. session.go keeps the same guard as defence in depth.
    readonly property bool testMode: Quickshell.env("MEI_TEST") === "1"

    // A live run is not a test run: the power actions are real there, because
    // MEI_TEST is deliberately not set. The first live trial still keeps
    // shutdown stubbed, so a stray confirmation cannot power the machine off.
    readonly property bool shutdownStubbed: Quickshell.env("MEI_STUB_SHUTDOWN") === "1"

    // action is one of "logout" | "reboot" | "shutdown"; the daemon validates it.
    function run(action) {
        if (testMode) {
            console.log("[mei-stub] suppressed session." + action + " (MEI_TEST=1)");
            return;
        }
        if (action === "shutdown" && root.shutdownStubbed) {
            console.log("[mei-stub] suppressed session.shutdown (MEI_STUB_SHUTDOWN=1)");
            return;
        }
        ctl.queued += "call session." + action + " {}\n";
        if (ctl.connected)
            ctl.flushQueued();
        else
            ctl.connected = true;
    }

    // Lock runs the shell's own lock verb (mei-shell lock), never the daemon.
    function lock() {
        if (testMode) {
            console.log("[mei-stub] suppressed lock (MEI_TEST=1)");
            return;
        }
        Quickshell.execDetached(["mei-shell", "lock"]);
    }

    Socket {
        id: ctl
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
}
