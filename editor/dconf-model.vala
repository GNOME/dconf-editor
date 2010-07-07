using Gee;

public class Key : GLib.Object
{
    private SettingsModel model;

    public Directory? parent;
    public int index;

    public string name;
    public string full_name;

    public SchemaKey? schema;
    
    public bool has_schema
    {
       private set {}
       public get { return schema != null; }
    }

    public string type_string
    {
       private set {}
       public get
       {
           if (_value != null)
           {
               if (_value.is_of_type(VariantType.STRING) && has_schema && schema.enum_name != null)
                   return "<enum>";
               else
                   return _value.get_type_string();
           }
           else
               return schema.type;
       }
    }

    private Variant? _value;
    public Variant value
    {
        get
        {
            update_value();
            if (_value != null)
                return _value;
            else
                return schema.default_value;
        }
        set
        {
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

    public Key(SettingsModel model, Directory parent, int index, string name, string full_name)
    {
        this.model = model;
        this.parent = parent;
        this.index = index;
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
    public int index;

    private KeyModel _key_model;
    public KeyModel key_model
    {
        get { update_children(); if (_key_model == null) _key_model = new KeyModel(this); return _key_model; }
        private set {}
    }

    public HashMap<string, Directory> _child_map = new HashMap<string, Directory>();
    public ArrayList<Directory> _children = new ArrayList<Directory>();
    public ArrayList<Directory> children
    {
        get { update_children(); return _children; }
        private set { }
    }

    public HashMap<string, Key> _key_map = new HashMap<string, Key>();
    private ArrayList<Key> _keys = new ArrayList<Key>();
    public ArrayList<Key> keys
    {
        get { update_children(); return _keys; }
        private set { }
    }

    private bool have_children;
    
    public Directory(SettingsModel model, Directory? parent, int index, string name, string full_name)
    {
        this.model = model;
        this.parent = parent;
        this.index = index;
        this.name = name;
        this.full_name = full_name;
    }
    
    public Directory get_child(string name)
    {
        if (_child_map.has_key(name))
            return _child_map[name];

        Directory directory = new Directory(model, this, _children.size, name, full_name + name + "/");
        _children.add(directory);
        _child_map.set(name, directory);
        return directory;
    }

    public Key get_key(string name)
    {
        if (_key_map.has_key(name))
            return _key_map[name];

        Key key = new Key(model, this, _keys.size, name, full_name + name);
        _keys.add(key);
        _key_map.set(name, key);
        return key;
    }

    public void load_schema(Schema schema, string path)
    {
        if (path == "")
        {
            foreach (var schema_key in schema.keys.values)
                get_key(schema_key.name);
        }
        else
        {
            string[] tokens = path.split("/", 2);
            string name = tokens[0];

            Directory directory = get_child(name);
            directory.load_schema(schema, tokens[1]);
        }
    }

    private void update_children()
    {
        if (have_children)
            return;
        have_children = true;
        
        string[] items = model.client.list(full_name);
        for (int i = 0; i < items.length; i++)
        {
            string item_name = full_name + items[i];

            if (DConf.is_dir(item_name))
            {
                string dir_name = items[i][0:-1];
                get_child(dir_name);
            }
            else
            {
                get_key(items[i]);
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
        path.append_index(get_key(iter).index);
        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        Key key = get_key(iter);

        if (column == 0)
            value = key;
        else if (column == 1)
            value = key.name;
        else if (key.value != null)
            value = key.value.print(false);
        else
            value = "";
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        int index = get_key(iter).index;
        if (index >= directory.keys.size - 1)
            return false;
        set_iter(out iter, directory.keys[index+1]);
        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        if (parent != null || directory.keys.size == 0)
            return false;
        set_iter(out iter, directory.keys[0]);
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return false;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return directory.keys.size;
        else
            return 0;
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        if (parent != null)
            return false;

        if (n >= directory.keys.size)
            return false;
        set_iter(out iter, directory.keys[n]);
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
        root = new Directory(this, null, 0, "/", "/");

        schemas = new SchemaList();
        try
        {
            schemas.load_directory("/usr/share/glib-2.0/schemas");
        } catch (Error e) {
            warning("Failed to parse schemas: %s", e.message);
        }

        /* Add keys for the values in the schemas */
        foreach (var schema in schemas.schemas)
            root.load_schema(schema, schema.path[1:schema.path.length]);
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
        Gtk.TreePath path = new Gtk.TreePath();
        path.append_index(get_directory(iter).index);
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
        if (directory.index >= directory.parent.children.size - 1)
            return false;
        set_iter(out iter, directory.parent.children[directory.index+1]);
        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        Directory directory = get_directory(parent);
        if (directory.children.size == 0)
            return false;
        set_iter(out iter, directory.children[0]);
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return get_directory(iter).children.size > 0;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        return get_directory(iter).children.size;
    }

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        Directory directory = get_directory(parent);
        if (n >= directory.children.size)
            return false;       
        set_iter(out iter, directory.children[n]);
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
