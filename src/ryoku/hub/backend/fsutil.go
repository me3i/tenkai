package main

import "os"

// Generic filesystem helpers. fileExists was lifted verbatim from upstream's
// backend/lock.go, which the lock removal (2026-11-01) deleted: the helper
// lives there upstream but is used all over this package (fastfetch, hwcaps,
// gpuvm, gputune, palettebridge, voxtype), so it gets a home of its own here.
func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}