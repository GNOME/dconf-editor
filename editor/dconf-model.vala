public class Key : GLib.Object
{
    private SettingsModel model;

    public string name;
    public string full_name;

    public Key? next;

    public SchemaKey? schema;

    private Variant? _value;
    public Variant value
    {
        get { update_value(); return _value; }
        set {
            _value = value;
            try
            {
                model.client.write(full_name, value, 0, null);
            }
            catch (GLib.Error e)
            {
            }
        }
    }

    public Key(SettingsModel model, string name, string full_name)
    {
        this.model = model;
        this.name = name;
        this.full_name = full_name;
        this.schema = model.schemas.keys.get(full_name);
    }

    private void update_value()
    {
        _value = model.client.read(full_name);
    }
}

public class Directory : GLib.Object
{
    private SettingsModel model;

    public string name;
    public string full_name;

    public Directory? parent;
    
    private KeyModel _key_model;
    public KeyModel key_model
    {
        get { update_children(); if (_key_model == null) _key_model = new KeyModel(this); return _key_model; }
        private set {}
    }

    private int _n_children;
    public int n_children
    {
        get { update_children(); return _n_children; }
        private set { _n_children = value; }
    }
    public Directory? _child;
    public Directory? child
    {
        get { update_children(); return _child; }
        private set { _child = value; }
    }
    public Directory? next;

    private int _n_keys;
    public int n_keys
    {
        get { update_children(); return _n_keys; }
        private set { _n_keys = value; }
    }
    private Key? _keys;
    public Key? keys
    {
        get { update_children(); return _keys; }
        private set { _keys = value; }
    }

    private bool have_children;
    
    public Directory(SettingsModel model, string name, string full_name, Directory? parent = null)
    {
        this.model = model;
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;
    }

    private void update_children()
    {
        if (have_children)
            return;
        have_children = true;

        Directory? last_directory = null;
        Key? last_key = null;
        string[] items = model.client.list(full_name);
        _n_children = 0;
        _n_keys = 0;
        for (int i = 0; i < items.length; i++)
        {
            string item_name = full_name + items[i];

            if (DConf.is_dir(item_name))
            {
                string dir_name = items[i][0:-1];

                Directory directory = new Directory(model, dir_name, item_name, this);
                if (last_directory == null)
                   child = directory;
                else
                   last_directory.next = directory;
                last_directory = directory;
                _n_children++;
            }
            else
            {
                Key key = new Key(model, items[i], item_name);
                if (last_key == null)
                    keys = key;
                else
                    last_key.next = key;
                last_key = key;
                _n_keys++;
            }
        }
    }
}

public class KeyModel: GLib.Object, Gtk.TreeModel/*, Gtk.TreeSortable*/
{
    private Directory directory;

    construct {}

    public KeyModel(Directory directory)
    {
        this.directory = directory;
    }

    public Gtk.TreeModelFlags get_flags()
    {
        return Gtk.TreeModelFlags.LIST_ONLY;
    }

    public int get_n_columns()
    {
        return 3;
    }

    public Type get_column_type(int index)
    {
        if (index == 0)
            return typeof(Key);
        else
            return typeof(string);
    }
    
    private void set_iter(out Gtk.TreeIter iter, Key key)
    {
        iter.stamp = 0;
        iter.user_data = key;
        iter.user_data2 = key;
        iter.user_data3 = key;
    }

    public Key get_key(Gtk.TreeIter iter)
    {
        return (Key)iter.user_data;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path)
    {
        if (path.get_depth() != 1)
            return false;

        return iter_nth_child(out iter, null, path.get_indices()[0]);
    }

    public Gtk.TreePath get_path(Gtk.TreeIter iter)
    {
        Gtk.TreePath path = new Gtk.TreePath();
        Key key = directory.keys;
        int index = 0;
        while (key != get_key(iter))
        {
            key = key.next;
            index++;
        }
        path.append_index(index);
        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        if (column == 0)
            value = get_key(iter);
        else if (column == 1)
            value = get_key(iter).name;
        else
            value = get_key(iter).value.print(false);
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        Key key = get_key(iter);
        if (key.next == null)
            return false;
        set_iter(out iter, key.next);
        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        if (parent != null || directory.n_keys == 0)
            return false;
        set_iter(out iter, directory.keys);
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return false;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return directory.n_keys;
        else
            return 0;
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        if (parent != null)
            return false;

        Key key = directory.keys;
        if (key == null)
            return false;
        for (int i = 0; i < n; i++)
        {
           key = key.next;
           if (key == null)
               return false;
        }

        set_iter(out iter, key);
        return true;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        return false;
    }

    public void ref_node(Gtk.TreeIter iter)
    {
        get_key(iter).ref();
    }

    public void unref_node(Gtk.TreeIter iter)
    {
        get_key(iter).unref();
    }
}

public class EnumModel: GLib.Object, Gtk.TreeModel
{
    private SchemaEnum schema_enum;

    construct {}

