package main

import (
	"context"
	"encoding/json"
	"log"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"
)

// The lock.
//
// Mei's lock is the shell's own surface: the shell covers the screen with a
// clock and a password field, and the password is checked against PAM. It is
// deliberately NOT login1's session lock and NOT SDDM's greeter: logind's
// Lock() would lock the owner's whole session from a test, and the greeter is
// a different program entirely.
//
// The password never becomes an argument, an environment entry, a file or a
// log line: it goes from the shell to this daemon over the local control
// socket, and from here straight into the helper's standard input.

const (
	lockHelperName    = "mei-lock-verify"
	lockVerifyTimeout = 20 * time.Second
)

// lockHelperPath finds the helper next to the shell's sources, so the daemon
// always runs the one from this checkout.
func lockHelperPath() string {
	base := os.Getenv("MEI_SHELL_DIR")
	if base == "" {
		return ""
	}
	return filepath.Join(base, "scripts", lockHelperName)
}

// lockVerify checks a password and answers with a JSON reply. The password
// arrived on the socket's second line, so it is never in a command line.
func (d *daemon) lockVerify(password string) string {
	ok, reason := verifyLockPassword(password)
	if !ok {
		// The password itself is never logged, only the reason.
		log.Printf("mei-shell: lock verification refused: %s", reason)
	}
	reply, err := json.Marshal(map[string]any{"ok": ok, "reason": reason})
	if err != nil {
		return `{"ok":false,"reason":"the check could not be answered"}`
	}
	return string(reply)
}

// verifyLockPassword runs the PAM helper with the password on its standard
// input. It returns whether the password was accepted and, when it was not, a
// short reason that is safe to show.
func verifyLockPassword(password string) (bool, string) {
	// A harness seam for the success path: the test cannot know a real
	// password, so it can point the check at a command that answers instead.
	// The PAM path is the default and is what a live run uses.
	if cmd := strings.TrimSpace(os.Getenv("MEI_LOCK_VERIFY_CMD")); cmd != "" {
		run := exec.Command(cmd)
		run.Stdin = strings.NewReader(password + "\n")
		if err := run.Run(); err != nil {
			return false, "the password was refused"
		}
		return true, ""
	}
	helper := lockHelperPath()
	if helper == "" {
		return false, "the lock helper is not available"
	}
	if _, err := os.Stat(helper); err != nil {
		return false, "the lock helper is missing"
	}
	if password == "" {
		return false, "no password given"
	}
	ctx, cancel := context.WithTimeout(context.Background(), lockVerifyTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, helper)
	// The password goes in on stdin and nowhere else: not in argv, not in the
	// environment, not in a file, and not in the log.
	cmd.Stdin = strings.NewReader(password + "\n")
	var stderr strings.Builder
	cmd.Stderr = &stderr
	err := cmd.Run()
	if ctx.Err() != nil {
		return false, "the check timed out"
	}
	if err != nil {
		reason := strings.TrimSpace(stderr.String())
		if reason == "" {
			reason = "the password was refused"
		}
		// The helper's own message never contains the password.
		return false, reason
	}
	return true, ""
}
