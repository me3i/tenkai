package main

// Mei's runtime overrides: the Settings pages are practical without ever
// writing Hyprland config. Every change is
//
//   1. persisted under Mei's own config dir (XDG_CONFIG_HOME/mei), and
//   2. applied to the RUNNING compositor through `hyprctl eval`, the Lua door
//      the Visuals page and the daemon's boot re-apply already use.
//
// Nothing here writes ~/.config/hypr or ~/.config/ryoku. A Hyprland reload
// re-reads its own config and drops the runtime values; `mei-shell` re-applies
// these files at boot (`mei-hub overrides apply`, called from daemon.go), so a
// reload costs a restart, not the setting.
//
//	mei-hub overrides apply        re-apply every persisted override (daemon boot)
//
// Layout of the store:
//
//	mei/displays.json       {"layout": [OutputLayout], "profiles": {name: [OutputLayout]}}
//	mei/keybinds.json       {"binds": [{keys,action,value}], "rebinds": {default: chosen}}
//	mei/hypr-advanced.json  the desktop store's own map minus keybinds/rebinds
//
// Besides the user's own rows, every apply also binds Mei's default chords
// (meiDefaultBinds: screenshot, clipboard, overview) unless the user claimed
// the chord first. Those are the shipped bindings, not saved settings.

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"

	wm "ryoku-wm"
)

// meiConfigDir is Mei's own settings dir. In a Mei session XDG_CONFIG_HOME is
// .run/config, so this is .run/config/mei — never the owner's ~/.config/ryoku.
func meiConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		if home := os.Getenv("HOME"); home != "" {
			base = filepath.Join(home, ".config")
		} else {
			base = ".config"
		}
	}
	return filepath.Join(base, "mei")
}

func meiDisplaysPath() string { return filepath.Join(meiConfigDir(), "displays.json") }
func meiKeybindsPath() string { return filepath.Join(meiConfigDir(), "keybinds.json") }
func meiAdvancedPath() string { return filepath.Join(meiConfigDir(), "hypr-advanced.json") }

// hyprEval runs one Lua snippet through the running compositor. An empty script
// is a no-op. The error carries hyprctl's own message so a rejected key names
// itself instead of failing silently.
func hyprEval(script string) error {
	if strings.TrimSpace(script) == "" {
		return nil
	}
	out, err := exec.Command("hyprctl", "eval", script).CombinedOutput()
	if err != nil {
		return fmt.Errorf("hyprctl eval: %v (%s)", err, strings.TrimSpace(string(out)))
	}
	return nil
}

func writeJSONFile(path string, v any) error {
	return atomicWrite(path, mustJSON(v), 0o644)
}

// ── displays ───────────────────────────────────────────────────────────────

// displaysDoc is the active layout plus the named profiles, one file so a
// profile and the layout it came from can never disagree about where they live.
type displaysDoc struct {
	Layout   []wm.OutputLayout            `json:"layout"`
	Profiles map[string][]wm.OutputLayout `json:"profiles,omitempty"`
}

func readDisplaysDoc() displaysDoc {
	var d displaysDoc
	if b, err := os.ReadFile(meiDisplaysPath()); err == nil {
		_ = json.Unmarshal(b, &d)
	}
	if d.Profiles == nil {
		d.Profiles = map[string][]wm.OutputLayout{}
	}
	return d
}

// monitorsLua renders the layout as `hl.monitor` calls. Only fields the layout
// actually carries are emitted, so an untouched field keeps the compositor's
// own choice. Mirror/VRR/colour have no monitor-rule form here; they stay in
// displays.json for the page to read back.
func monitorsLua(layout []wm.OutputLayout) string {
	var lines []string
	for _, o := range layout {
		name := strings.TrimSpace(o.Name)
		if name == "" {
			continue
		}
		if !o.Enabled {
			lines = append(lines, fmt.Sprintf("hl.monitor({ output = %s, disabled = true })", luaStr(name)))
			continue
		}
		fields := []string{"output = " + luaStr(name)}
		if mode := strings.TrimSpace(o.Mode); mode != "" {
			fields = append(fields, "mode = "+luaStr(mode))
		}
		fields = append(fields, fmt.Sprintf("position = %s", luaStr(fmt.Sprintf("%dx%d", o.X, o.Y))))
		if o.Scale > 0 {
			fields = append(fields, "scale = "+strconv.FormatFloat(o.Scale, 'f', -1, 64))
		}
		if o.Transform != 0 {
			fields = append(fields, fmt.Sprintf("transform = %d", o.Transform))
		}
		lines = append(lines, "hl.monitor({ "+strings.Join(fields, ", ")+" })")
	}
	return strings.Join(lines, "\n")
}

