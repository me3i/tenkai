# Three-finger workspace swipe

## Important version fact

The block requested in the brief (`gestures { workspace_swipe = true
workspace_swipe_fingers = 3 ... }`) **cannot work on this compositor**.
Hyprland 0.57.2 reports:

```
gestures:workspace_swipe          -> no such option
gestures:workspace_swipe_fingers  -> no such option
```

Upstream removed both in 0.51 and replaced them with the declarative gesture
API. `hyprctl descriptions` on this build lists only the tuning knobs; the
toggle/finger options are gone. Writing the old block would add a config error
and bind nothing.

The correct form, confirmed against the 0.57 wiki and accepted live:

```lua
hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })
```

## Repo change

New module `src/tenkai-configs/hypr/modules/gestures.lua`:

- `hl.gesture` for 3 fingers, horizontal, action `workspace`;
- `hl.config({ gestures = { ... } })` with distance 300, cancel ratio 0.5,
  min speed to force 30, direction lock on, lock threshold 10, create-new on.

`src/tenkai-configs/hypr/hyprland.lua` now requires it after
`modules.touchpad`.

## Live change

The live config manager rejects `hyprctl keyword` ("unknown request"), so the
runtime changes used `hyprctl eval` with the same API:

```bash
hyprctl eval 'hl.gesture({ fingers = 3, direction = "horizontal", action = "workspace" })'
hyprctl eval 'hl.config({ gestures = { workspace_swipe_distance = 300, ... } })'
```

Verified: `hyprctl configerrors` is empty and every knob reports `set: true`
with the requested value. `tests/run-all.sh::runtime/gestures-enabled` enforces
this.

**No live Hyprland config file was written.** The gesture is runtime-only until
the repo module is installed and required, so a config reload/relogin drops it.
This was observed: an autoscale-triggered reload cleared all six knobs to
`set: false`; they were reapplied and verified again. The persistence block is
`docs/audit-3/hypr-gestures-to-add.lua`, which mirrors the shipped module.

## Touchpad interaction

`input:touchpad:natural_scroll` is `false` (explicitly set in the live config).
It only controls two-finger scroll direction and does not affect the three-finger
workspace gesture.
`input:touchpad:scroll_method` does not exist on this build. No touchpad
setting was changed. Gestures are handled by Hyprland's native gesture system;
no libinput-gestures/fusuma daemon was added.

## What is not proven

The binding is registered and accepted by the compositor, but there is no
runtime query for "which gestures are registered" and no synthetic touch
injection here. A physical three-finger horizontal swipe is **UNVERIFIED**.
Manual check: swipe left/right with three fingers and confirm the workspace
changes.
