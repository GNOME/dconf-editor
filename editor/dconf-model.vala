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
    public Directory? nullable_parent { private get; construct; }
    public Directory parent { get { return nullable_parent == null ? (Directory) this : (!) nullable_parent; }}   // TODO make protected or even remove
    public string name { get; construct; }

    public string full_name { get; private set; }
    construct
    {
        full_name = nullable_parent == null ? "/" : ((!) nullable_parent).full_name + name + ((this is Directory) ? "/" : "");
    }
}

public class Directory : SettingObject
{
    public int index { get { return parent.children.index (this); }}        // TODO remove

    public HashTable<string, Directory> child_map = new HashTable<string, Directory> (str_hash, str_equal);
    public List<Directory> children = new List<Directory> ();     // TODO remove

    public Directory (Directory? parent, string name, DConf.Client client)
    {
        Object (nullable_parent: parent, name: name);

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
                create_folders ();
                create_gsettings_keys ();
                create_dconf_keys ();
            }
            return (!) _key_model;
        }
    }

    private void insert_key (Key key)
    {
        ((!) _key_model).insert_sorted ((SettingObject) key, (a, b) => { return strcmp (((SettingObject) a).name, ((SettingObject) b).name); });
    }

    /*\
    * * Folders creation
    \*/

    public void create_folders ()
    {
        children.foreach ((dir) => {
                ((!) _key_model).insert_sorted ((SettingObject) dir, (a, b) => {
                        return strcmp (((SettingObject) a).name, ((SettingObject) b).name);
                    });
            });
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

        string? nullable_summary = settings_schema_key.get_summary ();
        string? nullable_description = settings_schema_key.get_description ();
        Variant? default_value = settings.get_default_value (key_id);       /* TODO present also settings_schema_key.get_default_value () */
        if (default_value == null)
            assert_not_reached ();  // TODO report bug, shouldn't be nullable
        GSettingsKey new_key = new GSettingsKey (
                this,
                key_id,
                settings,
                settings.schema_id,
                ((!) (nullable_summary ?? "")).strip (),
                ((!) (nullable_description ?? "")).strip (),
                type_string,
                (!) default_value,
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
        DConfKey new_key = new DConfKey (client, this, key_id);
        item_changed.connect ((item) => {
                if ((item.has_suffix ("/") && new_key.full_name.has_prefix (item)) || item == new_key.full_name)    // TODO better
                {
                    new_key.is_ghost = client.read (new_key.full_name) == null;
                    new_key.value_changed ();
                }
            });
        insert_key ((Key) new_key);
    }
}

public abstract class Key : SettingObject
{
    public abstract string descriptor { owned get; }

    public string type_string { get; protected set; default = "*"; }
    public Variant properties { owned get; protected set; }

    public bool planned_change { get; set; default = false; }
    public Variant? planned_value { get; set; default = null; }

    public abstract Variant value { owned get; set; }

    public signal void value_changed ();

    protected static string key_to_description (string type)
    {
        switch (type)
        {
            case "b":
                return _("Boolean");
            case "s":
                return _("String");
            case "as":
                return _("String array");
            case "<enum>":
                return _("Enumeration");
            case "<flags>":
                return _("Flags");
            case "d":
                return _("Double");
            case "h":
                /* Translators: this handle type is an index; you may maintain the word "handle" */
                return _("D-Bus handle type");
            case "o":
                return _("D-Bus object path");
            case "ao":
                return _("D-Bus object path array");
            case "g":
                return _("D-Bus signature");
            case "y":       // TODO byte, bytestring, bytestring array
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
                return _("Integer");
            default:
                return type;
        }
    }