// applyDisplays persists (when asked) and applies the layout live.
func applyDisplays(layout []wm.OutputLayout, persist bool) error {
	if persist {
		d := readDisplaysDoc()
		d.Layout = layout
		if err := writeJSONFile(meiDisplaysPath(), d); err != nil {
			return err
		}
	}
	if err := hyprEval(monitorsLua(layout)); err != nil {
		return err
	}
	return printJSON(map[string]any{"ok": true, "monitors": len(layout)})
}

// ── keybinds ───────────────────────────────────────────────────────────────

type meiBind struct {
	Keys   string `json:"keys"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

type meiKeybinds struct {
	Binds []meiBind `json:"binds"`
	// Rebinds maps a shipped default chord to the chord the user chose. The
	// shipped chord's own dispatcher is read back from the live bind table, so
	// a rebind keeps doing what the shipped bind did.
	Rebinds map[string]string `json:"rebinds,omitempty"`
}

func readMeiKeybinds() meiKeybinds {
	var k meiKeybinds
	if b, err := os.ReadFile(meiKeybindsPath()); err == nil {
		_ = json.Unmarshal(b, &k)
	}
	if k.Rebinds == nil {
		k.Rebinds = map[string]string{}
	}
	return k
}

// bindDsp maps the four actions the Keybinds page offers onto the same hl.dsp
// forms the import layer generates (import_parse.go), so a bound action is
// exactly what a hand-written config would have produced.
func bindDsp(action, value string) (string, bool) {
	switch strings.TrimSpace(action) {
	case "exec":
		if strings.TrimSpace(value) == "" {
			return "", false
		}
		return "hl.dsp.exec_cmd(" + luaStr(value) + ")", true
	case "close":
		return "hl.dsp.window.close()", true
	case "fullscreen":
		return "hl.dsp.window.fullscreen()", true
	case "togglefloating":
		return `hl.dsp.window.float({ action = "toggle" })`, true
	case "global":
		// A shortcut the shell itself registers (mei:overview, mei:clipboard,
		// ...). Same form the shipped Ryoku config uses for its own surfaces.
		if strings.TrimSpace(value) == "" {
			return "", false
		}
		return "hl.dsp.global(" + luaStr(value) + ")", true
	}
	return "", false
}

// keybindsLua renders the custom binds plus every rebind that could be resolved
// into a dispatcher. Unresolvable rows are reported, never guessed.
func keybindsLua(k meiKeybinds) (string, []string) {
	var lines, skipped []string
	for _, b := range k.Binds {
		keys := strings.TrimSpace(b.Keys)
		if keys == "" {
			continue
		}
		dsp, ok := bindDsp(b.Action, b.Value)
		if !ok {
			skipped = append(skipped, b.Keys+" ("+b.Action+")")
			continue
		}
		lines = append(lines, "hl.bind("+luaStr(keys)+", "+dsp+")")
	}
	defs := make([]string, 0, len(k.Rebinds))
	for def := range k.Rebinds {
		defs = append(defs, def)
	}
	sort.Strings(defs)
	for _, def := range defs {
		chosen := strings.TrimSpace(k.Rebinds[def])
		if chosen == "" || chosen == def {
			continue
		}
		dsp, ok := liveDspForChord(def)
		if !ok {
			skipped = append(skipped, def+" -> "+chosen)
			continue
		}
		lines = append(lines, "hl.bind("+luaStr(chosen)+", "+dsp+")")
	}
	return strings.Join(lines, "\n"), skipped
}

// unbindLua removes the chords Mei applied last time, so a re-apply or a second
// Save replaces rather than duplicates. `hl.unbind` is the Lua IPC's own verb
// (verified in the nested session: it drops every bind on that chord), and the
// shipped keyword spelling does not exist here. A chord the shipped config also
// uses loses that bind too, which is what shadowing it means.
func unbindLua(k meiKeybinds) string {
	seen := map[string]bool{}
	var chords []string
	add := func(c string) {
		c = strings.TrimSpace(c)
		if c == "" || seen[c] {
			return
		}
		seen[c] = true
		chords = append(chords, c)
	}
	for _, b := range k.Binds {
		add(b.Keys)
	}
	for _, c := range k.Rebinds {
		add(c)
	}
	sort.Strings(chords)
	lines := make([]string, 0, len(chords))
	for _, c := range chords {
		lines = append(lines, "hl.unbind("+luaStr(c)+")")
	}
	return strings.Join(lines, "\n")
}

// meiDefaultBinds is the chord set Mei binds for itself, matching the chords the
// owner's Ryoku config uses (modules/binds.lua: Super+V clipboard, Super+Tab
// overview, Print / Super+Shift+S screenshot) plus Super+P for the wallpaper
// picker the qsbar hosts in-shell. They are not saved into keybinds.json: they
// are the shipped defaults the Settings page edits, so a user bind on the same
// chord always wins (see defaultBindsLua).
var meiDefaultBinds = []meiBind{
	{Keys: "PRINT", Action: "exec", Value: "mei-screenshot full"},
	{Keys: "SUPER + SHIFT + S", Action: "exec", Value: "mei-screenshot region"},
	{Keys: "SUPER + V", Action: "global", Value: "mei:clipboard"},
	{Keys: "SUPER + P", Action: "global", Value: "mei:wallpaper-menu"},
	{Keys: "SUPER + TAB", Action: "global", Value: "mei:overview"},
	{Keys: "SUPER + ALT + TAB", Action: "global", Value: "mei:overview"},
}

// defaultBindsLua renders Mei's own chords, skipping any chord the user already
// claimed with a bind or a rebind. Every chord is unbound first: the shipped
// config binds the same keys to ryoku:* globals, which no longer resolve here,
// and two binds on one chord would both fire.
func defaultBindsLua(user meiKeybinds) string {
	taken := map[string]bool{}
	for _, b := range user.Binds {
		taken[strings.TrimSpace(b.Keys)] = true
	}
	for def, chosen := range user.Rebinds {
		taken[strings.TrimSpace(def)] = true
		taken[strings.TrimSpace(chosen)] = true
	}
	var lines []string
	for _, b := range meiDefaultBinds {
		if taken[b.Keys] {
			continue
		}
		dsp, ok := bindDsp(b.Action, b.Value)
		if !ok {
			continue
		}
		lines = append(lines, "hl.unbind("+luaStr(b.Keys)+")", "hl.bind("+luaStr(b.Keys)+", "+dsp+")")
	}
	return strings.Join(lines, "\n")
}

// liveBind is the slice of `hyprctl binds -j` a rebind needs.
type liveBind struct {
	ModMask    int    `json:"modmask"`
	Key        string `json:"key"`
	Dispatcher string `json:"dispatcher"`
	Arg        string `json:"arg"`
}

var modBits = map[string]int{
	"SHIFT": 1, "CAPS": 2, "CTRL": 4, "CONTROL": 4, "ALT": 8, "MOD1": 8,
	"MOD2": 16, "MOD3": 32, "SUPER": 64, "WIN": 64, "MOD4": 64, "MOD5": 128,
}

// chordModsKey splits "SUPER + SHIFT + Q" into the compositor's modmask and key
// token. ok is false for a chord with no key.
func chordModsKey(chord string) (int, string, bool) {
	parts := strings.Split(chord, "+")
	mask, key := 0, ""
	for _, p := range parts {
		t := strings.ToUpper(strings.TrimSpace(p))
		if t == "" {
			continue
		}
		if bit, ok := modBits[t]; ok {
			mask |= bit
		} else {
			key = t
		}
	}
	if key == "" {
		return 0, "", false
	}
	return mask, key, true
}

// liveDspForChord finds the dispatcher the compositor currently runs for a
// chord and renders it as an hl.dsp expression. This is what lets a rebind keep
// the shipped bind's behaviour without the Hub re-deriving it from the
// catalogue.
func liveDspForChord(chord string) (string, bool) {
	mask, key, ok := chordModsKey(chord)
	if !ok {
		return "", false
	}
	out, err := exec.Command("hyprctl", "binds", "-j").Output()
	if err != nil {
		return "", false
	}
	var binds []liveBind
	if err := json.Unmarshal(out, &binds); err != nil {
		return "", false
	}
	for _, b := range binds {
		if b.ModMask != mask || !strings.EqualFold(b.Key, key) {
			continue
		}
		return dispatcherToDsp(b.Dispatcher, b.Arg)
	}
	return "", false
}

func applyKeybinds(k meiKeybinds, persist bool) error {
	// What Mei applied last time, before the file is replaced: those chords are
	// unbound first so this apply replaces them instead of stacking a second copy.
	prev := readMeiKeybinds()
	if persist {
		if err := writeJSONFile(meiKeybindsPath(), k); err != nil {
			return err
		}
	}
	script, skipped := keybindsLua(k)
	script = strings.TrimSpace(strings.Join([]string{unbindLua(prev), script, defaultBindsLua(k)}, "\n"))
	if err := hyprEval(script); err != nil {
		return err
	}
	if len(skipped) > 0 {
		fmt.Fprintf(os.Stderr, "keybinds: not applied: %s\n", strings.Join(skipped, ", "))
	}
	return printJSON(map[string]any{"ok": true, "applied": len(k.Binds), "skipped": skipped})
}

// ── advanced window-manager settings ───────────────────────────────────────

// advancedOptions is the dotted store key -> compositor option path, the same
// table WindowManagerPage reads with `hyprctl getoption`. Keeping it here is
// what makes a save write the value the page was showing.
var advancedOptions = map[string]string{
	"desktop.appearance.gapsIn":               "general:gaps_in",
	"desktop.appearance.gapsOut":              "general:gaps_out",
	"desktop.appearance.gapsWorkspaces":       "general:gaps_workspaces",
	"desktop.appearance.borderSize":           "general:border_size",
	"desktop.appearance.resizeOnBorder":       "general:resize_on_border",
	"desktop.appearance.snapEnabled":          "general:snap:enabled",
	"desktop.appearance.extendBorderGrab":     "general:extend_border_grab_area",
	"desktop.appearance.hoverIconOnBorder":    "general:hover_icon_on_border",
	"desktop.appearance.noFocusFallback":      "general:no_focus_fallback",
	"desktop.appearance.resizeCorner":         "general:resize_corner",
	"desktop.appearance.rounding":             "decoration:rounding",
	"desktop.appearance.roundingPower":        "decoration:rounding_power",
	"desktop.appearance.activeOpacity":        "decoration:active_opacity",
	"desktop.appearance.inactiveOpacity":      "decoration:inactive_opacity",
	"desktop.appearance.fullscreenOpacity":    "decoration:fullscreen_opacity",
	"desktop.appearance.dimInactive":          "decoration:dim_inactive",
	"desktop.appearance.dimStrength":          "decoration:dim_strength",
	"desktop.appearance.dimSpecial":           "decoration:dim_special",
	"desktop.appearance.dimAround":            "decoration:dim_around",
	"desktop.appearance.dimModal":             "decoration:dim_modal",
	"desktop.appearance.borderPartOfWindow":   "decoration:border_part_of_window",
	"desktop.appearance.blurEnabled":          "decoration:blur:enabled",
	"desktop.appearance.blurSize":             "decoration:blur:size",
	"desktop.appearance.blurPasses":           "decoration:blur:passes",
	"desktop.appearance.blurXray":             "decoration:blur:xray",
	"desktop.appearance.blurVibrancy":         "decoration:blur:vibrancy",
	"desktop.appearance.blurNoise":            "decoration:blur:noise",
	"desktop.appearance.blurContrast":         "decoration:blur:contrast",
	"desktop.appearance.blurBrightness":       "decoration:blur:brightness",
	"desktop.appearance.blurIgnoreOpacity":    "decoration:blur:ignore_opacity",
	"desktop.appearance.blurNewOptimizations": "decoration:blur:new_optimizations",
	"desktop.appearance.shadowEnabled":        "decoration:shadow:enabled",
	"desktop.appearance.shadowRange":          "decoration:shadow:range",
	"desktop.appearance.shadowPower":          "decoration:shadow:render_power",
	"desktop.appearance.shadowSharp":          "decoration:shadow:sharp",
	"desktop.appearance.shadowScale":          "decoration:shadow:scale",
	"desktop.appearance.animations":           "animations:enabled",
}

// flatten walks a nested store map into dotted paths. Arrays are leaves (the
// keybind arrays are handled separately, never here).
func flatten(prefix string, v any, out map[string]any) {
	if m, ok := v.(map[string]any); ok {
		for k, c := range m {
			p := k
			if prefix != "" {
				p = prefix + "." + k
			}
			flatten(p, c, out)
		}
		return
	}
	if prefix != "" {
		out[prefix] = v
	}
}

func luaValue(v any) (string, bool) {
	switch t := v.(type) {
	case bool:
		if t {
			return "true", true
		}
		return "false", true
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10), true
		}
		return strconv.FormatFloat(t, 'f', -1, 64), true
	case int:
		return strconv.Itoa(t), true
	case string:
		return luaStr(t), true
	}
	return "", false
}

// advancedLua renders the store's appearance keys as one hl.config call per
// top-level section, so a key this compositor rejects costs that section, not
// the whole save. Keys that are not compositor options stay in the file only.
func advancedLua(store map[string]any) ([]string, int) {
	flat := map[string]any{}
	flatten("", store, flat)
	groups := map[string][]string{} // section -> "sub = { ... }" or "key = value"
	applied := 0
	for key, raw := range flat {
		opt, ok := advancedOptions[key]
		if !ok {
			continue
		}
		val, ok := luaValue(raw)
		if !ok {
			continue
		}
		parts := strings.Split(opt, ":")
		if len(parts) < 2 {
			continue
		}
		// nest everything after the section
		expr := parts[len(parts)-1] + " = " + val
		for i := len(parts) - 2; i >= 1; i-- {
			expr = parts[i] + " = { " + expr + " }"
		}
		groups[parts[0]] = append(groups[parts[0]], expr)
		applied++
	}
	secs := make([]string, 0, len(groups))
	for s := range groups {
		secs = append(secs, s)
	}
	sort.Strings(secs)
	out := make([]string, 0, len(secs))
	for _, s := range secs {
		entries := groups[s]
		sort.Strings(entries)
		out = append(out, "hl.config({ "+s+" = { "+strings.Join(entries, ", ")+" } })")
	}
	return out, applied
}

func applyAdvanced(store map[string]any, persist bool) error {
	if persist {
		if err := writeJSONFile(meiAdvancedPath(), store); err != nil {
			return err
		}
	}
	scripts, n := advancedLua(store)
	var failed []string
	for _, s := range scripts {
		if err := hyprEval(s); err != nil {
			failed = append(failed, err.Error())
		}
	}
	if len(failed) > 0 {
		fmt.Fprintf(os.Stderr, "advanced: %d section(s) rejected: %s\n", len(failed), strings.Join(failed, "; "))
	}
	return printJSON(map[string]any{"ok": len(failed) == 0, "applied": n, "errors": failed})
}

// ── the desktop store path ─────────────────────────────────────────────────

// splitDesktopDraft pulls the keybinds out of the desktop draft the Hub sends
// and returns the rest (the appearance tree) unchanged.
func splitDesktopDraft(m map[string]any) (meiKeybinds, map[string]any) {
	d := childMap(m, "desktop")
	k := meiKeybinds{Binds: []meiBind{}, Rebinds: map[string]string{}}
	if rows, ok := d["keybinds"].([]any); ok {
		for _, r := range rows {
			row, ok := r.(map[string]any)
			if !ok {
				continue
			}
			k.Binds = append(k.Binds, meiBind{
				Keys:   strOf(row["keys"]),
				Action: strOf(row["action"]),
				Value:  strOf(row["value"]),
			})
		}
	}
	if rb, ok := d["keybindRebinds"].(map[string]any); ok {
		for a, b := range rb {
			if s := strOf(b); s != "" {
				k.Rebinds[a] = s
			}
		}
	}
	rest := deepCopyMap(m)
	rd := childMap(rest, "desktop")
	delete(rd, "keybinds")
	delete(rd, "keybindRebinds")
	return k, rest
}

func strOf(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case nil:
		return ""
	case float64:
		if t == float64(int64(t)) {
			return strconv.FormatInt(int64(t), 10)
		}
		return strconv.FormatFloat(t, 'f', -1, 64)
	case bool:
		if t {
			return "true"
		}
		return "false"
	}
	return ""
}

func deepCopyMap(m map[string]any) map[string]any {
	b, err := json.Marshal(m)
	if err != nil {
		return map[string]any{}
	}
	var out map[string]any
	if json.Unmarshal(b, &out) != nil || out == nil {
		return map[string]any{}
	}
	return out
}

// ── the verbs ──────────────────────────────────────────────────────────────

// applyMeiDesktop persists and applies a desktop draft (save), or only applies
// it (preview). No compositor config file is ever written.
func applyMeiDesktop(raw string, persist bool) error {
	var m map[string]any
	if err := json.Unmarshal([]byte(raw), &m); err != nil {
		return fmt.Errorf("parse desktop JSON: %w", err)
	}
	if m == nil {
		return fmt.Errorf("desktop settings must be a JSON object")
	}
	k, rest := splitDesktopDraft(m)
	if err := applyKeybinds(k, persist); err != nil {
		return err
	}
	return applyAdvanced(rest, persist)
}

// restoreMeiDesktop puts the compositor back on what the files say, which is
// what Revert and an unsaved quit mean.
func restoreMeiDesktop() error {
	k := readMeiKeybinds()
	adv := readJSONMap(meiAdvancedPath())
	if err := applyKeybinds(k, false); err != nil {
		return err
	}
	return applyAdvanced(adv, false)
}

// meiDesktopStore is what `desktop get` returns: the provider's defaults with
// Mei's persisted advanced map and keybinds merged over them, so the pages open
// on the state that was actually saved.
func meiDesktopStore() map[string]any {
	base := map[string]any{}
	if b, err := desktopClient().Defaults(); err == nil {
		_ = json.Unmarshal(b, &base)
	}
	merged := jsonMerge(base, readJSONMap(meiAdvancedPath()))
	d := childMap(merged, "desktop")
	k := readMeiKeybinds()
	rows := make([]any, 0, len(k.Binds))
	for _, b := range k.Binds {
		rows = append(rows, map[string]any{"keys": b.Keys, "action": b.Action, "value": b.Value, "release": false})
	}
	d["keybinds"] = rows
	rb := map[string]any{}
	for a, b := range k.Rebinds {
		rb[a] = b
	}
	d["keybindRebinds"] = rb
	return merged
}

// runOverrides is the `overrides` verb: the daemon calls `mei-hub overrides
// apply` once at boot, so the boot hook and the Settings save share one
// implementation instead of two drifting copies.
func runOverrides(args []string) error {
	if len(args) == 0 || args[0] != "apply" {
		return fmt.Errorf("overrides needs apply")
	}
	return reapplyMeiOverrides()
}

// reapplyMeiOverrides is the daemon's boot hook body: every override, in the
// order the compositor needs them (monitors, then config, then binds).
func reapplyMeiOverrides() error {
	d := readDisplaysDoc()
	if len(d.Layout) > 0 {
		if err := hyprEval(monitorsLua(d.Layout)); err != nil {
			fmt.Fprintf(os.Stderr, "overrides: displays: %v\n", err)
		}
	}
	if adv := readJSONMap(meiAdvancedPath()); len(adv) > 0 {
		scripts, _ := advancedLua(adv)
		for _, s := range scripts {
			if err := hyprEval(s); err != nil {
				fmt.Fprintf(os.Stderr, "overrides: advanced: %v\n", err)
			}
		}
	}
	k := readMeiKeybinds()
	script, skipped := keybindsLua(k)
	script = strings.TrimSpace(strings.Join([]string{unbindLua(k), script, defaultBindsLua(k)}, "\n"))
	if err := hyprEval(script); err != nil {
		fmt.Fprintf(os.Stderr, "overrides: keybinds: %v\n", err)
	}
	if len(skipped) > 0 {
		fmt.Fprintf(os.Stderr, "overrides: keybinds not applied: %s\n", strings.Join(skipped, ", "))
	}
	return nil
}
