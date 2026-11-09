pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

/**
 * The wallpaper painter, split out of the desktop widgets layer.
 *
 * The data lives in the `Wallpaper` bridge (modules/wallpaper/Wallpaper.qml,
 * subscribed to the ryogami topic). This surface draws it: a Bottom layer
 * PanelWindow carrying the reveal-fade WallpaperMod.Backdrop — stills with
 * the daemon's transition presets, live clips inside, decoding capped to the
 * surface resolution.
 *
 * Muffling it is what the F5/F6 cuts caused: with the desktop-widgets layer
 * removed, the topic bridge still subscribed and `frame.path` advanced, but
 * nothing consumed `wallpaperUrl`, so `ryogami wallpaper set` updated the
 * state file while the desktop kept the old frame.
 */
PanelWindow {
    id: root

    // The monitor this paint layer renders on, bound by the shell root's
    // per-screen scope.
    required property var screen

    // Wallpaper state, bound from the `Wallpaper` topic bridge.
    property string wallpaperUrl: ""
    property var wallpaperTransition: null
    property string videoUrl: ""
    property bool wallpaperLive: false
    property bool videoMuted: true
    property int videoVolume: 100
    property string wallpaperFit: "Cover"

    // Always-on backdrop layer: occupies the monitor but takes no input.
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.namespace: "tenkai-wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true; right: true; bottom: true }

    Backdrop {
        anchors.fill: parent
        readonly property real screenDpr: (root.screen && root.screen.devicePixelRatio) ? root.screen.devicePixelRatio : 1
        dpr: screenDpr
        url: root.wallpaperUrl
        fit: root.wallpaperFit
        transition: root.wallpaperTransition
        videoUrl: root.videoUrl
        live: root.wallpaperLive
        videoMuted: root.videoMuted
        videoVolume: root.videoVolume
    }
}
