package main

import (
	"strings"
	"testing"

	wm "ryoku-wm"
)

// The runtime-override builders are the whole "practical without writing
// Hyprland config" claim: if they emit the wrong Lua, a save silently does
// nothing. These pin the emitted forms to the hl API the repo's import layer
// already generates (import_parse.go).

func TestMonitorsLua(t *testing.T) {
	layout := []wm.OutputLayout{
		{Name: "DP-1", Enabled: true, Mode: "1920x1080@144", X: 0, Y: 0, Scale: 1},
		{Name: "HDMI-A-1", Enabled: false},
		{Name: "eDP-1", Enabled: true, Mode: "2880x1800@120", X: 1920, Y: 0, Scale: 1.5, Transform: 1},
	}
	got := monitorsLua(layout)
	want := []string{
		`hl.monitor({ output = "DP-1", mode = "1920x1080@144", position = "0x0", scale = 1 })`,
		`hl.monitor({ output = "HDMI-A-1", disabled = true })`,
		`hl.monitor({ output = "eDP-1", mode = "2880x1800@120", position = "1920x0", scale = 1.5, transform = 1 })`,
	}
	for _, w := range want {
		if !strings.Contains(got, w) {
			t.Errorf("monitorsLua missing %q\ngot:\n%s", w, got)
		}
	}
	// An empty name must never reach the compositor.
	if strings.Contains(monitorsLua([]wm.OutputLayout{{Enabled: true}}), "output") {
		t.Error("a nameless output emitted a monitor rule")
	}
}

func TestCustomBindLua(t *testing.T) {
	k := meiKeybinds{Binds: []meiBind{
		{Keys: "SUPER + J", Action: "exec", Value: "kitty"},
		{Keys: "SUPER + SHIFT + Q", Action: "close"},
		{Keys: "SUPER + F", Action: "fullscreen"},
		{Keys: "SUPER + T", Action: "togglefloating"},
		{Keys: "SUPER + E", Action: "exec", Value: ""}, // no command: skipped
		{Keys: "SUPER + U", Action: "nonsense"},        // unknown action: skipped
		{Keys: "", Action: "exec", Value: "kitty"},     // empty chord: skipped
	}}
	script, skipped := keybindsLua(k)
	for _, w := range []string{
		`hl.bind("SUPER + J", hl.dsp.exec_cmd("kitty"))`,
		`hl.bind("SUPER + SHIFT + Q", hl.dsp.window.close())`,
		`hl.bind("SUPER + F", hl.dsp.window.fullscreen())`,
		`hl.bind("SUPER + T", hl.dsp.window.float({ action = "toggle" }))`,
	} {
		if !strings.Contains(script, w) {
			t.Errorf("keybindsLua missing %q\ngot:\n%s", w, script)
		}
	}
	if len(skipped) != 2 {
		t.Errorf("expected the two unappliable rows reported, got %v", skipped)
	}
	if strings.Contains(script, "SUPER + E") || strings.Contains(script, "SUPER + U") {
		t.Errorf("an unappliable row was emitted:\n%s", script)
	}
}

func TestAdvancedLua(t *testing.T) {
	store := map[string]any{"desktop": map[string]any{"appearance": map[string]any{
		"gapsIn":        float64(8),
		"blurEnabled":   true,
		"shadowRange":   float64(20),
		"activeOpacity": 0.95,
		"notAnOption":   "x",
	}}}
	scripts, n := advancedLua(store)
	if n != 4 {
		t.Errorf("applied %d options, want 4 (notAnOption is stored only)", n)
	}
	joined := strings.Join(scripts, "\n")
	// One call per top-level section, so a key this compositor rejects costs its
	// own section rather than the whole save.
	for _, w := range []string{
		"hl.config({ general = { gaps_in = 8 } })",
		"decoration = { active_opacity = 0.95, blur = { enabled = true }, shadow = { range = 20 } }",
	} {
		if !strings.Contains(joined, w) {
			t.Errorf("advancedLua missing %q\ngot:\n%s", w, joined)
		}
	}
	if strings.Contains(joined, "notAnOption") {
		t.Errorf("a non-compositor key reached the compositor:\n%s", joined)
	}
}

