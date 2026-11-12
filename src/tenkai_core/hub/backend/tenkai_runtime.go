package main

// Tenkai's runtime overrides: the Settings pages are practical without ever
// writing Hyprland config. Every change is
//
//   1. persisted under Tenkai's own config dir (XDG_CONFIG_HOME/tenkai), and
//   2. applied to the RUNNING compositor through `hyprctl eval`, the Lua door
//      the Visuals page and the daemon's boot re-apply already use.
//
// Nothing here writes ~/.config/hypr or ~/.config/ryoku. A Hyprland reload
// re-reads its own config and drops the runtime values; `tenkai-shell` re-applies
// these files at boot (`tenkai-hub overrides apply`, called from daemon.go), so a
// reload costs a restart, not the setting.
//
//	tenkai-hub overrides apply        re-apply every persisted override (daemon boot)
//
// Layout of the store:
//
//	tenkai/displays.json       {"layout": [OutputLayout], "profiles": {name: [OutputLayout]}}
//	tenkai/keybinds.json       {"binds": [{keys,action,value}], "rebinds": {default: chosen}}
//	tenkai/hypr-advanced.json  the desktop store's own map minus keybinds/rebinds
//
// Besides the user's own rows, every apply also binds Tenkai's default chords
// (tenkaiDefaultBinds: screenshot, clipboard, overview) unless the user claimed
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

	wm "tenkai-wm"
)

// tenkaiConfigDir is Tenkai's own settings dir. In a Tenkai session XDG_CONFIG_HOME is
// .run/config, so this is .run/config/tenkai — never the owner's ~/.config/ryoku.
func tenkaiConfigDir() string {
	base := os.Getenv("XDG_CONFIG_HOME")
	if base == "" {
		if home := os.Getenv("HOME"); home != "" {
			base = filepath.Join(home, ".config")
		} else {
			base = ".config"
		}
	}
	return filepath.Join(base, "tenkai")
}

func tenkaiDisplaysPath() string { return filepath.Join(tenkaiConfigDir(), "displays.json") }
func tenkaiKeybindsPath() string { return filepath.Join(tenkaiConfigDir(), "keybinds.json") }
func tenkaiAdvancedPath() string { return filepath.Join(tenkaiConfigDir(), "hypr-advanced.json") }

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
	if b, err := os.ReadFile(tenkaiDisplaysPath()); err == nil {
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
		if err := writeJSONFile(tenkaiDisplaysPath(), d); err != nil {
			return err
		}
	}
	if err := hyprEval(monitorsLua(layout)); err != nil {
		return err
	}
	return printJSON(map[string]any{"ok": true, "monitors": len(layout)})
}

// ── keybinds ───────────────────────────────────────────────────────────────

type tenkaiBind struct {
	Keys   string `json:"keys"`
	Action string `json:"action"`
	Value  string `json:"value"`
}

type tenkaiKeybinds struct {
	Binds []tenkaiBind `json:"binds"`
	// Rebinds maps a shipped default chord to the chord the user chose. The
	// shipped chord's own dispatcher is read back from the live bind table, so
	// a rebind keeps doing what the shipped bind did.
	Rebinds map[string]string `json:"rebinds,omitempty"`
}

func readTenkaiKeybinds() tenkaiKeybinds {
	var k tenkaiKeybinds
	if b, err := os.ReadFile(tenkaiKeybindsPath()); err == nil {
		_ = json.Unmarshal(b, &k)
	}
	if k.Rebinds == nil {
		k.Rebinds = map[string]string{}
	}
	return k
}

// bindDsp maps the four actions the Keybinds page offers onto the same hl.dsp
// forms the config-import layer would generate, so a bound action is
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
		// A shortcut the shell itself registers (tenkai:overview, tenkai:clipboard,
		// ...). Same form the shipped Tenkai config uses for its own surfaces.
		if strings.TrimSpace(value) == "" {
			return "", false
		}
		return "hl.dsp.global(" + luaStr(value) + ")", true
	}
	return "", false
}

