package main

import (
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"strings"

	wm "ryoku-wm"
)

// testStubbed reports whether Mei is running a nested test session, where the
// session power actions must never reach the host (AGENTS.md rule 7). The QML
// SessionActions singleton carries the same guard; this one is defence in depth.
func testStubbed() bool { return os.Getenv("MEI_TEST") == "1" }

// shutdownStubbed reports the live trial's one remaining stub: the power
// actions are real in a live run (MEI_TEST is not set there), but shutdown
// stays stubbed for the first trial so a stray confirmation cannot power the
// machine off. The QML singleton carries the same guard.
func shutdownStubbed() bool { return os.Getenv("MEI_STUB_SHUTDOWN") == "1" }

// powerStubbed reports the live trial's wider stub: no power action may end
// the owner's session by accident. MEI_STUB_POWER=1 covers logout, reboot,
// suspend and shutdown. Lock is not a power action and is never stubbed here.
// The QML singleton carries the same guard.
func powerStubbed() bool { return os.Getenv("MEI_STUB_POWER") == "1" }

// session.go runs the session power actions the confirmation dialog triggers.
// Reboot and shutdown are system-level, so they go through systemctl. Logout
// ends the session by asking the compositor to exit, through the wm seam.
//
// There is deliberately no suspend action: the reference tree has none.
var sessionActions = map[string][]string{
	"reboot":   {"systemctl", "reboot"},
	"shutdown": {"systemctl", "poweroff"},
	// Suspend is a power action like the others: the same systemctl path, the
	// same stubs. The coordinated sleep transaction in sleepwake.go is a
	// different thing (it suspends only after a compositor-secure lock) and is
	// not what a power button means.
	"suspend": {"systemctl", "suspend"},
}

// sessionActionArgv returns the argv for a session power action, or false for an
// unknown one. Split from the exec so the documented mapping is unit-testable
// without powering the machine off.
func sessionActionArgv(action string) ([]string, bool) {
	argv, ok := sessionActions[action]
	return argv, ok
}

// startSession registers the session power-action calls the confirmation dialog
// invokes. Registration only: no process is spawned here.
func (d *daemon) startSession() {
	d.registerCall("session.logout", func(json.RawMessage) (any, error) {
		if testStubbed() {
			log.Printf("mei-shell: [mei-stub] suppressed session logout (MEI_TEST=1)")
			return map[string]any{"ok": true}, nil
		}
		if powerStubbed() {
			log.Printf("mei-shell: [mei-stub] suppressed session logout (MEI_STUB_POWER=1)")
			return map[string]any{"ok": true}, nil
		}
		if err := d.wmc.Act(wm.ActionSessionExit); err != nil {
			log.Printf("mei-shell: session logout: %v", err)
		}
		return map[string]any{"ok": true}, nil
	})
	for action := range sessionActions {
		action := action
		d.registerCall("session."+action, func(json.RawMessage) (any, error) {
			runSessionAction(action)
			return map[string]any{"ok": true}, nil
		})
	}
}

// runSessionAction fires the action's command and reaps it in the background, so
// a failure is logged without blocking the caller (reboot and poweroff normally
// never return). stderr is captured for the log; stdin and stdout are discarded.
func runSessionAction(action string) {
	if testStubbed() {
		log.Printf("mei-shell: [mei-stub] suppressed session %s (MEI_TEST=1)", action)
		return
	}
	if powerStubbed() {
		log.Printf("mei-shell: [mei-stub] suppressed session %s (MEI_STUB_POWER=1)", action)
		return
	}
	if action == "shutdown" && shutdownStubbed() {
		log.Printf("mei-shell: [mei-stub] suppressed session shutdown (MEI_STUB_SHUTDOWN=1)")
		return
	}
	argv, ok := sessionActionArgv(action)
	if !ok {
		log.Printf("mei-shell: unknown session action %q", action)
		return
	}
	cmd := exec.Command(argv[0], argv[1:]...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	if err := cmd.Start(); err != nil {
		log.Printf("mei-shell: session %s: %v", action, err)
		return
	}
	go func() {
		if err := cmd.Wait(); err != nil {
			log.Printf("mei-shell: session %s: %v: %s", action, err, strings.TrimSpace(stderr.String()))
		}
	}()
}