// A re-apply must replace the chords it set last time, not stack a second bind
// on them (measured nested: two hl.bind calls on one chord yield two entries,
// and the command then fires twice).
func TestUnbindLua(t *testing.T) {
	k := meiKeybinds{
		Binds:   []meiBind{{Keys: "SUPER + J", Action: "exec", Value: "kitty"}, {Keys: "SUPER + J", Action: "close"}},
		Rebinds: map[string]string{"SUPER + Q": "SUPER + X"},
	}
	got := unbindLua(k)
	if strings.Count(got, `hl.unbind("SUPER + J")`) != 1 {
		t.Errorf("duplicate chord not collapsed:\n%s", got)
	}
	if !strings.Contains(got, `hl.unbind("SUPER + X")`) {
		t.Errorf("rebind target not unbound:\n%s", got)
	}
	if strings.Contains(got, `hl.unbind("SUPER + Q")`) {
		t.Errorf("the shipped default chord must not be unbound:\n%s", got)
	}
}

// Mei's own chords (screenshot, clipboard, overview) are applied on every
// override pass, so they survive a Hyprland reload without being saved into the
// user's keybinds.json. A user bind on the same chord wins, and each default is
// unbound first because the shipped config already binds the same keys to
// ryoku:* globals.
func TestDefaultBindsLua(t *testing.T) {
	got := defaultBindsLua(meiKeybinds{})
	for _, w := range []string{
		`hl.unbind("PRINT")`,
		`hl.bind("PRINT", hl.dsp.exec_cmd("mei-screenshot full"))`,
		`hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("mei-screenshot region"))`,
		`hl.bind("SUPER + V", hl.dsp.global("mei:clipboard"))`,
		`hl.bind("SUPER + P", hl.dsp.global("mei:wallpaper-menu"))`,
		`hl.bind("SUPER + TAB", hl.dsp.global("mei:overview"))`,
		`hl.bind("SUPER + ALT + TAB", hl.dsp.global("mei:overview"))`,
	} {
		if !strings.Contains(got, w) {
			t.Errorf("defaultBindsLua missing %q\ngot:\n%s", w, got)
		}
	}

	// A user bind on one of the chords replaces that default, and only that one.
	user := meiKeybinds{Binds: []meiBind{{Keys: "SUPER + V", Action: "exec", Value: "cliphist"}}}
	got = defaultBindsLua(user)
	if strings.Contains(got, `hl.bind("SUPER + V"`) {
		t.Errorf("a user bind did not win over the default chord:\n%s", got)
	}
	if !strings.Contains(got, `hl.bind("SUPER + TAB", hl.dsp.global("mei:overview"))`) {
		t.Errorf("the other defaults must still apply:\n%s", got)
	}
}

// A desktop draft's keybinds move to keybinds.json and must not be echoed back
// into the advanced file, or every save would grow the store.
func TestSplitDesktopDraft(t *testing.T) {
	draft := map[string]any{"desktop": map[string]any{
		"appearance":     map[string]any{"gapsIn": float64(4)},
		"keybinds":       []any{map[string]any{"keys": "SUPER + J", "action": "exec", "value": "kitty"}},
		"keybindRebinds": map[string]any{"SUPER + Q": "SUPER + X"},
	}}
	k, rest := splitDesktopDraft(draft)
	if len(k.Binds) != 1 || k.Binds[0].Keys != "SUPER + J" || k.Binds[0].Value != "kitty" {
		t.Errorf("binds not split out: %+v", k.Binds)
	}
	if k.Rebinds["SUPER + Q"] != "SUPER + X" {
		t.Errorf("rebinds not split out: %+v", k.Rebinds)
	}
	d := childMap(rest, "desktop")
	if _, ok := d["keybinds"]; ok {
		t.Error("keybinds left in the advanced store")
	}
	if _, ok := d["keybindRebinds"]; ok {
		t.Error("rebinds left in the advanced store")
	}
	if _, ok := childMap(d, "appearance")["gapsIn"]; !ok {
		t.Error("appearance keys lost from the advanced store")
	}
}
