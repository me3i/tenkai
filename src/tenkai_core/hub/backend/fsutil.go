package main

import (
	"os"
	"path/filepath"
)

// Generic filesystem helpers. fileExists was lifted verbatim from upstream's
// backend/lock.go, which the lock removal (2026-11-01) deleted: the helper
// lives there upstream but is used all over this package (fastfetch, hwcaps,
// gpuvm, gputune, palettebridge, voxtype), so it gets a home of its own here.
func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}

// configHome returns XDG_CONFIG_HOME, falling back to $HOME/.config. Used by
// matugen, import_apply, rice, wm, desktop, schemes, reloadcover and (until
// this phase) voxtype.
func configHome() string {
	if b := os.Getenv("XDG_CONFIG_HOME"); b != "" {
		return b
	}
	return filepath.Join(os.Getenv("HOME"), ".config")
}

// dataHome returns XDG_DATA_HOME, falling back to $HOME/.local/share. Used by
// reloadcover and (until this phase) voxtype.
func dataHome() string {
	if b := os.Getenv("XDG_DATA_HOME"); b != "" {
		return b
	}
	return filepath.Join(os.Getenv("HOME"), ".local", "share")
}
