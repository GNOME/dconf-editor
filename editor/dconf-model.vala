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
    public string name { get; construct; }
    public string full_name { get; construct; }

    public string casefolded_name { get; private construct; }
    construct
    {
        casefolded_name = name.casefold ();
    }
}

public class Directory : SettingObject
{
    private HashTable<string, Directory> child_map = new HashTable<string, Directory> (str_hash, str_equal);

    public bool warning_multiple_schemas = false;

    public Directory (string full_name, string name, DConf.Client client)
    {
        Object (full_name: full_name, name: name);

        this.client = client;
    }

    /*\
    * * Keys management
    \*/

    private SettingsSchema? settings_schema = null;
    private string []? gsettings_key_map = null;

    private GLib.Settings settings;

    private DConf.Client client;

    private bool key_model_accessed = false;
    private GLib.ListStore _key_model = new GLib.ListStore (typeof (SettingObject));
    public GLib.ListStore key_model
    {
        get
        {
            if (!key_model_accessed)
            {
                key_model_accessed = true;
                create_gsettings_keys ();
                create_dconf_keys ();
            }
            return _key_model;
        }
    }

    public void insert_directory (Directory dir)
        requires (key_model_accessed == false)
    {
        child_map.insert (dir.name, dir);
        _key_model.insert_sorted (dir, (a, b) => { return strcmp (((Directory) a).name, ((Directory) b).name); });
    }

    public Directory? lookup_directory (string name)
    {
        if (key_model_accessed)
            assert_not_reached ();
        return child_map.lookup (name);
    }

    /*\
    * * Folders creation
    \*/

    public bool need_sorting (SortingOptions sorting_options)
    {
        return !sorting_options.is_key_model_sorted (key_model);
    }

    public void sort_key_model (SortingOptions sorting_options)
    {
        if (need_sorting (sorting_options))
            sorting_options.sort_key_model (key_model);
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
        ((!) _key_model).append (new_key);
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
        ((!) _key_model).append ((Key) new_key);
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
                string? nullable_min = "%'g".printf (double.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'g".printf (double.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%g".printf (double.MIN));
                max = (!) (nullable_max ?? "%g".printf (double.MAX));
                return;
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
                string? nullable_text = "%'.12g".printf (variant.get_double ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%g".printf (variant.get_double ()));
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

    public static uint64 get_variant_as_uint64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.BYTE:    return (int64) variant.get_byte ();
            case Variant.Class.UINT16:  return (int64) variant.get_uint16 ();
            case Variant.Class.UINT32:  return (int64) variant.get_uint32 ();
            case Variant.Class.UINT64:  return variant.get_uint64 ();
            default: assert_not_reached ();
        }
    }

    public static int64 get_variant_as_int64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.INT16:   return (int64) variant.get_int16 ();
            case Variant.Class.INT32:   return (int64) variant.get_int32 ();
            case Variant.Class.INT64:   return variant.get_int64 ();
            case Variant.Class.HANDLE:  return (int64) variant.get_handle ();
            default: assert_not_reached ();
        }
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
        Object (full_name: parent.full_name + name, name: name);

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
    public Variant default_value         { get; construct; }
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
        string? summary_nullable = summary.locale_to_utf8 (-1, null, null, null);
        summary = summary_nullable ?? summary;

        string? description_nullable = description.locale_to_utf8 (-1, null, null, null);
        description = description_nullable ?? description;

        Object (full_name: parent.full_name + name,
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

/*  public bool search_for (string text)
    {
        return summary.index_of (text) >= 0
            || description.index_of (text) >= 0;  // TODO use the "in" keyword
    } */
}

public class SettingsModel : Object
{
    private DConf.Client client = new DConf.Client ();
    private Directory root;

    public SettingsModel ()
    {
        SettingsSchemaSource? settings_schema_source = SettingsSchemaSource.get_default ();
        root = new Directory ("/", "/", client);

        if (settings_schema_source != null)
            parse_schemas ((!) settings_schema_source);

        create_dconf_views (root);

        client.watch_sync ("/");
    }

