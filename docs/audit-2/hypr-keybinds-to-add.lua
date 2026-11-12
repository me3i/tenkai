-- Tenkai workspace keybinds.
--
-- NOT applied automatically. The audited live config already contains
-- `require("modules.binds")` in hyprland.lua and its modules/binds.lua is
-- identical to src/tenkai-configs/hypr/modules/binds.lua, so there is nothing
-- to paste. Keep this file as the block to add for a tree that lacks the
-- workspace section. It writes nothing to ~/.config/hypr.
--
-- Paste inside modules/binds.lua, after `local K = require("modules.rebind")`
-- (K is defined there; a bare hyprland.lua does not define it).
--
-- Requires the fixed helper at ~/.config/hypr/scripts/tenkai-workspace
-- (src/tenkai-configs/hypr/scripts/tenkai-workspace). Super+N focuses the Nth
-- workspace of the current desktop through that helper; it does not dispatch
-- `workspace N` directly, because a Lua Hyprland config rejects the classic
-- dispatch form.

local mod = "SUPER"
local ws_helper = (os.getenv("HOME") or "") .. "/.config/hypr/scripts/tenkai-workspace"

local kp_off = { "KP_End", "KP_Down", "KP_Next", "KP_Left", "KP_Begin",
                 "KP_Right", "KP_Home", "KP_Up", "KP_Prior", "KP_Insert" }

for i = 1, 10 do
    local key = i % 10 -- 10 maps to the 0 key
    hl.bind(K(mod .. " + " .. key),             hl.dsp.exec_cmd(ws_helper .. " focus " .. i))
    hl.bind(K(mod .. " + ALT + " .. key),       hl.dsp.exec_cmd(ws_helper .. " move " .. i))
    hl.bind(K(mod .. " + SHIFT + " .. key),     hl.dsp.exec_cmd(ws_helper .. " movesilent " .. i))
    hl.bind(K(mod .. " + KP_" .. key),          hl.dsp.exec_cmd(ws_helper .. " focus " .. i))
    hl.bind(K(mod .. " + ALT + KP_" .. key),    hl.dsp.exec_cmd(ws_helper .. " move " .. i))
    hl.bind(K(mod .. " + SHIFT + KP_" .. key),  hl.dsp.exec_cmd(ws_helper .. " movesilent " .. i))
    hl.bind(K(mod .. " + " .. kp_off[i]),         hl.dsp.exec_cmd(ws_helper .. " focus " .. i))
    hl.bind(K(mod .. " + ALT + " .. kp_off[i]),   hl.dsp.exec_cmd(ws_helper .. " move " .. i))
    hl.bind(K(mod .. " + SHIFT + " .. kp_off[i]), hl.dsp.exec_cmd(ws_helper .. " movesilent " .. i))
end

hl.bind(K(mod .. " + H"),     hl.dsp.exec_cmd(ws_helper .. " hide"))
hl.bind(K(mod .. " + ALT + H"), hl.dsp.exec_cmd(ws_helper .. " scratch"))
hl.bind(K(mod .. " + mouse_up"),   hl.dsp.focus({ workspace = "r-1" }))
hl.bind(K(mod .. " + mouse_down"), hl.dsp.focus({ workspace = "r+1" }))
