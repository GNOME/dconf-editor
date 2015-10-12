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

public struct SchemaKey
{
    public string schema_id;
    public string name;
    public string? summary;
    public string? description;
    public Variant default_value;
    public string type;
    public string range_type;
    public Variant range_content;
}

public class SettingObject : Object
{
    public Directory? parent { get; protected set; }    // TODO make protected or even remove
    public string name { get; protected set; }
    public string full_name { get; protected set; }
}

public class Directory : SettingObject
{
    public int index { get { return parent.children.index (this); }}        // TODO remove

    public HashTable<string, Directory> child_map = new HashTable<string, Directory> (str_hash, str_equal);
    public List<Directory> children = new List<Directory> ();     // TODO remove

    public HashTable<string, Key> key_map = new HashTable<string, Key> (str_hash, str_equal);
    public GLib.ListStore key_model { get; set; default = new GLib.ListStore (typeof (SettingObject)); }

    public Directory (Directory? parent, string name, string full_name)
    {
        this.parent = parent;
        this.name = name;
        this.full_name = full_name;
    }
}

public abstract class Key : SettingObject
{
    public string path { get; protected set; }
    public abstract bool has_schema { get; }
    public string type_string { get; protected set; default = "*"; }
    public abstract Variant value { get; set; }

    public signal void value_changed ();

    public static string cool_text_value_from_variant (Variant variant, string type)        // called from subclasses and from KeyListBoxRow
    {
        switch (type)
        {
            case "b": return cool_boolean_text_value (variant.get_boolean (), false);
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y": return "%hhu (%s)".printf (variant.get_byte (), variant.print (false));   // TODO i18n problem here
            case "n": return "%'hi".printf (variant.get_int16 ());
            case "q": return "%'hu".printf (variant.get_uint16 ());
            case "i": return "%'i".printf (variant.get_int32 ());       // TODO why is 'li' failing to display '-'?
            case "u": return "%'u".printf (variant.get_uint32 ());      // TODO is 'lu' failing also?
            case "x": return "%'lli".printf (variant.get_int64 ());
            case "t": return "%'llu".printf (variant.get_uint64 ());
            case "d": return variant.get_double ().to_string ();        // TODO something; notably, number of chars after coma
            case "h": return "%'i".printf (variant.get_handle ());
            default: break;
        }
        if (type.has_prefix ("m"))
        {
            Variant? maybe_variant = variant.get_maybe ();
            if (maybe_variant == null)
                return cool_boolean_text_value (null, false);
            if (type == "mb")
                return cool_boolean_text_value (((!) maybe_variant).get_boolean (), false);
        }
        return variant.print (false);
    }

    public static string cool_boolean_text_value (bool? nullable_boolean, bool capitalized = true)
    {
        if (capitalized)
        {
            if (nullable_boolean == true)
                return _("True");
            if (nullable_boolean == false)
                return _("False");
            return _("Nothing");
        }
        else
        {
            if (nullable_boolean == true)
                return _("true");
            if (nullable_boolean == false)
                return _("false");
            /* Translators: "nothing" here is a keyword that should appear for consistence; please translate as "yourtranslation (nothing)" */
            return _("nothing");
        }
    }
}

public class DConfKey : Key
{
    private DConf.Client client;

    public override bool has_schema { get { return false; } }

    private Variant _value;
    public override Variant value
    {
        get
        {
            _value = client.read (full_name);
            return _value;  // TODO cannot that error?
        }
        set
        {
            _value = value;
            try
            {
                client.write_sync (full_name, value);
            }
            catch (Error e)
            {
            }
            value_changed ();
        }
    }

    public DConfKey (DConf.Client client, Directory parent, string name)
    {
        this.client = client;
        this.parent = parent;

        this.name = name;
        path = parent.full_name;
        full_name = path + name;

        type_string = value.get_type_string ();
    }
}

public class GSettingsKey : Key
{
    private DConf.Client client;

    public SchemaKey schema;

    public override bool has_schema { get { return true; } }

    private Variant? _value = null;
    public override Variant value
    {
        get
        {
            update_value ();
            return _value ?? schema.default_value;
        }
        set
        {
            _value = value;
            try
            {
                client.write_sync (full_name, value);
            }
            catch (Error e)
            {
            }
            value_changed ();
        }
    }

    public bool is_default
    {
        get { update_value (); return _value == null; }
    }

    public GSettingsKey (DConf.Client client, Directory parent, string name, SchemaKey schema)
    {
        this.client = client;
        this.parent = parent;

        this.name = name;
        path = parent.full_name;
        full_name = path + name;

        this.schema = schema;
        type_string = schema.type;
    }

    public void set_to_default ()
    {
        _value = null;
        try
        {
            client.write_sync (full_name, null);
        }
        catch (Error e)
        {
        }
        value_changed ();
    }

