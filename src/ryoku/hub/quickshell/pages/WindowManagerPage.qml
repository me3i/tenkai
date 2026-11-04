pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Ryoku.Ui
import Ryoku.Ui.Singletons
import ".."
import "../Singletons"

// Window Manager (COMPOSITOR). Every window-manager setting on one page: the
// neutral window rows the Hub ships (shape, gaps, borders, motion) and the
// exclusives the active provider ships (ProviderSchema), so a new compositor's
// knobs arrive with its package and never a Hub edit. It shows only the running
// provider: settings apply at the next login and the other compositor's store is
// unreachable from here, so there is nothing to edit for it. The head names the
// compositor; the switch to another lives here too, beside the honest list of
// what this compositor cannot do (the losses `apply --preview` reports, the same
// reasons that keep a hidden row from reading as a bug). Every setting rides the
// shared store (hub.hyprVal/hyprEdit) and the shared schema renderer, so a
// capability the compositor lacks drops its rows rather than showing dead knobs.
Item {
    id: pg
    property var hub

    function cap(s) { s = String(s || ""); return s.length ? s.charAt(0).toUpperCase() + s.slice(1) : s; }
    readonly property string providerName: Settings.provider
    readonly property string pTitle: pg.providerName !== "" ? pg.cap(pg.providerName) : I18n.tr("Window Manager")
    readonly property string pEyebrow: I18n.tr("COMPOSITOR")
    readonly property string pBlurb: I18n.tr("How windows look and behave here. Changes apply live and are saved to Mei's own config, never to your Hyprland files.")

    // Prefer the live read: the shared store is empty in Mei, so hu.hyprVal
    // would leave every row blank. Reading the running compositor is the whole
    // point; a store value (never present here) would only ever be stale.
    function hv(path) { return pg.live[path] !== undefined ? pg.live[path] : (pg.hub ? pg.hub.hyprVal(path) : undefined) }
    function cv(path) { return pg.live[path] !== undefined ? pg.live[path] : (pg.hub ? pg.hub.hyprCommittedVal(path) : undefined) }

    // ── live values ──────────────────────────────────────────────────────
    // Every row opens on what the compositor actually runs: the map below fills
    // the same dotted keys from `hyprctl getoption`. An edit goes through
    // hub.hyprEdit (the shared draft), Save calls `mei-hub desktop save`, which
    // persists to mei/hypr-advanced.json and applies each key with
    // `hl.config` through hyprctl; boot re-applies the file. No Hyprland config
    // is written, so a reload resets the runtime until Mei starts again.
    property var live: ({})
    readonly property var liveOptions: ({
        "desktop.appearance.gapsIn": "general:gaps_in",
        "desktop.appearance.gapsOut": "general:gaps_out",
        "desktop.appearance.gapsWorkspaces": "general:gaps_workspaces",
        "desktop.appearance.borderSize": "general:border_size",
        "desktop.appearance.resizeOnBorder": "general:resize_on_border",
        "desktop.appearance.snapEnabled": "general:snap:enabled",
        "desktop.appearance.extendBorderGrab": "general:extend_border_grab_area",
        "desktop.appearance.hoverIconOnBorder": "general:hover_icon_on_border",
        "desktop.appearance.noFocusFallback": "general:no_focus_fallback",
        "desktop.appearance.resizeCorner": "general:resize_corner",
        "desktop.appearance.rounding": "decoration:rounding",
        "desktop.appearance.roundingPower": "decoration:rounding_power",
        "desktop.appearance.activeOpacity": "decoration:active_opacity",
        "desktop.appearance.inactiveOpacity": "decoration:inactive_opacity",
        "desktop.appearance.fullscreenOpacity": "decoration:fullscreen_opacity",
        "desktop.appearance.dimInactive": "decoration:dim_inactive",
        "desktop.appearance.dimStrength": "decoration:dim_strength",
        "desktop.appearance.dimSpecial": "decoration:dim_special",
        "desktop.appearance.dimAround": "decoration:dim_around",
        "desktop.appearance.dimModal": "decoration:dim_modal",
        "desktop.appearance.borderPartOfWindow": "decoration:border_part_of_window",
        "desktop.appearance.blurEnabled": "decoration:blur:enabled",
        "desktop.appearance.blurSize": "decoration:blur:size",
        "desktop.appearance.blurPasses": "decoration:blur:passes",
        "desktop.appearance.blurXray": "decoration:blur:xray",
        "desktop.appearance.blurVibrancy": "decoration:blur:vibrancy",
        "desktop.appearance.blurNoise": "decoration:blur:noise",
        "desktop.appearance.blurContrast": "decoration:blur:contrast",
        "desktop.appearance.blurBrightness": "decoration:blur:brightness",
        "desktop.appearance.blurIgnoreOpacity": "decoration:blur:ignore_opacity",
        "desktop.appearance.blurNewOptimizations": "decoration:blur:new_optimizations",
        "desktop.appearance.shadowEnabled": "decoration:shadow:enabled",
        "desktop.appearance.shadowRange": "decoration:shadow:range",
        "desktop.appearance.shadowPower": "decoration:shadow:render_power",
        "desktop.appearance.shadowSharp": "decoration:shadow:sharp",
        "desktop.appearance.shadowScale": "decoration:shadow:scale",
        "desktop.appearance.animations": "animations:enabled"
    })

    // "int: 4" / "bool: true" / "float: 0.17" / "css gap data: 4 4 4 4" ->
    // the bare value the schema expects. An unrecognised shape is skipped
    // rather than guessed, so a row is never filled with an invented value.
    function parseOption(key, text) {
        var first = String(text).split("\n")[0] || "";
        var val = first.replace(/^\s*[a-z_ ]*:\s*/i, "").trim();
        if (val === "true") return true;
        if (val === "false") return false;
        if (/^-?[0-9]+$/.test(val)) return parseInt(val, 10);
        if (/^-?[0-9]*\.[0-9]+$/.test(val)) return parseFloat(val);
        var gap = val.match(/^(-?[0-9]+)[ ]/);
        if (gap) return parseInt(gap[1], 10);
        return undefined;
    }
    function ingest(key, text) {
        var v = pg.parseOption(key, text);
        if (v === undefined) return;
        var d = {};
        for (var k in pg.live) d[k] = pg.live[k];
        d[key] = v;
        pg.live = d;
    }

    // Every window-manager setting on one page: the neutral window rows the Hub
    // ships followed by the active provider's exclusives. effectiveRows is the
    // one source the rail gate reads too, so the page and the gate never diverge.
    // ProviderSchema.revision is read so the list rebuilds when the fetch lands.
    readonly property var rows: {
        ProviderSchema.revision;
        return pg.hub ? pg.hub.effectiveRows("windowmanager") : ProviderSchema.rowsFor("windowmanager");
    }

    // per-row visibility for the neutral rows: a dependent stays hidden until its
    // parent toggle is on. Provider rows carry their own `when` gate through the
    // sheet, so their keys are not named here and pass straight through.
    function gateOk(key, d) {
        switch (key) {
        case "desktop.appearance.dimStrength": return d["desktop.appearance.dimInactive"] === true;
        case "desktop.appearance.wobblyWindows": case "desktop.appearance.windowStyle": return d["desktop.appearance.animations"] === true;
        case "desktop.appearance.glowRange": case "desktop.appearance.glowColor": return d["desktop.appearance.glowEnabled"] === true;
        case "desktop.appearance.borderAngleSpeed": return d["desktop.appearance.animatedBorder"] === true;
        case "desktop.appearance.blurContrast": case "desktop.appearance.blurBrightness": case "desktop.appearance.blurSpecial":
        case "desktop.appearance.blurPopups": case "desktop.appearance.blurIgnoreOpacity": case "desktop.appearance.blurNewOptimizations":
        case "desktop.appearance.blurVibrancyDarkness":
            return d["desktop.appearance.blurEnabled"] === true;
        case "desktop.appearance.shadowSharp": case "desktop.appearance.shadowScale": case "desktop.appearance.shadowColor":
        case "desktop.appearance.shadowSpread": case "desktop.appearance.shadowOffsetX": case "desktop.appearance.shadowOffsetY":
            return d["desktop.appearance.shadowEnabled"] === true;
        }
        return true;
    }

    // draft/committed are flat maps off the store (dotted keys), the shape the
    // settings sheet reads. draft depends on hyprVal, so an edit rebuilds it.
    readonly property var draft: {
        var d = {};
        if (pg.hub)
            for (var i = 0; i < pg.rows.length; i++) { var k = pg.rows[i].key; if (k) d[k] = pg.hv(k); }
        return d;
    }
    readonly property var committed: {
        var d = {};
        if (pg.hub)
            for (var i = 0; i < pg.rows.length; i++) { var k = pg.rows[i].key; if (k) d[k] = pg.cv(k); }
        return d;
    }

    // the neutral gate applied; the shared renderer then drops caps and dead-key
    // rows, so the page and its gate read the same set the rail does.
    readonly property var settingsSchema: {
        var d = pg.draft, out = [];
        for (var i = 0; i < pg.rows.length; i++)
            if (pg.gateOk(pg.rows[i].key, d)) out.push(pg.rows[i]);
        return out;
    }

    // the cannot-do lines: the provider's unhonored reasons, deduped (many
    // keybinds collapse to one "no scratchpad" reason) and shown verbatim.
    readonly property var cannotDo: {
        ProviderSchema.revision;
        var seen = {}, out = [];
        var u = ProviderSchema.unhonored || [];
        for (var i = 0; i < u.length; i++) {
            var r = u[i] ? u[i].reason : "";
            if (r && !seen[r]) { seen[r] = true; out.push(r); }
        }
        return out;
    }

    // the rowless tab that carries the compositor itself
    readonly property string switchTab: I18n.tr("Compositor")

    function focusKey(k) { sp.focusKey(k) }
    SchemaPage {
        id: sp
        anchors.fill: parent
        schema: pg.settingsSchema
        draft: pg.draft
        defaults: pg.committed
        advanced: pg.hub ? pg.hub.advanced : false
        title: pg.pTitle
        eyebrow: pg.pEyebrow
        blurb: pg.pBlurb
        query: pg.hub ? pg.hub.query : ""
        onEdited: (k, v) => { if (pg.hub) pg.hub.hyprEdit(k, v); }
        onPickRequested: (r) => { if (pg.hub) pg.hub.openPick(r); }
        // Which compositor is running, how to change it, and what it cannot do
        // are about the compositor rather than about any group of settings, so
        // they get a tab of their own instead of repeating above every tab.
        tailTabs: [pg.switchTab]

        Column {
            width: parent.width
            spacing: Tokens.s5
            visible: sp.tab === pg.switchTab

            CompositorControl {
                id: wmPicker
                width: parent.width
                onChose: (target, current) => wmSheet.open(target, current)
            }

            // A rarely-touched list: folded, and its header says what it holds, so the
            // tab reads as a page rather than a wall of near-identical lines on
            // first sight. It opens in place when asked.
            SettingCard {
                id: cannotSec
                width: parent.width
                visible: pg.cannotDo.length > 0
                collapsible: true
                expanded: false
                title: I18n.tr("WHAT %1 CANNOT DO").arg(pg.pTitle.toUpperCase())
                summary: pg.cannotDo.length + " " + I18n.tr("SETTINGS")

                Column {
                    width: cannotSec.width
                    spacing: Tokens.s2

                    Text {
                        width: parent.width
                        leftPadding: Tokens.s4; rightPadding: Tokens.s4; topPadding: Tokens.s3
                        wrapMode: Text.WordWrap
                        text: I18n.tr("These settings have no equivalent here. They stay in your store and return if you switch back.")
                        color: Tokens.inkFaint
                        font.family: Tokens.ui
                        font.pixelSize: Tokens.fSmall
                        lineHeight: 1.3
                    }
                    Repeater {
                        model: pg.cannotDo
                        Row {
                            required property var modelData
                            width: cannotSec.width
                            spacing: Tokens.s2
                            bottomPadding: Tokens.s1
                            Text {
                                text: "\u00b7"
                                leftPadding: Tokens.s4
                                color: Tokens.inkFaint
                                font.family: Tokens.mono
                                font.pixelSize: Tokens.fSmall
                            }
                            Text {
                                width: cannotSec.width - Tokens.s6
                                wrapMode: Text.WordWrap
                                text: parent.modelData
                                color: Tokens.inkMuted
                                font.family: Tokens.ui
                                font.pixelSize: Tokens.fSmall
                                lineHeight: 1.3
                            }
                        }
                    }
                    Item { width: 1; height: Tokens.s2 }
                }
            }
        }
    }

    // the destructive switch confirmation, a full-page overlay; reload the picker
    // when it closes so the active row is fresh.
    CompositorSwitchSheet {
        id: wmSheet
        anchors.fill: parent
        onClosed: wmPicker.reload()
    }

    // ── the live read: one Process per option ────────────────────────────
    // Explicit fetchers rather than a factory: the map is fixed, a factory would
    // build the same set anyway, and this keeps the fetch visible in the file
    // (and lintable) like VisualsPage's fetchers.
    Component.onCompleted: {
        var keys = Object.keys(pg.liveOptions);
        for (var i = 0; i < keys.length; i++)
            liveFetch.createObject(pg, { key: keys[i], option: pg.liveOptions[keys[i]] }).running = true;
    }
    Component {
        id: liveFetch
        Process {
            property string key: ""
            property string option: ""
            command: ["hyprctl", "getoption", option]
            stdout: StdioCollector { onStreamFinished: pg.ingest(key, this.text) }
        }
    }
}
