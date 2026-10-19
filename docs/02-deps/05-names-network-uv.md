# 05 — Names, network calls, and uv

Phase 2 dependency mapping for the Mei fork of Ryoku v0.75.5-beta.20 (commit `98a0368253d9628be72b853985878a5db90e1547`).
Source is read-only. Every citation below was produced by `git grep -n`/`git show`/`sed` against
`/home/mei/projects/mei/upstream` (on-disk `ryoku/{shell,hub,wm,ui,palette-bridge}` and off-disk
blobs at `HEAD`). Labels: **[READ]** = line verified in file contents; **[UNVERIFIED]** = quoted from
docs/CHANGELOG or inferred, not re-read in source; **[TESTED]** = none (no build/run permitted).

Convention assumed for the "Mei action" columns: product prefix `ryoku` → `mei`, daemon/config
`ryogami` → `mei-wall` (it is an in-repo Rust daemon, not third-party). Third-party D-Bus names
(`org.freedesktop.*`, `org.kde.*`, `org.gnome.*`, `org.mpris.*`) are **interfaces to other
software** and must **never** be renamed.

---

## Q5 — Hard-coded names (sockets, locks, D-Bus, paths)

### Q5.1 Unix sockets

| Name | What it is | Where (file:line) | Env-derived / absolute |
|---|---|---|---|
| `ryoku-shell.sock` | The single control socket the Go shell daemon owns; command clients + the Hub dial it | `ryoku/shell/ipc/main.go:18` (const), `:20-26` (`sockPath()`), `:89` (dial) **[READ]** | Env-derived: `$XDG_RUNTIME_DIR/ryoku-shell.sock`, falls back to `/tmp` |
| `ryoku-shell.sock` (clients) | Hub backend dials the daemon socket | `ryoku/hub/backend/daemonclient.go:26-30` **[READ]** | Env-derived `$XDG_RUNTIME_DIR` |
| `ryoku-shell.sock` (QML) | Hub + shell QML `Socket`/services targets | `ryoku/hub/quickshell/Singletons/Settings.qml:47`, `Updates.qml:11`, `pages/RecordingPage.qml:68`, `pages/DisplaysPage.qml:192,211`; `ryoku/shell/quickshell/shell/services/{Config.qml:257,Clipboard.qml:20,Dock.qml:160,Holidays.qml:9,Keypresses.qml:15,Keyring.qml:37}`, `modules/bar/barstyles/kairos/settings/IslandSettings.qml:82`, `modules/bar/barstyles/qsbar/Theme.qml:3207`, `modules/bar/framebars/menus/MenuTheme.qml:36`, `modules/stage/Singletons/StageBackend.qml:92`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/settings/ComfortSettings.qml:24` **[READ]** | Env-derived `(Quickshell.env("XDG_RUNTIME_DIR") \|\| "/tmp")` |
| `ryoku-shell.sock.lock` | Flock guarding a double daemon start (socket file alone is not proof of liveness) | `ryoku/shell/ipc/daemon.go:277` (`holdDaemonLock(path + ".lock")`) **[READ]** | Derived from the socket path (env-derived) |
| `ryoku-shell.sock` (doctor) | `ryoku` CLI probes it | `ryoku/cli/internal/doctor/doctor.go:3192` (off-disk) **[READ]** | Env-derived |
| `ryogami.sock` | Rust/Go wallpaper daemon surface + depth IPC socket | `ryoku/shell/ryogami/daemon/proto.go:87-92` (`socketPath()`); `ryoku/shell/ipc/ryogami.go:37-42` (`ryogamiSock()`); `:49` dial, `:199` subscribe; wall-ui client `ryoku/shell/ryogami/wall-ui/qml/services/DaemonClient.qml:396` **[READ]** | Env-derived `$XDG_RUNTIME_DIR/ryogami.sock`, falls back to `/tmp` |
| `ryoku-pill.sock` | Consolidated-pill command socket — **dead in production** (single shell omits `SocketServer`), retained for the retire phase | `ryoku/shell/ipc/actions.go:105-116` (`pillSockPath()` at `:109-113`) **[READ]** | Env-derived `$XDG_RUNTIME_DIR/ryoku-pill.sock` |
| `/run/polkit/agent-helper.socket` | systemd-socket-activated polkit helper; daemon dials it (polkit ≥126 dropped setuid helper) | `ryoku/shell/ipc/polkit.go:63-69` (`polkitHelperSocket` at `:69`), dialed at `:78` **[READ]** | **Absolute** package var (test-overridable) |
| `/usr/lib/polkit-1/polkit-agent-helper-1` | Fallback setuid polkit helper path (pre-126 installs) | `ryoku/shell/ipc/polkit.go:59-61` (`polkitHelperPath` at `:61`) **[READ]** | **Absolute** |
| `Quickshell ipc.sock` | Per-instance Quickshell socket under the instance runtime dir (pruned by the daemon) | `ryoku/shell/ipc/qsruntime.go:12,24,60,80,111` **[READ]** | Env-derived `$XDG_RUNTIME_DIR` |

### Q5.2 Lock / marker files

| Name | What it is | Where (file:line) | Env-derived / absolute |
|---|---|---|---|
| `/tmp/ryoku-hub.lock` | Flock held for the life of a Hub instance (Super+, single-instance) | `ryoku/shell/ipc/control.go:177-179` **[READ]**; QML callers `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/controlcenter/ControlCenter.qml:215`, `.../providers/actions/catalog.js:35`, `.../modules/desktop/WidgetMenu.qml:118`, `.../welcome/StepCustomize.qml:71`; comment `ryoku/hub/quickshell/shell.qml:44`; `ryoku/apps/ryostore/backend/routing.go:56` (off-disk) **[READ]** | **Absolute `/tmp`** (not env-derived) |
| `/tmp/ryoshot.lock` | Flock single-instance for the screenshot overlay | `ryoku/shell/quickshell/shell/modules/bar/Frame.qml:71`, `.../launcher/.../actions/catalog.js:22`, `.../services/Capture.qml:176` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryopin.lock` | Flock single-instance for the pin overlay | `ryoku/shell/quickshell/ryoshot/shell.qml:717` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryoku-keys.lock` | Flock single-instance for the keybind cheatsheet | `ryoku/shell/quickshell/shell/modules/launcher/shared/providers/actions/catalog.js:36` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryostore.lock`, `/tmp/ryovm.lock` | Flock single-instance for the store / VM apps | `ryoku/apps/ryostore/ryostore.desktop:6`, `ryoku/apps/ryovm/ryovm.desktop:6`, `ryoku/apps/ryostore/backend/routing.go:45` (off-disk) **[READ]** | **Absolute `/tmp`** |
| `$XDG_RUNTIME_DIR/ryoku-qsbar-brightness.lock` | Single-flock serialising rapid brightness taps | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/RyokuPower.js:26` **[READ]** | Env-derived `$XDG_RUNTIME_DIR`, falls back to `/tmp` |
| `$XDG_RUNTIME_DIR/qylock.<session>.<suffix>` | Lock-screen proof markers (`locked`, `expected`, `proof.lock`) | `ryoku/shell/ipc/actions.go:185-195` (`lockProofPath`/`lockMarker`) **[READ]** | Env-derived `$XDG_RUNTIME_DIR` + `$XDG_SESSION_ID` |
| `$XDG_RUNTIME_DIR/ryoku-power-cutover.lock` | Login/deploy power cutover flock | `ryoku/shell/deploy.sh:33`; `ryoku/cli/internal/doctor/reconcile_lockscreen.go:172` (off-disk) **[READ]** | Env-derived |
| `$XDG_RUNTIME_DIR/ryoku-update.lock` | Updates flock | `ryoku/cli/internal/updater/update.go:269` (off-disk) **[READ]** | Env-derived `XDG_RUNTIME_DIR` |
| `.../ryoku/eq/filter-chain.conf` | (see runtime dirs) pipewire eq config | `ryoku/shell/systemd/user/ryoku-eq.service:13` **[READ]** | `%t` = runtime dir |

### Q5.3 D-Bus names / interfaces / paths

**Claimed (owned) names — these are "identities" the daemon presents:**

| Name | What it is | Where (file:line) |
|---|---|---|
| `org.gnome.keyring.SystemPrompter` | The daemon **claims this session-bus name**, reimplementing gcr's prompt as an island | `ryoku/shell/ipc/prompter.go:31` (const), `:80` (`RequestName`), `:86` (owner check) **[READ]** |
| `/org/gnome/keyring/Prompter` | Exported object path for the prompter | `ryoku/shell/ipc/prompter.go:32`, `:77` (`Export`) **[READ]** |
| `org.gnome.keyring.internal.Prompter` | Interface implemented (gcr wire contract) | `ryoku/shell/ipc/prompter.go:33`; callbacks/errors `:34-39` **[READ]** |
| `org.kde.StatusNotifierWatcher` | The daemon runs the **system-tray host**; claims this name | `ryoku/shell/ipc/tray.go:32` (name), `:33` (path `/StatusNotifierWatcher`), `:34` (iface), `:139` (`RequestName`) **[READ]** |
| `org.freedesktop.Notifications` | Notification D-Bus provider is **Quickshell itself** (a keep-list feature), not the Go daemon | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/panels/NotificationPanel.qml:25` (comment), `ryoku/shell/quickshell/shell/services/Notifs.qml:4` (import `Quickshell.Services.Notifications`) **[READ]** |

