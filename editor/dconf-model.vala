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
    public bool warning_multiple_schemas = false;

    public Directory (string full_name, string name)
    {
        Object (full_name: full_name, name: name);
    }
}

public abstract class Key : SettingObject
{
    public abstract string descriptor { owned get; }
    public abstract string get_copy_text ();

    public string type_string { get; protected set; default = "*"; }
    public Variant properties { owned get; protected set; }

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
    public override string get_copy_text ()
    {
        return is_ghost ? _("%s (key erased)").printf (full_name) : descriptor + " " + value.print (false);
    }

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

    public DConfKey (DConf.Client client, string parent_full_name, string name)
    {
        Object (full_name: parent_full_name + name, name: name);

        this.client = client;
        this.type_string = value.get_type_string ();

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));     // TODO add VariantBuilder add_parsed () function in vala/glib-2.0.vapi line ~5490
        builder.add ("b",    false);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "defined-by",  _("DConf backend"));
        builder.add ("{ss}", "parent-path", parent_full_name);
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
    public string schema_id      { private get; construct; }
    public string? schema_path   { private get; construct; }
    public string summary                { get; construct; }
    public string description    { private get; construct; }
    public Variant default_value         { get; construct; }
    public string range_type             { get; construct; }
    public Variant range_content         { get; construct; }

    public override string descriptor {
        owned get {
            if (schema_path == null)
            {
                string schema_path = SettingsModel.get_parent_path (full_name);
                return @"$schema_id:$schema_path $name";
            }
            return @"$schema_id $name";
        }
    }
    public override string get_copy_text ()
    {
        return descriptor + " " + value.print (false);
    }

    public GLib.Settings settings { get; construct; }

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
        if (settings.backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
            settings.backend.changed (full_name, null);
        // Alternative workaround: value_changed ();
    }

    public GSettingsKey (string parent_full_name, string name, GLib.Settings settings, string schema_id, string? schema_path, string summary, string description, string type_string, Variant default_value, string range_type, Variant range_content)
    {
        string? summary_nullable = summary.locale_to_utf8 (-1, null, null, null);
        summary = summary_nullable ?? summary;

        string? description_nullable = description.locale_to_utf8 (-1, null, null, null);
        description = description_nullable ?? description;

        Object (full_name: parent_full_name + name,
                name: name,
                settings : settings,
                // schema infos
                schema_id: schema_id,
                schema_path: schema_path,
                summary: summary,
                description: description,
                default_value: default_value,       // TODO devel default/admin default
                range_type: range_type,
                range_content: range_content);

        settings.changed [name].connect (() => value_changed ());

        this.type_string = type_string;

        string defined_by = schema_path == null ? _("Relocatable schema") : _("Schema with path");

        VariantBuilder builder = new VariantBuilder (new VariantType ("(ba{ss})"));
        builder.add ("b",    true);
        builder.open (new VariantType ("a{ss}"));
        builder.add ("{ss}", "key-name",    name);
        builder.add ("{ss}", "defined-by",  defined_by);
        builder.add ("{ss}", "parent-path", parent_full_name);
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

[Flags]
enum RelocatableSchemasEnabledMappings
{
    USER,
    BUILT_IN,
    INTERNAL,
    STARTUP
}

public class SettingsModel : Object
{
    private Settings application_settings;

    private SettingsSchemaSource? settings_schema_source = null;
    private HashTable<string, GenericSet<string>> relocatable_schema_paths = new HashTable<string, GenericSet<string>> (str_hash, str_equal);
    private HashTable<string, GenericSet<string>> startup_relocatable_schema_paths = new HashTable<string, GenericSet<string>> (str_hash, str_equal);
    private SchemaPathTree cached_schemas = new SchemaPathTree ("/"); // prefix tree for quick lookup and diff'ing on changes

    private DConf.Client client = new DConf.Client ();

    public signal void paths_changed (GenericSet<string> modified_path_specs);

    public SettingsModel (Settings application_settings)
    {
        this.application_settings = application_settings;
    }

    private void refresh_relocatable_schema_paths ()
    {
        relocatable_schema_paths.remove_all ();
        parse_relocatable_schemas_user_paths ();
        create_relocatable_schemas_built_in_paths ();
        parse_relocatable_schemas_startup_paths ();
    }

    public void add_mapping (string schema, string path)
    {
        add_relocatable_schema_info (startup_relocatable_schema_paths, schema, path);
    }

    public void finalize_model ()
    {
        refresh_relocatable_schema_paths ();
        application_settings.changed ["relocatable-schemas-user-paths"].connect (() => {
                RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
                if (!(RelocatableSchemasEnabledMappings.USER in enabled_mappings_flags))
                    return;

                refresh_relocatable_schema_paths ();
            });
        application_settings.changed ["relocatable-schemas-enabled-mappings"].connect (() => {
                refresh_relocatable_schema_paths ();
            });

        refresh_schema_source ();
        Timeout.add (3000, () => {
                refresh_schema_source ();
                return true;
            });

        client.changed.connect ((client, prefix, changes, tag) => {
                GenericSet<string> modified_path_specs = new GenericSet<string> (str_hash, str_equal);
                modified_path_specs.add (prefix);
                foreach (string change in changes)
                {
                    string item_path = prefix + change;
                    if (is_key_path (item_path))
                        modified_path_specs.add (get_parent_path (item_path));
                    else
                        modified_path_specs.add (item_path);
                }
                GenericSetIter<string> iter = modified_path_specs.iterator ();
                string? path_spec;
                while ((path_spec = iter.next_value ()) != null)
                {
                    if (cached_schemas.get_schema_count ((!) path_spec) > 0)
                        iter.remove ();
                }
                paths_changed (modified_path_specs);
            });
        client.watch_sync ("/");
    }

    private void refresh_schema_source ()
    {
        SettingsSchemaSource? settings_schema_source = create_schema_source ();
        if (settings_schema_source == null)
            return;

        GenericSet<string> modified_path_specs = new GenericSet<string> (str_hash, str_equal);

        string [] non_relocatable_schemas;
        string [] relocatable_schemas;
        ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        foreach (string schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = ((!) settings_schema_source).lookup (schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better

            cached_schemas.add_schema ((!) settings_schema, modified_path_specs);
        }

        foreach (string schema_id in relocatable_schemas)
        {
            GenericSet<string>? path_specs = relocatable_schema_paths.lookup (schema_id);
            if (path_specs == null)
                continue;

            SettingsSchema? settings_schema = ((!) settings_schema_source).lookup (schema_id, true);
            if (settings_schema == null || ((string?) ((!) settings_schema).get_path ()) != null)
                continue;       // TODO better

            cached_schemas.add_schema_with_path_specs ((!) settings_schema, (!) path_specs, modified_path_specs);
        }

        cached_schemas.remove_unmarked (modified_path_specs);

        this.settings_schema_source = settings_schema_source;

        if (modified_path_specs.length > 0)
            paths_changed (modified_path_specs);
    }

    private void parse_relocatable_schemas_user_paths ()
    {
        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.USER in enabled_mappings_flags))
            return;

        Variant user_paths_variant = application_settings.get_value ("relocatable-schemas-user-paths");
        VariantIter entries_iter;
        user_paths_variant.get ("a{ss}", out entries_iter);
        string schema_id;
        string path_spec;
        while (entries_iter.next ("{ss}", out schema_id, out path_spec))
            add_relocatable_schema_info (relocatable_schema_paths, schema_id, path_spec);
    }

    private void create_relocatable_schemas_built_in_paths ()
    {
        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags))
            return;

        string [,] known_mappings = ConfigurationEditor.known_mappings;
        for (int i = 0; i < known_mappings.length [0]; i++)
            add_relocatable_schema_info (relocatable_schema_paths, known_mappings [i,0], known_mappings [i,1]);
    }

    private void parse_relocatable_schemas_startup_paths ()
    {
        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.STARTUP in enabled_mappings_flags))
            return;

        startup_relocatable_schema_paths.foreach ((schema_id, paths) => {
                paths.foreach ((path_spec) => add_relocatable_schema_info (relocatable_schema_paths, schema_id, path_spec));
            });
    }

    private void add_relocatable_schema_info (HashTable<string, GenericSet<string>> map, string schema_id, ...)
    {
        GenericSet<string>? schema_info = map.lookup (schema_id);
        if (schema_info == null)
            schema_info = new GenericSet<string> (str_hash, str_equal);

        var args = va_list ();
        var next_arg = null;
        while ((next_arg = args.arg ()) != null)
        {
            string path_spec = (string) next_arg;
            if (path_spec == "")
                continue;
            if (!path_spec.has_prefix ("/"))
                path_spec = "/" + path_spec;
            if (!path_spec.has_suffix ("/"))
                path_spec += "/"; // TODO proper validation
            ((!) schema_info).add (path_spec);
        }
        if (((!) schema_info).length > 0)
            map.insert (schema_id, (!) schema_info);
    }



    public static ulong compute_schema_fingerprint (SettingsSchema? schema)
    {
        return 0; // TODO do not take path into consideration, only keys
    }

    // We need to create new schema sources in order to detect schema changes, since schema sources cache the info and the default schema source is also a cached instance
    // This code is adapted from GLib (https://git.gnome.org/browse/glib/tree/gio/gsettingsschema.c#n332)
    private SettingsSchemaSource? create_schema_source ()
    {
        SettingsSchemaSource? source = null;
        string[] system_data_dirs = GLib.Environment.get_system_data_dirs ();
        for (int i = system_data_dirs.length - 1; i >= 0; i--)
            source = try_prepend_dir (source, Path.build_filename (system_data_dirs [i], "glib-2.0", "schemas"));
        string user_data_dir = GLib.Environment.get_user_data_dir ();
        source = try_prepend_dir (source, Path.build_filename (user_data_dir, "glib-2.0", "schemas"));
        string? var_schema_dir = GLib.Environment.get_variable ("GSETTINGS_SCHEMA_DIR");
        if (var_schema_dir != null)
            source = try_prepend_dir (source, (!) var_schema_dir);
        return source;
    }

    private SettingsSchemaSource? try_prepend_dir (SettingsSchemaSource? source, string schemas_dir)
    {
        try {
            return new SettingsSchemaSource.from_directory (schemas_dir, source, true);
        } catch (GLib.Error e) {
        }
        return source;
    }

    /*\
    * * Content lookup
    \*/

    private LookupResultType lookup (string path, out GLib.ListStore? key_model, out bool multiple_schemas)
    {
        key_model = null;
        if (is_key_path (path))
        {
            string name = get_name (path);
            string parent_path = get_parent_path (path);
            GLib.ListStore? parent_key_model = null;
            switch (lookup (parent_path, out parent_key_model, out multiple_schemas))
            {
            case LookupResultType.FOLDER:
                Key? key = get_key_from_path_and_name ((!) parent_key_model, name);
                if (key != null)
                {
                    key_model = new ListStore (typeof (SettingObject));
                    ((!) key_model).append ((!) key);
                    return LookupResultType.KEY;
                }
                return LookupResultType.NOT_FOUND;
            default:
                return LookupResultType.NOT_FOUND;
            }
        }
        else
        {
            GLib.ListStore _key_model = new GLib.ListStore (typeof (SettingObject));
            lookup_gsettings (path, _key_model, out multiple_schemas);
            create_dconf_keys (path, _key_model);
            if (_key_model.get_n_items () > 0)
            {
                key_model = _key_model;
                return LookupResultType.FOLDER;
            }
            return LookupResultType.NOT_FOUND;
        }
    }

    /*\
    * * GSettings content creation
    \*/

    private void lookup_gsettings (string path, GLib.ListStore key_model, out bool multiple_schemas)
    {
        multiple_schemas = false;
        if (settings_schema_source == null)
            return;

        List<SettingsSchema> schemas;
        List<string> folders;
        cached_schemas.lookup (path, out schemas, out folders);
        if (schemas.length () > 0)
        {
            bool content_found = false;
            // prefer non-relocatable schema
            foreach (SettingsSchema schema in schemas)
            {
                if (((string?) schema.get_path ()) == null)
                    continue;
                create_gsettings_keys (path, (!) schema, key_model);
                content_found = true;
                break;
            }
            // otherwise any will do
            if (!content_found)
            {
                create_gsettings_keys (path, (!) schemas.data, key_model);
                content_found = true;
            }
        }
        foreach (string folder in folders)
        {
            if (get_folder_from_path_and_name (key_model, folder) == null)
            {
                Directory child = new Directory (path + folder + "/", folder);
                key_model.append (child);
            }
        }
    }

    /*\
    * * Schemas manipulation
    \*/

    public bool is_relocatable_schema (string id)
    {
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;

        refresh_schema_source ();   // first call
        if (settings_schema_source == null)
            return false;   // TODO better

        ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        return (id in relocatable_schemas);
    }

    public bool is_non_relocatable_schema (string id)
    {
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;

        if (settings_schema_source == null)
            return false;   // TODO better

        ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        return (id in non_relocatable_schemas);
    }

    public string? get_schema_path (string id)
    {
        if (settings_schema_source == null)
            return null;   // TODO better

        SettingsSchema? schema = ((!) settings_schema_source).lookup (id, true);
        if (schema == null)
            return null;

        return ((!) schema).get_path ();
    }

    /*\
    * * Path requests
    \*/

    public static string get_base_path (string path)
    {
        if (!is_key_path (path))
            return path;
        else
            return stripped_path (path);
    }

    public Directory? get_directory (string path)
    {
        Directory? dir = null;
        uint schemas_count = 0;
        uint subpaths_count = 0;
        cached_schemas.get_content_count (path, ref schemas_count, ref subpaths_count);
        if (schemas_count + subpaths_count > 0 || client.list (path).length > 0)
        {
            dir = new Directory (path, get_name (path));
            if (schemas_count > 1)
                ((!) dir).warning_multiple_schemas = true;
        }
        return dir;
    }

    public GLib.ListStore? get_children (Directory? parent)
    {
        if (parent == null)
            return null;
        GLib.ListStore? key_model = null;
        bool multiple_schemas;
        switch (lookup (((!) parent).full_name, out key_model, out multiple_schemas))
        {
        case LookupResultType.FOLDER:
            return key_model;
        default:
            return null;
        }
    }

    /*\
    * * GSettings keys creation
    \*/

    private void create_gsettings_keys (string parent_path, GLib.SettingsSchema settings_schema, GLib.ListStore key_model)
    {
        string[] gsettings_key_map = settings_schema.list_keys ();
        string? path = settings_schema.get_path ();
        GLib.Settings settings;
        if (path == null) // relocatable
            settings = new Settings.full (settings_schema, null, parent_path);
        else
            settings = new Settings.full (settings_schema, null, null);

        foreach (string key_id in gsettings_key_map)
            create_gsettings_key (parent_path, key_id, settings_schema, settings, key_model);
    }

    private void create_gsettings_key (string parent_path, string key_id, GLib.SettingsSchema settings_schema, GLib.Settings settings, GLib.ListStore key_model)
    {
        SettingsSchemaKey settings_schema_key = settings_schema.get_key (key_id);

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
                parent_path,
                key_id,
                settings,
                settings_schema.get_id (),
                settings_schema.get_path (),
                ((!) (nullable_summary ?? "")).strip (),
                ((!) (nullable_description ?? "")).strip (),
                type_string,
                (!) default_value,
                range_type,
                settings_schema_key.get_range ().get_child_value (1).get_child_value (0)
            );
        key_model.append (new_key);
    }

    /*\
    * * DConf keys creation
    \*/

    private void create_dconf_keys (string parent_path, GLib.ListStore key_model)
    {
        foreach (string item in client.list (parent_path))
        {
            string item_path = parent_path + item;
            if (DConf.is_dir (item_path))
            {
                string item_name = item [0:-1];
                if (get_folder_from_path_and_name (key_model, item_name) == null)
                    key_model.append (new Directory (item_path, item_name));
            }
            else if (DConf.is_key (item_path) && get_key_from_path_and_name (key_model, item) == null)
                create_dconf_key (parent_path, item, key_model);
        }
    }

    private void create_dconf_key (string parent_path, string key_id, GLib.ListStore key_model)
    {
        DConfKey new_key = new DConfKey (client, parent_path, key_id);
        key_model.append (new_key);
    }

    public SettingObject? get_object (string path)
    {
        if (!is_key_path (path))
            return get_directory (path);
        GLib.ListStore? key_model = get_children (get_directory (get_parent_path (path)));
        return get_key_from_path_and_name (key_model, get_name (path));
    }

    public static string[] to_segments (string path)
    {
        if (path == "/")
            return new string [0];
        int from = path.has_prefix ("/") ? 1 : 0;
        int to = path.has_suffix ("/") ? -1 : path.length;
        return path [from:to].split ("/");
    }

    public static string to_path (string[] segments)
    {
        if (segments.length == 0)
            return "/";
        return "/" + string.joinv ("/", (string?[]?) segments) + "/";
    }

    public static bool match_prefix (string[] spec_segments, string[] path_segments)
    {
        if (path_segments.length < spec_segments.length)
            return false;
        for (uint i = 0; i < path_segments.length; i++)
            if (spec_segments [i] != "" && spec_segments [i] != path_segments [i])
                return false;
        return true;
    }

    public static bool is_key_path (string path)
    {
        return !path.has_suffix ("/");
    }

    public static string get_name (string path)
    {
        if (path == "/")
            return "/";
        if (is_key_path (path))
            return path [path.last_index_of_char ('/') + 1:path.length];
        string tmp = path[0:-1];
        return tmp [tmp.last_index_of_char ('/') + 1:tmp.length];
    }

    public static string get_parent_path (string path)
    {
        if (path == "/")
            return path;
        return get_base_path (!is_key_path (path) ? path [0:-1] : path);
    }

    private static string stripped_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return path.slice (0, path.last_index_of_char ('/') + 1);
    }

    public static Key? get_key_from_path_and_name (GLib.ListStore? key_model, string key_name)
    {
        if (key_model == null)
            return null;
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject? object = (SettingObject?) ((!) key_model).get_object (position);
            if (object == null)
                assert_not_reached ();
            if ((!) object is Key && ((!) object).name == key_name)
                return (Key) (!) object;
            position++;
        }
        return null;
    }

    public static Directory? get_folder_from_path_and_name (GLib.ListStore? key_model, string folder_name)
    {
        if (key_model == null)
            return null;
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject? object = (SettingObject?) ((!) key_model).get_object (position);
            if (object == null)
                assert_not_reached ();
            if ((!) object is Directory && ((!) object).name == folder_name)
                return (Directory) (!) object;
            position++;
        }
        return null;
    }

    /*\
    * * Key value methods
    \*/

    public void apply_key_value_changes (HashTable<Key, Variant?> changes)
    {
        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        changes.foreach ((key, planned_value) => {
                if (key is GSettingsKey)
                {
                    string key_descriptor = key.descriptor;
                    string settings_descriptor = key_descriptor [0:key_descriptor.last_index_of_char (' ')]; // strip the key name
                    GLib.Settings? settings = delayed_settings_hashtable.lookup (settings_descriptor);
                    if (settings == null)
                    {
                        settings = ((GSettingsKey) key).settings;
                        ((!) settings).delay ();
                        delayed_settings_hashtable.insert (settings_descriptor, (!) settings);
                    }

                    if (planned_value == null)
                    {
                        ((!) settings).reset (key.name);
                        if (((!) settings).backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
                            ((!) settings).backend.changed (key.full_name, null);
                        // Alternative workaround: key.value_changed ();
                    }
                    else
                        ((!) settings).set_value (key.name, (!) planned_value);
                }
                else
                {
                    dconf_changeset.set (key.full_name, planned_value);

                    if (planned_value == null)
                        ((DConfKey) key).is_ghost = true;
                }
            });

        delayed_settings_hashtable.foreach_remove ((key_descriptor, schema_settings) => { schema_settings.apply (); return true; });

        try {
            client.change_sync (dconf_changeset);
        } catch (Error error) {
            warning (error.message);
        }
    }
}