    private void update_value ()
    {
        _value = client.read (full_name);
    }
}

public class SettingsModel : Object, Gtk.TreeModel
{
    private DConf.Client client = new DConf.Client ();
    private Directory root = new Directory (null, "/", "/");

    private signal void item_changed (string key);
    private void watch_func (DConf.Client client, string path, string [] items, string? tag)
    {
        foreach (string item in items)
            item_changed (path + item);     // TODO better
    }

    public SettingsModel ()
    {
        SettingsSchemaSource settings_schema_source = SettingsSchemaSource.get_default ();
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;
        settings_schema_source.list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        foreach (string settings_schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = settings_schema_source.lookup (settings_schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better
            string schema_path = ((!) settings_schema).get_path ();
            Directory view = create_gsettings_views (root, schema_path [1:schema_path.length]);
            create_keys (view, (!) settings_schema, schema_path);
        }

        client.changed.connect (watch_func);
        create_dconf_views (root);
        client.watch_sync ("/");
    }

    /*\
    * * Recursive creation of views (directories)
    \*/

    private Directory create_gsettings_views (Directory parent_view, string remaining)
    {
        if (remaining == "")
            return parent_view;

        string [] tokens = remaining.split ("/", 2);

        Directory view = get_child (parent_view, tokens [0]);
        return create_gsettings_views (view, tokens [1]);
    }

    private void create_dconf_views (Directory parent_view)
    {
        string [] items = client.list (parent_view.full_name);
        for (int i = 0; i < items.length; i++)
        {
            if (DConf.is_dir (parent_view.full_name + items [i]))
            {
                Directory view = get_child (parent_view, items [i][0:-1]);
                create_dconf_views (view);
            }
            else
                make_key (parent_view, items [i], null);
        }
    }

    private Directory get_child (Directory parent_view, string name)
    {
        Directory? view = parent_view.child_map.lookup (name);
        if (view != null)
            return (!) view;

        Directory new_view = new Directory (parent_view, name, parent_view.full_name + name + "/");
        parent_view.children.insert_sorted (new_view, (a, b) => { return strcmp (((Directory) a).name, ((Directory) b).name); });
        parent_view.child_map.insert (name, new_view);
        return new_view;
    }

    /*\
    * * Keys creation
    \*/

    private void create_keys (Directory view, SettingsSchema settings_schema, string schema_path)
    {
        string schema_id = settings_schema.get_id ();
        foreach (string key_id in settings_schema.list_keys ())
        {
            SettingsSchemaKey settings_schema_key = settings_schema.get_key (key_id);

            string range_type = settings_schema_key.get_range ().get_child_value (0).get_string (); // don’t put it in the switch, or it fails
            string type;
            switch (range_type)
            {
                case "enum":    type = "<enum>"; break;  // <choices> or enum="", and hopefully <aliases>
                case "flags":   type = "as";     break;  // TODO better
                default:
                case "type":    type = (string) settings_schema_key.get_value_type ().peek_string (); break;
            }

            SchemaKey key = SchemaKey () {
                    schema_id = schema_id,
                    name = key_id,
                    summary = settings_schema_key.get_summary (),
                    description = settings_schema_key.get_description (),
                    default_value = settings_schema_key.get_default_value (),
                    type = type,
                    range_type = range_type,
                    range_content = settings_schema_key.get_range ().get_child_value (1).get_child_value (0)
                };

            make_key (view, key_id, key);
        }
    }

    private void make_key (Directory view, string name, SchemaKey? schema_key)
    {
        Key? key = view.key_map.lookup (name);
        if (key != null)
            return;

        Key new_key;
        if (schema_key == null)
            new_key = new DConfKey (client, view, name);
        else
            new_key = new GSettingsKey (client, view, name, (!) schema_key);
        item_changed.connect ((key_name) => {
                if ((key_name.has_suffix ("/") && new_key.full_name.has_prefix (key_name)) || key_name == new_key.full_name)
                    new_key.value_changed ();
            });
        view.key_model.insert_sorted ((Key) new_key, (a, b) => { return strcmp (((SettingObject) a).name, ((SettingObject) b).name); });
        view.key_map.insert (name, (Key) new_key);
    }

    /*\
    * * TreeModel things
    \*/

    public Gtk.TreeModelFlags get_flags()
    {
        return 0;
    }

    public int get_n_columns()
    {
        return 3;
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

    public void get_value (Gtk.TreeIter iter, int column, out Value value)
    {
        switch (column)
        {
            case 0: value = get_directory (iter); break;
            case 1: value = get_directory (iter).name; break;
            case 2: value = get_directory (iter).full_name; break;
            default: assert_not_reached ();
        }
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
