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

public abstract class SettingObject : Object
{
    public abstract bool is_view { get; }

    public Directory? parent { get; construct; }    // TODO make protected or even remove
    public string name { get; construct; }

    public string full_name { get; private set; }
    construct
    {
        full_name = parent == null ? "/" : ((!) parent).full_name + name + (is_view ? "/" : "");
    }
}

public class Directory : SettingObject
{
    public override bool is_view { get { return true; } }

    public int index { get { return parent.children.index (this); }}        // TODO remove

    public HashTable<string, Directory> child_map = new HashTable<string, Directory> (str_hash, str_equal);
    public List<Directory> children = new List<Directory> ();     // TODO remove

    public Directory (Directory? parent, string name, DConf.Client client)
    {
        Object (parent: parent, name: name);

        this.client = client;
    }

    /*\
    * * Keys management
    \*/

    private SettingsSchema? settings_schema = null;
    private string []? gsettings_key_map = null;

    private GLib.Settings settings;

    private DConf.Client client;

    private GLib.ListStore? _key_model = null;
    public GLib.ListStore key_model
    {
        get
        {
            if (_key_model == null)
            {
                _key_model = new GLib.ListStore (typeof (SettingObject));
                create_gsettings_keys ();
                create_dconf_keys ();
            }
            return (!) _key_model;
        }
    }

    private void insert_key (Key key)
    {
        ((!) _key_model).insert_sorted (key, (a, b) => { return strcmp (((SettingObject) a).name, ((SettingObject) b).name); });
    }

    /*\
    * * GSettings keys creation
    \*/

    public void init_gsettings_keys (SettingsSchema _settings_schema)
    {
        settings_schema = _settings_schema;
    }

    private void create_gsettings_keys ()
    {
        if (settings_schema == null)
            return;

        gsettings_key_map = ((!) settings_schema).list_keys ();
        settings = new GLib.Settings (((!) settings_schema).get_id ());

        foreach (string key_id in (!) gsettings_key_map)
            create_gsettings_key (key_id, ((!) settings_schema).get_key (key_id));
    }

    private void create_gsettings_key (string key_id, SettingsSchemaKey settings_schema_key)
    {
        string range_type = settings_schema_key.get_range ().get_child_value (0).get_string (); // don’t put it in the switch, or it fails
        string type_string;
        switch (range_type)
        {
            case "enum":    type_string = "<enum>"; break;  // <choices> or enum="", and hopefully <aliases>
            case "flags":   type_string = "<flags>"; break; // flags=""
            default:
            case "type":    type_string = settings_schema_key.get_value_type ().dup_string (); break;
        }

        GSettingsKey new_key = new GSettingsKey (
                this,
                key_id,
                settings,
                settings.schema_id,
                ((!) (settings_schema_key.get_summary () ?? "")).strip (),
                ((!) (settings_schema_key.get_description () ?? "")).strip (),
                type_string,
                settings.get_default_value (key_id), /* TODO present also settings_schema_key.get_default_value () */
                range_type,
                settings_schema_key.get_range ().get_child_value (1).get_child_value (0)
            );
        insert_key (new_key);
    }

    /*\
    * * DConf keys creation
    \*/

    private signal void item_changed (string item);
    private void dconf_client_change (DConf.Client client, string path, string [] items, string? tag)
    {
        foreach (string item in items)
            item_changed (path + item);
    }

    private void create_dconf_keys ()
    {
        foreach (string item in client.list (full_name))
            if (DConf.is_key (full_name + item) && (settings_schema == null || !(item in gsettings_key_map)))
                create_dconf_key (item);
        client.changed.connect (dconf_client_change);       // TODO better
    }

    private void create_dconf_key (string key_id)
    {
        Key new_key = new DConfKey (client, this, key_id);
        item_changed.connect ((item) => {
                if ((item.has_suffix ("/") && new_key.full_name.has_prefix (item)) || item == new_key.full_name)    // TODO better
                    new_key.value_changed ();
            });
        insert_key (new_key);
    }
}

public abstract class Key : SettingObject
{
    public override bool is_view { get { return false; } }
    public abstract bool has_schema { get; }

    public string type_string { get; protected set; default = "*"; }
    public abstract Variant value { owned get; set; }

    public signal void value_changed ();