public enum LookupResultType
{
    KEY,
    FOLDER,
    NOT_FOUND
}

class CachedSchemaInfo
{
    public SettingsSchema schema;
    public ulong fingerprint;
    public bool marked;

    public CachedSchemaInfo (SettingsSchema schema, ulong? fingerprint=null)
    {
        this.schema = schema;
        if (fingerprint != null)
            this.fingerprint = (!) fingerprint;
        else
            this.fingerprint = SettingsModel.compute_schema_fingerprint (schema);
        marked = true;
    }
}

class SchemaPathTree
{
    private string path_segment;
    private HashTable<string, CachedSchemaInfo> schemas = new HashTable<string, CachedSchemaInfo> (str_hash, str_equal);
    private HashTable<string, SchemaPathTree> subtrees = new HashTable<string, SchemaPathTree> (str_hash, str_equal);
    private SchemaPathTree? wildcard_subtree = null;

    public SchemaPathTree (string path_segment)
    {
        this.path_segment = path_segment;
    }

    public uint get_schema_count (string path)
    {
        uint schemas_count = 0;
        uint subpaths_count = 0;
        get_content_count (path, ref schemas_count, ref subpaths_count);
        return schemas_count;
    }

    public void get_content_count (string path, ref uint schemas_count, ref uint subpaths_count)
    {
        List<SettingsSchema> path_schemas;
        List<string> subpaths;
        lookup (path, out path_schemas, out subpaths);
        schemas_count = path_schemas.length ();
        subpaths_count = subpaths.length ();
    }

