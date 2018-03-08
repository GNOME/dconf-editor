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

class ConfigurationEditor : Gtk.Application
{
    public static string [,] internal_mappings = {
            {"ca.desrt.dconf-editor.Bookmarks",
                "/ca/desrt/dconf-editor/"},
            {"ca.desrt.dconf-editor.Demo.EmptyRelocatable",
                "/ca/desrt/dconf-editor/Demo/EmptyRelocatable/"}
        };
    public static string [,] known_mappings = {
            {"com.gexperts.Tilix.Profile",
                "/com/gexperts/Tilix/profiles//"},
            {"org.gnome.builder.editor.language",
                "/org/gnome/builder/editor/language//"},
            {"org.gnome.builder.extension-type",
                "/org/gnome/builder/extension-types///"},   // doesn't help to discover interfaces of plugins, but it's hard to do more
            {"org.gnome.desktop.app-folders.folder",
                "/org/gnome/desktop/app-folders/folders//"},
            {"org.gnome.desktop.notifications.application",
                "/org/gnome/desktop/notifications/application//"},
            {"org.gnome.Epiphany.state",
                "/org/gnome/epiphany/state/"},
            {"org.gnome.Epiphany.state",
                "/org/gnome/epiphany/web-apps//state/"},
            {"org.gnome.Epiphany.web",
                "/org/gnome/epiphany/web/"},
            {"org.gnome.Epiphany.web",
                "/org/gnome/epiphany/web-apps//web/"},
            {"org.gnome.nm-applet.eap",
                "/org/gnome/nm-applet/eap//"},
            {"org.gnome.Terminal.Legacy.Profile",
                "/org/gnome/terminal/legacy/profiles://"},
            {"org.gnome.settings-daemon.plugins.media-keys.custom-keybinding",
                "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings//"},
            {"org.gnome.settings-daemon.plugins.sharing.service",
                "/org/gnome/settings-daemon/plugins/sharing//"},

            // TODO why a relocatable schema?
            {"org.gnome.Terminal.Legacy.Keybindings",
                "/org/gnome/terminal/legacy/keybindings/"},

            // https://bugzilla.gnome.org/show_bug.cgi?id=791387
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/beautifier_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/cargo_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/clang-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/cmake_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/code-index-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/color-picker-plugin/"},    // that's not color_picker_plugin
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/comment-code-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/c-pack-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/ctags-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/devhelp-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/documentation-card-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/eslint_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/find_other_file/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/flatpak-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/gcc-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/gdb-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/gettext-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/gnome-code-assistance-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/history-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/html-completion-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/html_preview_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/jedi_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/jhbuild_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/make_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/meson_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/mingw-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/mono_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/notification-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/npm_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/phpize_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/python_gi_imports_completion/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/python-pack-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/quick-highlight-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/retab-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/rust_langserv_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/rustup_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/spellcheck-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/symbol-tree-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/sysmon/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/sysprof-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/terminal/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/todo-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/vala-pack-plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/valgrind_plugin/"},
            {"org.gnome.builder.plugin", "/org/gnome/builder/plugins/xml-pack-plugin/"},

            // https://github.com/mate-desktop/mate-desktop/issues/300
            {"org.mate.panel.object",              "/org/mate/panel/objects//"},                // of the form object-x; see also bug
            {"org.mate.panel.toplevel",            "/org/mate/panel/toplevels//"},              // of the form toplevel-x
            {"org.mate.panel.toplevel.background", "/org/mate/panel/toplevels//background/"}    // in previous dirs
        };  // TODO add more well-known mappings

