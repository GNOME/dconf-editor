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
    private bool disable_warning = false;

    private const OptionEntry [] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print release version and exit"), null },
        { "I-understand-that-changing-options-can-break-applications", 0, 0, OptionArg.NONE, null, N_("Do not show initial warning"), null },
        {}
    };

    private const GLib.ActionEntry [] action_entries =
    {
        // generic
        { "copy", copy_cb, "s" },   // TODO is that really the good way to do things? (see Taquin)

        // app-menu
        { "about", about_cb },
        { "quit", quit_cb }
    };

    /*\
    * * Application init
    \*/

    public static int main (string [] args)
    {
        Intl.setlocale (LocaleCategory.ALL, "");
        Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
        Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
        Intl.textdomain (Config.GETTEXT_PACKAGE);

        ConfigurationEditor app = new ConfigurationEditor ();
        return app.run (args);
    }

    public ConfigurationEditor ()
    {
        Object (application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.HANDLES_COMMAND_LINE);

        add_main_option_entries (option_entries);
    }

    protected override int handle_local_options (VariantDict options)
    {
        if (options.contains ("version"))
        {
            /* NOTE: Is not translated so can be easily parsed */
            stdout.printf ("%1$s %2$s\n", "dconf-editor", Config.VERSION);
            return Posix.EXIT_SUCCESS;
        }
        if (options.contains ("I-understand-that-changing-options-can-break-applications"))
            disable_warning = true;
        return -1;
    }

    protected override void startup ()
    {
        base.startup ();

        Environment.set_application_name (_("dconf Editor"));
        Gtk.Window.set_default_icon_name ("ca.desrt.dconf-editor");

        add_action_entries (action_entries, this);

        Gtk.CssProvider css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/ca/desrt/dconf-editor/ui/dconf-editor.css");
        Gdk.Screen? screen = Gdk.Screen.get_default ();
        return_if_fail (screen != null);
        Gtk.StyleContext.add_provider_for_screen ((!) screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        test_backend ();
    }

    private static void test_backend ()
    {
        SettingsBackend? backend1 = SettingsBackend.get_default ();
        if (backend1 == null)
            return; // TODO something, probably
        string backend_name = ((!) backend1).get_type ().name ();
        if (backend_name == "GMemorySettingsBackend")       // called with GSETTINGS_BACKEND=memory
            warning (_("The Memory settings backend is used, no change will be saved on quit."));
        else if (backend_name == "GNullSettingsBackend")    // called with GSETTINGS_BACKEND=null
            warning (_("The Null settings backend is used, changes will not be saved."));
        else if (backend_name != "DConfSettingsBackend")
            warning (_("The backend used is unknown [%s], bad thing might happen.").printf (backend_name));
        else                                                // called by default or with GSETTINGS_BACKEND=dconf
            info (_("Looks like the DConf settings backend is used, all looks good."));
    }

    /*\
    * * Window activation
    \*/

    private bool first_window = true;

    protected override void activate ()
    {
        simple_activation ();
    }

    protected override int command_line (ApplicationCommandLine commands)
    {
        string [] args = commands.get_arguments ();

        if (args.length == 0)
        {
            assert_not_reached ();
            simple_activation ();
            return Posix.EXIT_FAILURE;
        }
        if (args.length == 1)   // ['dconf-editor']
        {
            simple_activation ();
            return Posix.EXIT_SUCCESS;
        }
        if (args.length > 1 && !first_window)
        {
            commands.print (_("Only one window can be opened for now.\n"));
            get_active_window ().present ();
            return Posix.EXIT_FAILURE;
        }

        args = args [1:args.length];

        string arg0 = args [0];
        if (" " in arg0)
        {
            if (args.length == 1)
            {
                args = arg0.split (" ");
                arg0 = args [0];
            }
            else
                return failure_space (commands);
        }

        if (args.length > 2)
        {
            commands.print (_("Cannot understand: too many arguments.\n"));
            simple_activation ();
            return Posix.EXIT_FAILURE;
        }

        int ret = Posix.EXIT_SUCCESS;

        if (arg0.has_prefix ("/"))
        {
            if (args.length == 2)
            {
                commands.print (_("Cannot understand second argument in this context.\n"));
                ret = Posix.EXIT_FAILURE;
            }
            DConfWindow window = new DConfWindow (disable_warning, null, arg0, null);
            add_window (window);
            first_window = false;
            window.present ();
            return ret;
        }

        string? key_name = null;

        if (args.length == 2)
        {
            key_name = args [1];
            if (" " in (!) key_name)
                return failure_space (commands);
            if ("/" in (!) key_name)
            {
                commands.print (_("Cannot understand: slash character in second argument.\n"));
                simple_activation ();
                return Posix.EXIT_FAILURE;
            }
        }

        string [] test_format = arg0.split (":");

        if (test_format.length > 2)
        {
            commands.print (_("Cannot understand: too many colons.\n"));
            simple_activation ();
            return Posix.EXIT_FAILURE;
        }

        string? path = null;

        if (test_format.length == 2)
        {
            path = test_format [1];
            if (!((!) path).has_prefix ("/") || !((!) path).has_suffix ("/"))
            {
                commands.print (_("Schema path should start and end with a “/”.\n"));
                simple_activation ();
                return Posix.EXIT_FAILURE;
            }
        }

        DConfWindow window = new DConfWindow (disable_warning, test_format [0], path, key_name);
        add_window (window);
        first_window = false;
        window.present ();
        return ret;
    }

    private int failure_space (ApplicationCommandLine commands)
    {
        commands.print (_("Cannot understand: space character in argument.\n"));
        simple_activation ();
        return Posix.EXIT_FAILURE;
    }

    private void simple_activation ()
    {
        if (first_window)
        {
            add_window (new DConfWindow (disable_warning, null, null, null));
            first_window = false;
        }
        get_active_window ().present ();
    }

    /*\
    * * Copy action
    \*/

    private Notification notification = new Notification (_("Copied to clipboard"));
    private uint notification_number = 0;

    private void copy_cb (SimpleAction action, Variant? gvariant)
    {
        if (gvariant == null)
            return;
        copy (((!) gvariant).get_string ().compress ());
    }

    public void copy (string text)
    {
        // clipboard
        Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null)
            return;

        Gtk.Clipboard clipboard = Gtk.Clipboard.get_default ((!) display);
        clipboard.set_text (text, text.length);

        // notification
        clean_copy_notification ();

        notification_number = Timeout.add_seconds (30, () => {
                withdraw_notification ("copy");
                notification_number = 0;
                return Source.REMOVE;
            });

        notification.set_body (text);
        send_notification ("copy", notification);
    }

    public void clean_copy_notification ()
    {
        if (notification_number > 0)
        {
            withdraw_notification ("copy");         // TODO needed, report bug: Shell cancels previous notification of the same name, instead of replacing it
            Source.remove (notification_number);
            notification_number = 0;
        }
    }

    /*\
    * * App-menu callbacks
    \*/

    public void about_cb ()
    {
        string [] authors = { "Robert Ancell", "Arnaud Bonatti" };
        Gtk.show_about_dialog (get_active_window (),
                               "program-name", _("dconf Editor"),
                               "version", Config.VERSION,
                               "comments", _("A graphical viewer and editor of applications’ internal settings."),
                               "copyright", _("Copyright \xc2\xa9 2010-2014 – Canonical Ltd\nCopyright \xc2\xa9 2015-2017 – Arnaud Bonatti"),
                               "license-type", Gtk.License.GPL_3_0,
                               "wrap-license", true,
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "logo-icon-name", "ca.desrt.dconf-editor",
                               "website", "https://wiki.gnome.org/Apps/DconfEditor",
                               null);
    }

    private void quit_cb ()
    {
        get_active_window ().destroy ();

        base.quit ();
    }
}
