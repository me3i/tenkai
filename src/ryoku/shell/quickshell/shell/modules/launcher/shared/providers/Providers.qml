import QtQuick
import "actions"
import "apps"

// Mei: the launcher is an application search. The off-list providers (web,
// radio, weather, packages, scripts, snippets, file find, calc, media, windows)
// are not instantiated: web and radio make network calls, the rest are out of
// scope. Actions stays because the main variant binds its category tab; every
// command in its catalog is local (some point at unbuilt helpers and simply
// fail if invoked).
Item {
    id: providers
    Actions { id: actionsProvider }
    Apps { id: appsProvider }

    property alias actions: actionsProvider
    property alias apps: appsProvider
}
