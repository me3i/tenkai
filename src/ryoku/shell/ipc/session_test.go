package main

import "testing"

// The power guards decide whether a session action may reach the machine.
// They are read from the environment, so each one is proved here both ways:
// the flag on (the action is suppressed) and the flag off (the action would
// run). A guard that cannot fail is not a guard.
func TestPowerGuards(t *testing.T) {
	t.Setenv("MEI_TEST", "")
	t.Setenv("MEI_STUB_SHUTDOWN", "")
	t.Setenv("MEI_STUB_POWER", "")

	if testStubbed() {
		t.Fatal("MEI_TEST unset must not report a stubbed test session")
	}
	if powerStubbed() {
		t.Fatal("MEI_STUB_POWER unset must not report a stubbed power action")
	}
	if shutdownStubbed() {
		t.Fatal("MEI_STUB_SHUTDOWN unset must not report a stubbed shutdown")
	}

	t.Setenv("MEI_TEST", "1")
	if !testStubbed() {
		t.Fatal("MEI_TEST=1 must report a stubbed test session")
	}

	t.Setenv("MEI_TEST", "")
	t.Setenv("MEI_STUB_POWER", "1")
	if !powerStubbed() {
		t.Fatal("MEI_STUB_POWER=1 must report a stubbed power action")
	}

	t.Setenv("MEI_STUB_POWER", "")
	t.Setenv("MEI_STUB_SHUTDOWN", "1")
	if !shutdownStubbed() {
		t.Fatal("MEI_STUB_SHUTDOWN=1 must report a stubbed shutdown")
	}
}

// The mapping is the contract: every power action the sidebar offers has to
// exist, and nothing else may.
func TestSessionActionArgv(t *testing.T) {
	for _, action := range []string{"logout", "reboot", "suspend", "shutdown"} {
		if _, ok := sessionActionArgv(action); action == "logout" {
			if ok {
				t.Fatal("logout is not a systemctl action")
			}
			continue
		} else if !ok {
			t.Fatalf("session action %q is missing", action)
		}
	}
	if _, ok := sessionActionArgv("selfdestruct"); ok {
		t.Fatal("an unknown action must not resolve")
	}
}
