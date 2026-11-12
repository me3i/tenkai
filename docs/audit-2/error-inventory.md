# Error inventory (audit-2)

Measured on the live nested session, one fresh `qs` start each time, log segment
taken from the last `Launching config` line so earlier runs do not count.

## Gate

The audit gate is zero occurrences of:

```
Type .* unavailable | TypeError | ReferenceError | Cannot read property
is not a type | Failed to load component | QML .* error
```

| run | gate matches | total log lines | `PeerClosedError` |
|---|---|---|---|
| before fixes | 0 | 829 | **772** |
| after subscription fix, 60 s idle | 0 | 11 | 0 |
| after font fix, 60 s idle | 0 | 11 | 0 |

The gate patterns were already zero before this pass; the user-visible "wall of
errors" was the 772 socket warnings, not QML type errors.

## What produced 772 warnings

Three long-lived subscriber sockets reconnected every 2 s because the lite
daemon has no `powerprofiles`, `updates` or `weather` topic (and `calendar` was
also requested by the holidays service). Each reconnect logged:

```
WARN quickshell.io.socket: Socket error for Socket(0x...) QLocalSocket::PeerClosedError
```

`Holidays.qml`, `PowerProfiles.qml`, `Updates.qml` and `Weather.qml` now stop on
the daemon's `err unknown topic` reply (`topicMissing`) instead of restarting the
2 s retry timer. A missing feature is reported once, not 250 times per start.

## Remaining lines in a clean start

```
1  WARN quickshell.io.fileview: got operation finished from dropped operation
2  WARN qt.qpa.wayland.textinput
1  WARN quickshell.dbus: Could not launch service org.freedesktop.UPower.PowerProfiles
1  WARN quickshell.service.powerprofiles: Could not start PowerProfilesDaemon
```

All are environmental (sandbox HOME, no UPower daemon) and allowlisted in
`tests/allowlist.txt` as category (b). The fileview warning is the dropped
operation consequence of the nested session; the PowerProfiles warning is
Quickshell's own service, not the Tenkai IPC socket.

## Fontconfig

Before the font fix every start also printed:

```
Fontconfig error: Cannot load config file ".../.run/home/.config/fontconfig/fonts.conf": File not found
Fontconfig error: Cannot load config file from .../fonts-override.conf
```

`./tenkai` now creates that file and links `MaterialSymbolsRounded.ttf` into
`.run/data/fonts`. The manual `.run/live-session.sh` used for this audit was
repaired the same way. Current starts: zero Fontconfig errors.

Evidence: `tests/evidence/<timestamp>/shell-log-grep.txt` and
`shell-current.log`.
