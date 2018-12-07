/*
  This file is part of Dconf Editor

  Dconf Editor is free software: you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation, either version 3 of the License, or
  (at your option) any later version.

  Dconf Editor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with Dconf Editor.  If not, see <https://www.gnu.org/licenses/>.
*/
/*
  This code has been inspired by the one for a similar function in Calendar
  https://gitlab.gnome.org/GNOME/gnome-calendar commit 474ce8b9da4a3322f2fe
  Copyright 2018 Georges Basile Stavracas Neto <georges.stavracas@gmail.com>
*/

private class NightLightMonitor : Object
{
    // warnings callable during init
    private const string warning_init_connection =
    "Impossible to get connection for session bus, night-light mode disabled.";
    private const string warning_init_dbus_proxy =
    "Impossible to get dbus proxy for session bus, night-light mode disabled.";
    private const string warning_cached_property =
    "Impossible to get cached property from proxy, night-light mode disabled.";

    // warnings callable when setting mode
    private const string warning_check_your_logs =
    "Something went wrong during the night mode support init, doing nothing.";
    private const string warning_get_gtksettings =
    "Something went wrong getting GtkSettings default object, doing nothing.";

    // schema static things
    private const string schema_name = "ca.desrt.dconf-editor.NightLight";  // TODO put in a library
    private const string automatic_night_mode_key = "automatic-night-mode";

    /*\
    * * Public interface
    \*/

    [CCode (notify = false)] public string schema_path { private get; internal construct; }

    public enum NightTime {
        UNKNOWN,
        NIGHT,
        DAY;

        internal static bool should_use_dark_theme (NightTime state)
        {
            return state == NightTime.NIGHT;
        }
    }
    [CCode (notify = true)] public NightTime  night_time            { internal get; private construct set; default = NightTime.UNKNOWN; }
    [CCode (notify = true)] public bool       dark_theme            { internal get; private construct set; default = false; }
    [CCode (notify = true)] public bool       automatic_night_mode  { internal get; private construct set; default = false; }

    internal NightLightMonitor (string _schema_path)
    {
        Object (schema_path: _schema_path);
        if (night_time == NightTime.UNKNOWN)    // disables mode if night_time has not been set at first try    // TODO specific warning?
            return;
        connect_properties ();
    }

    internal void set_use_night_mode (bool night_mode_state)
    {
        if (night_time == NightTime.UNKNOWN)    // do nothing but warn
            warning (warning_check_your_logs);
        else
        {
            paused = !night_mode_state;
            update ();
        }
    }

    /*\
    * * Init proxy
    \*/

    private GLib.Settings settings;
    private DBusProxy proxy;

    construct
    {
        settings = new GLib.Settings.with_path (schema_name, schema_path);
        automatic_night_mode = settings.get_boolean (automatic_night_mode_key);
        paused = !automatic_night_mode;

        DBusConnection? connection;
        init_connection (out connection);
        if (connection == null)
            return;

        DBusProxy? nullable_proxy;
        init_proxy ((!) connection, out nullable_proxy);
        if (nullable_proxy == null)
            return;

        proxy = (!) nullable_proxy;
        night_time = get_updated_night_time (ref proxy, automatic_night_mode);
    }

    private static void init_connection (out DBusConnection? connection)
    {
        try
        {
            connection = Bus.get_sync (BusType.SESSION, null);
        }
        catch (Error e)
        {
            warning (warning_init_connection);
            warning (e.message);
            connection = null;
        }
    }

    private static void init_proxy (DBusConnection connection, out DBusProxy? proxy)
    {
        try
        {
            proxy = new DBusProxy.sync (connection,
                                        DBusProxyFlags.GET_INVALIDATED_PROPERTIES,
                                        null,
                                        "org.gnome.SettingsDaemon.Color",
                                        "/org/gnome/SettingsDaemon/Color",
                                        "org.gnome.SettingsDaemon.Color",
                                        null);
        }
        catch (Error e)
        {
            warning (warning_init_dbus_proxy);
            warning (e.message);
            proxy = null;
        }
    }

    private static NightTime get_updated_night_time (ref DBusProxy proxy, bool automatic_night_mode)
    {
        Variant? variant_active = proxy.get_cached_property ("NightLightActive");
        Variant? variant_paused = proxy.get_cached_property ("DisabledUntilTomorrow");
        if (variant_active == null)
        {
            warning (warning_cached_property);
            return NightTime.UNKNOWN;
        }

        bool night_time_is_night = ((!) variant_active).get_boolean ();
        if (variant_paused != null)
            night_time_is_night = night_time_is_night && !(((!) variant_paused).get_boolean () && automatic_night_mode);

        if (night_time_is_night)
            return NightTime.NIGHT;
        else
            return NightTime.DAY;
    }

    /*\
    * * Private methods
    \*/

    private bool paused = false;

    private void connect_properties ()
    {
        proxy.g_properties_changed.connect (() => {
                night_time = get_updated_night_time (ref proxy, automatic_night_mode);
                if (night_time != NightTime.NIGHT)
                    paused = !automatic_night_mode;
                update ();
            });
        settings.changed [automatic_night_mode_key].connect ((_settings, _key_name) => {
                automatic_night_mode = _settings.get_boolean (_key_name);
                paused = !automatic_night_mode;
                update ();
            });
        update ();
    }

    private void update ()
    {
        if (automatic_night_mode)
        {
            if (paused)
                set_dark_theme_real (false);
            else
                set_dark_theme_real (NightTime.should_use_dark_theme (night_time));
        }
        else if (night_time == NightTime.NIGHT)
        {
            if (paused)
                set_dark_theme_real (false);
            else
                set_dark_theme_real (true);
        }
        else
            set_dark_theme_real (false);
    }
    private void set_dark_theme_real (bool night_mode)
    {
        if (_set_dark_theme_real (night_mode))
            dark_theme = night_mode;
    }
    private static bool _set_dark_theme_real (bool night_mode)
    {
        Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings == null)
        {
            warning (warning_get_gtksettings);
            return false;
        }

        if (night_mode != ((!) gtk_settings).gtk_application_prefer_dark_theme)
            ((!) gtk_settings).@set ("gtk-application-prefer-dark-theme", night_mode);
        return true;
    }
}
