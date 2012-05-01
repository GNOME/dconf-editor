class ConfigurationEditor : Gtk.Application
{
    private SettingsModel model;

    private Settings settings;
    private Gtk.Builder ui;
    private Gtk.ApplicationWindow window;
    private Gtk.TreeView dir_tree_view;
    private Gtk.TreeView key_tree_view;
    private Gtk.Grid key_info_grid;
    private Gtk.Label schema_label;
    private Gtk.Label summary_label;
    private Gtk.Label description_label;
    private Gtk.Label type_label;
    private Gtk.Label default_label;
    private Gtk.Action set_default_action;

    private Key? selected_key;

    public ConfigurationEditor()
    {
        Object(application_id: "ca.desrt.dconf-editor", flags: ApplicationFlags.FLAGS_NONE);
    }
    
    protected override void startup()
    {
        base.startup();

        settings = new Settings ("ca.desrt.dconf-editor.Settings");

        model = new SettingsModel();

        ui = new Gtk.Builder();
        try
        {
            string[] objects = { "set_default_action", "hpaned1" };
            ui.add_objects_from_file(Path.build_filename(Config.PKGDATADIR, "dconf-editor.ui"), objects);
        }
        catch (Error e)
        {
            critical("Failed to load UI: %s", e.message);
        }
        window = new Gtk.ApplicationWindow(this);
        window.set_default_size(600, 300);
        window.title = _("Configuration Editor");
        window.window_state_event.connect(main_window_window_state_event_cb);
        window.configure_event.connect(main_window_configure_event_cb);
        window.add((Gtk.HPaned)ui.get_object("hpaned1"));

        window.set_default_size (settings.get_int ("width"), settings.get_int ("height"));
        if (settings.get_boolean ("maximized"))
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

        /* Always select something */
        Gtk.TreeIter iter;
        if (model.get_iter_first(out iter))
            dir_tree_view.get_selection().select_iter(iter);
    }

    protected override void activate()
    {
        window.present();
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
            return "Integer [%s..%s]".printf(min.print(false), max.print(false));
        case "b":
            return "Boolean";
        case "s":
            return "String";
        case "<enum>":
            return "Enumeration";
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
                schema_name = selected_key.schema.schema.id;
                if (selected_key.schema.summary != null)
                    summary = selected_key.schema.summary;
                if (selected_key.schema.description != null)
                    description = selected_key.schema.description;
                type = key_to_description(selected_key);
                default_value = selected_key.schema.default_value.print(false);
            }
            else
            {
                schema_name = "No schema";
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
        if (!settings.get_boolean ("maximized"))
        {
            settings.set_int ("width", event.width);
            settings.set_int ("height", event.height);
        }

        return false;
    }

    private bool main_window_window_state_event_cb (Gtk.Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
        {
            var is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
            settings.set_boolean ("maximized", is_maximized);
        }

        return false;
    }

    public static int main(string[] args)
    {
        var app = new ConfigurationEditor();
        return app.run(args);
    }
}
