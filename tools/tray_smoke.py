"""Run under xvfb-run -a dbus-run-session: private tray host, restore and Quit test.

Usage: python3 tools/tray_smoke.py agent/target/release/agent
Needs python3-gi, Xvfb, xfwm4 and xwininfo. Never uses the real desktop's bus/config.
"""
import os
import pathlib
import subprocess
import sys
import tempfile
import time
from gi.repository import Gio, GLib


def wait(predicate, message):
    deadline = time.monotonic() + 20
    while time.monotonic() < deadline:
        while GLib.MainContext.default().iteration(False):
            pass
        value = predicate()
        if value:
            return value
        time.sleep(0.05)
    raise AssertionError(message)


bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
registered = []
xml = '''<node><interface name="org.kde.StatusNotifierWatcher">
<method name="RegisterStatusNotifierItem"><arg type="s" direction="in"/></method>
<property name="IsStatusNotifierHostRegistered" type="b" access="read"/>
</interface></node>'''


def register(conn, sender, path, interface, method, params, invocation):
    registered.append(params.unpack()[0])
    invocation.return_value(None)


bus.register_object('/StatusNotifierWatcher',
                    Gio.DBusNodeInfo.new_for_xml(xml).interfaces[0], register,
                    lambda *args: GLib.Variant('b', True), None)
bus.call_sync('org.freedesktop.DBus', '/org/freedesktop/DBus', 'org.freedesktop.DBus',
              'RequestName', GLib.Variant('(su)', ('org.kde.StatusNotifierWatcher', 0)),
              None, Gio.DBusCallFlags.NONE, 3000, None)
wm = subprocess.Popen(['xfwm4', '--compositor=off'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
app = None
try:
    with tempfile.TemporaryDirectory(prefix='deskctrl-tray-smoke-') as config:
        folder = pathlib.Path(config) / 'deskctrl'
        folder.mkdir()
        (folder / 'minimize-to-tray').write_text('true')
        env = dict(os.environ, XDG_CONFIG_HOME=config, DESK_NO_USB='1',
                   DESK_NO_VOICE='1', DESK_PORT='8794', DESK_TOKEN='traysmoketest', WGPU_BACKEND='gl')
        app = subprocess.Popen([str(pathlib.Path(sys.argv[1]).resolve()), '--minimized'], env=env)
        service = wait(lambda: registered and registered[0], 'tray did not register')

        def windows():
            return subprocess.check_output(['xwininfo', '-root', '-tree'], text=True)

        def window_id():
            for line in windows().splitlines():
                if '"ViL Agent"' in line:
                    return line.split()[0]

        wid = wait(window_id, 'agent window not created')

        def mapped():
            return 'Map State: IsViewable' in subprocess.check_output(['xwininfo', '-id', wid], text=True)

        wait(lambda: not mapped(), 'minimized window was not hidden')
        menu_path = bus.call_sync(service, '/StatusNotifierItem', 'org.freedesktop.DBus.Properties',
                                  'Get', GLib.Variant('(ss)', ('org.kde.StatusNotifierItem', 'Menu')),
                                  None, Gio.DBusCallFlags.NONE, 3000, None).unpack()[0]
        layout = bus.call_sync(service, menu_path, 'com.canonical.dbusmenu', 'GetLayout',
                               GLib.Variant('(iias)', (0, -1, [])), None,
                               Gio.DBusCallFlags.NONE, 3000, None).unpack()[1]
        items = {item[1].get('label'): item[0] for item in layout[2]}

        def click(label):
            bus.call_sync(service, menu_path, 'com.canonical.dbusmenu', 'Event',
                          GLib.Variant('(isvu)', (items[label], 'clicked', GLib.Variant('i', 0), 0)),
                          None, Gio.DBusCallFlags.NONE, 3000, None)

        click('Show ViL')
        wait(mapped, 'Show ViL did not restore the window')
        # Let the WM finish processing restore/focus before sending a separate close request.
        time.sleep(0.5)
        subprocess.run(['wmctrl', '-i', '-c', wid], check=True)
        wait(lambda: not mapped(), 'window close did not hide to tray')
        assert app.poll() is None, 'window close stopped the agent'
        click('Show ViL')
        wait(mapped, 'Show did not restore the window after close')
        click('Close application')
        wait(lambda: app.poll() is not None, 'Quit did not stop the agent')
        assert app.returncode == 0, app.returncode
        print('PASS: minimize hides; Show restores; window close hides without exiting; Show restores again; Close application exits cleanly')
finally:
    if app is not None and app.poll() is None:
        app.terminate()
        app.wait(timeout=10)
    wm.terminate()
    wm.wait(timeout=10)
