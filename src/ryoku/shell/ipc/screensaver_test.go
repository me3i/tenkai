package main

import (
	"testing"

	"github.com/godbus/dbus/v5"
)

// TestScreenSaverSlotHeld drives the ScreenSaver service on a private bus.
//
// The first half is the refusal: a stand-in owner already holds the session's
// slot, so Mei must leave it alone. The second half is the other direction:
// with the slot free, Mei takes it. Together they prove the check can fail.
//
// The private bus is the one privateBus (media_test.go) starts, so the live
// session's names are never involved.
func TestScreenSaverSlotHeld(t *testing.T) {
	addr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	t.Setenv("MEI_SCREENSAVER_NAME", "1")

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("cannot connect to the private bus: %v", err)
	}
	defer conn.Close()

	// The stand-in owner: something else already holds the session's slot.
	holder := &screensaverAgent{}
	if err := conn.Export(holder, dbus.ObjectPath(screensaverPath), screensaverIface); err != nil {
		t.Fatalf("cannot export the stand-in owner: %v", err)
	}
	reply, err := conn.RequestName(screensaverName, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		t.Fatalf("the stand-in owner did not get the name: %v (%v)", err, reply)
	}

	// Now Mei tries. It must not get the name.
	d := &daemon{}
	d.registerTopic("screensaver")
	if d.startScreensaver() {
		t.Fatal("Mei took the screensaver name although the slot was held")
	}

	// And the other way round: with the slot free, Mei takes it.
	free := &daemon{}
	free.registerTopic("screensaver")
	freeAddr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", freeAddr)
	if !free.startScreensaver() {
		t.Fatal("Mei did not take the screensaver name although the slot was free")
	}
}

// TestScreenSaverInhibitCount drives the Inhibit/UnInhibit bookkeeping: the
// count goes up, the count goes down, and the count is what the shell's idle
// service watches.
func TestScreenSaverInhibitCount(t *testing.T) {
	addr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	t.Setenv("MEI_SCREENSAVER_NAME", "1")

	d := &daemon{}
	d.registerTopic("screensaver")
	if !d.startScreensaver() {
		t.Fatal("the service was not offered on a free slot")
	}

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("cannot connect: %v", err)
	}
	defer conn.Close()
	obj := conn.Object(screensaverName, dbus.ObjectPath(screensaverPath))

	call := obj.Call(screensaverIface+".Inhibit", 0, "a test app", "playing a video")
	if call.Err != nil {
		t.Fatalf("Inhibit failed: %v", call.Err)
	}
	var cookie uint32
	if err := call.Store(&cookie); err != nil {
		t.Fatalf("Inhibit returned no cookie: %v", err)
	}
	if cookie == 0 {
		t.Fatal("Inhibit returned the cookie 0")
	}

	active := screensaverActive(t, obj)
	if len(active) != 1 {
		t.Fatalf("GetActive reports %d inhibitors, want 1", len(active))
	}

	if err := obj.Call(screensaverIface+".UnInhibit", 0, cookie).Err; err != nil {
		t.Fatalf("UnInhibit failed: %v", err)
	}
	active = screensaverActive(t, obj)
	if len(active) != 0 {
		t.Fatalf("GetActive reports %d inhibitors after UnInhibit, want 0", len(active))
	}
}

// screensaverActive reads the interface's GetActive array.
func screensaverActive(t *testing.T, obj dbus.BusObject) []map[string]dbus.Variant {
	t.Helper()
	call := obj.Call(screensaverIface+".GetActive", 0)
	if call.Err != nil {
		t.Fatalf("GetActive failed: %v", call.Err)
	}
	var out []map[string]dbus.Variant
	if err := call.Store(&out); err != nil {
		t.Fatalf("GetActive returned nothing storable: %v", err)
	}
	return out
}
