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

public class Key : GLib.Object
{
    private SettingsModel model;

    public Directory? parent;

    public string name;
    public string full_name;
    public string cool_text_value ()   // TODO better
    {
        // TODO number of chars after coma for double
        // bool is the only type that permits translation; keep strings for translators
        return type_string == "b" ? (value.get_boolean () ? _("True") : _("False")) : value.print (false);
    }

    public SchemaKey? schema;

    public bool has_schema
    {
        get { return schema != null; }
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

    private Variant? _value = null;
    public Variant value
    {
        get
        {
            update_value();
            return _value ?? schema.default_value;
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
        requires (has_schema)
    {
        value = null;
    }

    private void update_value()
    {
        _value = model.client.read(full_name);
    }

    public static Variant? get_min (string variant_type)
    {
        switch (variant_type)
        {
            case "y": return new Variant.byte (0);
            case "n": return new Variant.int16 (int16.MIN);
            case "q": return new Variant.uint16 (uint16.MIN);
            case "i": return new Variant.int32 (int32.MIN);
            case "u": return new Variant.uint32 (uint32.MIN);
            case "x": return new Variant.int64 (int64.MIN);
            case "t": return new Variant.uint64 (uint64.MIN);
            case "d": return new Variant.double (double.MIN);
            default:  return null;
        }
    }

    public static Variant? get_max (string variant_type)
    {
        switch (variant_type)
        {
            case "y": return new Variant.byte (255);
            case "n": return new Variant.int16 (int16.MAX);
            case "q": return new Variant.uint16 (uint16.MAX);
            case "i": return new Variant.int32 (int32.MAX);
            case "u": return new Variant.uint32 (uint32.MAX);
            case "x": return new Variant.int64 (int64.MAX);
            case "t": return new Variant.uint64 (uint64.MAX);
            case "d": return new Variant.double (double.MAX);
            default:  return null;
        }
    }
}

public class Directory : GLib.Object
{
    private SettingsModel model;

    public string name;
    public string full_name;

    public Directory? parent;

    public GLib.ListStore key_model { get; private set; default = new GLib.ListStore (typeof (Key)); }

    public int index
    {
       get { return parent.children.index (this); }
    }

    private GLib.HashTable<string, Directory> _child_map = new GLib.HashTable<string, Directory> (str_hash, str_equal);
    private GLib.List<Directory> _children = new GLib.List<Directory> ();
    public GLib.List<Directory> children
    {
        get { return _children; }
        private set { }
    }

    private GLib.HashTable<string, Key> _key_map = new GLib.HashTable<string, Key> (str_hash, str_equal);

    public Directory (SettingsModel model, Directory? parent, string name, string full_name)
    {
        this.model = model;
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;

        string [] items = model.client.list (full_name);
        for (int i = 0; i < items.length; i++)
            if (DConf.is_dir (full_name + items [i]))
                get_child (items [i][0:-1]);        // warning: don't return void
            else
                make_key (items [i]);
    }

    private Directory get_child (string name)
    {
        Directory? directory = _child_map.lookup (name);

        if (directory == null)
        {
            directory = new Directory (model, this, name, full_name + name + "/");
            _children.insert_sorted (directory, (a, b) => { return strcmp (((Directory) a).name, ((Directory) b).name); });
            _child_map.insert (name, directory);
        }

        return directory;
    }

    private void make_key (string name)
    {
        if (_key_map.lookup (name) != null)
            return;

        Key key = new Key (model, this, name, full_name + name);
        key_model.insert_sorted (key, (a, b) => { return strcmp (((Key) a).name, ((Key) b).name); });
        _key_map.insert (name, key);
    }

    public void load_schema (Schema schema, string path)
    {
        if (path == "")
        {
            foreach (SchemaKey schema_key in schema.keys.get_values ())
                make_key (schema_key.name);
        }
        else
        {
            string [] tokens = path.split ("/", 2);
            get_child (tokens [0]).load_schema (schema, tokens [1]);
        }
    }
}

public class SettingsModel: GLib.Object, Gtk.TreeModel
{
    public SchemaList schemas;

    public DConf.Client client;
    private Directory root;

    public signal void item_changed (string key);

    void watch_func (DConf.Client client, string path, string[] items, string? tag) {
        foreach (var item in items)
        {   // don't remove that!
            item_changed (path + item);
        }
    }

    public SettingsModel()
    {
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

        client = new DConf.Client ();
        client.changed.connect (watch_func);
        root = new Directory(this, null, "/", "/");
        client.watch_sync ("/");

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

    public Type get_column_type (int index)
    {
        return index == 0 ? typeof (Directory) : typeof (string);
    }

    private void set_iter (ref Gtk.TreeIter iter, Directory directory)
    {
        iter.stamp = 0;
        iter.user_data = directory;
        iter.user_data2 = directory;
        iter.user_data3 = directory;
    }

    public Directory get_directory (Gtk.TreeIter? iter)
    {
        return iter == null ? root : (Directory) iter.user_data;
    }

    public bool get_iter(out Gtk.TreeIter iter, Gtk.TreePath path)
    {
        iter = Gtk.TreeIter();

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
        var directory = get_directory(iter);
        if (directory.index >= directory.parent.children.length() - 1)
            return false;
        set_iter(ref iter, directory.parent.children.nth_data(directory.index+1));

        return true;
    }

    public bool iter_children(out Gtk.TreeIter iter, Gtk.TreeIter? parent)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(parent);
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

    public bool iter_nth_child(out Gtk.TreeIter iter, Gtk.TreeIter? parent, int n)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(parent);
        if (n >= directory.children.length())
            return false;
        set_iter(ref iter, directory.children.nth_data(n));

        return true;
    }

    public bool iter_parent(out Gtk.TreeIter iter, Gtk.TreeIter child)
    {
        iter = Gtk.TreeIter();

        var directory = get_directory(child);
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
