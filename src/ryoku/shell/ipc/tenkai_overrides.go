package main

// Tenkai's runtime overrides at boot. The Settings pages persist every change under
// XDG_CONFIG_HOME/tenkai and apply it to the running compositor with hyprctl. A
// Hyprland reload (or a new session) drops that runtime state, so the daemon
// re-applies the files once it starts.
//
// The applier lives in the Hub (`tenkai-hub overrides apply`), which already owns
// the compositor command builders; calling it instead of copying them here keeps
// one implementation of "what the files mean". Best effort: a missing Hub or a
// compositor that is not up yet is logged and never fatal.

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

func tenkaiHubBinary() string {
	if exe, err := os.Executable(); err == nil {
		cand := filepath.Join(filepath.Dir(exe), "tenkai-hub")
		if _, err := os.Stat(cand); err == nil {
			return cand
		}
	}
	if p, err := exec.LookPath("tenkai-hub"); err == nil {
		return p
	}
	return ""
}

// reapplyOverridesWhenReady waits for the compositor's own ready frame and then
// re-applies the overrides once more. The boot call runs before Hyprland has
// finished loading its config, and a config load rebuilds the keybind table, so
// a hl.bind issued that early is dropped (config values survive, binds do not —
// measured nested: gaps_in stuck, the bind did not). Applying again after the
// ready frame is what makes a persisted keybind come back at login.
func (d *daemon) reapplyOverridesWhenReady() {
	deadline := time.Now().Add(30 * time.Second)
	for time.Now().Before(deadline) {
		d.wmMu.Lock()
		ready := d.wmReady
		d.wmMu.Unlock()
		if ready {
			reapplyTenkaiOverrides()
			return
		}
		time.Sleep(200 * time.Millisecond)
	}
}

func reapplyTenkaiOverrides() {
	bin := tenkaiHubBinary()
	if bin == "" {
		fmt.Println("tenkai-shell: runtime overrides: tenkai-hub not found; skipped")
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	out, err := exec.CommandContext(ctx, bin, "overrides", "apply").CombinedOutput()
	if err != nil {
		fmt.Printf("tenkai-shell: runtime overrides: %v (%s)\n", err, strings.TrimSpace(string(out)))
		return
	}
	fmt.Println("tenkai-shell: runtime overrides re-applied from Tenkai's config")
}
