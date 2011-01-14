public class EditorWindow : Gtk.Window
{
    public SettingsModel model;

    private Gtk.TreeView dir_tree_view;
    private Gtk.TreeView key_tree_view;
    private Gtk.Label schema_label;
    private Gtk.Label summary_label;
    private Gtk.Label description_label;
    private Gtk.Label type_label;
    private Gtk.Label default_label;

    public EditorWindow()
    {
        set_title("Configuration Editor");
        set_default_size(600, 300);
        set_border_width(6);
        
        Gtk.HBox hbox = new Gtk.HBox(false, 6);
        hbox.show();
        add(hbox);

        model = new SettingsModel();

        Gtk.ScrolledWindow scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC);
        scroll.show();
        hbox.pack_start(scroll, false, false, 0);

        dir_tree_view = new DConfDirView();
        dir_tree_view.set_model(model);
        dir_tree_view.get_selection().changed.connect(dir_selected_cb); // FIXME: Put in view
        dir_tree_view.show();
        scroll.add(dir_tree_view);

        Gtk.VBox vbox = new Gtk.VBox(false, 6);
        vbox.show();
        hbox.pack_start(vbox, true, true, 0);
        
        scroll = new Gtk.ScrolledWindow(null, null);
        scroll.set_policy(Gtk.PolicyType.AUTOMATIC, Gtk.PolicyType.AUTOMATIC);
        scroll.show();
        vbox.pack_start(scroll, true, true, 0);

        key_tree_view = new DConfKeyView();
        key_tree_view.show();
        key_tree_view.get_selection().changed.connect(key_selected_cb);
        scroll.add(key_tree_view);

        Gtk.Table schema_table = new Gtk.Table(0, 2, false);
        schema_table.set_row_spacings(6);
        schema_table.set_col_spacings(6);
        schema_table.show();
        vbox.pack_start(schema_table, false, true, 0);

        schema_label = add_row(schema_table, 0, "Schema:");
        summary_label = add_row(schema_table, 1, "Summary:");
        description_label = add_row(schema_table, 2, "Description:");
        type_label = add_row(schema_table, 3, "Type:");
        default_label = add_row(schema_table, 4, "Default:");

        /* Always select something */
        Gtk.TreeIter iter;
        if (model.get_iter_first(out iter))
            dir_tree_view.get_selection().select_iter(iter);
    }
    
    private Gtk.Label add_row(Gtk.Table table, int row, string title)
    {
        var name_label = new Gtk.Label(title);
        name_label.set_alignment(0.0f, 0.0f);
        table.attach(name_label, 0, 1, row, row+1,
                     Gtk.AttachOptions.FILL,
                     Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.FILL, 0, 0);

        var value_label = new Gtk.Label("");
        value_label.set_alignment(0.0f, 0.0f);
        value_label.wrap = true;
        table.attach(value_label, 1, 2, row, row+1,
                     Gtk.AttachOptions.EXPAND | Gtk.AttachOptions.FILL,
                     Gtk.AttachOptions.SHRINK | Gtk.AttachOptions.FILL, 0, 0);

        name_label.show();
        value_label.show();

        return value_label;
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
            KeyModel key_model = (KeyModel) model;
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
        Key? key = get_selected_key();
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
}

class ConfigurationEditor
{
    private EditorWindow window;
    
    public ConfigurationEditor()
    {
        window = new EditorWindow();
        window.destroy.connect(Gtk.main_quit);
        
        window.show();
    }

    public static int main(string[] args)
    {
        Gtk.init(ref args);

        new ConfigurationEditor();

        Gtk.main();

        return 0;
    }
}
