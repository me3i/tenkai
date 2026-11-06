pragma Singleton

import Quickshell
import Ryoku.Ui.Singletons

// One launcher for XDG desktop entries. Quickshell parses Terminal=true into
// runInTerminal but spawns no terminal for it, so a TUI (btop, yazi, nvim) got no
// tty and died at once; mei-app owns which terminal the user picked (ported
// from Mei's ryoku-app, trimmed to the terminal role).
//
// Launching goes through Spawn rather than DesktopEntry.execute(): execute()
// hands the child the desktop's whole environment, and a Quickshell app that
// inherits the crash handle in it relaunches the desktop instead of starting.
Singleton {
    id: root

    // run(entry) launches the entry; run(entry, action) launches one of its
    // actions, which inherit Terminal= from the entry that declares them.
    function run(entry, action) {
        const target = action || entry;
        if (!target)
            return;
        const argv = entry && entry.runInTerminal ? (target.command || []) : [];
        if (argv.length === 0) {
            // Every launch goes through mei-app, not straight to Spawn: in a
            // live run mei-app hands the app the owner's real HOME and XDG
            // variables (Mei's own state stays in the project). Without the
            // flag it is a pass-through, so the nested session is unchanged.
            const cmd = ["mei-app", "run", "--"];
            const direct = (target.command || []).map(String);
            for (let i = 0; i < direct.length; i++)
                cmd.push(direct[i]);
            Spawn.run(cmd, entry ? entry.workingDirectory : "");
            return;
        }
        const command = ["mei-app", "terminal", "--"];
        for (let i = 0; i < argv.length; i++)
            command.push(String(argv[i]));
        Spawn.run(command);
    }
}
