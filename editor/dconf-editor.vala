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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

class ConfigurationEditor : Gtk.Application
{
    private Settings settings;
    private DConfWindow window;

    private const OptionEntry[] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print release version and exit"), null },
        { null }
    };

    private const GLib.ActionEntry[] action_entries =
    {
        { "about", about_cb },
        { "quit", quit }
    };

    /*\
    * * Application init
    \*/

    public ConfigurationEditor ()
    {
        Object (application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.FLAGS_NONE);

        add_main_option_entries (option_entries);
    }

    public static int main (string[] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        ConfigurationEditor app = new ConfigurationEditor ();
        return app.run (args);
    }

    protected override int handle_local_options (GLib.VariantDict options)
    {
        if (options.contains ("version"))
        {
            /* NOTE: Is not translated so can be easily parsed */
            stdout.printf ("%1$s %2$s\n", "dconf-editor", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }

        /* Activate */
        return -1;
    }

    protected override void startup ()
    {
        base.startup ();

        Environment.set_application_name (_("dconf Editor"));

        add_action_entries (action_entries, this);

        /* window */
        window = new DConfWindow ();

        settings = new Settings ("ca.desrt.dconf-editor.Settings");
        window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-fullscreen"))
            window.fullscreen ();
        else if (settings.get_boolean ("window-is-maximized"))
            window.maximize ();

        add_window (window);
    }

    protected override void activate ()
    {
        window.present ();
    }

    protected override void shutdown ()
    {
        base.shutdown ();
        settings.set_int ("window-width", window.window_width);
        settings.set_int ("window-height", window.window_height);
        settings.set_boolean ("window-is-maximized", window.window_is_maximized);
        settings.set_boolean ("window-is-fullscreen", window.window_is_fullscreen);
    }

    /*\
    * * App-menu callbacks
    \*/

    private void about_cb ()
    {
        string[] authors = { "Robert Ancell", "Arnaud Bonatti", null };
        string license = _("Dconf Editor is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version.\n\nDconf Editor is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU General Public License for more details.\n\nYou should have received a copy of the GNU General Public License along with this program. If not, see <http://www.gnu.org/licenses/>.");
        Gtk.show_about_dialog (this.get_active_window (),
                               "program-name", _("dconf Editor"),
                               "version", Config.VERSION,
                               "comments", _("Directly edit your entire configuration database"),
                               "copyright", _("Copyright \xc2\xa9 Canonical Ltd"),
                               "license", license,
                               "wrap-license", true,
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "logo-icon-name", "dconf-editor",
                               null);
    }
}