    public EnumModel(SchemaEnum schema_enum)
    {
        this.schema_enum = schema_enum;
    }

    public Gtk.TreeModelFlags get_flags()
    {
        return Gtk.TreeModelFlags.LIST_ONLY;
    }

    public int get_n_columns()
    {
        return 2;
    }

    public Type get_column_type(int index)
    {
        if (index == 0)
            return typeof(string);
        else
            return typeof(int);
    }
    
    private void set_iter(out Gtk.TreeIter iter, SchemaEnumValue value)
    {
        iter.stamp = 0;
        iter.user_data = value;
        iter.user_data2 = value;
        iter.user_data3 = value;
    }

    public SchemaEnumValue get_enum_value(Gtk.TreeIter iter)
    {
        return (SchemaEnumValue)iter.user_data;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path)
    {
        if (path.get_depth() != 1)
            return false;

        return iter_nth_child(out iter, null, path.get_indices()[0]);
    }

    public Gtk.TreePath get_path(Gtk.TreeIter iter)
    {
        Gtk.TreePath path = new Gtk.TreePath();
        path.append_index(get_enum_value(iter).index);
        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        if (column == 0)
            value = get_enum_value(iter).nick;
        else if (column == 1)
            value = get_enum_value(iter).value;
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        int index = get_enum_value(iter).index;
        if (index >= schema_enum.values.size - 1)
            return false;
        set_iter(out iter, schema_enum.values[index + 1]);
        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        if (parent != null || schema_enum.values.size == 0)
            return false;
        set_iter(out iter, schema_enum.values[0]);
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return false;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return schema_enum.values.size;
        else
            return 0;
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        if (parent != null)
            return false;

        if (n >= schema_enum.values.size)
            return false;
        set_iter(out iter, schema_enum.values[n]);
        return true;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        return false;
    }

    public void ref_node(Gtk.TreeIter iter)
    {
        get_enum_value(iter).ref();
    }

    public void unref_node(Gtk.TreeIter iter)
    {
        get_enum_value(iter).unref();
    }
}

public class SettingsModel: GLib.Object, Gtk.TreeModel
{
    public SchemaList schemas;

    public DConf.Client client;
    private Directory root;

    construct {}

    public SettingsModel()
    {
        client = new DConf.Client("", true, null, null);
        root = new Directory(this, "/", "/");

        schemas = new SchemaList();
        try
        {
            schemas.load_directory("/usr/share/glib-2.0/schemas");
        } catch (Error e) {
            warning("Failed to parse schemas: %s", e.message);
        }
    }

    public Gtk.TreeModelFlags get_flags()
    {
        return 0;
    }

    public int get_n_columns()
    {
        return 2;
    }

    public Type get_column_type(int index)
    {
        if (index == 0)
            return typeof(Directory);
        else
            return typeof(string);
    }
    
    private void set_iter(out Gtk.TreeIter iter, Directory directory)
    {
        iter.stamp = 0;
        iter.user_data = directory;
        iter.user_data2 = directory;
        iter.user_data3 = directory;
    }

    public Directory get_directory(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return root;
        else
            return (Directory)iter.user_data;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path)
    {
        if (!iter_nth_child(out iter, null, path.get_indices()[0]))
            return false;

        for (int i = 1; i < path.get_depth(); i++)
        {
            Gtk.TreeIter parent = iter;
            if (!iter_nth_child(out iter, parent, path.get_indices()[i]))
                return false;
        }

        return true;
    }

    public Gtk.TreePath get_path(Gtk.TreeIter iter)
    {
        Gtk.TreePath path;
        Gtk.TreeIter parent;
        if (iter_parent(out parent, iter))
            path = get_path(parent);
        else
            path = new Gtk.TreePath();

        int index = 0;
        Directory directory = get_directory(iter);
        Directory d = directory.parent.child;
        while (d != directory)
        {
            d = d.next;
            index++;
        }
        path.append_index(index);

        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        if (column == 0)
            value = get_directory(iter);
        else
            value = get_directory(iter).name;
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        Directory directory = get_directory(iter);
        if (directory.next == null)
            return false;
        set_iter(out iter, directory.next);
        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        Directory directory = get_directory(parent);
        if (directory.n_children == 0)
            return false;
        set_iter(out iter, directory.child);
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return get_directory(iter).n_children > 0;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        return get_directory(iter).n_children;
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        Directory directory = get_directory(parent);

        directory = directory.child;
        if (directory == null)
            return false;       
        for (int i = 0; i < n; i++)
        {
           directory = directory.next;
           if (directory == null)
               return false;
        }

        set_iter(out iter, directory);
        return true;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        Directory directory = get_directory(child);
        if (directory.parent == root)
            return false;
        set_iter(out iter, directory.parent);
        return true;
    }

    public void ref_node(Gtk.TreeIter iter)
    {
        get_directory(iter).ref();
    }

    public void unref_node(Gtk.TreeIter iter)
    {
        get_directory(iter).unref();
    }
}
