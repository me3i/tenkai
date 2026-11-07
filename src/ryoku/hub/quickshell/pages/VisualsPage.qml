pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."

// Visuals: the compositor's visual surface — blur, shadow, gaps, borders,
// corner rounding and the screen shader — as a live settings page.
//
// CRITICAL: Tenkai never writes the Hyprland config (~/.config/hypr). Every
// change is a runtime-only Lua evaluation call into the compositor
// (`hyprctl eval 'hl.config({...})'`; the legacy `hyprctl keyword` verb was
// removed from Hyprland's Lua IPC, this is the same door Tenkai's provider
// uses for screenShader/followMouse). A Hyprland reload re-reads
// decoration.lua/hyprland.lua and resets the runtime from them; Tenkai
// re-applies this page's persisted values from the daemon at boot
// (reapplyVisualOverrides in ryoku/shell/ipc/daemon.go), so nothing is lost.
//
// The page's only writer is hypr-visual.json under Tenkai's own config dir
// (XDG_CONFIG_HOME/tenkai/hypr-visual.json; in every Tenkai session that is
// .run/config/tenkai/hypr-visual.json, not the owner's real ~/.config/tenkai).
// FileView.writeAdapter() serialises the whole JsonAdapter, which is the
// Hub's one atomic write path. The file is the ONLY persisted state; the
// compositor is actuated separately and is always the one true readof the
// effective values (see the on-open fallback below).
Item {
    id: pg

    property var hub
    readonly property bool fullBleed: true

    // Factory defaults mirror the live session measured on the owner's
    // desktop (2026-11-03, hyprctl getoption): rounding 0, border 1, gaps
    // 4/7, blur off @4@1 pass, shadow off @45@4 render power, no shader.
    // Border colours default to mono grey — the palette wins whenever one is
    // available (see the palette-derived provider default), and a missing file
    // with no live value falls back to those greys, never red.
    readonly property var factory: ({
        "rounding": 0, "border_size": 1, "gaps_in": 4, "gaps_out": 7,
        "blur_enabled": false, "blur_size": 4, "blur_passes": 1,
        "shadow_enabled": false, "shadow_range": 45, "shadow_render_power": 4,
        "screen_shader": "none",
        "active_border": "#c3c3c3", "inactive_border": "#6e6e6e"
    })
    readonly property var factoryOrder: [
        "rounding", "border_size", "gaps_in", "gaps_out",
        "blur_enabled", "blur_size", "blur_passes",
        "shadow_enabled", "shadow_range", "shadow_render_power", "screen_shader",
        "active_border", "inactive_border"
    ]

    // committed = what is on disk; draft = what the controls show. The two
    // are re-assigned wholesale so bindings re-render.
    property var committed: ({})
    property var draft: ({})

    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")) + "/tenkai/hypr-visual.json"
    readonly property string homePath: Quickshell.env("HOME") || ""

    function clone(o) { var r = {}; for (var k in o) r[k] = o[k]; return r; }
    function fromAdapter() {
        return {
            "rounding": cfgA.rounding, "border_size": cfgA.border_size,
            "gaps_in": cfgA.gaps_in, "gaps_out": cfgA.gaps_out,
            "blur_enabled": cfgA.blur_enabled, "blur_size": cfgA.blur_size, "blur_passes": cfgA.blur_passes,
            "shadow_enabled": cfgA.shadow_enabled, "shadow_range": cfgA.shadow_range, "shadow_render_power": cfgA.shadow_render_power,
            "screen_shader": cfgA.screen_shader
        };
    }
    function adopt() {
        pg.committed = pg.fromAdapter();
        pg.draft = pg.clone(pg.committed);
    }
    function edit(k, v) {
        var d = pg.clone(pg.draft);
        d[k] = v;
        pg.draft = d;
        flushTimer.restart();
    }
    // Coalesce a burst of slider ticks into one adapter write + one eval.
    readonly property int flushMs: 150

    function luaStr(s) { return '"' + String(s).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'; }
    // The screen shader is a NAME in the file ("none" clears); the compositor
    // wants the absolute path of the baked shader, same resolution as the
    // stock provider (~/.config/hypr/shaders/<name>.glsl).
    function shaderPathFor(name) {
        if (!name || name === "none")
            return "";
        return pg.homePath + "/.config/hypr/shaders/" + name + ".glsl";
    }
    function luaConfig() {
        var d = pg.draft;
        var s = d.screen_shader === undefined ? "none" : d.screen_shader;
        // Hyprland 0.57's own form: rgb(rrggbb), matching what the provider
        // emits ("[\"col.active_border\"] = \"rgb(rrggbb)\"").
        function col(key, fallback) {
            var v = (d[key] || fallback).trim();
            var m = v.match(/^#?([0-9a-fA-F]{6})$/);
            return m ? "rgb(" + m[1].toLowerCase() + ")" : "rgb(" + fallback.replace("#", "").toLowerCase() + ")";
        }
        return "hl.config({"
            + " decoration = {"
            + " rounding = " + Math.round(Number(d.rounding) || 0)
            + ", blur = { enabled = " + (d.blur_enabled ? "true" : "false")
            + ", size = " + Math.round(Number(d.blur_size) || 1)
            + ", passes = " + Math.round(Number(d.blur_passes) || 1) + " }"
            + ", shadow = { enabled = " + (d.shadow_enabled ? "true" : "false")
            + ", range = " + Math.round(Number(d.shadow_range) || 0)
            + ", render_power = " + Math.round(Number(d.shadow_render_power) || 1) + " }"
            + ", screen_shader = " + pg.luaStr(pg.shaderPathFor(s))
            + " }"
            + ", general = {"
            + " border_size = " + Math.round(Number(d.border_size) || 0)
            + ", gaps_in = " + Math.round(Number(d.gaps_in) || 0)
            + ", gaps_out = " + Math.round(Number(d.gaps_out) || 0)
            + ", [\"col.active_border\"] = \"" + col("active_border", "#c3c3c3") + "\""
            + ", [\"col.inactive_border\"] = \"" + col("inactive_border", "#6e6e6e") + "\""
            + " } })";
    }
    function flushWrites() {
        if (!pg.draft)
            return;
        cfgA.rounding = pg.draft.rounding;
        cfgA.border_size = pg.draft.border_size;
        cfgA.gaps_in = pg.draft.gaps_in;
        cfgA.gaps_out = pg.draft.gaps_out;
        cfgA.blur_enabled = pg.draft.blur_enabled;
        cfgA.blur_size = pg.draft.blur_size;
        cfgA.blur_passes = pg.draft.blur_passes;
        cfgA.shadow_enabled = pg.draft.shadow_enabled;
        cfgA.shadow_range = pg.draft.shadow_range;
        cfgA.shadow_render_power = pg.draft.shadow_render_power;
        cfgA.screen_shader = pg.draft.screen_shader;
        cfgA.active_border = pg.draft.active_border;
        cfgA.inactive_border = pg.draft.inactive_border;
        // the Hub's atomic write path (whole adapter serialised to a temp
        // file, renamed over the target)
        cfg.writeAdapter();
        pg.committed = pg.clone(pg.draft);
        applyProc.command = ["hyprctl", "eval", pg.luaConfig()];
        applyProc.running = true;
    }

    // ── on-open: read the file; keys the file is missing fall back to a
    // live `hyprctl getoption` query, so the page shows the effective
    // compositor state rather than a guess. ──────────────────────────
    readonly property var factoryDefaults: pg.factory

    function fileModel() {
        var txt = "";
        try { txt = String(cfg.text() || ""); } catch (e) { return {}; }
        if (!txt.length)
            return {};
        try {
            var j = JSON.parse(txt);
            return (j && typeof j === "object" && !Array.isArray(j)) ? j : {};
        } catch (e) { return {}; }
    }
    function adoptMerged(fromFile, fromLive) {
        var merged = {};
        for (var i = 0; i < pg.factoryOrder.length; i++) {
            var k = pg.factoryOrder[i];
            merged[k] = (fromFile[k] !== undefined) ? fromFile[k]
                      : (fromLive[k] !== undefined ? fromLive[k] : pg.factoryDefaults[k]);
        }
        pg.committed = merged;
        pg.draft = pg.clone(merged);
    }
    function parseGetoption(key, text) {
        var first = String(text).split("\n")[0] || "";
        var val = first.replace(/^\s*[a-z_ ]*:\s*/i, "").trim();
        switch (key) {
        case "rounding": case "border_size": case "blur_size": case "blur_passes":
        case "shadow_range": case "shadow_render_power":
            return Math.round(Number(val) || 0);
        case "blur_enabled": case "shadow_enabled":
            return val === "true";
        case "gaps_in": case "gaps_out":
            return Math.round(Number(String(val).split(" ")[0]) || 0);
        case "screen_shader":
            if (val === "[[EMPTY]]" || val === "") return "none";
            var m = String(val).match(/([A-Za-z0-9_-]+)\.glsl/);
            return m ? m[1] : "none";
        case "active_border": case "inactive_border":
            // "gradient data: ffe0563b 0deg" → "#e0563b". A two-colour gradient
            // carries both: take the first, strip the alpha if present.
            var gx = String(val).match(/([0-9a-fA-F]{8}|[0-9a-fA-F]{6})/);
            if (!gx) return pg.factoryDefaults[key];
            var hx = gx[0].toUpperCase();
            if (hx.length === 8) hx = hx.slice(2);
            return "#" + hx;
        }
        return pg.factoryDefaults[key];
    }

    readonly property var optionNames: ({
        "rounding": "decoration:rounding",
        "border_size": "general:border_size",
        "gaps_in": "general:gaps_in",
        "gaps_out": "general:gaps_out",
        "blur_enabled": "decoration:blur:enabled",
        "blur_size": "decoration:blur:size",
        "blur_passes": "decoration:blur:passes",
        "shadow_enabled": "decoration:shadow:enabled",
        "shadow_range": "decoration:shadow:range",
        "shadow_render_power": "decoration:shadow:render_power",
        "screen_shader": "decoration:screen_shader",
        "active_border": "general:col.active_border",
        "inactive_border": "general:col.inactive_border"
    })

    property var liveFetch: ({})
    property var pendingFetch: []

    function openWithFallback() {
        var f = pg.fileModel();
        var missing = [];
        for (var i = 0; i < pg.factoryOrder.length; i++) {
            var k = pg.factoryOrder[i];
            if (f[k] === undefined)
                missing.push(k);
        }
        if (missing.length === 0) {
            pg.adoptMerged(f, {});
            return;
        }
        pg.pendingFetch = missing;
        pg.liveFetch = {};
        for (var j = 0; j < missing.length; j++) {
            var p = fetchers[missing[j]];
            p.running = true;
        }
    }
    function fetched(key, text) {
        pg.liveFetch[key] = pg.parseGetoption(key, text);
        var rest = [];
        for (var i = 0; i < pg.pendingFetch.length; i++)
            if (pg.pendingFetch[i] !== key) rest.push(pg.pendingFetch[i]);
        pg.pendingFetch = rest;
        if (pg.pendingFetch.length === 0)
            pg.adoptMerged(pg.fileModel(), pg.liveFetch);
    }

    Component.onCompleted: pg.openWithFallback()

    Timer {
        id: flushTimer
        interval: pg.flushMs
        repeat: false
        onTriggered: pg.flushWrites()
    }

    // hypr-visual.json — the page's only persisted state. seed-once: the
    // defaults are the compositor's measured live values, and a missing file
    // is created complete on the first edit.
    FileView {
        id: cfg
        path: pg.configPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: pg.openWithFallback()

        JsonAdapter {
            id: cfgA
            property int rounding: 0
            property int border_size: 1
            property int gaps_in: 4
            property int gaps_out: 7
            property bool blur_enabled: false
            property int blur_size: 4
            property int blur_passes: 1
            property bool shadow_enabled: false
            property int shadow_range: 45
            property int shadow_render_power: 4
            property string screen_shader: "none"
            property string active_border: "#c3c3c3"
            property string inactive_border: "#6e6e6e"
        }
    }

    // the actuator: one coalesced eval carrying every value (idempotent, so a
    // repeated flush can never drift)
    Process {
        id: applyProc
        command: ["true"]
        stdout: StdioCollector { }
        stderr: StdioCollector { }
    }

    // getoption fallbacks, one per key, only for keys the file lacks
    Process { id: fb_rounding; command: ["hyprctl", "getoption", "decoration:rounding"]; stdout: StdioCollector { onStreamFinished: pg.fetched("rounding", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_border_size; command: ["hyprctl", "getoption", "general:border_size"]; stdout: StdioCollector { onStreamFinished: pg.fetched("border_size", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_gaps_in; command: ["hyprctl", "getoption", "general:gaps_in"]; stdout: StdioCollector { onStreamFinished: pg.fetched("gaps_in", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_gaps_out; command: ["hyprctl", "getoption", "general:gaps_out"]; stdout: StdioCollector { onStreamFinished: pg.fetched("gaps_out", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_blur_enabled; command: ["hyprctl", "getoption", "decoration:blur:enabled"]; stdout: StdioCollector { onStreamFinished: pg.fetched("blur_enabled", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_blur_size; command: ["hyprctl", "getoption", "decoration:blur:size"]; stdout: StdioCollector { onStreamFinished: pg.fetched("blur_size", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_blur_passes; command: ["hyprctl", "getoption", "decoration:blur:passes"]; stdout: StdioCollector { onStreamFinished: pg.fetched("blur_passes", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_shadow_enabled; command: ["hyprctl", "getoption", "decoration:shadow:enabled"]; stdout: StdioCollector { onStreamFinished: pg.fetched("shadow_enabled", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_shadow_range; command: ["hyprctl", "getoption", "decoration:shadow:range"]; stdout: StdioCollector { onStreamFinished: pg.fetched("shadow_range", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_shadow_render_power; command: ["hyprctl", "getoption", "decoration:shadow:render_power"]; stdout: StdioCollector { onStreamFinished: pg.fetched("shadow_render_power", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_screen_shader; command: ["hyprctl", "getoption", "decoration:screen_shader"]; stdout: StdioCollector { onStreamFinished: pg.fetched("screen_shader", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_active_border; command: ["hyprctl", "getoption", "general:col.active_border"]; stdout: StdioCollector { onStreamFinished: pg.fetched("active_border", "" + text) } stderr: StdioCollector { } }
    Process { id: fb_inactive_border; command: ["hyprctl", "getoption", "general:col.inactive_border"]; stdout: StdioCollector { onStreamFinished: pg.fetched("inactive_border", "" + text) } stderr: StdioCollector { } }

    readonly property var fetchers: ({
        "rounding": fb_rounding, "border_size": fb_border_size, "gaps_in": fb_gaps_in, "gaps_out": fb_gaps_out,
        "blur_enabled": fb_blur_enabled, "blur_size": fb_blur_size, "blur_passes": fb_blur_passes,
        "shadow_enabled": fb_shadow_enabled, "shadow_range": fb_shadow_range, "shadow_render_power": fb_shadow_render_power,
        "screen_shader": fb_screen_shader,
        "active_border": fb_active_border, "inactive_border": fb_inactive_border
    })

    // ── head (matches every settings page) ───────────────────────────────
    Column {
        id: head
        anchors.top: parent.top
        anchors.topMargin: Tokens.s6
        x: Tokens.s6
        width: Math.max(320, pg.width - Tokens.s6 * 2 - Tokens.s3)
        spacing: Tokens.s3

        Row {
            height: Tokens.s5
            spacing: Tokens.s2
            Rectangle { width: 16; height: 1; color: Tokens.ink; anchors.verticalCenter: parent.verticalCenter }
            Text { text: "M"; color: Tokens.ink; font.family: Tokens.jp; font.pixelSize: 11; anchors.verticalCenter: parent.verticalCenter }
            Text {
                text: I18n.tr("COMPOSITOR"); color: Tokens.inkMuted; font.family: Tokens.ui
                font.pixelSize: 9; font.weight: Font.Medium; font.letterSpacing: Tokens.trackMark
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            text: I18n.tr("Visuals"); color: Tokens.ink
            font.family: Tokens.display; font.pixelSize: Tokens.fTitle
        }
        Text {
            width: Math.min(parent.width, 720)
            text: I18n.tr("Blur, shadow, gaps, borders, corner rounding and the screen shader. Applied live, saved to Tenkai's own hypr-visual.json — your Hyprland config is never written. A Hyprland reload resets the runtime; Tenkai re-applies this file at startup.")
            color: Tokens.inkMuted; font.family: Tokens.ui
            font.pixelSize: Tokens.fBody; wrapMode: Text.WordWrap
        }
    }

    // ── the grid ─────────────────────────────────────────────────────────
    Flickable {
        id: flick
        anchors {
            left: parent.left; right: parent.right
            top: head.bottom; bottom: statusLine.top
            leftMargin: Tokens.s6; rightMargin: Tokens.s6
            topMargin: Tokens.s5
        }
        contentWidth: width
        contentHeight: Math.max(col.height, height)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        ScrollBar.vertical: ScrollRail { policy: ScrollBar.AsNeeded }
        WheelScroll { }

        CardColumns {
            id: col
            width: flick.width - Tokens.s3
            spacing: Tokens.s5
            fillTo: flick.height

            readonly property int ctlW: Math.min(240, Math.max(160, Math.round(col.colWidth * 0.34)))

            // ── SHAPE ────────────────────────────────────────────────
            SettingCard {
                width: col.colWidth
                title: I18n.tr("SHAPE")
                summary: "rounding · border · colour"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    controlWidth: col.ctlW
                    label: I18n.tr("Corner rounding")
                    desc: I18n.tr("Radius applied to every window and layer surface.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.rounding) || 0))
                    unit: "px"
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 20
                        value: Math.round(Number(pg.draft.rounding) || 0)
                        onModified: (v) => pg.edit("rounding", Math.round(v))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    label: I18n.tr("Border size")
                    desc: I18n.tr("Thickness of the border drawn around windows.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.border_size) || 0))
                    unit: "px"
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 5
                        value: Math.round(Number(pg.draft.border_size) || 0)
                        onModified: (v) => pg.edit("border_size", Math.round(v))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    label: I18n.tr("Active border")
                    desc: I18n.tr("Colour of the focused window's border. Click to pick.")
                    source: "hypr-visual.json"
                    value: String(pg.draft.active_border || pg.factoryDefaults.active_border).toUpperCase()
                    ColorField {
                        anchors.fill: parent
                        value: String(pg.draft.active_border || pg.factoryDefaults.active_border)
                        onChosen: (hex) => pg.edit("active_border", String(hex).toUpperCase())
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    controlWidth: col.ctlW
                    label: I18n.tr("Inactive border")
                    desc: I18n.tr("Colour of every unfocused window's border.")
                    source: "hypr-visual.json"
                    value: String(pg.draft.inactive_border || pg.factoryDefaults.inactive_border).toUpperCase()
                    ColorField {
                        anchors.fill: parent
                        value: String(pg.draft.inactive_border || pg.factoryDefaults.inactive_border)
                        onChosen: (hex) => pg.edit("inactive_border", String(hex).toUpperCase())
                    }
                }
            }

            // ── SPACING ──────────────────────────────────────────────
            SettingCard {
                width: col.colWidth
                title: I18n.tr("SPACING")
                summary: "gaps"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    controlWidth: col.ctlW
                    label: I18n.tr("Gaps between windows")
                    desc: I18n.tr("Space between tiles.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.gaps_in) || 0))
                    unit: "px"
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 30
                        value: Math.round(Number(pg.draft.gaps_in) || 0)
                        onModified: (v) => pg.edit("gaps_in", Math.round(v))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    label: I18n.tr("Gaps around the screen")
                    desc: I18n.tr("Space between windows and the screen edge.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.gaps_out) || 0))
                    unit: "px"
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 40
                        value: Math.round(Number(pg.draft.gaps_out) || 0)
                        onModified: (v) => pg.edit("gaps_out", Math.round(v))
                    }
                }
            }

            // ── BLUR ─────────────────────────────────────────────────
            SettingCard {
                width: col.colWidth
                title: I18n.tr("BLUR")
                summary: "blur"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    controlWidth: 54
                    label: I18n.tr("Blur")
                    desc: I18n.tr("Frosted-glass behind windows and layer surfaces.")
                    source: "hypr-visual.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.draft.blur_enabled
                        onToggled: (v) => pg.edit("blur_enabled", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    enabled: !!pg.draft.blur_enabled
                    label: I18n.tr("Blur size")
                    desc: I18n.tr("How large the blur sample area is.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.blur_size) || 1))
                    Slid {
                        anchors.fill: parent
                        from: 1; to: 8
                        enabled: !!pg.draft.blur_enabled
                        value: Math.round(Number(pg.draft.blur_size) || 1)
                        onModified: (v) => pg.edit("blur_size", Math.round(v))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    enabled: !!pg.draft.blur_enabled
                    label: I18n.tr("Blur passes")
                    desc: I18n.tr("How many times the blur is applied.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.blur_passes) || 1))
                    Slid {
                        anchors.fill: parent
                        from: 1; to: 3
                        enabled: !!pg.draft.blur_enabled
                        value: Math.round(Number(pg.draft.blur_passes) || 1)
                        onModified: (v) => pg.edit("blur_passes", Math.round(v))
                    }
                }
            }

            // ── SHADOW ───────────────────────────────────────────────
            SettingCard {
                width: col.colWidth
                title: I18n.tr("SHADOW")
                summary: "shadow"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    controlWidth: 54
                    label: I18n.tr("Shadow")
                    desc: I18n.tr("Drop shadow beneath windows.")
                    source: "hypr-visual.json"
                    Sw {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        on: !!pg.draft.shadow_enabled
                        onToggled: (v) => pg.edit("shadow_enabled", v)
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    enabled: !!pg.draft.shadow_enabled
                    label: I18n.tr("Shadow range")
                    desc: I18n.tr("How far the shadow reaches from the window.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.shadow_range) || 0))
                    unit: "px"
                    Slid {
                        anchors.fill: parent
                        from: 0; to: 80
                        enabled: !!pg.draft.shadow_enabled
                        value: Math.round(Number(pg.draft.shadow_range) || 0)
                        onModified: (v) => pg.edit("shadow_range", Math.round(v))
                    }
                }
                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: true
                    controlWidth: col.ctlW
                    enabled: !!pg.draft.shadow_enabled
                    label: I18n.tr("Shadow power")
                    desc: I18n.tr("How hard the shadow falls off.")
                    source: "hypr-visual.json"
                    value: String(Math.round(Number(pg.draft.shadow_render_power) || 1))
                    Slid {
                        anchors.fill: parent
                        from: 1; to: 4
                        enabled: !!pg.draft.shadow_enabled
                        value: Math.round(Number(pg.draft.shadow_render_power) || 1)
                        onModified: (v) => pg.edit("shadow_render_power", Math.round(v))
                    }
                }
            }

            // ── SCREEN SHADER ────────────────────────────────────────
            SettingCard {
                width: col.colWidth
                title: I18n.tr("SCREEN SHADER")
                summary: "shader"

                SettingRow {
                    anchors.left: parent.left; anchors.right: parent.right
                    divider: false
                    block: true
                    label: I18n.tr("Post-process")
                    desc: I18n.tr("A full-screen filter baked into the compositor. None clears it.")
                    source: "hypr-visual.json"
                    Chips {
                        anchors.left: parent.left
                        options: ["none", "grain", "vignette", "halftone", "bone", "onebit"]
                        current: pg.draft.screen_shader || "none"
                        onChose: (k) => pg.edit("screen_shader", k)
                    }
                }
            }
        }
    }

    // ── status strip ─────────────────────────────────────────────────────
    Rectangle {
        id: statusLine
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: 44
        color: "transparent"
        Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Tokens.line }
        Row {
            anchors.left: parent.left
            anchors.leftMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            spacing: Tokens.s3
            Rectangle {
                width: 6; height: 6; radius: 3; color: Tokens.ink
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                text: I18n.tr("LIVE — APPLIED TO THE COMPOSITOR, SAVED TO TENKAI'S hypr-visual.json")
                color: Tokens.inkMuted
                font.family: Tokens.ui; font.pixelSize: Tokens.fMicro
                font.weight: Font.Medium; font.letterSpacing: Tokens.trackLabel
                anchors.verticalCenter: parent.verticalCenter
            }
        }
        Text {
            anchors.right: parent.right
            anchors.rightMargin: Tokens.s6
            anchors.verticalCenter: parent.verticalCenter
            text: I18n.tr("NEVER WRITES ~/.config/hypr")
            color: Tokens.inkFaint
            font.family: Tokens.mono; font.pixelSize: Tokens.fTiny
        }
    }
}