    public bool lookup (string path, out List<SettingsSchema> path_schemas, out List<string> subpaths)
    {
        path_schemas = new List<SettingsSchema> ();
        subpaths = new List<string> ();
        return lookup_segments (SettingsModel.to_segments (path), 0, ref path_schemas, ref subpaths);
    }

    private bool lookup_segments (string[] path_segments, int matched_prefix_length, ref List<SettingsSchema> path_schemas, ref List<string> subpaths)
    {
        if (matched_prefix_length == path_segments.length)
        {
            foreach (CachedSchemaInfo schema_info in schemas.get_values ())
                path_schemas.append (schema_info.schema);
            foreach (SchemaPathTree subtree in subtrees.get_values ())
                if (subtree.has_non_wildcard_content ())
                    subpaths.append (subtree.path_segment);
            return true;
        }
        bool found = false;
        if (wildcard_subtree != null)
            if (((!) wildcard_subtree).lookup_segments (path_segments, matched_prefix_length + 1, ref path_schemas, ref subpaths))
                found = true;
        SchemaPathTree? existing_subtree = subtrees.lookup (path_segments [matched_prefix_length]);
        if (existing_subtree != null)
            if (((!) existing_subtree).lookup_segments (path_segments, matched_prefix_length + 1, ref path_schemas, ref subpaths))
                found = true;
        return found;
    }

