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
// sees on top of it: a clock, the date and the password field.
//
// The password is Mei's own: the daemon checks it against PAM. The lock does
// not engage at all when that check cannot pass, because a lock that cannot
// be opened is a way to lose the session.
//
// The compositor gives the surface the keyboard, so while it is up the key
// presses cannot reach anything else.
Item {
    id: win

    // The surface around this content is the compositor's session lock
    // surface; it fills the output.
    anchors.fill: parent

    // The clock: a big time and the date, so the screen reads as a lock screen
    // and not as an error.
    property string clockText: ""
    property string dateText: ""

    Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: win.updateClock()
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

    function updateClock() {
        const now = new Date();
        const hh = String(now.getHours()).padStart(2, "0");
        const mm = String(now.getMinutes()).padStart(2, "0");
        win.clockText = hh + ":" + mm;
        const days = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"];
        const months = ["January", "February", "March", "April", "May", "June", "July",
            "August", "September", "October", "November", "December"];
        win.dateText = days[now.getDay()] + ", " + months[now.getMonth()] + " " + now.getDate();
    }

    Component.onCompleted: {
        win.updateClock();
        pw.text = "";
        // A surface that has only just been mapped cannot hold the item focus
        // yet, so the field is focused again on the next tick.
        Qt.callLater(function() {
            pw.forceActiveFocus();
        });
    }

    Column {
        anchors.centerIn: parent
        spacing: 18
        width: Math.min(420, win.width - 80)

        Text {
            text: win.clockText
            color: "#f2f2f5"
            font.pixelSize: 76
            font.weight: Font.Light
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }
        Text {
            text: win.dateText
            color: "#9a9aa4"
            font.pixelSize: 17
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }

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
