# UNVERIFIED / not claimed — audit-3

1. **Physical three-finger swipe.** The gesture is registered (`hl.gesture`
   returned ok) and all tuning knobs report `set: true`, but Hyprland 0.57 has
   no query for registered gestures and no touch events could be synthesised
   here. Swipe left/right manually to confirm.
2. **Super+N physical key press.** Unchanged from audit-2: the helper works when
   run directly and the IPC path is tested, but no key event was injected.
3. **`launcherTarget` UI click-through.** Still no shipped control; resolved as
   option (b) and unchanged in this pass. Verified at IPC/config level only.
4. **`screenShader` shell-level UI path.** Same: option (b), no UI control; the
   Hub control edits Hyprland's `decoration:screen_shader` instead.
5. **Gesture persistence.** No live Hyprland file was written, so the swipe is
   runtime-only until `hypr-gestures-to-add.lua` is installed/required; a reload
   or relogin drops it. This is deliberate, not a claim of persistence.
6. **TTY1 fish auto-exec.** The optional ROLLBACK block is still not installed;
   no reboot was performed, so login-time fish was not observed. The passwd
   entry itself is verified.
7. **"Only 1.00x" for manual profiles.** Autoscale and the generated layout are
   pinned to 1.0. The Hub can still apply an explicitly saved per-monitor scale;
   that path was left alone (see `scale.md`).
8. **UI after the scale change.** No screenshot or visual walkthrough was done;
   scale/zoom were verified through `hyprctl` JSON/getoption, not by eyeballing
   the bar.
