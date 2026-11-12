# Scale: 1.00x only

## Before

```
hyprctl monitors -j -> eDP-1: 1920x1080, scale 1.5
hyprctl getoption cursor:zoom_factor -> float: 1.000000, set: false
QT_SCALE_FACTOR= (empty)  GDK_SCALE= (empty)  GDK_DPI_SCALE= (empty)
```

The 1.5 came from `tenkai-monitor autoscale`, whose DPI buckets map a dense
internal panel to 1.25/1.5/1.75/2.0. The shipped Hyprland Lua config has no
static monitor line: the generated `monitors.lua` (if present) and autoscale are
the source of truth.

## Repo changes

1. `src/tenkai-configs/hypr/scripts/tenkai-monitor` — `dpiscale()` now returns
   `1.0` unconditionally. The helper still computes layout and modes, and its
   generated catch-all was already `scale = 1`; only the DPI-derived per-output
   scale is pinned.
2. `src/tenkai-configs/hypr/modules/misc.lua` — `cursor.zoom_factor = 1.0`.

Diff (abridged):

```diff
-    def dpiscale($name; $w; $h; $pw):
-      ... DPI bucket -> 1.0 / 1.25 / 1.5 / 1.75 / 2.0 ...
-      | snap($w; $h; $target);
+    def dpiscale($name; $w; $h; $pw): 1.0;
```

```diff
 hl.config({
+    cursor = {
+        zoom_factor = 1.0,
+    },
     misc = {
```

## Live changes

The live Lua config manager rejects `hyprctl keyword` ("unknown request"), so:

```bash
hyprctl eval 'hl.monitor({ output = "eDP-1", mode = "highrr", position = "0x0", scale = 1 })'
hyprctl eval 'hl.config({ cursor = { zoom_factor = 1.0 } })'
```

Verified after applying:

```
eDP-1: scale 1 (1920x1080, 144 Hz preserved)
cursor:zoom_factor -> float: 1.000000, set: true
```

The updated `tenkai-monitor` helper was installed to
`~/.config/hypr/scripts/tenkai-monitor` with a
`tenkai-monitor.pre-audit3.bak` backup, so the next login/hotplug autoscale
keeps 1x instead of recomputing 1.5. Running it once confirmed this: it wrote
its generated `~/.config/hypr/monitors.lua` (it did not exist before; the
generated file now pins eDP-1 to scale 1) and the live monitor stayed 1.

The reload that autoscale performs clears runtime-only `eval` state (gestures
and cursor zoom), which was observed and then reapplied. Monitor scale survives
because it comes from the generated `monitors.lua`; gestures and zoom only
survive once the repo modules are installed (see `gestures.md`).

## Not touched

- `QT_SCALE_FACTOR`, `GDK_SCALE`, `GDK_DPI_SCALE` were empty and were left
  alone. `tenkai-monitor` still derives `GDK_SCALE` from the live layout; with
  every monitor at 1 it resolves to 1.
- The shell's own font scale (none was non-1) and Hub display controls.

## Caveat


This pins **automatic** scaling. The Hub's Displays page can still apply an
explicit per-monitor scale from a saved profile (`tenkai-monitor apply/save`
uses the layout it is given). That path was not rewritten: forcing 1.0 there
would silently discard a profile the user explicitly saved. If "only 1.00x"
must also override manual profile choices, that is a separate decision.

`runtime/scale-is-1` fails if any monitor is not 1.0 or cursor zoom is not 1.
