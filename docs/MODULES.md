# MODULES — Tenkai's switchboard

One file, `.run/config/tenkai/shell.json` in a test session and `~/.config/tenkai/shell.json`
in a real one. It already held the theme and motion block; the `modules` map is new.
A **missing key means ON**, so any older shell.json keeps every module.

```jsonc
{
  "modules": {
    "bar": true,            // the frame bar: bar window, workspaces, widgets
    "launcher": true,       // app launcher surface + its shortcut
    "control_center": true, // quick settings / sidebar (SUPER+ESCAPE, Screenshot)
    "notifications": true,  // NotificationServer, owns org.freedesktop.Notifications
    "tray": true,           // daemon StatusNotifierWatcher host + tray panel rows
    "wallpaper": true,      // ryogami process + wallpaper menu
    "settings": true        // tenkai-hub (the 5-page Settings app)
  },
  "theme": {                // was already in the schema (settings.go)
    "theme": "Default",     // "Default" | "Wallpaper" | a static catalog name
    "matugen": { "mode": "Dark", "preference": "Darkness", "scheme_type": "TonalSpot", "contrast": 0 },
    "motion": { "scale": 1, "reduce": false }
  }
}
```

Shipped defaults are `true` for every module, `theme: "Default"` (the built-in
orange accents), `matugen.mode: "Dark"`, `motion: {1, false}`. They live in two
places that must agree:

- `src/tenkai_core/shell/quickshell/shell/services/Config.qml:208` (QML reader defaults)
- `src/tenkai_core/shell/ipc/settings.go:276` (`defaultSettings`, the daemon/Hub schema)

## Where each flag is read

| Flag | Read at | Effect |
|---|---|---|
| `bar` | `shell.qml:249` (Frame `LazyLoader`) + `:467`/`:484` (`barToggle`) + `:775` (`bar()` IPC) + `daemon.go:114` | no bar window is created at all; bar shortcuts are no-ops |
| `launcher` | `shell.qml:297` (launcher loader) + `:467`/`:484` + `:751` (`openSurface`) + `daemon.go:114` | loader never activates; shortcut/IPC return silently |
| `control_center` | `shell.qml:467`/`:477`/`:484` + `:751` + `daemon.go:114` + the new `modules/controlcenter/ControlCenterHost.qml` | `quicksettings` and `screenshot` commands are swallowed. With the bar off the panel is hosted by the shell's own host (see below) |
| `notifications` | `services/Notifs.qml:233-236` (`Loader.active`) | no `NotificationServer` object → no D-Bus name |
| `tray` | `daemon.go:91` (`moduleDisabled`) + `:478` (bootstrap) | no `StatusNotifierWatcher` host |
| `wallpaper` | `tenkai:588` (session template) + `shell.qml:467`/`:751` + `daemon.go:114` | ryogami is not started; wallpaper menu is swallowed |
| `settings` | `daemon.go:1244` (`hub` verb) | `tenkai-shell hub …` refuses; no hub process |
| `theme.theme`, `theme.matugen.*` | `settings.go:1106` (`onChange` → `scheduleTheme`) | re-themes live when shell.json is saved |
| `theme.motion.scale` / `.reduce` | `services/Motion.qml:15` and `:21` via `Config.theme` (`Config.qml:54`) | multiplies/collapses all central timings live |

The daemon half of the switchboard is `moduleDisabled` (`daemon.go:91`); the QML
half is `Config.moduleOn` (`Config.qml:47`). Both treat anything but an explicit
`false` as enabled.

## The control centre does not need the bar

The panel used to be reachable only through the bar's menu bus, which made the
`bar` module a hard dependency for the `control_center` module: with the bar off
the control centre could not open at all, although its own flag said it was on.

The panel now has its own surface host, `modules/controlcenter/ControlCenterHost.qml`,
built by the shell **only when the bar is off**. It reuses the bar style's
`ControlCenter` component and gives it a `Theme` instance of its own (the bar
creates one per bar root), so no panel QML was rewritten. With the bar on, the bar
style instantiates the same panel exactly as before, so that path is unchanged.

| bar | control_center | what happens | proof |
|---|---|---|---|
| off | on | the panel opens and closes on the shortcut, with no bar layer | `docs/tests/control-center-matrix.sh` A |
| on | off | the bar renders; the panel stays shut | same test, B |
| on | on | unchanged: the bar hosts the panel, and the request still reaches `ShellState` | same test, C |

`docs/tests/control-center-matrix.sh` runs all three as separate nested sessions
(one cold start each) and asserts `verify-untouched` after every one. The Phase 8
module matrix still passes with the change (50 TESTED, 0 FAIL).

## Disable a component

Edit the file (or have a script edit it) and save:

```bash
jq '.modules.launcher = false' ~/.config/tenkai/shell.json > /tmp/s && mv /tmp/s ~/.config/tenkai/shell.json
```

Restart semantics (measured in `docs/tests/phase8.sh`, scenario S10):

