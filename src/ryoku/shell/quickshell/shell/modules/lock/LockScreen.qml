pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import shell.services

// Mei's lock screen: a full-screen cover with a clock and a password field.
//
// It is the shell's own lock, not the compositor's session lock: it covers
// Mei's surfaces and asks for the account password, which the daemon checks
// against PAM. Nothing here can lock the session itself, so a mistake in this
// file can never lock the owner out of their machine.
//
// While it is up the keyboard is exclusive, so the bar and the launcher under
// it cannot be reached.
PanelWindow {
    id: win

    required property var screen

    color: "#0b0b0f"
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "ryoku-lock"
    WlrLayershell.keyboardFocus: Lock.locked ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    visible: Lock.locked

    // The clock: a big time and the date, so the screen reads as a lock screen
    // and not as an error.
    property string clockText: ""
    property string dateText: ""

    Timer {
        interval: 1000
        repeat: true
        running: win.visible
        onTriggered: win.updateClock()
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

    Component.onCompleted: win.updateClock()
    onVisibleChanged: if (visible) {
        win.updateClock();
        pw.text = "";
        win.focus = true;
        pw.forceActiveFocus();
        // A window that has only just been mapped cannot hold the item focus
        // yet, so the field is focused again on the next tick.
        Qt.callLater(function() {
            win.focus = true;
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
            // The field holds the focus as soon as the window is mapped, so a
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
