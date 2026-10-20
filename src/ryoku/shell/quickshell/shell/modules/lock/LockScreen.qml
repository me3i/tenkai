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

    // The input, where the greeter puts it: a column at the bottom right, with
    // the password's stars, the needle cursor that pulses, the hint that fades
    // when you type, and the UNLOCK label. (Upstream's own panel, without the
    // greeter's user name and fingerprint hint.)
    Column {
        id: loginPanel
        anchors.right: parent.right
        anchors.rightMargin: 80 * (win.height / 768)
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 80 * (win.height / 768)
        width: 350 * (win.height / 768)
        spacing: 8 * (win.height / 768)

        Text {
            id: errText
            width: parent.width
            height: 15 * (win.height / 768)
            verticalAlignment: Text.AlignBottom
            horizontalAlignment: Text.AlignRight
            text: Lock.error
            color: "#ff4444"
            font.pixelSize: 10 * (win.height / 768)
            font.letterSpacing: 2 * (win.height / 768)
            visible: text !== ""
        }

        Item {
            width: parent.width
            height: 30 * (win.height / 768)

            TextInput {
                id: pw
                anchors.fill: parent
                echoMode: TextInput.Password
                passwordCharacter: "\u2726"
                color: "#666666"
                font.pixelSize: 14 * (win.height / 768)
                font.letterSpacing: 10 * (win.height / 768)
                horizontalAlignment: TextInput.AlignRight
                verticalAlignment: TextInput.AlignVCenter
                focus: true
                cursorVisible: false
                onAccepted: win.tryUnlock()

                // The hint, fading out once there is something to type over.
                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "TYPE YOUR PASSWORD"
                    font.pixelSize: 10 * (win.height / 768)
                    font.letterSpacing: 4 * (win.height / 768)
                    color: "#333333"
                    opacity: pw.text.length === 0 ? 0.55 : 0
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 400
                            easing.type: Easing.InOutSine
                        }
                    }
                }

                // The needle cursor: a thin line that pulses while the lock is
                // up.
                Rectangle {
                    id: needleCursor
                    width: 1.5 * (win.height / 768)
                    height: 12 * (win.height / 768)
                    color: "#ffffff"
                    anchors.verticalCenter: parent.verticalCenter
                    x: pw.cursorRectangle.x
                    visible: pw.focus && pw.text.length > 0
                    SequentialAnimation {
                        loops: Animation.Infinite
                        running: needleCursor.visible
                        NumberAnimation {
                            target: needleCursor
                            property: "opacity"
                            from: 1
                            to: 0.1
                            duration: 450
                        }
                        NumberAnimation {
                            target: needleCursor
                            property: "opacity"
                            from: 0.1
                            to: 1
                            duration: 450
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: 40 * (win.height / 768)

            Text {
                id: loginBtn
                anchors.right: parent.right
                anchors.rightMargin: btnMa.containsMouse ? 25 * (win.height / 768) : 0
                anchors.verticalCenter: parent.verticalCenter
                text: pw.text.length > 0 ? "UNLOCK" : "TYPE YOUR PASSWORD"
                font.pixelSize: 11 * (win.height / 768)
                font.letterSpacing: 4 * (win.height / 768)
                font.weight: Font.Bold
                color: btnMa.containsMouse ? "#ffffff" : "#666666"
                Behavior on color {
                    ColorAnimation {
                        duration: 200
                    }
                }
                Behavior on anchors.rightMargin {
                    NumberAnimation {
                        duration: 250
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Text {
                anchors.left: loginBtn.right
                anchors.leftMargin: 8 * (win.height / 768)
                anchors.verticalCenter: parent.verticalCenter
                text: "\u2726"
                font.pixelSize: 10 * (win.height / 768)
                color: "#ffffff"
                opacity: btnMa.containsMouse ? 1.0 : 0
                Behavior on opacity {
                    NumberAnimation {
                        duration: 200
                    }
                }
            }
            MouseArea {
                id: btnMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.tryUnlock()
            }
        }
    }

    // The password field holds the focus for as long as the lock is up: the
    // shell's own surfaces may ask for it, and a key press that lands
    // somewhere else is a key press the owner cannot see. The compositor gives
    // the keyboard to the lock's surface, but the field inside it has to be
    // given the focus again, and it is checked often enough that a key press
    // right after the lock appears is never lost.
    Timer {
        interval: 500
        repeat: true
        running: true
        onTriggered: if (pw.activeFocus === false)
            pw.forceActiveFocus()
    }

    // The lock engaging is the moment the field has to be ready.
    Connections {
        target: Lock
        function onLockedChanged() {
            if (Lock.locked)
                Qt.callLater(function() {
                    pw.forceActiveFocus();
                });
        }
    }

    Component.onCompleted: {
        pw.text = "";
        // A surface that has only just been mapped cannot hold the item focus
        // yet, so the field is focused again on the next tick.
        Qt.callLater(function() {
            pw.forceActiveFocus();
        });
    }

    // The compositor shows the surface a moment after it is created, and the
    // focus is only good once it is really on the screen. Without this the
    // first keys after the lock appears could land nowhere.
    onVisibleChanged: if (visible)
        Qt.callLater(function() {
            pw.forceActiveFocus();
        });

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
