class ConfigurationEditor : Gtk.Application
{
    private SettingsModel model;

    private Settings settings;
    private Gtk.Builder ui;
    private Gtk.ApplicationWindow window;
    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_fullscreen = false;
    private Gtk.TreeView dir_tree_view;
    private Gtk.TreeView key_tree_view;
    private Gtk.Grid key_info_grid;
    private Gtk.Label schema_label;
    private Gtk.Label summary_label;
    private Gtk.Label description_label;
    private Gtk.Label type_label;
    private Gtk.Label default_label;
    private Gtk.Action set_default_action;
    private Gtk.Box search_box;
    private Gtk.Entry search_entry;
    private Gtk.Label search_label;

    private Key? selected_key;

    private const GLib.ActionEntry[] action_entries =
    {
        { "find",  find_cb  },
        { "about", about_cb },
        { "quit",  quit_cb  }
    };

    public ConfigurationEditor()
    {
        Object(application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.FLAGS_NONE);
    }

    protected override void startup()
    {
        base.startup();
        
        Environment.set_application_name (_("dconf Editor"));

        add_action_entries (action_entries, this);

        settings = new Settings ("ca.desrt.dconf-editor.Settings");

        model = new SettingsModel();

        ui = new Gtk.Builder();
        try
        {
            string[] objects = { "set_default_action", "box1", "menu" };
            ui.add_objects_from_file(Path.build_filename(Config.PKGDATADIR, "dconf-editor.ui"), objects);
        }
        catch (Error e)
        {
            error("Failed to load UI: %s", e.message);
        }
        window = new Gtk.ApplicationWindow(this);
        window.set_default_size(600, 300);
        window.title = _("dconf Editor");
        window.window_state_event.connect(main_window_window_state_event_cb);
        window.configure_event.connect(main_window_configure_event_cb);
        window.add((Gtk.Box)ui.get_object("box1"));

        var menu_ui = new Gtk.Builder();
        try
        {
            menu_ui.add_from_file(Path.build_filename(Config.PKGDATADIR, "dconf-editor-menu.ui"));
        }
        catch (Error e)
        {
            error("Failed to load menu UI: %s", e.message);
        }
        set_app_menu((MenuModel)menu_ui.get_object("menu"));

        window.set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-fullscreen"))
            window.fullscreen ();
        else if (settings.get_boolean ("window-is-maximized"))
            window.maximize ();

        dir_tree_view = new DConfDirView();
        dir_tree_view.set_model(model);
        dir_tree_view.get_selection().changed.connect(dir_selected_cb); // FIXME: Put in view
        dir_tree_view.show();
        var scroll = (Gtk.ScrolledWindow)ui.get_object("directory_scrolledwindow");
        scroll.add(dir_tree_view);

        key_tree_view = new DConfKeyView();
        key_tree_view.show();
        key_tree_view.get_selection().changed.connect(key_selected_cb);
        scroll = (Gtk.ScrolledWindow)ui.get_object("key_scrolledwindow");
        scroll.add(key_tree_view);

        key_info_grid = (Gtk.Grid)ui.get_object("key_info_grid");
        schema_label = (Gtk.Label)ui.get_object("schema_label");
        summary_label = (Gtk.Label)ui.get_object("summary_label");
        description_label = (Gtk.Label)ui.get_object("description_label");
        type_label = (Gtk.Label)ui.get_object("type_label");
        default_label = (Gtk.Label)ui.get_object("default_label");
        set_default_action = (Gtk.Action)ui.get_object("set_default_action");
        set_default_action.activate.connect(set_default_cb);

        search_box = (Gtk.Box)ui.get_object("search_box");
        search_entry = (Gtk.Entry)ui.get_object("search_entry");
        search_label = (Gtk.Label)ui.get_object("search_label");
        search_entry.activate.connect(find_next_cb);
        var search_box_close_button = (Gtk.Button)ui.get_object("search_box_close_button");
        search_box_close_button.clicked.connect(close_search_cb);

        var search_next_button = (Gtk.Button)ui.get_object("search_next_button");
        search_next_button.clicked.connect(find_next_cb);

        /* Always select something */
        Gtk.TreeIter iter;
        if (model.get_iter_first(out iter))
            dir_tree_view.get_selection().select_iter(iter);
    }
    
