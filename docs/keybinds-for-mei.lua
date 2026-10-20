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

-- The launcher. Mei's shell registers the shortcut name with the compositor,
-- so this needs no config bind of its own.
hl.bind(mainMod .. " + D", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:launcher\")'"), { locked = true })

-- The control centre (the sidebar).
hl.bind(mainMod .. " + B", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:quicksettings\")'"), { locked = true })
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:quicksettings\")'"), { locked = true })

-- The clipboard history.
hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:clipboard\")'"), { locked = true })

-- The wallpaper menu.
hl.bind(mainMod .. " + P", hl.dsp.exec_cmd("hyprctl dispatch 'hl.dsp.global(\"ryoku:wallpaper-menu\")'"), { locked = true })

-- --- screenshots ---------------------------------------------------------------
-- Mei's helper is local: grim or slurp write a PNG into your Pictures folder,
-- the clipboard gets the image and a notification says where it went. There is
-- no upload and no share service, no network call of any kind.

hl.bind("Print", hl.dsp.exec_cmd("mei-screenshot region"), { locked = true })
hl.bind("SUPER + Print", hl.dsp.exec_cmd("mei-screenshot full"), { locked = true })
-- Mei has no image editor, so a bind that opened one on the capture is left
-- out: decide whether to drop it or to point it at an editor you already have.

-- --- brightness ---------------------------------------------------------------
-- Mei's own verb: it steps the panel by 5% and the OSD shows the value.

hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("mei-shell brightness down"), { locked = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("mei-shell brightness up"), { locked = true })

-- --- volume -------------------------------------------------------------------
-- Mei's verb steps the sink by 5% and flashes the OSD.

hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("mei-shell audio down"), { repeating = true, locked = true })
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("mei-shell audio up"), { repeating = true, locked = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("mei-shell audio mute"), { locked = true })
-- the microphone has no verb in Mei, so it goes straight to wpctl
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })

-- --- media keys ----------------------------------------------------------------
-- Mei reads the same MPRIS sessions any playerctl does, and drives them itself.

hl.bind("XF86AudioPause", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("mei-shell media previous"), { locked = true })
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("mei-shell media next"), { locked = true })
hl.bind(mainMod .. " + SPACE", hl.dsp.exec_cmd("mei-shell media playpause"), { locked = true })

-- --- reload --------------------------------------------------------------------

hl.bind(mainMod .. " + R", hl.dsp.exec_cmd("mei-shell reload"), { locked = true })

-- --- workspaces ----------------------------------------------------------------
-- These need no shell at all: the compositor focuses the workspace, and Mei's
-- bar cells follow. Moving a window to a workspace is the compositor's own
-- job too, so it needs no shell either:
--
--     hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace " .. ws))

-- --- rescue binds (they depend on no shell at all) --------------------------------
-- These two are the safety net: they work even if Mei is broken, because they
-- only use the compositor and your own terminal. Put them near the top of the
-- file, so they are there whatever else you paste.

-- a terminal of your choice (replace the command with yours)
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd("your-terminal"))

-- the revert: it stops Mei and starts <your previous shell> again. It does NOT edit
-- your Hyprland config; the autostart line stays a manual step, so nothing
-- here can rewrite your configuration behind your back.
hl.bind(mainMod .. " + SHIFT + R", hl.dsp.exec_cmd("bash ~/projects/mei/docs/revert-to-the previous shell.sh"))

-- If the screen is blank and no terminal is reachable: Ctrl+Alt+F3 gives you a
-- TTY. Log in, then:
--     bash ~/projects/mei/docs/revert-to-the previous shell.sh

-- --- switching over -------------------------------------------------------------
--
-- 1. In ~/.config/hypr/config/autostart.lua, comment out:
--
--      -- hl.exec_cmd("<your previous shell's start command>")
--
--    and add:
--
--      hl.exec_cmd("~/projects/mei/mei live --profile full")
--
-- 2. Log out and back in (or run `<your previous shell's stop command>` and then the line above).
--
-- The autostart line is safe to use as it stands: `./mei start` never asks a
-- question, it does nothing if Mei is already running, and it refuses (with a
-- log line and a non-zero exit) if your old shell still owns the notification
-- or tray name, so a double start cannot happen. Add the fallback so a broken
-- Mei hands the session back to <your previous shell>:
--
--      hl.exec_cmd("~/projects/mei/mei start --fallback \"<your previous shell's start command>\"")
--
-- The fallback only runs when no Mei process is left, so the two shells are
-- never both running. Keep `--real-power` off for the first days: logout,
-- reboot and suspend stay stubbed until you add it deliberately.
--
-- To go back, in one command:
--
--      sed -i 's|^# hl.exec_cmd("<your previous shell's start command>")|hl.exec_cmd("<your previous shell's start command>")|' ~/.config/hypr/config/autostart.lua
--
--    and comment Mei's line again, then log out and back in.
