public class ConfModel : Gtk.TreeStore
{
    public ConfModel()
    {
        set_column_types({typeof(string), typeof(string)});
    }
    
    private Gtk.TreeIter? get_iter(string[] split_key, int length)
    {
        if (length == 1) // NOTE: Assumes key started with /
            return null;

        Gtk.TreeIter? parent = get_iter(split_key, length - 1);
        string key = split_key[length - 1];

        Gtk.TreeIter iter;
        bool have_iter = iter_children(out iter, parent);
        while (have_iter)
        {
            string name;
            get(iter, 0, out name, -1);
            if (name == key)
                return iter;
            if (name > key)
            {
                insert_before(out iter, parent, iter);
                break;
            }
            have_iter = iter_next(ref iter);
        }
        if (!have_iter)
            append(out iter, parent);

        set(iter, 0, key, -1);

        return iter;
    }

    public void add_key(string key)
    {
        string[] tokens = key.split("/", -1);    
        Gtk.TreeIter? iter = get_iter(tokens, tokens.length);
        set(iter, 1, key, -1);
    }
}

public class EditorWindow : Gtk.Window
{
    public ConfModel model;

    private DConf.Client client;
    private Gtk.TreeView tree_view;
    private Gtk.Label name_label;
    private Gtk.Label value_label;

    public EditorWindow(DConf.Client client)
    {
        this.client = client;
        set_title("Configuration Editor");
        set_default_size(600, 300);
        set_border_width(6);
        
        Gtk.HBox hbox = new Gtk.HBox(false, 6);
        hbox.show();
        add(hbox);

        model = new ConfModel();

        tree_view = new Gtk.TreeView();
        tree_view.set_headers_visible(false);
        tree_view.set_model(model);
        tree_view.insert_column_with_attributes(-1, "Key", new Gtk.CellRendererText(), "text", 0, null);
        tree_view.get_selection().changed.connect(key_selected_cb);
        tree_view.show();
        hbox.pack_start(tree_view, false, false, 0);

        Gtk.VBox vbox = new Gtk.VBox(false, 6);
        vbox.show();
        hbox.pack_start(vbox, true, true, 0);

        name_label = new Gtk.Label("");
        name_label.set_alignment(0.0f, 0.5f);
        name_label.show();
        vbox.pack_start(name_label, false, true, 0);

        value_label = new Gtk.Label("");
        value_label.set_alignment(0.0f, 0.5f);
        value_label.show();
        vbox.pack_start(value_label, false, true, 0);
    }
    
    private string? get_selected_key()
    {
        Gtk.TreeIter iter;
        if (!tree_view.get_selection().get_selected(null, out iter))
            return null;

        string key;
        model.get(iter, 1, out key, -1);
        return key;
    }
    
    private void key_selected_cb()
    {
        string? key = get_selected_key();
        if (key == null)
        {
            name_label.set_text("");
            value_label.set_text("");
        }
        else
        {
            GLib.Variant value = client.read(key);
            name_label.set_text(key);
            value_label.set_text(value == null ? "(unset)" : value.print(false));
        }
    }
}

class ConfigurationEditor
{
    private DConf.Client client;
    private EditorWindow window;
    
    public ConfigurationEditor()
    {
        client = new DConf.Client("", true, null, null);
        window = new EditorWindow(client);
        window.destroy.connect(Gtk.main_quit);
        
        read_keys("/");

        window.show();
    }

    private void read_keys(string parent)
    {
        string[] keys = client.list(parent);
        for (int i = 0; i < keys.length; i++)
        {
            if (DConf.is_rel_dir(keys[i]))
                read_keys(parent + keys[i]);
            else
                window.model.add_key(parent + keys[i]);
        }
    }

    public static int main(string[] args)
    {
        Gtk.init(ref args);

        new ConfigurationEditor();

        Gtk.main();

        return 0;
    }
}
