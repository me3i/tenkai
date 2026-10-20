# Mei

Mei is a nested-session development tree for the Ryoku desktop shell. The owner-facing
acceptance state is in `docs/STATUS.md`; test evidence is under `.run/logs/`.

## Installer notes: backlight and brightness

The brightness helper (`src/ryoku/shell/scripts/ryoku-cmd-brightness`) uses
`brightnessctl`, with a sysfs fallback. It needs write access to the backlight device.

A fresh Arch install may not grant that access. The later `install.sh` and `./mei doctor`
must perform this read-only check and print the exact remediation:

```bash
shopt -s nullglob
backlights=(/sys/class/backlight/*)
if ((${#backlights[@]} == 0)); then
  echo "No backlight device; brightness will be unavailable."
elif [ ! -w "${backlights[0]}/brightness" ]; then
  echo "No write access to ${backlights[0]}/brightness."
  echo "Fix (choose one, then log out and back in):"
  echo "  1. sudo usermod -aG video \"$USER\""
  echo "  2. Add this line to /etc/udev/rules.d/90-backlight.rules:"
  echo 'SUBSYSTEM=="backlight", ACTION=="add", RUN+="/bin/chgrp video /sys/class/backlight/%k/brightness", RUN+="/bin/chmod g+w /sys/class/backlight/%k/brightness"'
  echo "     sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=backlight"
fi
```

The check is read-only. Do not change groups or udev rules automatically from the test
harness; print the commands and let the owner apply them. The helper reports a missing
`brightnessctl` or a failed write instead of silently succeeding.

## Known limit: multiple backlight devices

The current helper has no backlight **selector**. On a machine with more than one entry under
`/sys/class/backlight/` (for example an internal panel plus an external device), it uses
`brightnessctl`'s default/first device. This is correct on the owner's single
`intel_backlight` laptop, but multi-backlight machines are **not supported** until the
upstream selector (`ryoku-hw-backlight`, absent here) is packaged. The later installer and
`./mei doctor` should warn when the count is greater than one rather than silently choosing:

```bash
backlights=(/sys/class/backlight/*)
((${#backlights[@]} > 1)) && echo "Multiple backlights; the current helper does not select one."
```

`install.sh` and `./mei doctor` do not exist in this tree yet; these are requirements for the
later installer, not implemented checks.