**Consumed (client) names/interfaces — third-party, must not be renamed:**

| Name | Feature | Where (file:line) |
|---|---|---|
| `org.freedesktop.PolicyKit1(.Authority/.AuthenticationAgent/.Error.Failed)` | polkit auth agent | `ryoku/shell/ipc/polkit.go:43-48` **[READ]** |
| `org.freedesktop.login1(.Manager/.Session)` | suspend/sleep/wake + session lookup | `ryoku/shell/ipc/sleepwake.go:21-25`, `:119`; `ryoku/shell/ipc/polkit.go:489-494`, `:580-581` **[READ]** |
| `org.freedesktop.NetworkManager(.Settings/.Device/.Device.Wireless/.AccessPoint/.Connection.Active/.Settings.Connection)` | network/battery-adjacent status | `ryoku/shell/ipc/network.go:28-38` **[READ]** |
| `org.freedesktop.UPower.PowerProfiles` (+ `org.freedesktop.DBus.Properties`) | power profiles | `ryoku/shell/ipc/powerprofiles.go:26-28`, `:74`, `:191-192` **[READ]** |
| `org.mpris.MediaPlayer2.*` | media/lyrics | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/MprisArtwork.qml:24`; `ryoku/shell/ipc/music.go` (player option matching) **[READ]** |
| `org.freedesktop.portal.ScreenCast` / `org.freedesktop.portal.Desktop` | portal share-status probe | `ryoku/hub/backend/sharestatus.go:12-18,35` **[READ]** |
| `org.freedesktop.DBus` / `.Properties` | generic | `ryoku/hub/backend/aura.go:109`; `ryoku/shell/ipc/tray.go:37,582`; `ryoku/shell/ipc/sleepwake.go:644,804-806` **[READ]** |
| `org.freedesktop.secrets` / `org.freedesktop.Secret.*` | Secret Service (used by prompter interop + tests; production prompt path) | `ryoku/shell/ipc/e2e_manual_test.go:26,74-81`; `prompter_interop_test.go:64-162` **[READ]** |
| `org.gnome.desktop.interface` | gsettings accent/theme/fonts (wallpaper+matugen) | `ryoku/shell/ipc/matugen.go:1289,1361-1362,1390,1626-1628`; `icons.go:126` **[READ]** |
| `org.quickshell` | **app-id** targeted to raise the Hub window (not a bus name) | `ryoku/shell/ipc/control.go:158-161` **[READ]** |
| `org.kde.syntaxhighlighting` | QML code-block highlighting import | `ryoku/shell/quickshell/shell/components/CodeHighlight.qml:2` **[READ]** |
| `org.libvirt.unix.manage` | polkit action in generated VM domain | `ryoku/hub/backend/gpuapply.go:188` **[READ]** |

### Q5.4 Runtime directories

| Path | What it is | Where (file:line) |
|---|---|---|
| `$XDG_RUNTIME_DIR/ryoku-idle-output/` | idle-policy state (`lock`, `generation`) | `ryoku/shell/ipc/sleepwake.go:1028-1032` **[READ]** |
| `$XDG_RUNTIME_DIR/ryoku/pins/` | pin captures handed to `ryopin` | `ryoku/shell/CHANGELOG.md:1818` **[UNVERIFIED]** |
| `%t/ryoku/eq/filter-chain.conf` | pipewire equalizer config loaded by `ryoku-eq.service` | `ryoku/shell/systemd/user/ryoku-eq.service:13` **[READ]** |
| `$XDG_RUNTIME_DIR/ryogami-wall` | wall-ui picker runtime dir | `ryoku/shell/ryogami/wall-ui/qml/Config.qml:87` **[READ]** |
| `$XDG_RUNTIME_DIR/ryoku-update.json`, `.../ryoku-update-answer` | update progress island state/answer (Hub shells) | `ryoku/hub/quickshell/pages/UpdatesPage.qml:114-115`; `docs/cli.md:64`, `docs/updates.md:96` **[READ]/[UNVERIFIED]** |
| `$XDG_RUNTIME_DIR/ryoku-rashin/setup.json` | Rashin setup progress (Hub) | `ryoku/hub/quickshell/pages/RashinPage.qml:150`; `docs/rashin.md:357` **[READ]** |
| `$XDG_RUNTIME_DIR/qylock.locked` | lock-screen marker (legacy/CHANGELOG) | `ryoku/shell/CHANGELOG.md:3806`; `ryoku/shell/ipc/lock_test.go:144,151` **[READ]/[UNVERIFIED]** |

### Q5.5 Config / cache / state filesystem paths

| Path | Feature | Where (file:line) |
|---|---|---|
| `~/.config/ryoku/` (config dir) | base config dir | `ryoku/shell/ryogami/daemon/config.go:53-57` (`ryokuConfigDir()`) **[READ]** |
| `~/.config/ryoku/ryogami.json` | wallpaper daemon config | `ryoku/shell/ryogami/daemon/config.go:60`; `ryoku/cli/internal/doctor/reconcile_retired_wallpaper_keys.go:115` (off-disk) **[READ]** |
| `~/.config/ryoku/shell.json` | the shell's settings store (bar/dock/etc.) | `ryoku/shell/ryogami/daemon/config.go:202,232`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/WallpaperSelector.qml:52`; `ryoku/shell/ipc/daemon.go:156` **[READ]** |
| `~/.config/ryoku/theme.json` | selected theme | `ryoku/shell/ipc/matugen.go:407,432,451,495`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/settings/ThemeSettings.qml:21` **[READ]** |
| `~/.config/ryoku/matugen.json` | matugen knobs | `ryoku/shell/ipc/matugen.go:30`; `ThemeSettings.qml:34`; `MatugenSettings.qml:21` **[READ]** |
| `~/.config/ryoku/plugins.json` | plugin enable/placement | `ryoku/shell/ipc/bar.go:124,456` **[READ]** |
| `~/.config/ryoku/keyring.json` | keyring unlock policy | `docs/cli.md:165`; `ryoku/hub/quickshell/schema/LockscreenPage.js:34` **[UNVERIFIED]** |
| `~/.config/ryoku/hub.toml` | Hub persisted state | `ryoku/hub/backend/config.go:11` **[READ]** |
| `~/.config/ryoku/{desktop.json,lighting.json,gpu-presets.json}` | Hub state | `ryoku/hub/backend/desktop.go:18`, `lighting.go:11,53`, `gpupreset.go:226` **[READ]** |
| `~/.config/ryoku/rices/` | rice store | `ryoku/hub/backend/rice.go:18,1165` **[READ]** |
| `~/.config/ryogami-wall/config.json` | wall-ui picker config (skwd keys) | `ryoku/shell/ryogami/daemon/config.go:264-284`; `transitions.go:361-382`; `ryoku/shell/ryogami/wall-ui/qml/Config.qml:16` **[READ]** |
| `~/.cache/ryogami/` | ryogami cache (`colors.json`) | `ryoku/shell/ryogami/daemon/config.go:117-119`; `ryoku/shell/ryogami/wall-ui/data/config.json.example:53` **[READ]** |
| `~/.cache/ryoku/music` | music art/lyrics cache | `ryoku/shell/ipc/music.go:27` **[READ]** |
| `~/.cache/ryoku/colors.json` | the palette file the bridge serves | `ryoku/palette-bridge/main.go:240`; `doctor.sh:5` **[READ]** |
| `~/.cache/{claude,codex,opencode}-usage.json` | AI usage caches (AI feature) | `ryoku/shell/systemd/user/ryoku-ai-usage.service:2` **[READ]** |
| `~/.local/state/ryoku/ryostage/` | ryostage venv + models | `ryoku/shell/scripts/ryostage:24` **[READ]** |
| `~/.local/state/ryoku/{depth,parallax}` | legacy ryostage dirs (adopted by rename) | `ryoku/shell/scripts/ryostage:26-28` **[READ]** |

### Q5.6 `.desktop` / systemd unit names

| Name | Where (file:line) |
|---|---|
| `ryoku-hub.desktop` (`Name=Ryoku Hub`, `Exec=ryoku-shell hub open`) | `ryoku/hub/ryoku-hub.desktop:3,6` **[READ]** |
| `ryogami-wall.desktop` (`Name=Ryogami Wallpapers`, `Exec=ryogami wallpaper ui`) | `ryoku/shell/ryogami/wall-ui/data/ryogami-wall.desktop:3,6` **[READ]** |
| `ryostore.desktop`, `ryovm.desktop`, `ryoku-nvim.desktop` | `ryoku/apps/ryostore/ryostore.desktop:6`, `ryoku/apps/ryovm/ryovm.desktop:6`, `ryoku/apps/nvim/ryoku-nvim.desktop` (off-disk) **[READ]** |
| `ryoku-shell.service` | `ryoku/shell/systemd/user/ryoku-shell.service` **[READ]** |
| `ryogami.service` | `ryoku/shell/systemd/user/ryogami.service`; CLI refs `ryoku/cli/internal/doctor/reconcile_ryogami_wallpaper.go:26` (off-disk) **[READ]** |
| `ryoku-ai-usage.service` + `.timer` | `ryoku/shell/systemd/user/ryoku-ai-usage.service`,`ryoku-ai-usage.timer` **[READ]** |
| `ryoku-eq.service` | `ryoku/shell/systemd/user/ryoku-eq.service` **[READ]** |
| `ryoku-idle.service`, `ryoku-clamshell.service`, `ryoku-bootstrap.service`, `ryoku-session.target` | `ryoku/shell/systemd/user/` **[READ]** |
| `10-ryoku.conf` (xdg-desktop-portal-gnome drop-in) | `ryoku/shell/systemd/user/xdg-desktop-portal-gnome.service.d/10-ryoku.conf` **[READ]** |
| `ryoku-bootstrap.conf` (niri drop-in) | `ryoku/shell/systemd/user/niri.service.d/ryoku-bootstrap.conf` **[READ]** |
| `ryoku-palette-bridge.service` (`ExecStart=/usr/bin/ryoku-palette-bridge`) | `ryoku/palette-bridge/packaging/systemd/ryoku-palette-bridge.service:7` **[READ]** |
| `ryoku-rashin.service` | `ryoku/rashin/systemd/ryoku-rashin.service` (off-disk) **[READ]** |
| Package names `ryoku-shell`, `ryoku-hub`, `ryogami`, `ryoku-palette-bridge`, `ryoku-desktop`, `ryoku-rashin` | `release/packages/*/PKGBUILD` (off-disk) **[READ]** |

### Q5.7 Quickshell config names (`qs -c <name>`)

`hub` (`ryoku/shell/ipc/control.go:142`, `crashenv.go:7`), `shell`, `ryoshot`, `ryopin`, `keys`, `keys-hint`, `welcome`, `ryostore`, `ryovm` (dirs under `ryoku/shell/quickshell/`; off-disk `ryoku/apps/*/quickshell`). The Hub is selected by path when `RYOKU_SHELL_DIR` is set (`control.go:138-143`). **[READ]**

---

## Q4 — Network call inventory

Legend for "keep?" uses the Mei keep-list: bar/workspaces/launcher/control-sidebar/clock-date/audio/
brightness/network/battery/tray/notifications/wallpaper+matugen/trimmed ryoku-shell/Settings
appearance+shell.

### Q4.1 Go shell daemon (`ryoku/shell/ipc/*.go`) — feature output is streamed to QML, so QML never fetches

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://nagerholidays.com/api/v4/Holidays` | `ryoku/shell/ipc/calendar.go:19` **[READ]** | Holiday names in the calendar/clock popout | clock-date-adjacent → keep calendar locally, **disable network (holidays only)** |
| `https://lrclib.net/api/get` | `ryoku/shell/ipc/music.go:37` **[READ]** | Lyrics (exact match) | audio/media — **not on keep-list → disable** |
| `https://lrclib.net/api/search` | `ryoku/shell/ipc/music.go:38` **[READ]** | Lyrics (search) | media — disable |
| `https://api.deezer.com/search` | `ryoku/shell/ipc/music.go:39` **[READ]** | Cover-art fallback | media — disable |
| `https://itunes.apple.com/search` | `ryoku/shell/ipc/music.go:40` **[READ]** | Cover-art fallback | media — disable |
| `https://i.scdn.co`, `https://*.googleusercontent.com`, `https://i.ytimg.com/vi/...` | `ryoku/shell/ipc/music.go:541,543,634,663-664,677-679` **[READ]** | Art URL rewriting/upgrade | media — disable |
| `https://api.open-meteo.com/v1/forecast` | `ryoku/shell/ipc/weather.go:38` **[READ]** | Weather forecast | **weather NOT on keep-list → disable** |
| `https://geocoding-api.open-meteo.com/v1/search` | `ryoku/shell/ipc/weather.go:39` **[READ]** | Location geocoding | weather — disable |
| `https://ipwho.is/` | `ryoku/shell/ipc/weather.go:40` **[READ]** | Keyless IP-geolocation fallback (privacy) | weather — disable **especially this** |
| `https://air-quality-api.open-meteo.com/v1/air-quality` | `ryoku/shell/ipc/weather.go:41` **[READ]** | Air-quality | weather — disable |

No `net/http` calls elsewhere in `ipc/*.go` (network control is D-Bus/NetworkManager, not HTTP). **[READ]**

### Q4.2 Hub backend (`ryoku/hub/backend/*.go`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `http://127.0.0.1:47616/healthz` | `ryoku/hub/backend/palettebridge.go:122` (also `:131` Endpoint) **[READ]** | Local palette-bridge health for wallpaper/matugen | **keep** (loopback, part of wallpaper+matugen) |
| `https://github.com/ryoku-dev/ryostore/releases/download/rices/` | `ryoku/hub/backend/ricepublish.go:92` **[READ]** | Publish/fetch rices | **not on keep-list → disable** |
| `https://api.openai.com/v1` | `ryoku/hub/backend/voxtype.go:243` **[READ]** | Whisper cloud dictation endpoint written to config | AI dictation — **disable** |
| `127.0.0.1:6742` (TCP OpenRGB SDK) | `ryoku/hub/backend/openrgb.go:23,174`; `lighting.go:1155,1183` **[READ]** | RGB lighting control | not on keep-list → disable |
| `http://libvirt.org/schemas/...` | `ryoku/hub/backend/gpudomain.go:124` **[READ]** | XML **namespace URI** in generated domain (not a fetch) | harmless; GPU/VM only — drop with feature |

### Q4.3 Shell QML (`ryoku/shell/quickshell/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://api.duckduckgo.com/?q=...` (via `curl -s --max-time 8`) | `ryoku/shell/quickshell/shell/modules/launcher/shared/providers/web/Web.qml:93`; URL builder `.../web/ddg.js:8` **[READ]** | Launcher instant answers | launcher is kept — online answer optional; **keep or gate off** (browser-open still works) |
| Search URLs opened via `Qt.openUrlExternally` (`google.com`, `duckduckgo.com`, `youtube.com`, `github.com`, `wikipedia.org`, `aur.archlinux.org`, `npmjs.com`) | `.../launcher/shared/providers/web/engines.js:6-13`, `Web.qml:55` **[READ]** | Launcher `?`/`!bang` search (opens browser) | **keep** (user-initiated browser open, no daemon call) |
| `https://speed.cloudflare.com/__down`, `.../__up` (XHR GET/POST) | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/CloudflareSpeedTest.qml:21-22,106,201,223,278` **[READ]** | Network speed-test widget | network is kept but speed test is an extra widget — **optional; can gate off** |
| `https://litterbox.catbox.moe/resources/internals/api.php` | `ryoku/shell/quickshell/ryoshot/shell.qml:854` **[READ]** | Screenshot/annotation upload (ryoshot) | ryoshot not on keep-list → **disable** |
| `http://localhost:9000` (cobalt) + `yt-dlp` | `ryoku/shell/quickshell/shell/services/Stash.qml:61`; scripts `stash-cobalt.sh:19`; `stash-download.sh:25` **[READ]** | Stash media downloader | not on keep-list → **disable** |
| YouTube/SomaFM streams (`youtube.com/@.../live`, `ice1.somafm.com/...`) | `ryoku/shell/scripts/ryoku-cmd-radio:31-34` **[READ]** | Launcher radio provider | not on keep-list → **disable** |
| `https://api.anthropic.com/api/oauth/usage` | `ryoku/shell/bin/claude-usage:20` **[READ]** | AI usage pill | AI — **disable** (`codex-usage`/`opencode-usage` read local state only) **[READ]** |

### Q4.4 Hub QML (`ryoku/hub/quickshell/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://geocoding-api.open-meteo.com/v1/search` (via `curl`) | `ryoku/hub/quickshell/SettingsSheet.qml:998-999` **[READ]** | Weather location search in Settings | weather — **disable** |
| `http://127.0.0.1:<port>` | `ryoku/hub/quickshell/pages/RashinPage.qml:177` **[READ]** | Local Rashin/Hermes backend link | AI — **disable** |
| `https://api.openai.com/v1` (schema string) | `ryoku/hub/quickshell/schema/DictationPage.js:52` **[READ]** | Whisper remote preset | AI — **disable** |
| `https://github.com/...` credit/placeholder URLs | `ryoku/hub/quickshell/pages/CreditsPage.qml:24-55`; `ImportPage.qml:739`; `PluginsPage.qml:527` **[READ]** | Static links (no fetch) | harmless; drop with pages if trimmed |

### Q4.5 palette-bridge (`ryoku/palette-bridge/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `127.0.0.1:47616` (listener; routes `/colors.json`, `/v1/palette`, `/v1/events`, `/healthz`) | `ryoku/palette-bridge/main.go:241,255-258,267` **[READ]** | Serves wallpaper palette to browser integrations | local; wallpaper+matugen — **keep** if browser theming kept, else optional |
| `http://127.0.0.1:47616/v1/events` | `ryoku/palette-bridge/spicetify/ryoku-wallpaper-colors.js:6` **[READ]** | Spotify recolor | optional integration — drop if not wanted |
| `http://127.0.0.1:47616/v1/events` | `ryoku/palette-bridge/zen-extension/background.js:3`; `zen-extension/manifest.json:6` **[READ]** | Zen browser recolor | optional |
| `http://127.0.0.1:47616` | `ryoku/palette-bridge/doctor.sh:6` **[READ]** | Local health check | keep (loopback) |
| `https://upload.wikimedia.org/...` / `https://refact0r.github.io/...` | `ryoku/palette-bridge/templates/vesktop-colors.css:49`; `vesktop/midnight-ryoku.theme.css:7` **[READ]** | CSS assets fetched by Discord/vesktop, not the daemon | optional |

### Q4.6 ryogami wallpaper daemon + picker (`ryoku/shell/ryogami/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://wallhaven.cc/api/v1/search` | `ryoku/shell/ryogami/wall-ui/qml/wallpaper/WallhavenService.qml:190` **[READ]** | Online wallpaper search | wallpaper kept; **online source optional → gate off** |
| `https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/` | `ryoku/shell/ryogami/wall-ui/qml/wallpaper/SteamWorkshopService.qml:244` **[READ]** | Steam Workshop wallpapers | optional → gate off |
| `https://raw.githubusercontent.com/ryoku-dev/ryostore/main` | `RyowallsSource.qml:23` **[READ]** | Ryowalls catalogue | optional → gate off |
| `https://motionbgs.com`, `https://moewalls.com`, `https://go.moewalls.com/download.php`, regex on `moewalls.com/wp-content/...` | `RyowallsSource.qml:24-25,201,204,346` **[READ]** | Motion wallpaper scraping | optional → gate off |
| `https://api.github.com/repos/...`, `https://raw.githubusercontent.com/...`, `https://media.githubusercontent.com/media/...`, `https://wsrv.nl/?url=` | `RyowallsSource.qml:130-134,214,228-231` **[READ]** | Repo/thumbnail fetch | optional → gate off |
| (Rust daemon) | none found in `ryoku/shell/ryogami/daemon/*.rs` **[READ]** | — | wallpaper engine itself is offline — **keep** |

---

## Q6 — uv usage

`uv` is a Python project/venv manager. The `ryoku-shell` PKGBUILD hard-depends on it.

| Use | Where (file:line) | Feature it serves | Keep-list? |
|---|---|---|---|
| PKGBUILD `depends=(... 'uv')`, rationale comment | `release/packages/ryoku-shell/PKGBUILD:16-18` **[READ]** | provisions the ryostage Python 3.13 venv | no |
| `uv python install 3.13` / `uv venv` / `uv pip install` | `ryoku/shell/scripts/ryostage:348,357-362,371` **[READ]** | **ryostage** cut-out engine (Subject-in-front / Parallax; rembg + onnxruntime) | **not on keep-list** |
| PKGBUILD `depends=('uv' 'nodejs' 'gcc' ...)` | `release/packages/ryoku-rashin/PKGBUILD:21-29` **[READ]** | Rashin/Hermes installer+runtime | AI — excluded |
| `haveCmd("uv")` preflight | `ryoku/rashin/backend/setup.go:78-86,219` **[READ]** | Rashin preflight | AI — excluded |

**Verdict:** No keep-list feature needs `uv`. Its only shell-package consumer is `ryostage`
(the Stage/depth cut-out effect), which is an extra beyond the base wallpaper+matugen; the other
consumer is Rashin (AI). The base wallpaper engine is the Rust/go `ryogami`, matugen is Go/CLI, and
the picker is pure Rust/QML. If Stage and Rashin are excluded (as the keep-list implies), **drop
`uv` from `ryoku-shell`'s `depends`** and do not ship `ryostage`/`ryoku-rashin`. No other
`ryoku/shell/scripts/*` or `ryoku/shell/bin/*` or systemd unit invokes `uv`/`uvx` **[READ]**.

---

## Rename / redirect table for Mei

Prefix convention: `ryoku` → `mei`; daemon `ryogami` → `mei-wall`. Env vars `RYOKU_*` → `MEI_*`.
Third-party D-Bus and standard paths are **unchanged**.

| Artifact (current) | Kind | Where | Env/abs | Mei action |
|---|---|---|---|---|
| `ryoku-shell.sock` | socket | `ipc/main.go:18` + all QML clients | env `$XDG_RUNTIME_DIR` | → `mei-shell.sock` (update Go + every QML `sockPath`) |
| `ryoku-shell.sock.lock` | lock | `ipc/daemon.go:277` | env | derive from new socket name |
| `ryoku-pill.sock` | dead socket | `ipc/actions.go:113` | env | **delete** (consolidated-shell dead code) |
| `ryogami.sock` | socket | `ryogami/daemon/proto.go:92`, `ipc/ryogami.go:42`, `DaemonClient.qml:396` | env | → `mei-wall.sock` |
| `/tmp/ryoku-hub.lock` | lock | `control.go:179` + 4 QML + `ryostore/routing.go:56` | **abs `/tmp`** | → `/tmp/mei-hub.lock` |
| `/tmp/ryoshot.lock` | lock | Frame.qml:71, catalog.js:22, Capture.qml:176 | **abs `/tmp`** | → `/tmp/mei-shot.lock` (drop if ryoshot excluded) |
| `/tmp/ryopin.lock` | lock | ryoshot/shell.qml:717 | abs | drop (ryopin) |
| `/tmp/ryoku-keys.lock` | lock | catalog.js:36 | abs | → `/tmp/mei-keys.lock` |
| `ryoku-qsbar-brightness.lock` | lock | `qsbar/RyokuPower.js:26` | env | → `mei-qsbar-brightness.lock` |
| `qylock.<sess>.<suffix>` | markers | `ipc/actions.go:185-195` | env+`XDG_SESSION_ID` | → `mei-lock.<sess>.<suffix>` (keep suffix names `locked`/`expected`/`proof.lock`) |
| `ryoku-idle-output/` | runtime dir | `sleepwake.go:1028-1032` | env | → `mei-idle-output/` |
| `ryoku/eq/filter-chain.conf` | runtime path | `ryoku-eq.service:13` | `%t` | → `mei/eq/filter-chain.conf` |
| `ryoku/pins/` | runtime dir | CHANGELOG:1818 | env | → `mei/pins/` |
| `ryoku-update.json`, `ryoku-update-answer` | runtime files | `UpdatesPage.qml:114-115` | env | → `mei-update*.json` |
| `ryoku-rashin/setup.json` | runtime file | `RashinPage.qml:150` | env | drop (Rashin excluded) |
| `/run/polkit/agent-helper.socket` | socket | `polkit.go:69` | **abs, distro-owned** | **KEEP** (belongs to polkit, not Ryoku) |
| `/usr/lib/polkit-1/polkit-agent-helper-1` | path | `polkit.go:61` | abs | **KEEP** |
| `org.gnome.keyring.SystemPrompter` + `/org/gnome/keyring/Prompter` + `org.gnome.keyring.internal.Prompter` | D-Bus name/path/iface | `prompter.go:31-39,77-80` | n/a | **KEEP** (third-party contract; gnome-keyring/gcr drives it) |
| `org.kde.StatusNotifierWatcher` (+ `/StatusNotifierWatcher`) | D-Bus name/path | `tray.go:32-34,139` | n/a | **KEEP** (freedesktop/KDE tray contract, required for tray keep-list) |
| `org.freedesktop.*`, `org.mpris.*`, `org.gnome.desktop.interface` | D-Bus | polkit/network/upower/login1/portal/matugen | n/a | **KEEP** (all third-party) |
| `org.quickshell` | app-id | `control.go:161` | n/a | **KEEP** (Quickshell's own id) |
| `~/.config/ryoku/` + `ryogami.json`,`shell.json`,`theme.json`,`matugen.json`,`plugins.json`,`keyring.json`,`hub.toml`,`desktop.json`,`lighting.json`,`gpu-presets.json`,`rices/` | config | config.go:53-60; matugen.go; bar.go; hub/backend/* | `$XDG_CONFIG_HOME` | → `~/.config/mei/`; `ryogami.json`→`mei-wall.json`; add a one-time migrator (doctor `reconcile_*` already migrates keys) |
| `~/.config/ryogami-wall/config.json` | config | config.go:264-284; Config.qml:16 | `$XDG_CONFIG_HOME` | → `~/.config/mei-wall/config.json` |
| `~/.cache/ryogami/`, `~/.cache/ryoku/{music,colors.json}` | cache | config.go:117-119; music.go:27; main.go:240 | `$XDG_CACHE_HOME` | → `~/.cache/mei-wall/`, `~/.cache/mei/` |
| `~/.local/state/ryoku/ryostage` | state | ryostage:24 | `$XDG_STATE_HOME` | drop with Stage |
| `ryoku-shell.service`, `ryogami.service`, `ryoku-eq/-idle/-clamshell/-bootstrap.service`, `ryoku-session.target`, `10-ryoku.conf`, `ryoku-bootstrap.conf` | systemd units/drop-ins | `ryoku/shell/systemd/user/*` | n/a | rename units to `mei-*`/`mei-wall.service`; keep `PartOf`/`WantedBy` graph |
| `ryoku-ai-usage.service`/`.timer` | systemd | same dir | n/a | **drop** (AI) |
| `ryoku-palette-bridge.service`, `ryoku-rashin.service` | systemd | palette-bridge/rashin | n/a | rename bridge → `mei-palette-bridge`; drop rashin |
| `ryoku-hub.desktop`, `ryogami-wall.desktop`, `ryostore/ryovm/ryoku-nvim.desktop` | .desktop | hub/shell/apps | n/a | rename to `mei-*`; `Exec` follows new binary names |
| `ryoku-shell`, `ryoku-hub`, `ryogami`, package names | binaries/pkgs | PKGBUILDs | n/a | → `mei-shell`, `mei-hub`, `mei-wall` |
| `RYOKU_*` env (`RYOKU_POLKIT_AGENT`, `RYOKU_SHELL_DIR`, `RYOKU_CLIP_PERSIST`, `RYOKU_PLUGINS_DIR`, `RYOKU_PALETTE*`, hub `RYOKU_GPU_*`/`RYOKU_*_ROOT`/`RYOKU_DRYRUN`) | env | `polkit.go:35,180`; `actions.go:20`; `clipboard.go:45`; `bar.go:402`; `palette-bridge/doctor.sh:5-6`; `hub/backend/*` | n/a | → `MEI_*` (update unit `Environment=`, `environment.d/ryoku-session.conf:32`, deploy.sh) |
| `qs -c hub`/`shell`/`ryoshot`/`ryopin`/`keys`/`keys-hint`/`welcome` | Quickshell config names | control.go:142; quickshell/ | n/a | rename dirs if rebranding; `hub`→`mei-hub` config id |
| `127.0.0.1:47616` | palette bridge port | main.go:241; hub palettebridge.go:122; js/manifest | n/a | keep (loopback) or change + update integrations |
| `127.0.0.1:6742`, `localhost:9000` | OpenRGB / cobalt | openrgb.go:23; Stash.qml:61 | n/a | drop with RGB / Stash |

---

## Necessity / exclusions

Keep-list verdicts (what to **disable** or **remove**, not rebrand):

1. **Weather** — `weather.go:38-41` (open-meteo ×3, **`ipwho.is` IP-geolocation**) and Hub
   `SettingsSheet.qml:998-999`. Not on the keep-list. Removing also removes the third-party IP
   lookup (privacy win). Delete the daemon weather service, the `weather` state topic, the
   `Weather*` QML widgets/panels, and the Hub weather settings.
2. **Music lyrics/art** — `music.go:37-40` (lrclib, Deezer, iTunes) and the `scdn.co`/
   `googleusercontent`/`ytimg.com` art rewrites (`music.go:541-679`). If the media widget is kept
   for MPRIS metadata + local art only, strip the HTTP resolution block and the network cache.
   "audio" on the keep-list means volume/device control, not online lyric/art lookup.
3. **AI**: `bin/claude-usage:20` (anthropic), `ryoku-ai-usage.{service,timer}`,
   `hub/backend/voxtype.go:243` (OpenAI Whisper), `hub DictationPage.js:52`,
   `hub RashinPage.qml:177`, `ryoku-rashin` package/unit. Disable all.
4. **Rices/Ryostore publish** — `hub/backend/ricepublish.go:92` (GitHub releases). Not on keep-list;
   the Settings "appearance" surface can stay offline (themes/fonts/colors) but must not fetch rices.
5. **RGB lighting** — `hub/backend/openrgb.go:23,174`, `lighting.go:1155`. Drop with the feature.
6. **ryoshot screenshot upload** — `ryoshot/shell.qml:854` (litterbox). If screenshots are kept,
   strip the upload path; otherwise drop ryoshot entirely (also removes `/tmp/ryoshot.lock`,
   `/tmp/ryopin.lock`).
7. **Stash / media downloader** — `Stash.qml:61` (localhost:9000 cobalt), `stash-download.sh:25`
   (yt-dlp), `stash-cobalt.sh`, `ryoku-cmd-radio:31-34` (YouTube/SomaFM). Drop.
8. **Online wallpaper sources** — `ryogami/wall-ui` `WallhavenService.qml:190`,
   `SteamWorkshopService.qml:244`, `RyowallsSource.qml:23-25,130-231,346` (wallhaven, Steam Workshop,
   moewalls, motionbgs, GitHub raw, wsrv.nl). Wallpaper+matugen is on the keep-list, but the **local**
   engine and matugen need none of these; ship the picker with online sources removed or gated off.
9. **Network speed-test widget** — `CloudflareSpeedTest.qml:21-22`. Optional extra; gate off unless
   wanted under the kept "network" feature.
10. **Launcher web instant-answer** — `Web.qml:93` `/ ddg.js:8`. Launcher is on the keep-list; the
    `?`/`!bang` browser-open paths (`engines.js:6-13`) can stay, but the DDG `curl` fetch is an
    optional online extra — gate off (or leave, low risk, user-initiated).
11. **palette-bridge browser integrations** — spicetify/zen/vesktop files under
    `ryoku/palette-bridge/{spicetify,zen-extension,vesktop}`. The local loopback bridge
    (`main.go:241-258`) is fine; ship integrations only if browser recoloring is wanted.
12. **uv dependency** — drop from `ryoku-shell` `depends` (`PKGBUILD:16-18`) together with
    `ryostage` (Stage cut-out) and Rashin; no keep-list feature needs it.

Unchanged / must-not-touch: `/run/polkit/agent-helper.socket`, `/usr/lib/polkit-1/polkit-agent-helper-1`,
and every `org.freedesktop.*`/`org.kde.StatusNotifierWatcher`/`org.gnome.keyring.*`/`org.mpris.*`
D-Bus name — these are contracts with other software, not Ryoku branding.