    private static string [] skipped_schemas = {
            "ca.desrt.dconf-editor.Demo.Relocatable",
            "org.gnome.Epiphany.permissions",   // keyfile backend ~/.config/epiphany/permissions.ini && ~/.config/epiphany/app-epiphany-*/permissions.ini
            "org.gnome.yelp.documents",         // keyfile backend ~/.config/yelp/yelp.cfg even if there's a dconf fallback (!)
            // TODO don't skip?
            "org.gnome.settings-daemon.peripherals.keyboard.deprecated",
            "org.gnome.settings-daemon.peripherals.mouse.deprecated",
            "org.gnome.settings-daemon.peripherals.touchpad.deprecated",
            "org.gnome.settings-daemon.peripherals.trackball.deprecated",
            "org.gnome.settings-daemon.peripherals.wacom.deprecated",
            "org.gnome.settings-daemon.peripherals.wacom.eraser.deprecated",
            "org.gnome.settings-daemon.peripherals.wacom.stylus.deprecated",
            "org.gnome.settings-daemon.peripherals.wacom.tablet-button.deprecated",
            // TODO disable such schemas automatically?
            "com.gexperts.Tilix.SettingsList",
            "org.gnome.Terminal.SettingsList"
        };

    private static bool disable_warning = false;
    private static string [] remaining = new string [3];

    private const OptionEntry [] option_entries =
    {
        { "version", 'v', 0, OptionArg.NONE, null, N_("Print release version and exit"), null },
        { "list-relocatable-schemas", 0, 0, OptionArg.NONE, null, N_("Print relocatable schemas and exit"), null },

        { "I-understand-that-changing-options-can-break-applications", 0, 0, OptionArg.NONE, ref disable_warning, N_("Do not show initial warning"), null },

        { OPTION_REMAINING, 0, 0, OptionArg.STRING_ARRAY, ref remaining, "args", N_("[PATH|FIXED_SCHEMA [KEY]|RELOCATABLE_SCHEMA:PATH [KEY]]") },
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
        Object (application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.HANDLES_COMMAND_LINE|ApplicationFlags.HANDLES_OPEN);

//        TODO needs gio-2.0 >= 2.56
//        set_option_context_parameter_string (_("..."));
//        set_option_context_summary (_("..."));
//        set_option_context_description (_("..."));

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
        if (options.contains ("list-relocatable-schemas"))
        {
            // get installed schemas

            string [] non_relocatable_schemas;
            string [] relocatable_schemas;

            SettingsSchemaSource? settings_schema_source = SettingsSchemaSource.get_default ();
            if (settings_schema_source == null)
            {
                warning ("No schema source!");
                return Posix.EXIT_FAILURE;
            }
            ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

            // sort out schemas ids

            string [] known_schemas_installed = {};
            string [] known_schemas_skipped = {};
            string [] unknown_schemas = {};

            string [] schemas_ids = {};
            for (int i = 0; i < known_mappings.length [0]; i++)
                schemas_ids += known_mappings [i,0];
            for (int i = 0; i < internal_mappings.length [0]; i++)
                schemas_ids += internal_mappings [i,0];

            foreach (string schema_id in relocatable_schemas)
            {
                if (schema_id in schemas_ids)
                    known_schemas_installed += schema_id;
                else if (schema_id in skipped_schemas)
                    known_schemas_skipped += schema_id;
                else
                    unknown_schemas += schema_id;
            }

            // print

            if (known_schemas_installed.length > 0)
            {
                stdout.printf (_("Known schemas installed:") + "\n");
                foreach (string schema_id in known_schemas_installed)
                    stdout.printf (@"  $schema_id\n");
            }
            else
                stdout.printf (_("No known schemas installed.") + "\n");
            stdout.printf ("\n");
            if (known_schemas_skipped.length > 0)
            {
                stdout.printf (_("Known schemas skipped:") + "\n");
                foreach (string schema_id in known_schemas_skipped)
                    stdout.printf (@"  $schema_id\n");
            }
            else
                stdout.printf (_("No known schemas skipped.") + "\n");
            stdout.printf ("\n");
            if (unknown_schemas.length > 0)
            {
                stdout.printf (_("Unknown schemas:") + "\n");
                foreach (string schema_id in unknown_schemas)
                    stdout.printf (@"  $schema_id\n");
            }
            else
                stdout.printf (_("No unknown schemas.") + "\n");
            return Posix.EXIT_SUCCESS;
        }
        return -1;
    }

