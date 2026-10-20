-- keybinds-for-mei.lua
--
-- A snippet for ME to paste into ~/.config/hypr/config/keybinds.lua (or a new
-- file it includes). Nothing here has been written to your config: the agent
-- only read it. Every line uses a mechanism that is already verified in your
-- own config: hl.dsp.global("...") for a shortcut Mei's shell registers with
-- the compositor, hl.dsp.exec_cmd("...") for a command, and hl.dsp.focus for
-- the compositor's own workspace focus.
--
-- How it works: Mei's shell registers the shortcut names ryoku:launcher,
-- ryoku:quicksettings, ryoku:clipboard and ryoku:wallpaper-menu over the
-- global-shortcuts protocol, so they need no config bind of their own. A
-- hyprctl dispatch of those names is what reaches Mei.

local mainMod = "SUPER"

-- --- surfaces -----------------------------------------------------------------

-- launcher (your SUPER + D)
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:launcher\")'"), { locked = true })

-- the control centre / sidebar (your SUPER + B and SUPER + V)
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:quicksettings\")'"), { locked = true })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:quicksettings\")'"), { locked = true })

-- clipboard history (your SUPER + C)
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:clipboard\")'"), { locked = true })

-- wallpaper menu (your SUPER + P)
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:wallpaper-menu\")'"), { locked = true })

-- --- screenshots (your Print binds) --------------------------------------------
-- Mei's helper is local: grim or slurp write a PNG into your Pictures folder,
-- the clipboard gets the image and a notification says where it went. There is
-- no upload and no network call of any kind.

hl.bind("Print", hl.dsp.exec_cmd("mei-screenshot region"), { locked = true })
hl.bind("SUPER + Print", hl.dsp.exec_cmd("mei-screenshot full"), { locked = true })
-- your SHIFT + Print and SUPER + SHIFT + Print also opened an editor on the
-- capture. Mei has no image editor, so those two are left out: decide whether
-- to drop them or to point them at an editor you already have.

-- --- brightness (your XF86MonBrightness binds) --------------------------------
-- Mei's own verb: it steps the panel by 5% and the OSD shows the value.

hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("mei-shell brightness down"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("mei-shell brightness up"), { locked = true })

-- --- volume (your XF86Audio* binds) -------------------------------------------
-- Mei's verb steps the sink by 5% and flashes the OSD.

hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("mei-shell audio down"), { repeating = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("mei-shell audio up"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("mei-shell audio mute"), { locked = true })
-- the microphone has no verb in Mei, so it goes straight to wpctl
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- --- media keys (your playerctl binds) ----------------------------------------
-- Mei reads the same MPRIS sessions playerctl does, and drives them itself.

hl.bind("XF86AudioPause", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("mei-shell media previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("mei-shell media next"), { locked = true })
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })

-- --- reload (your SUPER + R) ---------------------------------------------------

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("mei-shell reload"), { locked = true })

-- --- workspaces (your SUPER + 1..0 binds) -------------------------------------
-- These need no shell at all: the compositor focuses the workspace, and Mei's
-- bar cells follow. The "move a window with the number" half (your SUPER +
-- SHIFT + number) has no Mei equivalent: decide whether to keep it for the
-- compositor's own move binds or to drop it.

for i = 1, 10 do
  local ws = tostring(i)
  local key = tostring(i % 10)
  hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ workspace = tonumber(ws) }), { locked = true })
end

-- --- deliberately NOT bound here ------------------------------------------------
-- lock (XF86PowerOff, SUPER + L): Mei's lock is being rebuilt as an in-shell
--   PAM lock (see docs/PARITY.md). Until it lands, do not bind it: the verb
--   Mei has today is logind's session lock, which would lock your whole
--   session. Test the lock from the live checklist first.
-- music popup (SUPER + M), system panel (SUPER + B is the control centre now),
--   network panel (SUPER + N), calendar (SUPER + S), guide (SUPER + H) and the
--   bar's autohide toggle (SUPER + A): no Mei equivalent that is reachable by
--   a key. The network, music and system panels live inside Mei's control
--   centre, which the binds above open; the calendar and the guide are out of
--   scope by your own decision.

-- --- switching over -------------------------------------------------------------
--
-- 1. In ~/.config/hypr/config/autostart.lua, comment out:
--
--      -- hl.exec_cmd("serpantinumd start")
--
--    and add:
--
--      hl.exec_cmd("~/projects/mei/mei live --profile full")
--
-- 2. Log out and back in (or run `serpantinumd stop` and then the line above).
--
-- To go back, in one command:
--
--      sed -i 's|^# hl.exec_cmd("serpantinumd start")|hl.exec_cmd("serpantinumd start")|' ~/.config/hypr/config/autostart.lua
--
--    and comment Mei's line again, then log out and back in.
