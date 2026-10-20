pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window

// Mei's lock screen clock: the "orbital" dial from Ryoku's clockwork
// lockscreen theme.
//
// Upstream: ryoku/lockscreen/qylock/themes/clockwork/orbital/Main.qml
// (Ryoku, GPL-3.0-or-later, the theme by Darkkal44). The dial, the two
// rings of ticks, the spotlight that follows the minute and the second, the
// big hour numeral and the date are kept as they are.
//
// What was dropped, and why:
// - the greeter's own parts (the SDDM components, the user and session
//   models, the fingerprint hint, the reveal and the windup): a session lock
//   is not a greeter, and those are not on Mei's keep list;
// - the bundled Outfit font: the theme ships it without a licence file, so
//   it is not bundled here (the system's own font is used instead);
// - the sparks: they belong to the greeter's reveal.
//
// The clock only runs while the lock is up: this component exists exactly as
// long as the lock's surface does, and the surface exists exactly as long as
// the session is locked.
Item {
    id: root

    // The theme's scale: everything is measured against a 768 point high
    // screen.
    readonly property real s: Screen.height / 768
    readonly property bool isLight: false

    // The theme's colours.
    readonly property color mainText: isLight ? "#000000" : "#ffffff"
    readonly property color subColor: isLight ? "#666666" : "#555555"
    readonly property color pillColor: isLight ? "#e8e8e8" : "#080808"
    readonly property color pillBorder: isLight ? "#cccccc" : "#1a1a1a"
    readonly property color pillInnerLine: isLight ? "#bbbbbb" : "#222222"

    // The time, and the smooth angles the spotlight follows.
    property int curH: new Date().getHours()
    property int curM: new Date().getMinutes()
    property int curS: new Date().getSeconds()
    property int curMS: new Date().getMilliseconds()
    readonly property real localTimeMS: (curH * 3600000) + (curM * 60000) + (curS * 1000) + curMS
    readonly property real smoothSecAngle: -((localTimeMS % 60000) / 60000.0) * 360.0
    readonly property real smoothMinAngle: -((localTimeMS % 3600000) / 3600000.0) * 360.0

    // The clock only wakes while it is on screen. This component lives as long
    // as the lock's surface does, so the timer stops with the lock.
    Timer {
        interval: 16
        running: true
        repeat: true
        onTriggered: {
            const d = new Date();
            root.curH = d.getHours();
            root.curM = d.getMinutes();
            root.curS = d.getSeconds();
            root.curMS = d.getMilliseconds();
        }
    }

    Item {
        id: clockContainer
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 800 * root.s
        height: parent.height
        readonly property real cx: 40 * root.s
        readonly property real cy: height * 0.5
        readonly property real minR: 320 * root.s
        readonly property real secR: 480 * root.s

        // The pill the hour numeral sits next to.
        Rectangle {
            id: indicatorPill
            z: 1
            x: clockContainer.cx + 230 * root.s
            anchors.verticalCenter: parent.verticalCenter
            width: 330 * root.s
            height: 90 * root.s
            radius: 45 * root.s
            color: root.pillColor
            border.color: root.pillBorder
            border.width: 1 * root.s
            Rectangle {
                x: 170 * root.s
                anchors.verticalCenter: parent.verticalCenter
                width: 1 * root.s
                height: 35 * root.s
                color: root.pillInnerLine
            }
        }

        // The minute ring: 60 ticks and the numbers every five minutes.
        Repeater {
            model: 60
            delegate: Item {
                z: 10
                property real base: index * 6
                property real relAngle: {
                    var a = (base + root.smoothMinAngle) % 360;
                    if (a > 180)
                        a -= 360;
                    if (a < -180)
                        a += 360;
                    return a;
                }
                property real spotlight: Math.max(0, 1.0 - Math.abs(relAngle) / 4.0)
                property bool isMajor: index % 5 == 0
                property real disp: (base + root.smoothMinAngle) * Math.PI / 180
                property real tx: clockContainer.cx + clockContainer.minR * Math.cos(disp)
                property real ty: clockContainer.cy + clockContainer.minR * Math.sin(disp)
                visible: tx > -600 * root.s && tx < 1800 * root.s
                Rectangle {
                    x: parent.tx - width / 2
                    y: parent.ty - height / 2
                    width: parent.isMajor ? 2 * root.s : 1 * root.s
                    height: parent.isMajor ? 18 * root.s : 10 * root.s
                    color: Qt.rgba(1, 1, 1, parent.spotlight > 0 ? 1.0 : (parent.isMajor ? 0.3 : 0.15))
                    rotation: parent.disp * 180 / Math.PI + 90
                }
                Text {
                    visible: parent.isMajor
                    property real nRad: clockContainer.minR - 35 * root.s
                    x: clockContainer.cx + nRad * Math.cos(parent.disp) - width / 2
                    y: clockContainer.cy + nRad * Math.sin(parent.disp) - height / 2
                    text: String(index).padStart(2, "0")
                    font.pixelSize: 22 * root.s
                    font.weight: parent.spotlight > 0.5 ? Font.Bold : Font.Normal
                    color: Qt.rgba(1, 1, 1, parent.spotlight > 0 ? (0.4 + parent.spotlight * 0.6) : 0.25)
                    rotation: parent.disp * 180 / Math.PI
                    transformOrigin: Item.Center
                }
            }
        }

        // The second ring: the same 60 ticks, a little further out.
        Repeater {
            model: 60
            delegate: Item {
                z: 10
                property real base: index * 6
                property real relAngle: {
                    var a = (base + root.smoothSecAngle) % 360;
                    if (a > 180)
                        a -= 360;
                    if (a < -180)
                        a += 360;
                    return a;
                }
                property real spotlight: Math.max(0, 1.0 - Math.abs(relAngle) / 4.0)
                property bool isMajor: index % 5 == 0
                property real disp: (base + root.smoothSecAngle) * Math.PI / 180
                property real tx: clockContainer.cx + clockContainer.secR * Math.cos(disp)
                property real ty: clockContainer.cy + clockContainer.secR * Math.sin(disp)
                visible: tx > -600 * root.s && tx < 1800 * root.s
                Rectangle {
                    x: parent.tx - width / 2
                    y: parent.ty - height / 2
                    width: parent.isMajor ? 1.5 * root.s : 1 * root.s
                    height: parent.isMajor ? 13 * root.s : 8 * root.s
                    color: Qt.rgba(1, 1, 1, parent.spotlight > 0 ? 1.0 : (parent.isMajor ? 0.3 : 0.15))
                    rotation: parent.disp * 180 / Math.PI + 90
                }
                Text {
                    visible: parent.isMajor
                    property real nRad: clockContainer.secR - 30 * root.s
                    x: clockContainer.cx + nRad * Math.cos(parent.disp) - width / 2
                    y: clockContainer.cy + nRad * Math.sin(parent.disp) - height / 2
                    text: String(index).padStart(2, "0")
                    font.pixelSize: 16 * root.s
                    font.weight: parent.spotlight > 0.5 ? Font.Bold : Font.Normal
                    color: Qt.rgba(1, 1, 1, parent.spotlight > 0 ? (0.4 + parent.spotlight * 0.6) : 0.25)
                    rotation: parent.disp * 180 / Math.PI
                    transformOrigin: Item.Center
                }
            }
        }

        // The hour, and the date next to it.
        Text {
            anchors.right: indicatorPill.left
            anchors.rightMargin: 40 * root.s
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.curH).padStart(2, "0")
            font.pixelSize: 110 * root.s
            font.weight: Font.Black
            color: root.mainText
        }
        Column {
            anchors.left: indicatorPill.right
            anchors.leftMargin: 110 * root.s
            anchors.verticalCenter: parent.verticalCenter
            spacing: 5 * root.s
            Text {
                text: Qt.formatDate(new Date(), "dd MMM yyyy").toUpperCase()
                font.pixelSize: 13 * root.s
                font.letterSpacing: 4 * root.s
                color: root.subColor
            }
            Text {
                text: Qt.formatDate(new Date(), "dddd").toUpperCase()
                font.pixelSize: 18 * root.s
                font.letterSpacing: 8 * root.s
                font.weight: Font.Bold
                color: root.mainText
            }
        }
    }
}
