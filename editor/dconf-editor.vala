class ConfigurationEditor
{
    private SettingsModel model;

    private Gtk.Builder ui;
    private Gtk.Window window;
    private Gtk.TreeView dir_tree_view;
    private Gtk.TreeView key_tree_view;
    private Gtk.Label schema_label;
    private Gtk.Label summary_label;
    private Gtk.Label description_label;
    private Gtk.Label type_label;
    private Gtk.Label default_label;

    public ConfigurationEditor()
    {
        model = new SettingsModel();

        ui = new Gtk.Builder();
        try
        {
            ui.add_from_file(Path.build_filename(Config.PKGDATADIR, "dconf-editor.ui"));
        }
        catch (Error e)
        {
            critical("Failed to load UI: %s", e.message);
        }
        window = (Gtk.Window)ui.get_object("main_window");
        window.destroy.connect(Gtk.main_quit);

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

        schema_label = (Gtk.Label)ui.get_object("schema_label");
        summary_label = (Gtk.Label)ui.get_object("summary_label");
        description_label = (Gtk.Label)ui.get_object("description_label");
        type_label = (Gtk.Label)ui.get_object("type_label");
        default_label = (Gtk.Label)ui.get_object("default_label");

        /* Always select something */
        Gtk.TreeIter iter;
        if (model.get_iter_first(out iter))
            dir_tree_view.get_selection().select_iter(iter);
    }

    public void show()
    {
        window.show();
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

    private Key? get_selected_key()
    {
        Gtk.TreeIter iter;
        Gtk.TreeModel model;
        if (key_tree_view.get_selection().get_selected(out model, out iter))
        {
            var key_model = (KeyModel) model;
            return key_model.get_key(iter);
        }
        else
            return null;
    }

    private string type_to_description(string type)
    {
        switch(type)
        {
        case "i":
           return "Integer";
        case "b":
           return "Boolean";
        case "s":
           return "String";
        case "enum":
           return "Enumeration";
        default:
           return type;
        }
    }

    private void key_selected_cb()
    {
        var key = get_selected_key();
        string schema_name = "", summary = "", description = "", type = "", default_value = "";

        if (key != null)
        {
            if (key.schema != null)
            {
                schema_name = key.schema.schema.id;
                if (key.schema.summary != null)
                    summary = key.schema.summary;
                if (key.schema.description != null)
                    description = key.schema.description;
                type = type_to_description(key.schema.type);
                default_value = key.schema.default_value.print(false);
            }
            else
            {
                schema_name = "No schema";
            }
        }

        schema_label.set_text(schema_name);
        summary_label.set_text(summary);
        description_label.set_text(description.strip());
        type_label.set_text(type);
        default_label.set_text(default_value);
    }

    public static int main(string[] args)
    {
        Gtk.init(ref args);

        var editor = new ConfigurationEditor();
        editor.show ();

        Gtk.main();

        return 0;
    }
}