    public void add_schema (SettingsSchema schema, GenericSet<string> modified_path_specs)
    {
        string? schema_path = schema.get_path ();
        if (schema_path == null)
            return;
        add_schema_to_path_spec (new CachedSchemaInfo (schema), SettingsModel.to_segments ((!) schema_path), 0, modified_path_specs);
    }

    public void add_schema_with_path_specs (SettingsSchema schema, GenericSet<string> path_specs, GenericSet<string> modified_path_specs)
    {
        ulong fingerprint = SettingsModel.compute_schema_fingerprint (schema);
        path_specs.foreach ((path_spec) => {
                add_schema_to_path_spec (new CachedSchemaInfo (schema, fingerprint), SettingsModel.to_segments (path_spec), 0, modified_path_specs);
            });
    }

    private bool add_schema_to_path_spec (CachedSchemaInfo schema_info, string[] path_spec, int matched_prefix_length, GenericSet<string> modified_path_specs)
    {
        if (matched_prefix_length == path_spec.length)
        {
            CachedSchemaInfo? existing_schema_info = schemas.lookup (schema_info.schema.get_id ());
            if (existing_schema_info != null && ((!) existing_schema_info).fingerprint == schema_info.fingerprint)
            {
                ((!) existing_schema_info).schema = schema_info.schema; // drop old schemas to avoid keeping more than one schema source in memory
                ((!) existing_schema_info).marked = true;
                return false;
            }
            schemas.insert (schema_info.schema.get_id (), schema_info);
            modified_path_specs.add (SettingsModel.to_path (path_spec));
            return true;
        }
        string segment = path_spec [matched_prefix_length];
        if (segment == "")
        {
            if (wildcard_subtree == null)
                wildcard_subtree = new SchemaPathTree (""); // doesn't add an immediate subtree, so doesn't count as modification for this node
            return ((!) wildcard_subtree).add_schema_to_path_spec (schema_info, path_spec, matched_prefix_length + 1, modified_path_specs);
        }
        else
        {
            SchemaPathTree? existing_subtree = subtrees.lookup (segment);
            if (existing_subtree == null)
            {
                SchemaPathTree new_subtree = new SchemaPathTree (segment);
                subtrees.insert (segment, new_subtree);
                existing_subtree = new_subtree;
                modified_path_specs.add (SettingsModel.to_path (path_spec [0:matched_prefix_length]));
            }
            return ((!) existing_subtree).add_schema_to_path_spec (schema_info, path_spec, matched_prefix_length + 1, modified_path_specs);
        }
    }

