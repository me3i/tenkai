import Quickshell
import shell.services
import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G3", root.ink)

    implicitWidth: trayRow.implicitWidth
    implicitHeight: 28
    // MEI: the Repeater is fed from this array, refreshed in onItemsChanged.
    // Binding the model straight at the services singleton resolved to an empty
    // array in the bar instance and never re-fired (measured n=1, row width 0).
    property var trayModel: []
    // MEI: no `visible` gate. Upstream used `visible: trayRow.implicitWidth > 0`,
    // which is circular: the bar collapses an empty slot (width 0, opacity 0),
    // so the row measured 0 even after an item arrived, the widget stayed
    // invisible, and the whole status cluster (tray + bell) stayed collapsed.
    // With no gate the widget is 0-wide while empty and draws as soon as a
    // pinned item exists.

    function toggleHide(item) {
        root.trayToggleHide(item)
    }

    Row {
        id: trayRow
        anchors.centerIn: parent
        spacing: root.v2IconClusterSpacing

        Repeater {
            model: rootMod.trayModel

            delegate: Item {
                id: trayDelegate
                required property var modelData

                // System-tray actions share the bar's compact 24px centre pitch:
                // 22px action cell plus the surrounding Row's 2px cluster gap.
                implicitWidth: root.v2ActionIconCellWidth
                implicitHeight: 28
                // MEI: the model below holds only pinned services (refreshTrayModel),
                // so the cell is always drawn. The old per-delegate binding
                // `root.trayPinned.indexOf(modelData.service) >= 0` evaluated before
                // modelData was readable and never recovered, so a pinned pixmap
                // item stayed unpainted (theme-name items happened to win the race).
                visible: true

                Image {
                    anchors.centerIn: parent
                    source: modelData.iconPath ? "file://" + modelData.iconPath : (modelData.iconName ? Icons.path(modelData.iconName, true) : "")
                    sourceSize.width: 14
                    sourceSize.height: 14
                    width: 14
                    height: 14
                    fillMode: Image.PreserveAspectFit
                    smooth: true
                }

                MouseArea {
                    id: ma
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (e) => {
                        if (e.button === Qt.LeftButton)
                            Tray.activate(modelData.service)
                        else if (e.button === Qt.RightButton) {
                            // MEI: right click opens the item's own menu, the
                            // call the tray panel makes. Upstream toggled
                            // pin/unpin here, which left an item that publishes
                            // a dbusmenu with no way to open it from the bar;
                            // pin/unpin stays available on the panel row.
                            if (modelData.menu != null) {
                                var gp = ma.mapToItem(null, ma.width / 2, 0)
                                root.openTrayMenu(modelData.service, gp.x,
                                                  root.trayDisplayName(modelData),
                                                  modelData.iconPath ? "file://" + modelData.iconPath
                                                                     : (modelData.iconName ? Icons.path(modelData.iconName, true) : ""))
                            } else {
                                rootMod.toggleHide(modelData)
                            }
                        }
                    }
                }
            }
        }

        // ── toggle: more_horiz icon + seal count badge ──
        Item {
            id: toggleBtn
            implicitWidth: root.v2ActionIconCellWidth
            implicitHeight: 28
            visible: hiddenCount > 0

            // count CURRENTLY-EXISTING tray items that are not pinned (= hidden behind this
            // button), iterating Tray.items so stale pinned IDs can't inflate the count
            readonly property int hiddenCount: {
                var n = 0, its = Tray.items
                for (var i = 0; i < its.length; i++) if (root.trayPinned.indexOf(its[i].service) < 0) n++
                return n
            }
            readonly property int totalCount:  Tray.items.length
            readonly property string tooltipText: (totalCount === 1 ? I18n.tr("%1 app").arg(totalCount)
                                                                     : I18n.tr("%1 apps").arg(totalCount))
                                                  + (hiddenCount > 0 ? I18n.tr(" · %1 hidden").arg(hiddenCount) : "")

            TooltipMixin { id: tip; root: rootMod.root; owner: toggleBtn; text: toggleBtn.tooltipText }

            IconText {
                id: moreIcon
                anchors.centerIn: parent
                text: "\uE5D3"   // more_horiz
                font.pixelSize: 16
                color: toggleMa.containsMouse
                    ? rootMod.contentColor
                    : Qt.rgba(rootMod.contentColor.r, rootMod.contentColor.g, rootMod.contentColor.b, 0.7)
                Behavior on color { ColorAnimation { duration: 150 } }
            }

            // count badge - top-right
            Rectangle {
                id: toggleBadge
                visible: toggleBtn.hiddenCount > 0
                width: Math.max(12, toggleBadgeTxt.implicitWidth + 6)
                height: 12
                radius: 6
                color: root.widgetHasFill("G3") ? rootMod.contentColor : root.seal
                anchors.verticalCenter: moreIcon.verticalCenter
                anchors.verticalCenterOffset: -6
                anchors.horizontalCenter: moreIcon.horizontalCenter
                anchors.horizontalCenterOffset: 7
                Text {
                    id: toggleBadgeTxt
                    anchors.centerIn: parent
                    text: toggleBtn.hiddenCount
                    color: root.widgetHasFill("G3") ? root.widgetAssignedColor("G3") : root.paper
                    font.family: root.mono
                    font.pixelSize: 7
                    font.weight: Font.Bold
                }
            }

            MouseArea {
                id: toggleMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: tip.show()
                onExited: { tip.hide() }
                onClicked: { tip.hide(); root.trayVisible = !root.trayVisible }
            }
        }
    }
    // MEI: pin a service the first time it appears, so its icon is drawn
    // without a trip through the panel (Theme.trayAutoPin), then re-measure the
    // anchor once the slot has expanded.
    function refreshTrayModel() {
        var its = Tray.items || []
        var out = []
        for (var i = 0; i < its.length; i++)
            if (root.trayPinned.indexOf(its[i].service) >= 0) out.push(its[i])
        rootMod.trayModel = out
    }
    Connections {
        target: Tray
        function onItemsChanged() {
            root.trayAutoPin()
            rootMod.refreshTrayModel()
            Qt.callLater(publishAnchor)
        }
    }
    // A pin/unpin from the tray panel changes Theme.trayPinned without touching
    // Tray.items; rebuild the strip so the bar follows.
    Connections {
        target: root
        function onTrayPinnedChanged() {
            rootMod.refreshTrayModel()
            Qt.callLater(publishAnchor)
        }
    }

    // MEI: publish this row's screen-x centre for the themed tray menu and the
    // qsbar test IPC. The width changes when an icon appears/disappears, which
    // is exactly when the anchor moves.
    function publishAnchor() {
        if (!visible) return
        root.trayAnchorX = mapToItem(null, width / 2, 0).x
    }
    onWidthChanged: publishAnchor()
    onVisibleChanged: publishAnchor()
    Component.onCompleted: Qt.callLater(function() {
        rootMod.refreshTrayModel()
        publishAnchor()
    })
}
