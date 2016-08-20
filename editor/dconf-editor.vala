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
    private const OptionEntry [] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print release version and exit"), null },
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
        Object (application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.FLAGS_NONE);

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
        return -1;
    }

    protected override void startup ()
    {
        base.startup ();

        Environment.set_application_name (_("dconf Editor"));
        Gtk.Window.set_default_icon_name ("dconf-editor");

        add_action_entries (action_entries, this);

        Gtk.CssProvider css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/ca/desrt/dconf-editor/ui/dconf-editor.css");
        Gdk.Screen? screen = Gdk.Screen.get_default ();
        return_if_fail (screen != null);
        Gtk.StyleContext.add_provider_for_screen ((!) screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);

        add_window (new DConfWindow ());
    }

    protected override void activate ()
    {
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
        copy (((!) gvariant).get_string ());
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
                               "comments", _("Directly edit your entire configuration database"),
                               "copyright", _("Copyright \xc2\xa9 2010-2014 – Canonical Ltd\nCopyright \xc2\xa9 2015-2016 – Arnaud Bonatti"),
                               "license-type", Gtk.License.GPL_3_0,
                               "wrap-license", true,
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "logo-icon-name", "dconf-editor",
                               null);
    }

    private void quit_cb ()
    {
        get_active_window ().destroy ();

        base.quit ();
    }
}