    protected static void get_min_and_max_string (out string min, out string max, string type_string)
    {
        switch (type_string)
        {
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                min = "%hhu".printf (uint8.MIN);    // TODO format as in
                max = "%hhu".printf (uint8.MAX);    //   cool_text_value_from_variant()
                return;
            case "n":
                string? nullable_min = "%'hi".printf (int16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hi".printf (int16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hi".printf (int16.MIN));
                max = (!) (nullable_max ?? "%hi".printf (int16.MAX));
                return;
            case "q":
                string? nullable_min = "%'hu".printf (uint16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hu".printf (uint16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hu".printf (uint16.MIN));
                max = (!) (nullable_max ?? "%hu".printf (uint16.MAX));
                return;
            case "i":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;     // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_min = "%'u".printf (uint32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'u".printf (uint32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%u".printf (uint32.MIN));
                max = (!) (nullable_max ?? "%u".printf (uint32.MAX));
                return;     // TODO is 'lu' failing also?
            case "x":
                string? nullable_min = "%'lli".printf (int64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'lli".printf (int64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%lli".printf (int64.MIN));
                max = (!) (nullable_max ?? "%lli".printf (int64.MAX));
                return;
            case "t":
                string? nullable_min = "%'llu".printf (uint64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'llu".printf (uint64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%llu".printf (uint64.MIN));
                max = (!) (nullable_max ?? "%llu".printf (uint64.MAX));
                return;
            case "d":
                min = double.MIN.to_string ();
                max = double.MAX.to_string ();
                return;     // TODO something
            case "h":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;
            default: assert_not_reached ();
        }
    }

    public static string cool_text_value_from_variant (Variant variant, string type)        // called from subclasses and from KeyListBoxRow
    {
        switch (type)
        {
            case "b":
                return cool_boolean_text_value (variant.get_boolean (), false);
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                return "%hhu (%s)".printf (variant.get_byte (), variant.print (false));     // TODO i18n problem here
            case "n":
                string? nullable_text = "%'hi".printf (variant.get_int16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hi".printf (variant.get_int16 ()));
            case "q":
                string? nullable_text = "%'hu".printf (variant.get_uint16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hu".printf (variant.get_uint16 ()));
            case "i":
                string? nullable_text = "%'i".printf (variant.get_int32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));           // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_text = "%'u".printf (variant.get_uint32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%u".printf (variant.get_uint32 ()));
            case "x":
                string? nullable_text = "%'lli".printf (variant.get_int64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%lli".printf (variant.get_int64 ()));
            case "t":
                string? nullable_text = "%'llu".printf (variant.get_uint64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%llu".printf (variant.get_uint64 ()));
            case "d":
                return variant.get_double ().to_string ();                                  // TODO something; notably, number of chars after coma
            case "h":
                string? nullable_text = "%'i".printf (variant.get_handle ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));
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

    protected static bool show_min_and_max (string type)
    {
        return (type == "d" || type == "y" || type == "n" || type == "q" || type == "i" || type == "u" || type == "x" || type == "t");
    }
}

public class DConfKey : Key
{
    public override string descriptor { owned get { return full_name; } }

    private DConf.Client client;

    public bool is_ghost { get; set; default = false; }
    public void erase ()
    {
        try
        {
            client.write_sync (full_name, null);
        }
        catch (Error error)
        {
            warning (error.message);
        }
        is_ghost = true;
        planned_change = false;
        value_changed ();
    }

    public override Variant value
    {
        owned get
        {
            return (!) client.read (full_name);
        }
        set
        {
            try
            {
                client.write_sync (full_name, value);
            }
            catch (Error error)
            {
                warning (error.message);
            }
            value_changed ();
        }
    }

    public DConfKey (DConf.Client client, Directory parent, string name)
    {
        Object (nullable_parent: parent, name: name);

        this.client = client;
        this.type_string = value.get_type_string ();

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));     // TODO add VariantBuilder add_parsed () function in vala/glib-2.0.vapi line ~5490
        builder.add ("b",    false);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "parent-path", parent.full_name);
        builder.add ("{ss}", "type-code",   type_string);
        builder.add ("{ss}", "type-name",   key_to_description (type_string));
        if (show_min_and_max (type_string))
        {
            string min, max;
            get_min_and_max_string (out min, out max, type_string);

            builder.add ("{ss}", "minimum", min);
            builder.add ("{ss}", "maximum", max);
        }
        builder.close ();
        properties = builder.end ();
    }
}

public class GSettingsKey : Key
{
    public string schema_id              { get; construct; }
    public string summary                { get; construct; }
    public string description    { private get; construct; }
    public Variant default_value { private get; construct; }
    public string range_type             { get; construct; }
    public Variant range_content         { get; construct; }

    public override string descriptor { owned get { return @"$schema_id $name"; } }

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
        Object (nullable_parent: parent,
                name: name,
                // schema infos
                schema_id: schema_id,
                summary: summary,
                description: description,
                default_value: default_value,       // TODO devel default/admin default
                range_type: range_type,
                range_content: range_content);

        this.settings = settings;
        settings.changed [name].connect (() => value_changed ());

        this.type_string = type_string;

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));
        builder.add ("b",    true);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "parent-path", parent.full_name);
        builder.add ("{ss}", "type-code",   type_string);
        builder.add ("{ss}", "type-name",   key_to_description (type_string));
        builder.add ("{ss}", "schema-id",   schema_id);
        builder.add ("{ss}", "summary",     summary);
        builder.add ("{ss}", "description", description);
        builder.add ("{ss}", "default-value", cool_text_value_from_variant (default_value, type_string));
        if (show_min_and_max (type_string))
        {
            string min, max;
            if (range_type == "range")     // TODO test more; and what happen if only min/max is in range?
            {
                min = cool_text_value_from_variant (range_content.get_child_value (0), type_string);
                max = cool_text_value_from_variant (range_content.get_child_value (1), type_string);
            }
            else
                get_min_and_max_string (out min, out max, type_string);

            builder.add ("{ss}", "minimum", min);
            builder.add ("{ss}", "maximum", max);
        }
        builder.close ();
        properties = builder.end ();
    }

    public bool search_for (string text)
    {
        return summary.index_of (text) >= 0
            || description.index_of (text) >= 0;  // TODO use the "in" keyword
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

    public Directory get_root_directory ()
    {
        return root;
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
        return iter == null ? root : (Directory) ((!) iter).user_data;
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
