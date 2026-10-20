#!/usr/bin/env python3
"""Minimal StatusNotifierItem + dbusmenu for the Mei tray test.

Registers on whatever bus DBUS_SESSION_BUS_ADDRESS names -- the nested private
bus only. It starts no app, opens no socket and touches no service: it just
publishes one tray item whose menu has two rows, and appends every call it
receives to --event-log so the harness can prove Activate/menu events arrived.

  --icon-name NAME   publish IconName (icon-theme path)
  --pixmap           publish a 24x24 IconPixmap instead (no theme lookup)
  --event-log PATH   where to append events
"""
import argparse
import os
import signal
import sys

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

ITEM_IFACE = "org.kde.StatusNotifierItem"
MENU_IFACE = "com.canonical.dbusmenu"
PROPS_IFACE = "org.freedesktop.DBus.Properties"
BUS_NAME = "org.kde.StatusNotifierItem.meitest"  # overridden by --bus-name
ITEM_PATH = "/StatusNotifierItem"
MENU_PATH = "/MenuBar"

parser = argparse.ArgumentParser()
parser.add_argument("--icon-name", default="dialog-information")
parser.add_argument("--pixmap", action="store_true")
parser.add_argument("--event-log", required=True)
parser.add_argument("--title", default="Mei Tray Test")
parser.add_argument("--bus-name", default="org.kde.StatusNotifierItem.meitest")
parser.add_argument("--no-register", action="store_true",
                    help="publish the objects without calling the watcher (reply probe)")
args = parser.parse_args()

logf = open(args.event_log, "a", buffering=1)


def log(msg):
    logf.write(msg + "\n")


def pixmap_24():
    # solid teal, ARGB32 big-endian (A,R,G,B)
    px = bytes([0xFF, 0x1F, 0x9E, 0x8F]) * (24 * 24)
    return dbus.Array([(dbus.Int32(24), dbus.Int32(24), dbus.ByteArray(px))],
                      signature="(iiay)")


def props():
    icon_name = "" if args.pixmap else args.icon_name
    return {
        "Category": dbus.String("ApplicationStatus", variant_level=1),
        "Id": dbus.String("mei-tray-test", variant_level=1),
        "Title": dbus.String(args.title, variant_level=1),
        "Status": dbus.String("Active", variant_level=1),
        "IconName": dbus.String(icon_name, variant_level=1),
        "IconThemePath": dbus.String("", variant_level=1),
        "IconPixmap": (pixmap_24() if args.pixmap else dbus.Array([], signature="(iiay)")),
        "AttentionIconName": dbus.String("", variant_level=1),
        "AttentionIconPixmap": dbus.Array([], signature="(iiay)"),
        "OverlayIconName": dbus.String("", variant_level=1),
        "OverlayIconPixmap": dbus.Array([], signature="(iiay)"),
        "ToolTip": dbus.Struct(
            (dbus.String(""), dbus.Array([], signature="(iiay)"),
             dbus.String(args.title), dbus.String("Mei tray acceptance item")),
            signature="sa(iiay)ss", variant_level=1),
        "ItemIsMenu": dbus.Boolean(True, variant_level=1),
        "Menu": dbus.ObjectPath(MENU_PATH, variant_level=1),
        "WindowId": dbus.UInt32(0, variant_level=1),
    }


class Item(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, ITEM_PATH)
        self._p = props()
        self._name = dbus.service.BusName(args.bus_name, bus)

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def Activate(self, x, y):
        log("Activate %d %d" % (int(x), int(y)))

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def SecondaryActivate(self, x, y):
        log("SecondaryActivate %d %d" % (int(x), int(y)))

    @dbus.service.method(ITEM_IFACE, in_signature="ii", out_signature="")
    def ContextMenu(self, x, y):
        log("ContextMenu %d %d" % (int(x), int(y)))

    @dbus.service.method(ITEM_IFACE, in_signature="is", out_signature="")
    def Scroll(self, delta, orientation):
        log("Scroll %d %s" % (int(delta), str(orientation)))

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return dbus.Dictionary(self._p, signature="sv")[prop]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return dbus.Dictionary(self._p, signature="sv")

    @dbus.service.method(PROPS_IFACE, in_signature="ssv", out_signature="")
    def Set(self, iface, prop, value):
        log("Set %s" % str(prop))

    @dbus.service.method("org.freedesktop.DBus.Introspectable",
                         in_signature="", out_signature="s")
    def Introspect(self):
        return "<node/>"


class Menu(dbus.service.Object):
    def __init__(self, bus):
        super().__init__(bus, MENU_PATH)
        self.revision = dbus.UInt32(1)

    def layout(self):
        # root -> two rows, one disabled: flat so the themed menu shows both
        # without a submenu hop.
        def row(i, text, enabled):
            return (dbus.Int32(i),
                    dbus.Dictionary({"label": dbus.String(text),
                                     "enabled": dbus.Boolean(enabled),
                                     "visible": dbus.Boolean(True)}, signature="sv"),
                    dbus.Array([], signature="v"))
        return (dbus.Int32(0),
                dbus.Dictionary({"children-display": dbus.String("submenu")}, signature="sv"),
                dbus.Array([row(1, "Say hello", True),
                            row(2, "Disabled row", False)], signature="v"))

    @dbus.service.method(MENU_IFACE, in_signature="iias", out_signature="(u(ia{sv}av))")
    def GetLayout(self, parent, depth, names):
        log("GetLayout %d %d" % (int(parent), int(depth)))
        return (self.revision, self.layout())

    @dbus.service.method(MENU_IFACE, in_signature="isvu", out_signature="")
    def Event(self, item_id, event_id, data, timestamp):
        log("MenuEvent %d %s" % (int(item_id), str(event_id)))

    @dbus.service.method(MENU_IFACE, in_signature="i", out_signature="b")
    def AboutToShow(self, item_id):
        log("AboutToShow %d" % int(item_id))
        return False

    @dbus.service.method(MENU_IFACE, in_signature="", out_signature="u")
    def GetRevision(self):
        return self.revision

    @dbus.service.method(PROPS_IFACE, in_signature="ss", out_signature="v")
    def GetProp(self, iface, prop):
        table = {"Version": dbus.UInt32(3), "Status": dbus.String("normal"),
                 "TextDirection": dbus.String("ltr"),
                 "IconThemePath": dbus.Array([], signature="s")}
        return table[prop]

    @dbus.service.method(PROPS_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAllProps(self, iface):
        return dbus.Dictionary({"Version": dbus.UInt32(3),
                                "Status": dbus.String("normal"),
                                "TextDirection": dbus.String("ltr"),
                                "IconThemePath": dbus.Array([], signature="s")},
                               signature="sv")

    @dbus.service.method("org.freedesktop.DBus.Introspectable",
                         in_signature="", out_signature="s")
    def Introspect(self):
        return "<node/>"


def main():
    DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()
    Item(bus)
    Menu(bus)

    if args.no_register:
        log("not registering (probe mode)")
    else:
        watcher = bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher")
        dbus.Interface(watcher, "org.kde.StatusNotifierWatcher") \
            .RegisterStatusNotifierItem(args.bus_name)
        log("registered " + args.bus_name)
    print("ready " + args.bus_name, flush=True)

    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *a: loop.quit())
    signal.signal(signal.SIGINT, lambda *a: loop.quit())
    loop.run()
    log("stopped")


if __name__ == "__main__":
    main()