    public void remove_unmarked (GenericSet<string> modified_path_specs)
    {
        remove_unmarked_from_path ("/", modified_path_specs);
    }

    private void remove_unmarked_from_path (string path_spec, GenericSet<string> modified_path_specs)
    {
        bool modified = false;
        schemas.foreach_remove ((schema_id, cached_schema_info) => {
                if (!cached_schema_info.marked)
                {
                    modified = true;
                    return true;
                }
                cached_schema_info.marked = false;
                return false;
            });

        if (wildcard_subtree != null)
        {
            ((!) wildcard_subtree).remove_unmarked_from_path (path_spec + "/", modified_path_specs);
            if (((!) wildcard_subtree).is_empty ())
            {
                wildcard_subtree = null; // doesn't remove an immediate subtree, so doesn't count as modification for this node
            }
        }

        string [] empty_subtrees = {};
        foreach (SchemaPathTree subtree in subtrees.get_values ())
        {
            subtree.remove_unmarked_from_path (path_spec + subtree.path_segment + "/", modified_path_specs);
            if (subtree.is_empty ())
                empty_subtrees += subtree.path_segment;
        }
        if (empty_subtrees.length > 0)
        {
            foreach (string empty_subtree_segment in empty_subtrees)
                subtrees.remove (empty_subtree_segment);
            modified = true;
        }

        if (modified)
            modified_path_specs.add (path_spec);
    }

    private bool has_non_wildcard_content ()
    {
        return schemas.size() > 0 || subtrees.size () > 0;
    }

    private bool is_empty ()
    {
        return schemas.size () == 0 && wildcard_subtree == null && subtrees.size () == 0;
    }
}
