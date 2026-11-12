-- Tenkai three-finger workspace swipe (Hyprland 0.51+ gesture API).
--
-- NOT applied to ~/.config/hypr by this audit. Copy to
-- ~/.config/hypr/modules/gestures.lua and add
--     require("modules.gestures")
-- to hyprland.lua after modules.touchpad.
--
-- Do not use the old `gestures { workspace_swipe = ... }` block: 0.57 removed
-- workspace_swipe and workspace_swipe_fingers (`no such option`).

hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

hl.config({
    gestures = {
        workspace_swipe_distance = 300,
        workspace_swipe_cancel_ratio = 0.5,
        workspace_swipe_min_speed_to_force = 30,
        workspace_swipe_direction_lock = true,
        workspace_swipe_direction_lock_threshold = 10,
        workspace_swipe_create_new = true,
    },
})
