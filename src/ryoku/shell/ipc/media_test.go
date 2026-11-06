package main

import (
	"bufio"
	"os/exec"
	"strings"
	"sync"
	"testing"

	"github.com/godbus/dbus/v5"
)

// A fake MPRIS player, so the media verbs can be proved against a real bus
// without a real player. It records which method was called.
type fakePlayer struct {
	mu    sync.Mutex
	calls []string
}

func (f *fakePlayer) record(name string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.calls = append(f.calls, name)
}

func (f *fakePlayer) called() []string {
	f.mu.Lock()
	defer f.mu.Unlock()
	out := make([]string, len(f.calls))
	copy(out, f.calls)
	return out
}

func (f *fakePlayer) PlayPause() *dbus.Error { f.record("PlayPause"); return nil }
func (f *fakePlayer) Play() *dbus.Error      { f.record("Play"); return nil }
func (f *fakePlayer) Pause() *dbus.Error     { f.record("Pause"); return nil }
func (f *fakePlayer) Next() *dbus.Error      { f.record("Next"); return nil }
func (f *fakePlayer) Previous() *dbus.Error  { f.record("Previous"); return nil }
func (f *fakePlayer) Stop() *dbus.Error      { f.record("Stop"); return nil }
func (f *fakePlayer) Raise() *dbus.Error     { return nil }
func (f *fakePlayer) Lower() *dbus.Error     { return nil }
func (f *fakePlayer) SetPosition(o dbus.ObjectPath, v int64) *dbus.Error {
	return nil
}

// privateBus starts a private session bus and returns its address.
func privateBus(t *testing.T) string {
	t.Helper()
	cmd := exec.Command("dbus-daemon", "--session", "--fork", "--print-address=1")
	out, err := cmd.Output()
	if err != nil {
		t.Skipf("dbus-daemon is not available: %v", err)
	}
	addr := strings.TrimSpace(string(out))
	if addr == "" {
		// --fork with --print-address can print on stderr
		t.Skip("dbus-daemon printed no address")
	}
	return addr
}

// TestMediaControl drives a fake MPRIS player: the verb must reach the player
// the shell reported, and the "no player" case must fail cleanly.
func TestMediaControl(t *testing.T) {
	addr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("cannot connect to the private bus: %v", err)
	}
	defer conn.Close()

	player := &fakePlayer{}
	const name = "org.mpris.MediaPlayer2.tenkaitest"
	reply, err := conn.RequestName(name, dbus.NameFlagDoNotQueue)
	if err != nil || reply != dbus.RequestNameReplyPrimaryOwner {
		t.Fatalf("cannot own %s: %v (%v)", name, err, reply)
	}
	if err := conn.Export(player, dbus.ObjectPath(mprisPlayersPath+"/player"), "org.mpris.MediaPlayer2.Player"); err != nil {
		t.Fatalf("cannot export the fake player: %v", err)
	}

	d := &daemon{music: &musicState{player: name}}

	if err := d.mediaControl("playpause"); err != nil {
		t.Fatalf("media.playpause failed: %v", err)
	}
	if err := d.mediaControl("next"); err != nil {
		t.Fatalf("media.next failed: %v", err)
	}
	if err := d.mediaControl("previous"); err != nil {
		t.Fatalf("media.previous failed: %v", err)
	}
	got := player.called()
	want := []string{"PlayPause", "Next", "Previous"}
	if len(got) != len(want) {
		t.Fatalf("the player got %v, want %v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("the player got %v, want %v", got, want)
		}
	}

	// an unknown action must not reach the player
	before := len(player.called())
	if err := d.mediaControl("selfdestruct"); err == nil {
		t.Fatal("an unknown media action must be refused")
	}
	if len(player.called()) != before {
		t.Fatal("an unknown media action reached the player")
	}

	// With no player reported and none on the bus, the verb must fail
	// cleanly. That needs a bus of its own: the fake player above would
	// otherwise be found by the fallback.
	emptyAddr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", emptyAddr)
	empty := &daemon{music: &musicState{}}
	if err := empty.mediaControl("playpause"); err == nil {
		t.Fatal("media control with no player must fail")
	}
}

// TestMediaMethodMap: the verb table and the MPRIS method table must agree.
func TestMediaMethodMap(t *testing.T) {
	for verb, method := range mediaMethod {
		if method == "" {
			t.Fatalf("the verb %q has no MPRIS method", verb)
		}
	}
	if _, ok := mediaMethod["selfdestruct"]; ok {
		t.Fatal("an unknown action must not be in the table")
	}
}

// The bus helper must be able to list the players, or the fallback in
// mediaPlayerName is dead code.
func TestPrivateBusListsNames(t *testing.T) {
	addr := privateBus(t)
	t.Setenv("DBUS_SESSION_BUS_ADDRESS", addr)
	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		t.Fatalf("cannot connect: %v", err)
	}
	defer conn.Close()
	var names []string
	if err := conn.BusObject().Call("org.freedesktop.DBus.ListNames", 0).Store(&names); err != nil {
		t.Fatalf("cannot list names: %v", err)
	}
	if len(names) == 0 {
		t.Fatal("the private bus listed no names")
	}
	_ = bufio.NewReader
}
