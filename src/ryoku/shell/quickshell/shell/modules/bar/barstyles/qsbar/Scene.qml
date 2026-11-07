// QS Bar (Quickshell Rise) entry, adapted to Tenkai's barstyle contract.
//
// Tenkai loads a barstyle Scene once per monitor via Frame's Loader, so this
// Scene hosts the single bar system a single time on the primary output. The
// VariantRoot inside fans one bar across every screen itself, so multi-monitor
// behaviour is unchanged.
//
// There is a single qsbar now: no V1/V2 variants, no runtime switch. The bar
// form (islands · full · fit · dock · notch) is a Theme property, not a
// separate implementation. IpcRouter owns the external IPC surface.

import Quickshell
import QtQuick
import "../../../../services/lib/screens.js" as Screens
import "."
import "core"

Item {
    id: sceneRoot

    // The screen, set by Frame's per-monitor Loader.
    property var modelData: null

    // TENKAI: the in-shell wallpaper picker lives on the hosted bar system
    // (VariantRoot -> Theme.openImagePicker), so Frame forwards a `wallpaper`
    // surface request here instead of launching the external ryogami picker this
    // build does not ship.
    function openPicker(mode) {
        if (host.item)
            host.item.openPicker(mode);
    }

    width: 0
    height: 0

    // Host the single shell system on exactly one Scene: the primary output, the
    // first entry of the shared deduped screen list (services/lib/screens.js).
    // Matching by name (not object identity) keeps exactly one Scene primary even
    // when a duplicate output announce briefly swaps the ShellScreen object, so
    // the bar system is never hosted twice.
    readonly property bool isPrimary: {
        var list = Screens.uniqueByName(Quickshell.screens)
        return list.length > 0 && !!sceneRoot.modelData
            && list[0].name === sceneRoot.modelData.name
    }

    Loader {
        id: host
        active: sceneRoot.isPrimary
        sourceComponent: Component {
            Item {
                // The seam Frame's `wallpaper` surface request calls into; the
                // bar system itself (VariantRoot) owns the picker, so the host
                // item forwards rather than reimplementing it.
                function openPicker(mode) { barRoot.openPicker(mode) }

                VariantRoot {
                    id: barRoot
                }

                IpcRouter {
                    barRoot: barRoot
                }
            }
        }
    }
}
