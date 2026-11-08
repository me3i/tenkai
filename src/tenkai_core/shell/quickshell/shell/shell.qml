//@ pragma UseQApplication
// Threaded render loop: the frame's blob melt is a per-frame spring plus live
// scene-graph MultiEffects (menu glass blur, blobs); threaded is vsync-locked and
// frees the GUI thread so those effects get regular frame deltas and never ghost
// or stutter. `basic` idled a touch cheaper on NVIDIA but smeared the live effects
// when switching menu pages, so this matches the frame's proven render setup.
//@ pragma DefaultEnv QSG_RENDER_LOOP=threaded
//@ pragma DefaultEnv QS_DROP_EXPENSIVE_FONTS=1
//@ pragma DefaultEnv QT_QUICK_FLICKABLE_WHEEL_DECELERATION=10000
pragma ComponentBehavior: Bound

import Quickshell
import shell.services

import "modules/stage/Singletons" as StageCfg
import "components"
import "modules/wallpaper"
import "modules/wallpaper/Singletons" as WallCfg
import "modules/desktop"

import "modules/bar"
import "modules/controlcenter"
import "modules/dock"
import "modules/launcher"

import "modules/clipboard"
import QtQuick
import Quickshell.Io
import Quickshell.Wayland
import "modules/osd"
import "modules/notifications"
import "modules/capture"
import "modules/confirm"
import Tenkai.Ui.Singletons

/**
 * The single resident Tenkai shell instance.
 *
 * One ShellRoot for the whole desktop. It brings the shared service singletons
 * online, holds the per-monitor ShellState every surface binds its visibility
 * to, and registers the shell's in-QML global shortcuts. Each monitor
 * gets one Scope carrying that screen's ShellState slice (st); every migrated
 * surface is instantiated once inside it and binds its screen and its visibility
 * to the slice, so a keybind that flips a flag on the active monitor reveals or
 * hides exactly this monitor's copy in-process, where the old shell spawned a
 * ryoku-shell client per press across separate surface processes.
 *
 * The ryoku-shell daemon launches this instance as `qs -c shell`, the live
 * desktop. Where the compositor offers a global-shortcuts protocol its binds
 * dispatch straight to the shortcuts registered here.
 *
 * UseQApplication is declared once for the whole shell (the tray needs Qt
 * Widgets), replacing the six per-surface copies the old multi-process shell paid.
 */