    private void parse_schemas (SettingsSchemaSource settings_schema_source)
    {
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;

        HashTable<string, Directory> path_and_schema = new HashTable<string, Directory> (str_hash, str_equal);

        settings_schema_source.list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        foreach (string schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = settings_schema_source.lookup (schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better

            string schema_path = ((!) settings_schema).get_path ();

            Directory view = create_gsettings_views (root, schema_path [1:schema_path.length]);
            view.init_gsettings_keys ((!) settings_schema);

            Directory? schema_already_installed_there = path_and_schema.lookup (schema_path);
            if (schema_already_installed_there != null)
            {
                ((!) schema_already_installed_there).warning_multiple_schemas = true;
                view.warning_multiple_schemas = true;
            }
            else
                path_and_schema.insert (schema_path, view);
        }
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
        Directory? view = parent_view.lookup_directory (name);
        if (view != null)
            return (!) view;

        Directory new_view = new Directory (parent_view.full_name + name + "/", name, client);
        parent_view.insert_directory (new_view);
        return new_view;
    }

    /*\
    * * Path requests
    \*/

    public static string get_base_path (string path)
    {
        if (path.has_suffix ("/"))
            return path;
        else
            return stripped_path (path);
    }

    public Directory? get_directory (string path)
    {
        if (path == "/")
            return root;

        SettingObject? dir = root;

        string [] names = path.split ("/");
        uint index = 1;
        while (index < names.length - 1)
        {
            dir = get_folder_from_path_and_name (((Directory) (!) dir).key_model, names [index]);
            if (dir == null)
                return null;
            index++;
        }

        return (Directory) (!) dir;
    }

    public SettingObject? get_object (string path)
    {
        if (path.has_suffix ("/"))
            return get_directory (path);
        Directory? parent = get_directory (get_base_path (path));
        if (parent == null)
            return null;
        string name = path [path.last_index_of_char ('/') + 1:path.length];
        return get_key_from_path_and_name (((!) parent).key_model, name);
    }

    public string get_parent_path (string path)
    {
        if (path == "/")
            return path;
        return get_base_path (path.has_suffix ("/") ? path [0:-1] : path);
    }

    private static string stripped_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return path.slice (0, path.last_index_of_char ('/') + 1);
    }

    public static Key? get_key_from_path_and_name (GLib.ListStore key_model, string key_name)
    {
        uint position = 0;
        while (position < key_model.get_n_items ())
        {
            SettingObject? object = (SettingObject?) key_model.get_object (position);
            if (object == null)
                assert_not_reached ();
            if ((!) object is Key && ((!) object).name == key_name)
                return (Key) (!) object;
            position++;
        }
        return null;
    }

    public static Directory? get_folder_from_path_and_name (GLib.ListStore key_model, string folder_name)
    {
        uint position = 0;
        while (position < key_model.get_n_items ())
        {
            SettingObject? object = (SettingObject?) key_model.get_object (position);
            if (object == null)
                assert_not_reached ();
            if ((!) object is Directory && ((!) object).name == folder_name)
                return (Directory) (!) object;
            position++;
        }
        return null;
    }
}

/*\
* * Sorting
\*/

public enum MergeType {
    MIXED,
    FIRST,
    LAST
}

public class SortingOptions : Object
{
    public bool case_sensitive { get; set; default = false; }
    public MergeType sort_folders { get; set; default = MergeType.MIXED; }

    public SettingComparator get_comparator ()
    {
        if (sort_folders == MergeType.FIRST)
        {
            if (case_sensitive)
                return new FoldersFirstCaseSensitive ();
            else
                return new FoldersFirstCaseInsensitive ();
        }
        else if (sort_folders == MergeType.LAST)
        {
            if (case_sensitive)
                return new FoldersLastCaseSensitive ();
            else
                return new FoldersLastCaseInsensitive ();
        }
        else // if (sort_folders == MergeType.MIXED)
        {
            if (case_sensitive)
                return new FoldersMixedCaseSensitive ();
            else
                return new FoldersMixedCaseInsensitive ();
        }
    }

    public void sort_key_model (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        model.sort ((a, b) => comparator.compare ((SettingObject) a, (SettingObject) b));
    }

    public bool is_key_model_sorted (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        uint last = model.get_n_items () - 1;
        for (int i = 0; i < last; i++)
        {
            SettingObject item = (SettingObject) model.get_item (i);
            SettingObject next = (SettingObject) model.get_item (i + 1);
            if (comparator.compare (item, next) > 0)
                return false;
        }
        return true;
    }
}

/* Comparison functions */

public interface SettingComparator : Object
{
    public abstract int compare (SettingObject a, SettingObject b);
}

class FoldersMixedCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersMixedCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        return strcmp (a.name, b.name);
    }
}

class FoldersFirstCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return -1;
        if (!(a is Directory) && b is Directory)
            return 1;
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersFirstCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return -1;
        if (!(a is Directory) && b is Directory)
            return 1;
        return strcmp (a.name, b.name);
    }
}

class FoldersLastCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return 1;
        if (!(a is Directory) && b is Directory)
            return -1;
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersLastCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return 1;
        if (!(a is Directory) && b is Directory)
            return -1;
        return strcmp (a.name, b.name);
    }
}