// keybindsLua renders the custom binds plus every rebind that could be resolved
// into a dispatcher. Unresolvable rows are reported, never guessed.
func keybindsLua(k tenkaiKeybinds) (string, []string) {
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

// unbindLua removes the chords Tenkai applied last time, so a re-apply or a second
// Save replaces rather than duplicates. `hl.unbind` is the Lua IPC's own verb
// (verified in the nested session: it drops every bind on that chord), and the
// shipped keyword spelling does not exist here. A chord the shipped config also
// uses loses that bind too, which is what shadowing it means.
func unbindLua(k tenkaiKeybinds) string {
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

// tenkaiDefaultBinds is the chord set Tenkai binds for itself, matching the chords the
// owner's Tenkai config uses (modules/binds.lua: Super+V clipboard, Super+Tab
// overview, Print / Super+Shift+S screenshot) plus Super+P for the wallpaper
// picker the qsbar hosts in-shell. They are not saved into keybinds.json: they
// are the shipped defaults the Settings page edits, so a user bind on the same
// chord always wins (see defaultBindsLua).
var tenkaiDefaultBinds = []tenkaiBind{
	{Keys: "PRINT", Action: "exec", Value: "tenkai-screenshot full"},
	{Keys: "SUPER + SHIFT + S", Action: "exec", Value: "tenkai-screenshot region"},
	{Keys: "SUPER + V", Action: "global", Value: "tenkai:clipboard"},
	{Keys: "SUPER + P", Action: "global", Value: "tenkai:wallpaper-menu"},
	{Keys: "SUPER + TAB", Action: "global", Value: "tenkai:overview"},
	{Keys: "SUPER + ALT + TAB", Action: "global", Value: "tenkai:overview"},
}

// defaultBindsLua renders Tenkai's own chords, skipping any chord the user already
// claimed with a bind or a rebind. Every chord is unbound first: the shipped
// config binds the same keys to ryoku:* globals, which no longer resolve here,
// and two binds on one chord would both fire.
func defaultBindsLua(user tenkaiKeybinds) string {
	taken := map[string]bool{}
	for _, b := range user.Binds {
		taken[strings.TrimSpace(b.Keys)] = true
	}
	for def, chosen := range user.Rebinds {
		taken[strings.TrimSpace(def)] = true
		taken[strings.TrimSpace(chosen)] = true
	}
	var lines []string
	for _, b := range tenkaiDefaultBinds {
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

func applyKeybinds(k tenkaiKeybinds, persist bool) error {
	// What Tenkai applied last time, before the file is replaced: those chords are
	// unbound first so this apply replaces them instead of stacking a second copy.
	prev := readTenkaiKeybinds()
	if persist {
		if err := writeJSONFile(tenkaiKeybindsPath(), k); err != nil {
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
	"desktop.appearance.shadowColor":          "decoration:shadow:color",
	"desktop.appearance.blurSpecial":          "decoration:blur:special",
	"desktop.appearance.blurPopups":           "decoration:blur:popups",
	"desktop.appearance.blurVibrancyDarkness": "decoration:blur:vibrancy_darkness",
	"desktop.appearance.activeBorder":         "general:col.active_border",
	"desktop.appearance.inactiveBorder":       "general:col.inactive_border",
	"desktop.appearance.layout":               "general:layout",
	"desktop.appearance.animations":           "animations:enabled",
}

// advancedColors are the keys whose value is a #rrggbb colour: Hyprland's Lua
// API wants rgb(rrggbb), not the hex string the pickers store.
var advancedColors = map[string]bool{
	"desktop.appearance.activeBorder":   true,
	"desktop.appearance.inactiveBorder": true,
	"desktop.appearance.shadowColor":    true,
}

// advancedPaletteBorders are the two keys the provider leaves alone while the
// wallpaper palette owns the border: writing a fixed colour would pin the
// border the user asked to follow the theme.
var advancedPaletteBorders = map[string]bool{
	"desktop.appearance.activeBorder":   true,
	"desktop.appearance.inactiveBorder": true,
}

// luaRGB turns a stored #rrggbb (or #aarrggbb) colour into Hyprland's Lua
// colour form; anything already in rgb()/rgba() form is passed through.
func luaRGB(hex string) string {
	h := strings.TrimSpace(hex)
	if strings.HasPrefix(h, "rgb") {
		return h
	}
	h = strings.TrimPrefix(h, "#")
	if h == "" {
		return "rgb(00000000)"
	}
	return "rgb(" + h + ")"
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
	paletteWins := false
	if v, ok := flat["desktop.appearance.borderFollowsPalette"].(bool); ok {
		paletteWins = v
	}
	// One tree per section, rendered once. A flat "sub = {...}" per key would
	// repeat the same nested table (blur, shadow, snap) and Lua keeps only the
	// last one -- which silently dropped every neighbour option, e.g. all blur
	// keys but one.
	trees := map[string]*luaTree{} // section -> tree
	applied := 0
	for key, raw := range flat {
		opt, ok := advancedOptions[key]
		if !ok {
			continue
		}
		if paletteWins && advancedPaletteBorders[key] {
			continue
		}
		if advancedColors[key] {
			if hex, ok := raw.(string); ok {
				raw = luaRGB(hex)
			}
		}
		val, ok := luaValue(raw)
		if !ok {
			continue
		}
		parts := strings.Split(opt, ":")
		if len(parts) < 2 {
			continue
		}
		t, ok := trees[parts[0]]
		if !ok {
			t = newLuaTree()
			trees[parts[0]] = t
		}
		t.set(parts[1:], val)
		applied++
	}
	secs := make([]string, 0, len(trees))
	for s := range trees {
		secs = append(secs, s)
	}
	sort.Strings(secs)
	out := make([]string, 0, len(secs))
	for _, s := range secs {
		out = append(out, "hl.config({ "+s+" = "+trees[s].render()+" })")
	}
	return out, applied
}

// luaTree is the nested-table builder behind advancedLua: one leaf per option,
// siblings merged under a single key instead of repeated table constructors.
type luaTree struct {
	leaves map[string]string
	kids   map[string]*luaTree
}

func newLuaTree() *luaTree {
	return &luaTree{leaves: map[string]string{}, kids: map[string]*luaTree{}}
}

func (t *luaTree) set(path []string, expr string) {
	if len(path) == 1 {
		t.leaves[path[0]] = expr
		return
	}
	kid, ok := t.kids[path[0]]
	if !ok {
		kid = newLuaTree()
		t.kids[path[0]] = kid
	}
	kid.set(path[1:], expr)
}

func (t *luaTree) render() string {
	keys := make([]string, 0, len(t.leaves)+len(t.kids))
	for k := range t.leaves {
		keys = append(keys, k)
	}
	for k := range t.kids {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, 0, len(keys))
	for _, k := range keys {
		if kid, ok := t.kids[k]; ok {
			parts = append(parts, k+" = "+kid.render())
			continue
		}
		parts = append(parts, k+" = "+t.leaves[k])
	}
	return "{ " + strings.Join(parts, ", ") + " }"
}

func applyAdvanced(store map[string]any, persist bool) error {
	if persist {
		if err := writeJSONFile(tenkaiAdvancedPath(), store); err != nil {
			return err
		}
	}
	scripts, n := advancedLua(store)
	if persist {
		if err := writeTenkaiSettingsDropIn(scripts); err != nil {
			fmt.Fprintf(os.Stderr, "advanced: drop-in: %v\n", err)
		}
	}
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

// writeTenkaiSettingsDropIn renders the same live scripts into the drop-in the
// shipped hyprland.lua optional()s, so a saved setting is loaded by the
// compositor at boot even before the daemon re-applies the store. Only this
// Tenkai-owned file is written: the user's hand-edited modules (binds.lua,
// decoration.lua, monitors.lua, user.lua) are never touched. The previous
// content is kept as tenkai_settings.lua.bak before an overwrite.
func writeTenkaiSettingsDropIn(scripts []string) error {
	if len(scripts) == 0 {
		return nil
	}
	path := filepath.Join(hyprConfigDir(), "tenkai_settings.lua")
	body := "-- Written by Tenkai's Settings (tenkai-hub) on every Save. Loaded by\n" +
		"-- hyprland.lua through optional(\"tenkai_settings\"). Do not edit: put your\n" +
		"-- own changes in ~/.config/hypr/user.lua, which loads last and wins.\n\n" +
		strings.Join(scripts, "\n") + "\n"
	if old, err := os.ReadFile(path); err == nil && string(old) != body {
		if err := os.WriteFile(path+".bak", old, 0o644); err != nil {
			return err
		}
	}
	return atomicWrite(path, []byte(body), 0o644)
}

// applyTenkaiDesktopKey is the shell's `setSetting` for one compositor key: it
// merges a single dotted store leaf into the saved map, re-applies the whole map
// live (so the compositor is authoritative on every key it holds) and rewrites
// the drop-in. A key this compositor has no option for is stored and reported.
func applyTenkaiDesktopKey(path, rawValue string) error {
	var v any
	if err := json.Unmarshal([]byte(rawValue), &v); err != nil {
		return fmt.Errorf("value must be JSON: %w", err)
	}
	if _, ok := advancedOptions[path]; !ok {
		return fmt.Errorf("%s has no compositor option", path)
	}
	store := readJSONMap(tenkaiAdvancedPath())
	segs := strings.Split(path, ".")
	cur := store
	for i := 0; i < len(segs)-1; i++ {
		next, ok := cur[segs[i]].(map[string]any)
		if !ok {
			next = map[string]any{}
			cur[segs[i]] = next
		}
		cur = next
	}
	cur[segs[len(segs)-1]] = v
	return applyAdvanced(store, true)
}

// ── the desktop store path ─────────────────────────────────────────────────

// splitDesktopDraft pulls the keybinds out of the desktop draft the Hub sends
// and returns the rest (the appearance tree) unchanged.
func splitDesktopDraft(m map[string]any) (tenkaiKeybinds, map[string]any) {
	d := childMap(m, "desktop")
	k := tenkaiKeybinds{Binds: []tenkaiBind{}, Rebinds: map[string]string{}}
	if rows, ok := d["keybinds"].([]any); ok {
		for _, r := range rows {
			row, ok := r.(map[string]any)
			if !ok {
				continue
			}
			k.Binds = append(k.Binds, tenkaiBind{
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

// applyTenkaiDesktop persists and applies a desktop draft (save), or only applies
// it (preview). No compositor config file is ever written.
func applyTenkaiDesktop(raw string, persist bool) error {
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

// restoreTenkaiDesktop puts the compositor back on what the files say, which is
// what Revert and an unsaved quit mean.
func restoreTenkaiDesktop() error {
	k := readTenkaiKeybinds()
	adv := readJSONMap(tenkaiAdvancedPath())
	if err := applyKeybinds(k, false); err != nil {
		return err
	}
	return applyAdvanced(adv, false)
}

// tenkaiDesktopStore is what `desktop get` returns: the provider's defaults with
// Tenkai's persisted advanced map and keybinds merged over them, so the pages open
// on the state that was actually saved.
func tenkaiDesktopStore() map[string]any {
	base := map[string]any{}
	if b, err := desktopClient().Defaults(); err == nil {
		_ = json.Unmarshal(b, &base)
	}
	merged := jsonMerge(base, readJSONMap(tenkaiAdvancedPath()))
	d := childMap(merged, "desktop")
	k := readTenkaiKeybinds()
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

// runOverrides is the `overrides` verb: the daemon calls `tenkai-hub overrides
// apply` once at boot, so the boot hook and the Settings save share one
// implementation instead of two drifting copies.
func runOverrides(args []string) error {
	if len(args) == 0 || args[0] != "apply" {
		return fmt.Errorf("overrides needs apply")
	}
	return reapplyTenkaiOverrides()
}

// reapplyTenkaiOverrides is the daemon's boot hook body: every override, in the
// order the compositor needs them (monitors, then config, then binds).
func reapplyTenkaiOverrides() error {
	d := readDisplaysDoc()
	if len(d.Layout) > 0 {
		if err := hyprEval(monitorsLua(d.Layout)); err != nil {
			fmt.Fprintf(os.Stderr, "overrides: displays: %v\n", err)
		}
	}
	if adv := readJSONMap(tenkaiAdvancedPath()); len(adv) > 0 {
		scripts, _ := advancedLua(adv)
		for _, s := range scripts {
			if err := hyprEval(s); err != nil {
				fmt.Fprintf(os.Stderr, "overrides: advanced: %v\n", err)
			}
		}
	}
	k := readTenkaiKeybinds()
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
