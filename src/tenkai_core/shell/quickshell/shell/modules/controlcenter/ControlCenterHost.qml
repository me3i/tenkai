pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import shell.services
import "../bar/barstyles/qsbar" as Qsbar
import "../bar/barstyles/qsbar/controlcenter" as Cc

// The control centre's own surface host.
//
// The panel itself is the bar style's ControlCenter, reused as it is: it reads
// its open state (controlVisible), its screen and its layout from a bar style
// Theme, so this host owns a Theme instance of its own (the bar creates one per
// bar root) and passes it in. Nothing in the panel is rewritten.
//
// It exists because the panel used to be reachable only through the bar's menu
// bus, which made the bar module a hard dependency: with the bar off the
// control centre could not open at all, although its module flag said it was on.
// The bar keeps its own host (the bar style instantiates the same panel), so
// this host is only built when the bar is off and a session with the bar on is
// unchanged.
Item {
    id: root

    // The panel opens on the focused monitor. The Theme carries the screen
    // because the panel binds its surface to activePopupScreen.
    // The shortcut is a toggle: a second request closes the panel again, the
    // same way the bar's own control-centre button behaves.
    function toggle(mon) {
        if (theme.controlVisible) {
            hide();
            return;
        }
        show(mon);
    }

    function show(mon) {
        const screens = ShellState.screens;
        let s = null;
        if (mon && mon !== "") {
            for (let i = 0; i < screens.length; i++) {
                if (screens[i].name === mon) {
                    s = screens[i];
                    break;
                }
            }
        }
        if (!s && screens.length > 0)
            s = screens[0];
        if (s) {
            theme.activePopupScreen = s;
            theme.activePopupScreenName = s.name || "";
        }
        theme.controlVisible = true;
    }

    function hide() {
        theme.controlVisible = false;
    }

    // The Theme instance the panel reads. The bar creates its own instance per
    // bar root; this one exists only when the bar does not.
    Qsbar.Theme {
        id: theme
    }

    Component.onCompleted: {
        // The panel binds its surface to activePopupScreen when it is created,
        // so the screen has to be known by then. Without a bar there is
        // nothing else to set it.
        const screens = ShellState.screens;
        if (screens.length > 0) {
            theme.activePopupScreen = screens[0];
            theme.activePopupScreenName = screens[0].name || "";
        }
    }

    Connections {
        target: ShellState
        function onSurfaceRequested(id, mon, ctx) {
            // "quick-settings" and its sub-pages ("quick-settings#capture",
            // "#stage") all open the same panel.
            if (id.indexOf("quick-settings") !== 0)
                return;
            root.toggle(mon);
        }
        function onSurfaceClosed(id, mon) {
            if (id.indexOf("quick-settings") !== 0)
                return;
            root.hide();
        }
    }

    Cc.ControlCenter {
        id: cc
        root: theme
    }
}
