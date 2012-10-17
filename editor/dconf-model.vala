public class Key : GLib.Object
{
    private SettingsModel model;

    public Directory? parent;

    public string name;
    public string full_name;

    public SchemaKey? schema;
    
    public bool has_schema
    {
        get { return schema != null; }
    }

    public int index
    {
        get { return parent.keys.index (this); }
    }

    public string type_string
    {
       private set {}
       public get
       {
           if (value != null)
           {
               if (value.is_of_type(VariantType.STRING) && has_schema && schema.enum_name != null)
                   return "<enum>";
               else
                   return value.get_type_string();
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
                model.client.write_sync(full_name, value);
            }
            catch (GLib.Error e)
            {
            }
            value_changed();
        }
    }

    public Variant? get_min()
    {
        switch (value.classify ())
        {
        case Variant.Class.BYTE:
            return new Variant.byte(0);
        case Variant.Class.INT16:
            return new Variant.int16(int16.MIN);
        case Variant.Class.UINT16:
            return new Variant.uint16(uint16.MIN);
        case Variant.Class.INT32:
            return new Variant.int32(int32.MIN);
        case Variant.Class.UINT32:
            return new Variant.uint32(uint32.MIN);
        case Variant.Class.INT64:
            return new Variant.int64(int64.MIN);
        case Variant.Class.UINT64:
            return new Variant.uint64(uint64.MIN);
        case Variant.Class.DOUBLE:
            return new Variant.double(double.MIN);
        default:
            return null;
        }
    }

    public Variant? get_max()
    {
        switch (value.classify ())
        {
        case Variant.Class.BYTE:
            return new Variant.byte(255);
        case Variant.Class.INT16:
            return new Variant.int16(int16.MAX);
        case Variant.Class.UINT16:
            return new Variant.uint16(uint16.MAX);
        case Variant.Class.INT32:
            return new Variant.int32(int32.MAX);
        case Variant.Class.UINT32:
            return new Variant.uint32(uint32.MAX);
        case Variant.Class.INT64:
            return new Variant.int64(int64.MAX);
        case Variant.Class.UINT64:
            return new Variant.uint64(uint64.MAX);
        case Variant.Class.DOUBLE:
            return new Variant.double(double.MAX);
        default:
            return null;
        }
    }

    public bool is_default
    {
        get { update_value(); return _value == null; }
    }

    public signal void value_changed();

	void item_changed (string key)
    {
		if ((key.has_suffix ("/") && full_name.has_prefix (key)) || key == full_name)
			value_changed ();
	}

    public Key(SettingsModel model, Directory parent, string name, string full_name)
    {
        this.model = model;
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;
        this.schema = model.schemas.keys.lookup(full_name);

		model.item_changed.connect (item_changed);
    }

    public void set_to_default()
    {
        if (!has_schema)
            return;

        _value = null;
        try
        {
            model.client.write_sync(full_name, null);
        }
        catch (GLib.Error e)
        {
        }
        value_changed();
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

    public int index
    {
       get { return parent.children.index (this); }
    }

    public GLib.HashTable<string, Directory> _child_map = new GLib.HashTable<string, Directory>(str_hash, str_equal);
    public GLib.List<Directory> _children = new GLib.List<Directory>();
    public GLib.List<Directory> children
    {
        get { update_children(); return _children; }
        private set { }
    }

    public GLib.HashTable<string, Key> _key_map = new GLib.HashTable<string, Key>(str_hash, str_equal);
    private GLib.List<Key> _keys = new GLib.List<Key>();
    public GLib.List<Key> keys
    {
        get { update_children(); return _keys; }
        private set { }
    }

    private bool have_children;
    
    public Directory(SettingsModel model, Directory? parent, string name, string full_name)
    {
        this.model = model;
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;
    }
    
    public Directory get_child(string name)
    {
        Directory? directory = _child_map.lookup(name);

        if (directory == null)
        {
            directory = new Directory(model, this, name, full_name + name + "/");
            _children.insert_sorted(directory, compare_directories);
            _child_map.insert(name, directory);
        }

        return directory;
    }

    private static int compare_directories(Directory a, Directory b)
    {
        return strcmp(a.name, b.name);
    }

    public Key get_key(string name)
    {
        Key? key = _key_map.lookup(name);

        if (key == null)
        {
            key = new Key(model, this, name, full_name + name);
            _keys.insert_sorted(key, compare_keys);
            _key_map.insert(name, key);
        }

        return key;
    }

    public static int compare_keys(Key a, Key b)
    {
        return strcmp(a.name, b.name);
    }

    public void load_schema(Schema schema, string path)
    {
        if (path == "")
        {
            foreach (var schema_key in schema.keys.get_values())
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

public class KeyModel: GLib.Object, Gtk.TreeModel
{
    private Directory directory;

    public KeyModel(Directory directory)
    {
        this.directory = directory;
        foreach (var key in directory.keys)
            key.value_changed.connect(key_changed_cb); // FIXME: Need to delete this callbacks
    }

    private void key_changed_cb(Key key)
    {
        Gtk.TreeIter iter;
        if (!get_iter_first(out iter))
            return;

        do
        {
            if(get_key(iter) == key)
            {
                row_changed(get_path(iter), iter);
                return;
            }
        } while(iter_next(ref iter));
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
    
    private void set_iter(ref Gtk.TreeIter iter, Key key)
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

    public bool get_iter(ref Gtk.TreeIter iter, Gtk.TreePath path)
    {
        if (path.get_depth() != 1)
            return false;

        return iter_nth_child(out iter, null, path.get_indices()[0]);
    }

    public Gtk.TreePath? get_path(Gtk.TreeIter iter)
    {
        var path = new Gtk.TreePath();
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
        else if (column == 2)
        {
            if (key.value != null)
                value = key.value.print(false);
            else
                value = "";
        }
        else if (column == 4)
        {
            if (key.is_default)
                value = Pango.Weight.NORMAL;            
            else
                value = Pango.Weight.BOLD;
        }
        else
            value = 0;
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        int index = get_key(iter).index;
        if (index >= directory.keys.length() - 1)
            return false;
        set_iter(ref iter, directory.keys.nth_data(index+1));
        return true;
    }

    public bool iter_children(ref Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        if (parent != null || directory.keys.length() == 0)
            return false;
        set_iter(ref iter, directory.keys.nth_data(0));
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return false;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return (int)directory.keys.length();
        else
            return 0;
    }

    public bool iter_nth_child(ref Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        if (parent != null)
            return false;

        if (n >= directory.keys.length())
            return false;
        set_iter(ref iter, directory.keys.nth_data(n));
        return true;
    }

    public bool iter_parent(ref Gtk.TreeIter iter, Gtk.TreeIter child)
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
    
    private void set_iter(ref Gtk.TreeIter iter, SchemaValue value)
    {
        iter.stamp = 0;
        iter.user_data = value;
        iter.user_data2 = value;
        iter.user_data3 = value;
    }

    public SchemaValue get_enum_value(Gtk.TreeIter iter)
    {
        return (SchemaValue)iter.user_data;
    }

    public bool get_iter(ref Gtk.TreeIter iter, Gtk.TreePath path)
    {
        if (path.get_depth() != 1)
            return false;

        return iter_nth_child(out iter, null, path.get_indices()[0]);
    }

    public Gtk.TreePath? get_path(Gtk.TreeIter iter)
    {
        var path = new Gtk.TreePath();
        path.append_index((int)get_enum_value(iter).index);
        return path;
    }

    public void get_value(Gtk.TreeIter iter, int column, out Value value)
    {
        if (column == 0)
            value = get_enum_value(iter).nick;
        else if (column == 1)
            value = get_enum_value(iter).value;
        else
            value = 0;
    }

    public bool iter_next(ref Gtk.TreeIter iter)
    {
        uint index = get_enum_value(iter).index;
        if (index >= schema_enum.values.length () - 1)
            return false;
        set_iter(ref iter, schema_enum.values.nth_data(index + 1));
        return true;
    }

    public bool iter_children(ref Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        if (parent != null || schema_enum.values.length() == 0)
            return false;
        set_iter(ref iter, schema_enum.values.nth_data(0));
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return false;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        if (iter == null)
            return (int) schema_enum.values.length();
        else
            return 0;
    }

    public bool iter_nth_child(ref Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        if (parent != null)
            return false;

        if (n >= schema_enum.values.length())
            return false;
        set_iter(ref iter, schema_enum.values.nth_data(n));
        return true;
    }

    public bool iter_parent(ref Gtk.TreeIter iter, Gtk.TreeIter child)
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

	public signal void item_changed (string key);

	void watch_func (DConf.Client client, string path, string[] items, string? tag) {
		foreach (var item in items) {
			item_changed (path + item);
		}
	}

    public SettingsModel()
    {
        client = new DConf.Client ();
        client.changed.connect (watch_func);
        root = new Directory(this, null, "/", "/");
        client.watch_sync ("/");

        schemas = new SchemaList();
        try
        {
            var dirs = GLib.Environment.get_system_data_dirs();

            /* Walk directories in reverse so the schemas in the
             * directory which appears first in the XDG_DATA_DIRS are
             * not overridden. */
            for (int i = dirs.length - 1; i >= 0; i--)
            {
                var path = Path.build_filename (dirs[i], "glib-2.0", "schemas");
                if (File.new_for_path (path).query_exists ())
                    schemas.load_directory (path);
            }

            var dir = GLib.Environment.get_variable ("GSETTINGS_SCHEMA_DIR");
            if (dir != null)
                schemas.load_directory(dir);
        } catch (Error e) {
            warning("Failed to parse schemas: %s", e.message);
        }

        /* Add keys for the values in the schemas */
        foreach (var schema in schemas.schemas.get_values())
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
    
    private void set_iter(ref Gtk.TreeIter iter, Directory directory)
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

    public bool get_iter(ref Gtk.TreeIter iter, Gtk.TreePath path)
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

    public Gtk.TreePath? get_path(Gtk.TreeIter iter)
    {
        var path = new Gtk.TreePath();
        for (var d = get_directory(iter); d != root; d = d.parent)
            path.prepend_index((int)d.index);
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
        if (directory.index >= directory.parent.children.length() - 1)
            return false;
        set_iter(ref iter, directory.parent.children.nth_data(directory.index+1));
        return true;
    }

    public bool iter_children(ref Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        Directory directory = get_directory(parent);
        if (directory.children.length() == 0)
            return false;
        set_iter(ref iter, directory.children.nth_data(0));
        return true;
    }

    public bool iter_has_child(Gtk.TreeIter iter)
    {
        return get_directory(iter).children.length() > 0;
    }

    public int iter_n_children(Gtk.TreeIter? iter)
    {
        return (int) get_directory(iter).children.length();
    }

    public bool iter_nth_child(ref Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        Directory directory = get_directory(parent);
        if (n >= directory.children.length())
            return false;
        set_iter(ref iter, directory.children.nth_data(n));
        return true;
    }

    public bool iter_parent(ref Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        Directory directory = get_directory(child);
        if (directory.parent == root)
            return false;
        set_iter(ref iter, directory.parent);
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