    public static string cool_text_value_from_variant (Variant variant, string type)        // called from subclasses and from KeyListBoxRow
    {
        switch (type)
        {
            case "b": return cool_boolean_text_value (variant.get_boolean (), false);
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y": return "%hhu (%s)".printf (variant.get_byte (), variant.print (false));               // TODO i18n problem here
            case "n": return "%'hi".printf (variant.get_int16 ()).locale_to_utf8 (-1, null, null, null) ?? "%hi".printf (variant.get_int16 ());
            case "q": return "%'hu".printf (variant.get_uint16 ()).locale_to_utf8 (-1, null, null, null) ?? "%hu".printf (variant.get_uint16 ());
            case "i": return "%'i".printf (variant.get_int32 ()).locale_to_utf8 (-1, null, null, null) ?? "%i".printf (variant.get_int32 ());     // TODO why is 'li' failing to display '-'?
            case "u": return "%'u".printf (variant.get_uint32 ()).locale_to_utf8 (-1, null, null, null) ?? "%u".printf (variant.get_uint32 ());
            case "x": return "%'lli".printf (variant.get_int64 ()).locale_to_utf8 (-1, null, null, null) ?? "%lli".printf (variant.get_int64 ());
            case "t": return "%'llu".printf (variant.get_uint64 ()).locale_to_utf8 (-1, null, null, null) ?? "%llu".printf (variant.get_uint64 ());
            case "d": return variant.get_double ().to_string ();                                            // TODO something; notably, number of chars after coma
            case "h": return "%'i".printf (variant.get_handle ()).locale_to_utf8 (-1, null, null, null) ?? "%i".printf (variant.get_int32 ());
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
    public override bool has_schema { get { return false; } }

    private DConf.Client client;

    private Variant _value;
    public override Variant value
    {
        owned get
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
        Object (parent: parent, name: name);

        this.client = client;
        this.type_string = value.get_type_string ();
    }
}

public class GSettingsKey : Key
{
    public override bool has_schema { get { return true; } }

    public string schema_id { get; construct; }
    public string summary { get; construct; }
    public string description { get; construct; }
    public Variant default_value { get; construct; }
    public string range_type { get; construct; }
    public Variant range_content { get; construct; }

    private GLib.Settings settings;

    public override Variant value
    {
        owned get { return settings.get_value (name); }
        set { settings.set_value (name, value); }
    }

    public bool is_default
    {
        get { return settings.get_user_value (name) == null; }
    }

    public void set_to_default ()
    {
        settings.reset (name);
    }

    public GSettingsKey (Directory parent, string name, GLib.Settings settings, string schema_id, string summary, string description, string type_string, Variant default_value, string range_type, Variant range_content)
    {
        Object (parent: parent,
                name: name,
                // schema infos
                schema_id: schema_id,
                summary: summary,
                description: description,
                default_value: default_value,       // TODO devel default/admin default
                range_type: range_type,
                range_content: range_content);

        this.settings = settings;
        settings.changed [name].connect (() => { value_changed (); });

        this.type_string = type_string;
    }
}

public class SettingsModel : Object, Gtk.TreeModel
{
    private DConf.Client client = new DConf.Client ();
    private Directory root;

    public SettingsModel ()
    {
        SettingsSchemaSource settings_schema_source = SettingsSchemaSource.get_default ();
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;
        settings_schema_source.list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        root = new Directory (null, "/", client);

        foreach (string schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = settings_schema_source.lookup (schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better

            string schema_path = ((!) settings_schema).get_path ();
            Directory view = create_gsettings_views (root, schema_path [1:schema_path.length]);
            view.init_gsettings_keys ((!) settings_schema);
        }

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

    private void create_dconf_views (Directory view)
    {
        foreach (string item in client.list (view.full_name))
            if (DConf.is_dir (view.full_name + item))
                create_dconf_views (get_child (view, item [0:-1]));
    }

    private Directory get_child (Directory parent_view, string name)
    {
        Directory? view = parent_view.child_map.lookup (name);
        if (view != null)
            return (!) view;

        Directory new_view = new Directory (parent_view, name, client);
        parent_view.children.insert_sorted (new_view, (a, b) => { return strcmp (((Directory) a).name, ((Directory) b).name); });
        parent_view.child_map.insert (name, new_view);
        return new_view;
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
