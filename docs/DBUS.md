# DBUS.md — the two well-known names Tenkai claims

**Status: DECIDED — option B, implemented.** The tray half was already option B
in the code; the notifications half now has the same guard. See "What was
implemented" at the end for the exact diff and what is and is not verified.

## The names

| Name | Claimed by | Where |
| --- | --- | --- |
| `org.freedesktop.Notifications` | the Quickshell `NotificationServer` object | `src/tenkai_core/shell/quickshell/shell/services/Notifs.qml` (instantiated inside a `Loader` whose `active` is `Config.moduleOn("notifications")`) |
| `org.kde.StatusNotifierWatcher` | the `tenkai-shell` daemon | `src/tenkai_core/shell/ipc/tray.go` (`watcherName`, path `/StatusNotifierWatcher`, same interface) |

`./tenkai` already treats both as Tenkai's claims: `live_claims()` lists them
under both profiles, and `live_print_claims()` exempts exactly these two names
from the "collision" verdict.

## Why the naive fix (option a: own `org.tenkai.*` instead) does not work

* **Notifications.** `Notifs.qml:232` states the constraint in the code:
  "NotificationServer has no enable property and merely instantiating it claims
  org.freedesktop.Notifications." Quickshell's `NotificationServer` is the
  freedesktop server implementation; it has no name property, and the freedesktop
  spec makes `org.freedesktop.Notifications` the address every client calls
  `Notify()` on. Owning only `org.tenkai.Notifications` would mean writing our own
  server plus a proxy that owns the standard name anyway — more code and one more
  process, against the project's no-bloat rule.
* **Tray.** `org.kde.StatusNotifierWatcher` is a lookup key, not a brand: tray
  items publish on the bus and call `RegisterStatusNotifierItem` on
  `org.kde.StatusNotifierWatcher`. A watcher under any other name is invisible to
  them, so a proxy would again have to own the standard name.

Both names are therefore effectively mandatory for any shell that renders
notifications and a tray.

## Options

**Option A — standard names, exclusive, documented (current behaviour).**
Tenkai claims both names and the docs state that the previous shell's user
units must be stopped/masked while Tenkai runs. Consequence: two shells cannot
coexist in one session; the last one to start wins and the first one loses its
notifications and tray silently.

**Option B — standard names, but back off if already owned (CHOSEN).**
Same claims, plus a start-up guard: before claiming, read
`org.freedesktop.DBus.GetNameOwner`; if another process already owns the name,
print one line and leave the name alone instead of fighting for it. The
`prompter.go:87` code already does exactly this pattern for the keyring
prompter ("disabled: <name> already owned"), so it is an established convention
in this daemon rather than new machinery. No extra process, no proxy.
(For `NotificationServer` the equivalent guard has to live in QML: check the
owner before activating the Loader.)

**Option C — `org.tenkai.*` plus a proxy.** Rejected on evidence above unless
the owner wants it anyway: it needs a new daemon, and it still ends up owning
the standard names to be usable.

## Which process holds which name, per scenario

| Scenario | `org.freedesktop.Notifications` | `org.kde.StatusNotifierWatcher` |
| --- | --- | --- |
| Only Tenkai running, notifications module on | `qs`/tenkai-shell shell process | `tenkai-shell` daemon |
| Only Tenkai running, notifications module off | unowned (nothing claims it) | `tenkai-shell` daemon |
| Only Tenkai running, tray module off | shell process | unowned (`daemon.go:652` logs it) |
| Tenkai and the previous shell both running | whichever started last — undefined | same |
| Neither running | unowned, the session bus fallback applies | unowned |

The two-shell case is the one to decide about; the other rows are already
well-defined by the code above.

## What was implemented (option B)

**Tray — already option B, unchanged.** `tenkai-shell` claims
`org.kde.StatusNotifierWatcher` with `dbus.NameFlagDoNotQueue` and sets
`isWatcher` only when the reply is `RequestNameReplyPrimaryOwner`
(`src/tenkai_core/shell/ipc/tray.go:139-140`). If another watcher owns the name,
the daemon runs host-only. No code change was needed; this document previously
described the tray as if it fought for the name, which was wrong.

**Notifications — guard added.** `Notifs.qml` now probes ownership with

```
busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
  org.freedesktop.DBus GetNameOwner s org.freedesktop.Notifications
```

before the `Loader` that instantiates `NotificationServer` is allowed to activate:

* exit 0 → another process owns the name → the server is never created, so the
  existing server keeps the session's notifications, and a 10 s timer re-probes
  so a later exit does not leave them off for the rest of the session;
* non-zero exit (no owner, or no `busctl`) → the server is created and claims the
  name, i.e. the previous behaviour.

**Verification.** `qmllint` on the file exits 0. The runtime behaviour is
**UNVERIFIED**: proving it needs two shells in one session, which this pass is
not allowed to run. The claim in the code is the D-Bus semantics of
`GetNameOwner` (it raises `org.freedesktop.DBus.Error.NameHasNoOwner` when
unowned), not an observation of Tenkai.
