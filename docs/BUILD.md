# BUILD.md — one command, from a clean checkout

```
./install.sh          # builds, then asks before each system step; `n` skips them all
./install.sh --dry-run  # prints the plan, writes nothing
```

`install.sh` is the only build entry; there is no Makefile, justfile or `./tenkai
build`. Step 2 does all of the building, before any prompt, so answering `n` to
every prompt gives a full build with no system writes (no systemd units, no
Hyprland deploy, no package installs, no sudo).

## What step 2 produces

| Artefact | Path |
| --- | --- |
| Go daemons | `.run/bin/{tenkai-shell,tenkai-hub,tenkai-wm-hyprland,ryogami}` |
| Blobs plugin | `.run/build/blobs/qml/Tenkai/Blobs/*.so`, copied to `.run/qml/Tenkai/Blobs` |
| QML import tree | `.run/qml/Tenkai/{Ui,FrameBars,PluginKit,Wm/Hyprland,Blobs}`, each with a `qmldir` |

The QML tree is assembled by the script itself (`sync_dir` calls in
`install.sh`), not by hand. The launcher exports `QML2_IMPORT_PATH` /
`QML_IMPORT_PATH` = `$RUN/qml` (`tenkai:1601`, `:1643`, `:2243`), and the shell
imports the plugin as `import Tenkai.Blobs` (`Frame.qml:6`,
`popouts/Popout.qml:4`, `capture/CameraOverlay.qml:7`). The plugin's `qmldir`
declares `module Tenkai.Blobs`, `classname Tenkai_BlobsPlugin`; only the binary
target keeps the old file name (`libryoku-blobsplugin.so`), which QML never
sees.

## Measured on 2026-11-08

Clean copy of `HEAD` produced with `git archive HEAD | tar -x -C <empty dir>`
(no `.run` present), then `yes n | ./install.sh` → exit 0.

```
f8c4469f2b4e371b24dee5981024db8d382732d5b705876776b4137667b17e26  .run/bin/tenkai-shell
07a947e2b96880f6ab586cb60a736b8e82518cb05423665e75640e24488dac8c  .run/bin/tenkai-hub
3188198ac87bcbf1ab474d779a272afc229fcc46c7939c73eb47276f515ca5c8  .run/bin/tenkai-wm-hyprland
d824a81f84b88292b929d37c0251ae81b84cb39acb748fefee8644fce5b30a6e  .run/bin/ryogami
```

These hashes are a record, not a reproducible-build guarantee: Go binaries embed
build paths and the toolchain version, so a different machine or Go version will
differ. What was proven is that the four binaries and the whole QML tree come out
of one documented command on an empty checkout.

**Not proven here:** that the assembled tree actually renders. Starting it would
join or disturb the live session, which this pass is not allowed to do.
