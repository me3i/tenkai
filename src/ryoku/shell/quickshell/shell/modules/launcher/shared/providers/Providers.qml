import QtQuick
import "apps"

// Mei: the launcher is an application search. Every off-list provider (actions,
// web, radio, weather, packages, scripts, snippets, file find, calc, media,
// windows) is not instantiated: web and radio make network calls, the rest are
// out of scope. The "/" command mode belongs to the Actions provider, so it is
// disabled with it (owner decision). The provider files stay on disk.
Item {
    id: providers
    Apps { id: appsProvider }

    property alias apps: appsProvider
}
