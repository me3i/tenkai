package main

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/godbus/dbus/v5"
)

// Media playback control.
//
// The shell reads MPRIS, so it knows which player is playing, but the daemon
// had no verb to drive it: the media keys had nothing to call. These verbs talk
// to the player over the **session bus**, which is local (no network), and
// they act on the player the shell last reported, so the key acts on the app
// the now-playing card is showing.
//
// The names match what the owner's keybinds need: play-pause, next, previous.

const (
	mprisPlayerIface = "org.mpris.MediaPlayer2.Player"
	mprisPlayersPath = "/org/mpris/MediaPlayer2"
)

// mediaMethod maps a verb to the MPRIS method it calls.
var mediaMethod = map[string]string{
	"playpause": "PlayPause",
	"play":      "Play",
	"pause":     "Pause",
	"next":      "Next",
	"previous":  "Previous",
	"stop":      "Stop",
}

// startMedia registers the playback verbs. The player is resolved per call, so
// a key always acts on whatever is playing now, not on a stale name.
func (d *daemon) startMedia() {
	for verb := range mediaMethod {
		verb := verb
		d.registerCall("media."+verb, func(json.RawMessage) (any, error) {
			return nil, d.mediaControl(verb)
		})
	}
}

// mediaControl drives the active MPRIS player.
func (d *daemon) mediaControl(verb string) error {
	method, ok := mediaMethod[verb]
	if !ok {
		return fmt.Errorf("err media: unknown action %q", verb)
	}
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		return fmt.Errorf("err media: %w", err)
	}
	defer conn.Close()

	name, err := d.mediaPlayerName(conn)
	if err != nil {
		return err
	}
	call := conn.Object(name, dbus.ObjectPath(mprisPlayersPath+"/player"))
	if err := call.Call(mprisPlayerIface+"."+method, 0).Err; err != nil {
		return fmt.Errorf("err media: %s on %s: %w", method, name, err)
	}
	return nil
}

// mediaPlayerName prefers the player the shell last reported (the now-playing
// card's player), so the key acts on the app on screen. With no report yet, it
// falls back to the first MPRIS player on the bus.
func (d *daemon) mediaPlayerName(conn *dbus.Conn) (string, error) {
	if d.music != nil {
		if name := strings.TrimSpace(d.music.player); name != "" {
			return name, nil
		}
	}
	var names []string
	if err := conn.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
		return "", fmt.Errorf("err media: cannot list the bus: %w", err)
	}
	for _, name := range names {
		if strings.HasPrefix(name, "org.mpris.MediaPlayer2.") && !strings.HasSuffix(name, ".instance") {
			return name, nil
		}
	}
	return "", fmt.Errorf("err media: no MPRIS player on the bus")
}