    protected override void startup ()
    {
        base.startup ();

        Environment.set_application_name (_("dconf Editor"));
        Gtk.Window.set_default_icon_name ("ca.desrt.dconf-editor");

        add_action_entries (action_entries, this);
        set_accels_for_action ("ui.copy-path", { "<Primary><Shift>c" });

        Gtk.CssProvider css_provider = new Gtk.CssProvider ();
        css_provider.load_from_resource ("/ca/desrt/dconf-editor/ui/dconf-editor.css");
        Gdk.Screen? screen = Gdk.Screen.get_default ();
        return_if_fail (screen != null);
        Gtk.StyleContext.add_provider_for_screen ((!) screen, css_provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION);
    }

/*  TODO why calling this function makes the app crashy, even with '-DG_SETTINGS_ENABLE_BACKEND=1' (and even '-DGIO_COMPILATION=1') given?
    https://bugzilla.gnome.org/show_bug.cgi?id=791597
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
    } */

    /*\
    * * Window activation
    \*/

    protected override void activate ()
    {
        simple_activation ();
    }

    protected override void open (GLib.File [] files, string hint)
    {
        warning ("Flatpak test, " + files.length.to_string () + " files.");
        simple_activation ();
    }

    protected override int command_line (ApplicationCommandLine commands)
    {
        string [] args = {};
        foreach (string? i in remaining)
            if (i != null)
                args += (!) i;

        if (args.length == 0)
        {
            simple_activation ();
            return Posix.EXIT_SUCCESS;
        }
        Gtk.Window? test_window = get_active_window ();
        if (test_window != null)
        {
            commands.print (_("Only one window can be opened for now.\n"));
            ((!) test_window).present ();
            return Posix.EXIT_FAILURE;
        }

        string arg0 = strdup (args [0]);
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

        if (arg0.has_prefix ("/"))
        {
            Gtk.Window window = get_new_window (null, arg0, null);
            if (args.length == 2)
            {
                commands.print (_("Cannot understand second argument in this context.\n"));
                window.present ();
                return Posix.EXIT_FAILURE;
            }
            else
            {
                window.present ();
                return Posix.EXIT_SUCCESS;
            }
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

        string [] test_format = arg0.split (":", 2);
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

        Gtk.Window window = get_new_window (test_format [0], path, key_name);
        window.present ();
        return Posix.EXIT_SUCCESS;
    }

    private int failure_space (ApplicationCommandLine commands)
    {
        commands.print (_("Cannot understand: space character in argument.\n"));
        simple_activation ();
        return Posix.EXIT_FAILURE;
    }

    private void simple_activation ()
    {
        Gtk.Window? window = get_active_window ();
        if (window == null)
            window = get_new_window (null, null, null);
        ((!) window).present ();
    }

    private Gtk.Window get_new_window (string? schema, string? path, string? key_name)
    {
        DConfWindow window = new DConfWindow (disable_warning, schema, path, key_name);
        add_window (window);
        return (Gtk.Window) window;
    }

    /*\
    * * Copy action
    \*/

    private Notification notification = new Notification (_("Copied to clipboard"));
    private uint notification_number = 0;

    private void copy_cb (SimpleAction action, Variant? gvariant)
        requires (gvariant != null)
    {
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
        Gtk.Window? window = get_active_window ();
        if (window == null)
            return;
        Gtk.show_about_dialog ((!) window,
                               "program-name", _("dconf Editor"),
                               "version", Config.VERSION,
                               "comments", _("A graphical viewer and editor of applications’ internal settings."),
                               "copyright", _("Copyright \xc2\xa9 2010-2014 – Canonical Ltd\nCopyright \xc2\xa9 2015-2018 – Arnaud Bonatti\nCopyright \xc2\xa9 2017-2018 – Davi da Silva Böger"),
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
        Gtk.Window? window = get_active_window ();
        if (window != null)
            ((!) window).destroy ();

        base.quit ();
    }
}