    private void close_search_cb ()
    {
        search_box.hide();
    }

    protected override void activate()
    {
        window.present();
    }

    protected override void shutdown ()
    {
        base.shutdown();
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.set_boolean ("window-is-fullscreen", window_is_fullscreen);
    }

    private void dir_selected_cb()
    {
        KeyModel? key_model = null;

        Gtk.TreeIter iter;
        if (dir_tree_view.get_selection().get_selected(null, out iter))
            key_model = model.get_directory(iter).key_model;

        key_tree_view.set_model(key_model);

        /* Always select something */
        if (key_model != null && key_model.get_iter_first(out iter))
            key_tree_view.get_selection().select_iter(iter);
    }

    private string key_to_description(Key key)
    {
        switch(key.schema.type)
        {
        case "y":
        case "n":
        case "q":
        case "i":
        case "u":
        case "x":
        case "t":
        case "d":
            Variant min, max;
            if (key.schema.range != null)
            {
                min = key.schema.range.min;
                max = key.schema.range.max;
            }
            else
            {
                min = key.get_min();
                max = key.get_max();
            }
            return _("Integer [%s..%s]").printf(min.print(false), max.print(false));
        case "b":
            return _("Boolean");
        case "s":
            return _("String");
        case "<enum>":
            return _("Enumeration");
        default:
            return key.schema.type;
        }
    }

    private void key_selected_cb()
    {
        if(selected_key != null)
            selected_key.value_changed.disconnect(key_changed_cb);
    
        Gtk.TreeIter iter;
        Gtk.TreeModel model;
        if (key_tree_view.get_selection().get_selected(out model, out iter))
        {
            var key_model = (KeyModel) model;
            selected_key = key_model.get_key(iter);
        }
        else
            selected_key = null;

        if(selected_key != null)
            selected_key.value_changed.connect(key_changed_cb);

        key_info_grid.sensitive = selected_key != null;
        set_default_action.sensitive = selected_key != null && !selected_key.is_default;

        string schema_name = "", summary = "", description = "", type = "", default_value = "";

        if (selected_key != null)
        {
            if (selected_key.schema != null)
            {
                var gettext_domain = selected_key.schema.gettext_domain;
                schema_name = selected_key.schema.schema.id;
                if (selected_key.schema.summary != null)
                    summary = selected_key.schema.summary;
                if (gettext_domain != null && summary != "")
                    summary = dgettext(gettext_domain, summary);
                if (selected_key.schema.description != null)
                    description = selected_key.schema.description;
                if (gettext_domain != null && description != "")
                    description = dgettext(gettext_domain, description);
                type = key_to_description(selected_key);
                default_value = selected_key.schema.default_value.print(false);
            }
            else
            {
                schema_name = _("No schema");
            }
        }

        schema_label.set_text(schema_name);
        summary_label.set_text(summary.strip());
        description_label.set_text(description.strip());
        type_label.set_text(type);
        default_label.set_text(default_value);
    }

    private void key_changed_cb(Key key)
    {
        set_default_action.sensitive = selected_key != null && !selected_key.is_default;
    }

    private void set_default_cb (Gtk.Action action)
    {
        if (selected_key == null)
            return;
        selected_key.set_to_default();
    }

    private bool main_window_configure_event_cb (Gtk.Widget widget, Gdk.EventConfigure event)
    {
        if (!window_is_maximized && !window_is_fullscreen)
        {
            window_width = event.width;
            window_height = event.height;
        }

        return false;
    }

    private bool main_window_window_state_event_cb (Gtk.Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        if ((event.changed_mask & Gdk.WindowState.FULLSCREEN) != 0)
            window_is_fullscreen = (event.new_window_state & Gdk.WindowState.FULLSCREEN) != 0;

        return false;
    }

    private void find_cb()
    {
        search_box.show();
        search_entry.grab_focus();
    }

