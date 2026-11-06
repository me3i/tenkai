package main

// The compositor's border defaults, derived from the matugen palette written
// to cache/tenkai/colors.json. The live wallpaper accent (Hyprland's `wc`) still
// wins when it is set — these are the floor, not the ceiling: they exist so a
// session whose palette is available gets its own colour instead of the
// hardcoded Tenkai red that shipped before the Visuals page had a border
// control. With no palette at all, mono grey.

import (
	"encoding/json"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
)

const (
	monoBorderActive   = "#c3c3c3"
	monoBorderInactive = "#6e6e6e"
)

var paletteHexRe = regexp.MustCompile(`^#?[0-9a-fA-F]{6}$`)

func normalizePaletteHex(h string) string {
	h = strings.TrimSpace(h)
	if !paletteHexRe.MatchString(h) {
		return ""
	}
	if !strings.HasPrefix(h, "#") {
		h = "#" + h
	}
	return strings.ToLower(h)
}

func paletteColorsPath() string {
	base := os.Getenv("XDG_CACHE_HOME")
	if base == "" {
		if home := os.Getenv("HOME"); home != "" {
			base = filepath.Join(home, ".cache")
		} else {
			base = ".cache"
		}
	}
	return filepath.Join(base, "tenkai", "colors.json")
}

// readPaletteColors pulls the primary and outline roles out of the palette the
// theme pass wrote. Missing file, missing keys, or unusable hexes all mean the
// mono fallback, never an invented colour.
func readPaletteColors() (primary, outline string, ok bool) {
	b, err := os.ReadFile(paletteColorsPath())
	if err != nil {
		return "", "", false
	}
	var c struct {
		Primary string `json:"primary"`
		Outline string `json:"outline"`
	}
	if err := json.Unmarshal(b, &c); err != nil {
		return "", "", false
	}
	p := normalizePaletteHex(c.Primary)
	o := normalizePaletteHex(c.Outline)
	if p == "" || o == "" {
		return "", "", false
	}
	return p, o, true
}

// paletteLuminance is a simple perceived brightness (Rec. 709 coefficients) —
// enough to pick the darker of two palette roles, which is all the inactive
// border needs.
func paletteLuminance(hex string) float64 {
	h := strings.TrimPrefix(hex, "#")
	r, err1 := strconv.ParseUint(h[0:2], 16, 8)
	g, err2 := strconv.ParseUint(h[2:4], 16, 8)
	b, err3 := strconv.ParseUint(h[4:6], 16, 8)
	if err1 != nil || err2 != nil || err3 != nil {
		return 0
	}
	return 0.2126*float64(r) + 0.7152*float64(g) + 0.0722*float64(b)
}

// paletteBorderDefaults resolves the border colours: primary for the active
// border, the darker of (outline, primary) for the inactive one. Mono grey
// only when no palette is available at all.
func paletteBorderDefaults() (active, inactive string) {
	p, o, ok := readPaletteColors()
	if !ok {
		return monoBorderActive, monoBorderInactive
	}
	active = p
	if paletteLuminance(o) <= paletteLuminance(p) {
		inactive = o
	} else {
		inactive = p
	}
	return active, inactive
}
