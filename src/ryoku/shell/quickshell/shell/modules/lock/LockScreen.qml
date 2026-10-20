pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import shell.services

// Mei's lock screen: the content of the compositor's session lock.
//
// The lock itself belongs to the compositor (ext-session-lock-v1): it covers
// every output and nothing else can be drawn over it, so a crash of the shell
// leaves the session locked instead of open. This file is only what the user
// sees on top of it.
//
// The clock is the "orbital" dial from Ryoku's clockwork lockscreen theme
// (OrbitalClock.qml, adapted from upstream). The password field is Mei's own:
// the daemon checks it against PAM. The lock does not engage at all when that
// check cannot pass, because a lock that cannot be opened is a way to lose
// the session.
//
// The compositor gives the surface the keyboard, so while it is up the key
// presses cannot reach anything else.
Item {
    id: win

    // The surface around this content is the compositor's session lock
    // surface; it fills the output.
    anchors.fill: parent

    // The dial, and with it the time and the date.
    OrbitalClock {
        anchors.fill: parent
    }

    // The prompt, on the free right-hand side of the dial.
    Column {
        anchors.right: parent.right
        anchors.rightMargin: 90 * (win.height / 768)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16
        width: Math.min(420, win.width * 0.32)

        TextField {
            id: pw
            width: parent.width
            placeholderText: "Password"
            echoMode: TextInput.Password
            color: "#f2f2f5"
            placeholderTextColor: "#6a6a74"
            selectByMouse: true
            activeFocusOnTab: true
            // The field holds the focus as soon as the surface is mapped, so a
            // keypress cannot land somewhere else while the lock is up.
            focus: true
            onAccepted: win.tryUnlock()
            // The theme's own shape: a dark pill with a thin border.
            background: Rectangle {
                radius: height / 2
                color: "#080808"
                border.color: "#222222"
                border.width: 1
            }
        }

        Text {
            text: Lock.error
            color: "#e06a6a"
            font.pixelSize: 14
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
            visible: text !== ""
        }

        Button {
            text: "Unlock"
            enabled: pw.text !== "" && !Lock.busy
            onClicked: win.tryUnlock()
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // The password field holds the focus for as long as the lock is up: the
    // shell's own surfaces may ask for it, and a key press that lands
    // somewhere else is a key press the owner cannot see.
    Timer {
        interval: 2000
        repeat: true
        running: true
        onTriggered: if (pw.activeFocus === false)
            pw.forceActiveFocus()
    }

    Component.onCompleted: {
        pw.text = "";
        // A surface that has only just been mapped cannot hold the item focus
        // yet, so the field is focused again on the next tick.
        Qt.callLater(function() {
            pw.forceActiveFocus();
        });
    }

    function tryUnlock() {
        if (Lock.busy || pw.text === "")
            return;
        Lock.verify(pw.text);
        // The field is cleared whatever the answer: a wrong password is not
        // left on screen.
        pw.text = "";
        pw.forceActiveFocus();
    }
}
