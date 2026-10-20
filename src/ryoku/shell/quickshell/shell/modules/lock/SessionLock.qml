pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import shell.services

// Mei's session lock: the compositor's own lock (ext-session-lock-v1).
//
// The compositor locks the session itself: while it is up, no other client
// can draw over it, no key press reaches a window and the compositor's own
// keybinds do nothing. The password is still Mei's own: the daemon checks it
// against PAM, and the lock does not engage at all when that check cannot
// pass.
//
// A crash of the shell leaves the session locked rather than open. The
// recovery steps are in docs/LIVE-CHECKLIST.md.
//
// The lock object is wrapped in an Item on purpose: the lock's own default
// property is its surface, so anything else declared inside it would be taken
// for the surface and the lock would refuse to engage.
Item {
    id: root

    WlSessionLock {
        id: proto

        // The lock follows the shell's own state: the daemon's readiness check
        // has to pass before it engages.
        //
        // The property is set imperatively and not through a binding: the
        // compositor writes the lock state into it as well, and that write
        // breaks a binding, so the shell's state would never reach the
        // compositor.
        locked: false

        // The protocol wants a surface for every output. The component is
        // instantiated once for each of them, and the root of the component
        // has to be the session lock surface itself.
        surface: Component {
            WlSessionLockSurface {
                color: "#0b0b0f"
                LockScreen {}
            }
        }

        // The compositor's answer, so the shell and the tests can see it.
        //
        // The report is sent a tick later on purpose: the compositor is still
        // building the lock surface while it tells the shell about the lock,
        // and the shell must not talk to the daemon in the middle of that.
        function report() {
            Qt.callLater(function() {
                Lock.reportProtocol(proto.locked, proto.secure);
            });
        }

        onLockStateChanged: report()
        onSecureStateChanged: report()

        Component.onCompleted: {
            // The shell's state may already be "locked" when the object is
            // built.
            proto.locked = Lock.locked;
            // The compositor confirms the lock a moment after the request, so
            // the first report is sent again shortly.
            report();
        }
    }

    // The shell's state goes into the compositor, and releasing the lock goes
    // through the protocol's own way out, so the compositor is told the
    // session may be used again.
    Connections {
        target: Lock
        function onLockedChanged() {
            proto.locked = Lock.locked;
        }
        function onUnlocked() {
            proto.locked = false;
            proto.unlock();
        }
    }
}