| Flag | When it takes effect |
|---|---|
| `launcher` | **live** — the open launcher is torn down, the next shortcut does nothing (S10) |
| `tray` | **restart** — the watcher stays claimed until the daemon restarts (S10) |
| `bar`, `control_center`, `notifications` | live by the same `LazyLoader`/`Loader` bindings as the launcher; only the launcher path is timed in S10 |
| `wallpaper` | **restart** — ryogami is started by the session script, not the shell |
| `settings` | next `tenkai-shell hub …` call (the verb checks per call) |

To turn something back on, set it to `true` (or delete the key) and restart the
session. Nothing else is generated or rewritten.

## Prove a toggle

```bash
bash docs/tests/phase8.sh            # one nested session per scenario, verify-untouched at both ends
```

It rewrites only `.run/config/tenkai/shell.json`, starts a session per scenario and
asserts: bar layer present/absent (`hyprctl layers`), launcher surface count,
screen pixel diff below the bar for the control centre, D-Bus owners on the
nested bus, `ryogami` process presence, hub verb output, stray processes after
stop. Evidence lands in `.run/logs/phase8-*.log` and `.run/shots/phase8-*.png`.

## Missing optional dependencies

| Missing | What the shell does | Proof |
|---|---|---|
| `brightnessctl` (or no `/sys/class/backlight` device) | the bar's brightness widget probe parses nothing, so `BrightnessWidget.qml:19` keeps it hidden; the IPC verb returns an error string; no process dies | S9a |
| PipeWire socket (`$XDG_RUNTIME_DIR/pipewire-0`) | Quickshell logs the service failure once; the shell, bar and every other module stay up; no QML TypeError | S9b |
| a tray host / SNI apps | no watcher is claimed when `tray:false`; with the tray on but no apps the icon row is simply empty | S4 |

## Swap a theme

1. Set `theme.theme` in shell.json:
   - `"Default"` — Tenkai's built-in dynamic default (orange accents, shipped look)
   - `"Wallpaper"` — derive every colour from the current wallpaper
   - a static name from `src/tenkai_core/shell/ipc/themes_gen.go`: `Catppuccin Mocha`,
     `Dracula`, `Everforest Dark Medium`, `Gruvbox Dark Medium`, `Kanagawa Wave`,
     `Nord Dark`, `One Dark`, `Rose Pine`, `Solarized Dark`, `Tokyo Night`
2. Save; the daemon's settings store notices the theme signature change and
   re-runs the palette pass (`settings.go:1106-1110`). No restart needed.
3. `theme.matugen.mode` chooses `dark`, `light` or `smart` (wallpaper luminance);
   `theme.json`'s `followWallpaper` remains the colour-source master.

## Add a widget — worked example

A simple clock-style widget in the right group. No daemon, no D-Bus, no new
process; it is a QML Item inside the existing bar window.

**1. The widget** — `src/tenkai_core/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/TenkaiClock.qml`:

```qml
import QtQuick
import Ryoku.Ui.Singletons

Item {
    id: rootMod
    required property var root
    readonly property color contentColor: root.widgetContentColor("G20", root.widgetIconColor)
    property string clockText: Qt.formatTime(new Date(), "hh:mm")

    visible: implicitWidth > 0.5
    implicitWidth: row.implicitWidth + 18
    implicitHeight: 28

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        UiText {
            anchors.verticalCenter: parent.verticalCenter
            text: rootMod.clockText
            color: rootMod.contentColor
            font.family: rootMod.root.fontFamily
            font.pixelSize: rootMod.root.fontSize
        }
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: rootMod.clockText = Qt.formatTime(new Date(), "hh:mm") }
}
```

(`widgetContentColor`, `fontFamily`, `fontSize` are the same bar-root properties
`StorageWidget.qml` uses; copy its `UiText` block if you want the exact typography.)

**2. Register it** in `.../qsbar/BarSlot.qml`, next to `compStorage` (line 989):

```qml
    Component {
        id: compTenkaiClock
        TenkaiClock {
            root: barSlot.root
            readonly property real barContentLeftInset: 9
            readonly property real barContentRightInset: 9
        }
    }
```

and add it to the registry (line 1250):

```qml
        "G15": compBluetooth, "G16": compCpuTemperature, "G17": compGpu,
        "G18": compStorage, "G19": compLayout, "G20": compTenkaiClock
```

**3. Place it** in a free right-group slot (`rightModel`, line 2136): replace one
`ListElement { gid: ""; extra: true }` with:

```qml
            ListElement { gid: "G20"; extra: true }
```

**4. Make it toggleable** in Settings → Bar by adding to `.../qsbar/core/widgets.json`:

```json
  { "id": "tenkaiclock", "gid": "G20", "label": "Tenkai clock", "visKey": "tenkaiclock" }
```

The Settings card reads that file; `visKey` is the per-widget visibility key the
bar already stores. **5.** Restart the session (`./tenkai stop && ./tenkai run`). QML is
loaded from source, so no build step. To remove the widget, delete the
`ListElement` (or set the visibility key off) — the rest can stay.

## What this is not

- No plugin manager and no second config file: the flags sit in the file the
  settings store already owns.
- No Hyprland config is read or written by any toggle; a disabled module is a
  no-op, never a compositor edit.