    private void find_next_cb()
    {
        search_label.set_text("");

        /* Get the current position in the tree */
        Gtk.TreeIter iter;
        var key_iter = Gtk.TreeIter();
        var have_key_iter = false;
        if (dir_tree_view.get_selection().get_selected(null, out iter))
        {
            if (key_tree_view.get_selection().get_selected(null, out key_iter))
            {
                var dir = model.get_directory(iter);            
                if (dir.key_model.iter_next(ref key_iter))
                    have_key_iter = true;
                else
                    get_next_iter(ref iter);
            }
        }
        else if (!model.get_iter_first(out iter))
            return;

        var on_first_directory = true;
        do
        {
            /* Select next directory that matches */
            var dir = model.get_directory(iter);
            if (!have_key_iter)
            {
                have_key_iter = dir.key_model.get_iter_first(out key_iter);
                if (!on_first_directory && dir.name.index_of(search_entry.text) >= 0)
                {
                    dir_tree_view.expand_to_path(model.get_path(iter));
                    dir_tree_view.get_selection().select_iter(iter);
                    dir_tree_view.scroll_to_cell(model.get_path(iter), null, false, 0, 0);
                    return;
                }
            }
            on_first_directory = false;

            /* Select next key that matches */
            if (have_key_iter)
            {
                do
                {
                    var key = dir.key_model.get_key(key_iter);
                    if (key_matches(key, search_entry.text))
                    {
                        dir_tree_view.expand_to_path(model.get_path(iter));
                        dir_tree_view.get_selection().select_iter(iter);
                        dir_tree_view.scroll_to_cell(model.get_path(iter), null, false, 0, 0);
                        key_tree_view.get_selection().select_iter(key_iter);
                        key_tree_view.scroll_to_cell(dir.key_model.get_path(key_iter), null, false, 0, 0);
                        return;
                    }
                } while(dir.key_model.iter_next(ref key_iter));
            }
            have_key_iter = false;
        } while(get_next_iter(ref iter));

        search_label.set_text(_("Not found"));
    }

    private bool key_matches (Key key, string text)
    {
        /* Check key name */
        if (key.name.index_of(text) >= 0)
            return true;

        /* Check key schema (description) */
        if (key.schema != null)
        {
            if (key.schema.summary != null && key.schema.summary.index_of(text) >= 0)
                return true;
            if (key.schema.description != null && key.schema.description.index_of(text) >= 0)
                return true;
        }

        /* Check key value */
        if (key.value.is_of_type(VariantType.STRING) && key.value.get_string().index_of(text) >= 0)
            return true;

        return false;
    }

    private bool get_next_iter(ref Gtk.TreeIter iter)
    {
        /* Search children next */
        if (model.iter_has_child(iter))
        {
            model.iter_nth_child(out iter, iter, 0);
            return true;
        }

        /* Move to the next branch */
        while (!model.iter_next(ref iter))
        {
            /* Otherwise move to the parent and onto the next iter */
            if (!model.iter_parent(out iter, iter))
                return false;
        }

        return true;
    }

    private void about_cb()
    {
        string[] authors = { "Robert Ancell", null };
        string license = _("This program is free software; you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation; either version 2 of the License, or (at your option) any later version.\n\nThis program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more details.\n\nYou should have received a copy of the GNU General Public License along with this program; if not, write to the Free Software Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA");
        Gtk.show_about_dialog (window,
                               "program-name", _("dconf Editor"),
                               "version", Config.VERSION,
                               "comments",
                               _("Directly edit your entire configuration database"),
                               "copyright", _("Copyright \xc2\xa9 Canonical Ltd"),
                               "license", license,
                               "wrap-license", true,
                               "authors", authors,
                               "translator-credits", _("translator-credits"),
                               "logo-icon-name", "dconf-editor",
                               null);
    }

    private void quit_cb()
    {
        window.destroy();
    }

    public static int main(string[] args)
    {
		Intl.setlocale (LocaleCategory.ALL, "");
		Intl.bindtextdomain (Config.GETTEXT_PACKAGE, Config.LOCALEDIR);
		Intl.bind_textdomain_codeset (Config.GETTEXT_PACKAGE, "UTF-8");
		Intl.textdomain (Config.GETTEXT_PACKAGE);

        var app = new ConfigurationEditor();
        return app.run(args);
    }
}