ShellRoot {
    id: root
    // One deferred-build wave for the cheap event-driven surfaces (the OSDs and
    // the notification column), armed 1.5 s into boot so a keypress or an
    // arriving toast never waits on a component build. Everything heavier is
    // built on its own first open and torn down a grace period after every
    // close, so nothing parses, instantiates or commits for a surface nobody
    // asked for. The grace is what protects the animations: a surface is only
    // ever destroyed while it sits closed.
    property int warm: 0
    Timer { interval: 1500; running: true; repeat: false; onTriggered: root.warm = 1 }

    // Diagnostic: the last surface id actually requested through ShellState,
    // i.e. after the module gate in toggleSurface/openSurface. A gated request
    // leaves it empty, so harnesses can assert the gate itself rather than a
    // screenshot margin.
    property string surfaceTrace: ""
    Connections {
        target: ShellState
        function onSurfaceRequested(id, mon, context) { root.surfaceTrace = id }
    }

    // Construct the shared services (ShellState's per-monitor state now, heavier
    // providers as surfaces migrate) at load rather than on the first keybind.
    ServiceLoader {
        services: [ShellState, ScreenTime, Keypresses, KeyboardLayout, Idle]
    }

    // The control centre's own surface host. It is built only when the bar is
    // off: the bar style instantiates the same panel, so a session with the bar
    // on keeps exactly one control centre, hosted by the bar as before. With
    // the bar off this host answers the "quick-settings" surface request, so
    // the control_center module flag no longer depends on the bar module.
    LazyLoader {
        id: controlCenterLoader
        activeAsync: Config.moduleOn("control_center") && !Config.moduleOn("bar")
        ControlCenterHost { }
    }

    readonly property string reloadStatePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/tenkai-reload-cover.json"
    readonly property string reloadCoverBin: Quickshell.env("TENKAI_SHELL_DIR")
        ? Quickshell.env("TENKAI_SHELL_DIR") + "/scripts/tenkai-reload-cover"
        : "tenkai-reload-cover"
    property string reloadToken: ""
    property bool reloadFinishSent: false
    property bool reloadReleaseArmed: false
    property var reloadScreens: ({})
    function setReloadScreenReady(name: string, ready: bool): void {
        var next = ({});
        for (var key in reloadScreens)
            next[key] = reloadScreens[key];
        next[name] = ready;
        reloadScreens = next;
        finishReloadCover();
    }
    function finishReloadCover(): void {
        if (!reloadToken || reloadFinishSent)
            return;
        for (var i = 0; i < Quickshell.screens.length; i++) {
            var screen = Quickshell.screens[i];
            if (!screen || !reloadScreens[screen.name])
                return;
        }
        if (!reloadReleaseArmed) {
            reloadReleaseArmed = true;
            reloadHold.restart();
        }
    }

    FileView {
        id: reloadState
        path: root.reloadStatePath
        blockLoading: true
        printErrors: false
        onLoaded: {
            try {
                const token = JSON.parse(text() || "{}").token;
                root.reloadToken = typeof token === "string" && /^[0-9a-f]{32}$/.test(token) ? token : "";
            } catch (error) {
                root.reloadToken = "";
            }
            root.finishReloadCover();
        }
    }
    Timer {
        id: reloadHold
        interval: 1500
        onTriggered: {
            if (!root.reloadToken || root.reloadFinishSent)
                return;
            root.reloadFinishSent = true;
            reloadFinish.command = [root.reloadCoverBin, "finish", root.reloadToken];
            reloadFinish.running = true;
        }
    }

    Process {
        id: reloadFinish
    }

    // Power Saver strips compositor blur and shadow too (the heaviest present-time
    // GPU cost), reusing the decoration.lua path lowPowerMode already takes. Perf
    // folds the active power profile into its switches; mirror the profile-driven
    // "saver" flag to a cache the compositor reads, and reload it when it flips
    // so it re-reads the value live. Seeded once at load with no reload
    // (login already parsed the right value); only a later profile change reloads.
    FileView {
        id: hyprPerf
        path: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/tenkai/hypr-perf.json"
        printErrors: false
        property bool armed: false
        onSaved: if (hyprPerf.armed) Wm.reloadConfig("")
        JsonAdapter { id: hyprPerfA; property bool saver: false }
        Component.onCompleted: {
            hyprPerfA.saver = Perf.saver;
            hyprPerf.writeAdapter();
        }
    }
    Connections {
        target: Perf
        function onSaverChanged() {
            hyprPerf.armed = true;
            hyprPerfA.saver = Perf.saver;
            hyprPerf.writeAdapter();
        }
    }

    // One per-monitor surface stack. Each screen gets a Scope carrying its
    // ShellState slice (st); every resident surface binds its screen and its
    // visibility to that slice, so flipping a flag on the active monitor reveals
    // or hides this monitor's copy. The order here reads top-to-bottom only; the
    // Wayland layer each surface maps on decides the real stacking.
    Variants {
        model: ShellState.screens

        Scope {
            id: perScreen
            required property var modelData
            readonly property var st: ShellState.forScreen(modelData)
            readonly property bool reloadReady: wallpaper.reloadReady && desktop.reloadReady
            onReloadReadyChanged: root.setReloadScreenReady(modelData.name, reloadReady)
            Component.onCompleted: root.setReloadScreenReady(modelData.name, reloadReady)

            // Always-on backdrop and desktop widget layer.
            Wallpaper {
                id: wallpaper
                screen: perScreen.modelData
            }
            // Step 1 kept the bar and the wallpaper as the shell's surfaces and
            // turned the desktop widget layer off. The wallpaper painter (and
            // its reveal transition) lives INSIDE this surface, so the surface
            // itself must stay visible -- step 5 found that `active: false` left
            // the screen showing Hyprland's built-in wallpaper. Widgets stay
            // off: `widgetsEnabled: false` gates every tile, the glass backdrop
            // and the plugin repeater below.
            Desktop {
                id: desktop
                screen: perScreen.modelData
                active: true
                widgetsEnabled: false
                wallpaperUrl: wallpaper.wallpaperUrl
                wallpaperPath: wallpaper.wallpaperPath
                wallpaperFit: wallpaper.fit
                wallpaperTransition: wallpaper.transition
                videoUrl: wallpaper.videoUrl
                wallpaperLive: wallpaper.live
                videoMuted: wallpaper.videoMuted
                videoVolume: wallpaper.videoVolume
            }
















            // Stage now renders entirely inside the desktop surface (one stack:
            // backdrop, layers, widgets), so there is no separate Background
            // surface here (docs/stage.md). Built on first enable or first
            // placement; cava and its buffers never exist while the visualizer
            // is off.





















            // The frame bar (Phase 2): reads its own reveal from this slice.
            // TENKAI: gated, so bar=false creates no bar window at all (not just a
            // hidden one). LazyLoader is the pattern the other toggle surfaces
            // here already use.
            LazyLoader {
                activeAsync: Config.moduleOn("bar")
                Frame {
                    modelData: perScreen.modelData
                    // park the record island flush beside this monitor's dock band
                    dockLaneEdge: dockLoader.item ? dockLoader.item.edge : ""
                    dockLaneSize: dockLoader.item ? dockLoader.item.bandSize : 0
                    dockLaneCenter: dockLoader.item ? dockLoader.item.bandCenter : 0
                }
            }

            // The dock: a resident per-monitor surface on the edge opposite the
            // bar. Style-agnostic, so it lives here rather than inside a bar style;
            // it is not built until the user turns it on (Hub -> Bar Studio -> Dock).
            LazyLoader {
                id: dockLoader
                activeAsync: Dock.cfg("enabled", false)
                DockSurface {
                    id: perScreenDock
                    screen: perScreen.modelData
                    // Edit widgets steps the dock back so the whole desktop is the canvas.
                    visible: Dock.cfg("enabled", false)
                        && !(StageCfg.StageSession.widgets && StageCfg.StageSession.monitor === perScreen.modelData.name)
                }
            }

            // The dock's right-click context menu: a full-screen overlay on the
            // monitor that owns the open menu (the thin dock strip cannot host it).
            LazyLoader {
                id: dockMenuLoader
                property bool open: Dock.menuOpen && Dock.menuScreen === perScreen.modelData.name
                activeAsync: open || dockMenuHold.running
                onOpenChanged: if (!open && active) dockMenuHold.restart()
                DockMenuOverlay {
                    screen: perScreen.modelData
                }
            }
            Timer { id: dockMenuHold; interval: 2000 }

            // Toggle-driven overlays: built on first open (async, so the key
            // press never blocks on a component build) and destroyed 15 s after
            // every close, once the slide-out has long finished.
            // The inner surface must be BORN closed and opened one tick later:
            // its reveal is driven by an active-change, and an item created with
            // the flag already true would never animate (or show) at all.
            LazyLoader {
                id: launcherLoader
                property bool open: perScreen.st ? perScreen.st.launcherOpen : false
                property bool showNow: false
                activeAsync: Config.moduleOn("launcher") && (open || launcherHold.running)
                onItemChanged: if (launcherLoader.item) Qt.callLater(function() { launcherLoader.showNow = launcherLoader.open; })
                onOpenChanged: {
                    if (launcherLoader.open) {
                        if (launcherLoader.item) launcherLoader.showNow = true;
                        return;
                    }
                    launcherLoader.showNow = false;
                    if (launcherLoader.active) launcherHold.restart();
                }
                Launcher {
                    screen: perScreen.modelData
                    active: launcherLoader.showNow
                    onRequestClose: if (perScreen.st) perScreen.st.launcherOpen = false
                }
            }
            Timer { id: launcherHold; interval: 15000 }









































            Timer { id: clipboardHold; interval: 15000 }
            // Shell-wide per-monitor surfaces. The OSDs and the popup column are
            // small and event-driven (a keypress or an arriving toast must never
            // wait on a build), so they join the first wave and stay resident.
            // The capture overlays are per-flow: built on the flow's first
            // signal, kept across the flow's pauses, dropped 20 s after it ends.
            LazyLoader {
                id: osdVolumeLoader
                activeAsync: root.warm >= 1
                OsdWindow {
                    modelData: perScreen.modelData
                    kind: "volume"
                }
            }
            LazyLoader {
                id: osdMicLoader
                activeAsync: root.warm >= 1
                OsdWindow {
                    modelData: perScreen.modelData
                    kind: "mic"
                }
            }
            LazyLoader {
                id: osdBrightnessLoader
                activeAsync: root.warm >= 1
                OsdWindow {
                    modelData: perScreen.modelData
                    kind: "brightness"
                }
            }
            LazyLoader {
                id: osdKeyboardLoader
                activeAsync: root.warm >= 1
                KeyboardOsdWindow {
                    modelData: perScreen.modelData
                }
            }
            LazyLoader {
                id: notifsLoader
                activeAsync: root.warm >= 1 || Notifs.popups.length > 0
                NotificationPopups {
                    modelData: perScreen.modelData
                }
            }
            LazyLoader {
                id: regionLoader
                property bool open: Recorder.anyActive || Recorder.chooserOpen
                activeAsync: open || regionHold.running
                onOpenChanged: if (!open && active) regionHold.restart()
                RegionOverlay {
                    modelData: perScreen.modelData
                }
            }
            Timer { id: regionHold; interval: 20000 }
            LazyLoader {
                id: captureLoader
                property bool open: Capture.selecting !== ""
                activeAsync: open || captureHold.running
                onOpenChanged: if (!open && active) captureHold.restart()
                CaptureOverlay {
                    modelData: perScreen.modelData
                }
            }
            Timer { id: captureHold; interval: 20000 }
            LazyLoader {
                id: cameraLoader
                property bool open: Camera.active
                activeAsync: open || cameraHold.running
                onOpenChanged: if (!open && active) cameraHold.restart()
                CameraOverlay {
                    modelData: perScreen.modelData
                }
            }
            Timer { id: cameraHold; interval: 20000 }
            LazyLoader {
                id: keypressLoader
                property bool open: Keypresses.active
                activeAsync: open || keypressHold.running
                onOpenChanged: if (!open && active) keypressHold.restart()
                KeypressOverlay {
                    modelData: perScreen.modelData
                }
            }
            Timer { id: keypressHold; interval: 20000 }
            // Shown only on the monitor whose frame bar raised it; the positive
            // button runs the power action through the daemon, then clears.
            LazyLoader {
                id: confirmLoader
                property bool open: ShellState.sessionAction !== ""
                activeAsync: open || confirmHold.running
                onOpenChanged: if (!open && active) confirmHold.restart()
                TenkaiConfirmationDialog {
                    modelData: perScreen.modelData
                    action: ShellState.sessionActionMonitor === perScreen.modelData.name ? ShellState.sessionAction : ""
                    message: ShellState.sessionMessage
                    positiveLabel: ShellState.sessionPositive
                    negativeLabel: I18n.tr("Cancel")
                    onConfirmed: a => { SessionActions.run(a); ShellState.clearSessionAction(); }
                    onCancelled: ShellState.clearSessionAction()
                }
            }
            Timer { id: confirmHold; interval: 5000 }
        }
    }

    // The single surface-toggle mapping. Every shell surface id resolves to one
    // transition here: a per-monitor ShellState flip, a global config toggle, or
    // a request onto the frame menu bus. Both routes to a surface end in this one
    // call -- a CustomShortcut press where the compositor bridges global
    // shortcuts, and the surfaceRequested bus a `ryoku-shell <id>` spawn drives
    // where that protocol is absent (niri) -- so a toggle is defined once.
    // Which shell.json module owns a toggle id ("" = always available).
    function surfaceModule(id) {
        switch (id) {
        case "launcher": return "launcher";
        case "quicksettings": case "screenshot": return "control_center";
        case "wallpaper-menu": return "wallpaper";
        case "barToggle": return "bar";
        }
        return "";
    }
    // The same mapping for an IPC surface id ("quick-settings#capture", ...).
    function surfaceModuleId(id) {
        if (id === "launcher") return "launcher";
        if (id.indexOf("quick-settings") === 0) return "control_center";
        if (id.indexOf("wallpaper") === 0) return "wallpaper";
        return "";
    }
    function toggleSurface(id) {
        const mod = surfaceModule(id);
        if (mod && !Config.moduleOn(mod)) return;
        const st = ShellState.forActive();
        switch (id) {
        case "barToggle":
            if (st)
                st.barRevealed = !st.barRevealed;
            break;
        case "launcher":
            if (st)
                st.launcherOpen = !st.launcherOpen;
            break;
        case "quicksettings":
            ShellState.requestSurfaceActive("quick-settings", undefined);
            break;
        case "wallpaper-menu":
            ShellState.requestSurfaceActive("wallpaper", undefined);
            break;
        case "clipboard":
            if (st)
                st.clipboardOpen = !st.clipboardOpen;
            break;
        case "stash":
            ShellState.requestSurfaceActive("stash", undefined);
            break;
        case "screenshot":
            ShellState.requestSurfaceActive("quick-settings#capture", undefined);
            break;
        case "compress":
            ShellState.requestSurfaceActive("stash#compress", undefined);
            break;
        case "install":
            ShellState.requestSurfaceActive("stash#install", undefined);
            break;
        }
    }

    // The style-independent half of the surface bus. With no global-shortcuts
    // protocol a keybind reaches a surface only by spawning `ryoku-shell <id>`,
    // which arrives here as a surfaceRequested. Frame-menu surfaces are opened by
    // the per-monitor FrameMenuManager (Frame.qml), which maps in every bar
    // style; the shell-wide flag surfaces have no such host, so this routes them
    // through the same toggleSurface a shortcut press uses. Frame-menu ids never
    // match here, so a surface still opens exactly once.
    Connections {
        target: ShellState
        function onSurfaceRequested(id, mon, ctx) {
            switch (id) {
            case "barToggle":
            case "launcher":
            case "clipboard":