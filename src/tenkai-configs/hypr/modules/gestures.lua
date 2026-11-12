-- Three-finger horizontal trackpad swipe switches workspaces.
--
-- Hyprland 0.51 replaced the old `gestures:workspace_swipe*` booleans with the
-- declarative `hl.gesture` API and removed `workspace_swipe` /
-- `workspace_swipe_fingers` entirely: setting them on 0.57 is a config error
-- ("no such option"). The tuning knobs below still exist and are applied here
-- so the swipe matches the old feel.
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
