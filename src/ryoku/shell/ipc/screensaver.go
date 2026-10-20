package main

import (
	"encoding/json"
	"log"
	"os"
	"sync"

	"github.com/godbus/dbus/v5"
)

// The org.freedesktop.ScreenSaver service.
//
// Chromium, Electron and some video players call this to say "do not sleep
// while I am playing". The previous shell provided the service, so without it
// those apps silently stop holding the idle off once that shell is gone.
//
// The service is only offered where it belongs: MEI_SCREENSAVER_NAME=1, which
// only the full live profile sets. The name is claimed with DoNotQueue, so if
// another agent already holds the session's slot the request fails and this
// daemon leaves it alone: two screensaver agents must never fight.
//
// The inhibitor count is published on the "screensaver" topic, which is what
// the shell's idle service watches: while the count is above zero the shell
// holds an idle inhibit of its own, so the compositor does not idle either.

const (
	screensaverName  = "org.freedesktop.ScreenSaver"
	screensaverPath  = "/org/freedesktop/ScreenSaver"
	screensaverIface = "org.freedesktop.ScreenSaver"
)

// screensaverAgent is the ScreenSaver service: Inhibit and UnInhibit, with
// the cookie the caller gets back.
type screensaverAgent struct {
	mu       sync.Mutex
	next     uint32
	active   map[uint32]struct{}
	onChange func(count int)
}

func newScreensaverAgent(onChange func(count int)) *screensaverAgent {
	return &screensaverAgent{active: map[uint32]struct{}{}, onChange: onChange}
}

// Inhibit(app, reason) returns the cookie the caller passes to UnInhibit.
func (a *screensaverAgent) Inhibit(app string, reason string) (uint32, *dbus.Error) {
	a.mu.Lock()
	a.next++
	cookie := a.next
	a.active[cookie] = struct{}{}
	count := len(a.active)
	change := a.onChange
	a.mu.Unlock()
	log.Printf("mei-shell: screensaver inhibit from %q (%q), %d active", app, reason, count)
	if change != nil {
		change(count)
	}
	return cookie, nil
}

// UnInhibit(cookie) releases one inhibit.
func (a *screensaverAgent) UnInhibit(cookie uint32) *dbus.Error {
	a.mu.Lock()
	delete(a.active, cookie)
	count := len(a.active)
	change := a.onChange
	a.mu.Unlock()
	log.Printf("mei-shell: screensaver inhibit released, %d active", count)
	if change != nil {
		change(count)
	}
	return nil
}

// GetActive is the other method of the interface: the running inhibitors, as
// the interface describes them (an array of "cookie" entries).
func (a *screensaverAgent) GetActive() ([]map[string]dbus.Variant, *dbus.Error) {
	a.mu.Lock()
	defer a.mu.Unlock()
	out := make([]map[string]dbus.Variant, 0, len(a.active))
	for cookie := range a.active {
		out = append(out, map[string]dbus.Variant{"cookie": dbus.MakeVariant(uint32(cookie))})
	}
	return out, nil
}

// startScreensaver offers the ScreenSaver service, but only where it is asked
// for and only when the name is free. It reports whether it took the slot.
func (d *daemon) startScreensaver() bool {
	topic := d.registerTopic("screensaver")
	agent := newScreensaverAgent(func(count int) {
		frame, _ := json.Marshal(map[string]any{"count": count})
		topic.publish(frame)
	})
	if os.Getenv("MEI_SCREENSAVER_NAME") != "1" {
		log.Printf("mei-shell: the screensaver service is not offered here (set MEI_SCREENSAVER_NAME=1)")
		return false
	}
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		log.Printf("mei-shell: screensaver service not offered: %v", err)
		return false
	}
	if err := conn.Export(agent, dbus.ObjectPath(screensaverPath), screensaverIface); err != nil {
		log.Printf("mei-shell: screensaver service not offered: %v", err)
		return false
	}
	// DoNotQueue: if the slot is taken, the request fails and the other agent
	// keeps it. Mei never steals the name.
	reply, err := conn.RequestName(screensaverName, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		log.Printf("mei-shell: screensaver service not offered (the slot is held): %v", err)
		return false
	}
	log.Printf("mei-shell: screensaver service offered (%s)", screensaverName)
	frame, _ := json.Marshal(map[string]any{"count": 0})
	topic.publish(frame)
	return true
}
