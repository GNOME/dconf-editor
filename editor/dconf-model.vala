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

    public Directory (string full_name, string name)
    {
        Object (full_name: full_name, name: name);
    }

    /*\
    * * Keys management
    \*/

    public SettingsSchema? settings_schema { get; set; default=null; }
    public GLib.ListStore? key_model { get; set; default=null; }

    public void insert_directory (Directory dir)
        requires (key_model == null)
    {
        child_map.insert (dir.name, dir);
    }

    public Directory? lookup_directory (string name)
    {
        if (key_model != null)
            assert_not_reached ();
        return child_map.lookup (name);
    }

    public string[] get_children ()
    {
        if (key_model != null)
            assert_not_reached ();
        string[] names = new string [child_map.size ()];
        int i = 0;
        child_map.get_values ().foreach ((dir) => names [i++] = dir.name);
        return names;
    }

    public void init_gsettings_keys (SettingsSchema _settings_schema)
    {
        if (settings_schema == null)
            settings_schema = _settings_schema;
        else if (_settings_schema.get_id () != ((!) settings_schema).get_id ())
            warning_multiple_schemas = true;
    }
}

public abstract class Key : SettingObject
{
    public abstract string descriptor { owned get; }

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

class RelocatableSchemaInfo
{
    public SettingsSchema schema;
    public List<PathSpec> path_specs; // FIXME? cannot have a List<string[]>

    public RelocatableSchemaInfo (SettingsSchema schema)
    {
        this.schema = schema;
        this.path_specs = new List<PathSpec> ();
    }
}

class PathSpec
{
    public string[] segments;

    public PathSpec (string[] segs)
    {
        segments = segs;
    }

    public PathSpec.from_path (string path)
    {
        segments = path [1:-1].split ("/");
    }
}

public class SettingsModel : Object
{
    private Settings application_settings;
    private SettingsSchemaSource? settings_schema_source;
    private DConf.Client client = new DConf.Client ();
    private Directory root;

    private HashTable<string, RelocatableSchemaInfo> relocatable_schema_paths = new HashTable<string, RelocatableSchemaInfo> (str_hash, str_equal);

    public SettingsModel (Settings application_settings)
    {
        this.application_settings = application_settings;

        settings_schema_source = SettingsSchemaSource.get_default ();
        root = new Directory ("/", "/");

        parse_schemas ();
        create_dconf_views (root);

        parse_relocatable_schemas_user_paths ();
        create_relocatable_schemas_built_in_paths ();
    }

    public void add_mapping (string schema, string path)
    {
        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.STARTUP in enabled_mappings_flags))
            return;

        add_relocatable_schema_info (schema, path);
    }

    public void finalize_model ()
    {
        create_relocatable_schemas_views ();

        client.watch_sync ("/");
    }

    private void parse_schemas ()
    {
        if (settings_schema_source == null)
            return;

        string [] non_relocatable_schemas;
        string [] relocatable_schemas;

        ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        foreach (string schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = ((!) settings_schema_source).lookup (schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better

            string schema_path = ((!) settings_schema).get_path ();

            Directory view = create_gsettings_views (root, schema_path [1:schema_path.length]);
            view.init_gsettings_keys ((!) settings_schema);
        }
    }

    private void parse_relocatable_schemas_user_paths ()
    {
        if (settings_schema_source == null)
            return;

        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.USER in enabled_mappings_flags))
            return;

        Variant user_paths_variant = application_settings.get_value ("relocatable-schemas-user-paths");
        VariantIter entries_iter;
        user_paths_variant.get ("a{ss}", out entries_iter);
        string schema_id;
        string path_spec;
        while (entries_iter.next ("{ss}", out schema_id, out path_spec))
            add_relocatable_schema_info (schema_id, path_spec);
    }

    private void create_relocatable_schemas_built_in_paths ()
    {
        if (settings_schema_source == null)
            return;

        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) application_settings.get_flags ("relocatable-schemas-enabled-mappings");
        if (!(RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags))
            return;

        string [,] known_mappings = ConfigurationEditor.known_mappings;
        for (int i = 0; i < known_mappings.length [0]; i++)
            add_relocatable_schema_info (known_mappings [i,0], known_mappings [i,1]);
    }

    private void add_relocatable_schema_info (string schema_id, ...)
    {
        RelocatableSchemaInfo? schema_info = relocatable_schema_paths.lookup (schema_id);
        if (schema_info == null)
        {
            SettingsSchema? schema = ((!) settings_schema_source).lookup (schema_id, true);
            if (schema == null || ((string?) ((!) schema).get_path ()) != null) // TODO report bug, get_path () should be string? (this is not a question :)
                return;
            schema_info = new RelocatableSchemaInfo ((!) schema);
        }

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
            if (!("//" in path_spec)) // no wild cards, just create the views
            {
                Directory view = create_gsettings_views (root, path_spec [1:path_spec.length]);
                view.init_gsettings_keys (((!) schema_info).schema);
            }
            else // try to fill the holes later in create_relocatable_schemas_views
                ((!) schema_info).path_specs.append (new PathSpec.from_path ((string) path_spec));
        }
        if (((!) schema_info).path_specs.length () > 0)
            relocatable_schema_paths.insert (schema_id, (!) schema_info);
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

    private Queue<Directory> search_nodes = new Queue<Directory> ();

    private void create_relocatable_schemas_views ()
    {
        search_nodes.clear (); // subtrees that need yet to be matched against the path specs
        search_nodes.push_head (root); // start with the whole known tree
        while (!search_nodes.is_empty ())
        {
            Directory subtree = search_nodes.pop_tail ();
            string subtree_path = subtree.full_name;
            string[] subtree_segments = subtree_path == "/" ? new string [0] : subtree_path [1:-1].split ("/");
            relocatable_schema_paths.get_values ().foreach ((schema_info) => {
                    schema_info.path_specs.foreach ((spec) => {
                            string[] spec_segments = spec.segments;
                            if (subtree_segments.length > spec_segments.length)
                                return; // spec too short, cannot match anything below the subtree
                            int matched_prefix_length = 0;
                            while (matched_prefix_length < subtree_segments.length)
                            {
                                if (spec_segments [matched_prefix_length] != ""
                                        && spec_segments [matched_prefix_length] != subtree_segments [matched_prefix_length])
                                    return; // mismatch in one of the subtree ancestors, spec incompatible with subtree
                                matched_prefix_length++;
                            }
                            // search subtree recursively for matches with spec. the search may queue new paths for further iterations
                            create_relocatable_schemas_views_in_subtree (subtree, spec_segments, matched_prefix_length, (!) schema_info.schema);
                        });
                });
        }
    }

    private void create_relocatable_schemas_views_in_subtree (Directory view, string[] spec_segments, int matched_prefix_length, SettingsSchema schema)
    {
        Directory parent = view;
        Directory? child = null;
        while (matched_prefix_length < spec_segments.length
                && spec_segments [matched_prefix_length] != ""
                && (child = parent.lookup_directory (spec_segments [matched_prefix_length])) != null)
        {
            matched_prefix_length++;
            parent = (!) child;
        }

        if (matched_prefix_length == spec_segments.length)
            parent.init_gsettings_keys (schema); // matched the whole spec to an already existing path
        else if (spec_segments [matched_prefix_length] == "")
        {
            // wild card found, must branch out and match against existing children (there might be none)
            foreach (string name in parent.get_children ())
                create_relocatable_schemas_views_in_subtree ((!) parent.lookup_directory (name), spec_segments, matched_prefix_length + 1, schema);
        }
        else if (child == null)
        {
            // reached a dead end, if the rest of the spec has no wild cards, we add this branch to the tree
            for (int i = matched_prefix_length; i < spec_segments.length; i++) // must test this before creating
                if (spec_segments [i] == "")
                    return; // further wild cards can only be matched by existing folders, but we already reached a dead end, abort
            // the spec contains all the final folder names, so we can create them
            for (int i = matched_prefix_length; i < spec_segments.length; i++)
            {
                parent = get_child (parent, spec_segments [i]);
                search_nodes.push_head (parent); // a created node may be matched by a wild card in another spec, so we push it into the queue
            }
            parent.init_gsettings_keys (schema);
        }
        else
            assert_not_reached ();
    }

    private Directory get_child (Directory parent_view, string name)
    {
        Directory? view = parent_view.lookup_directory (name);
        if (view != null)
            return (!) view;

        Directory new_view = new Directory (parent_view.full_name + name + "/", name);
        parent_view.insert_directory (new_view);
        return new_view;
    }

    /*\
    * * Schemas manipulation
    \*/

    public bool is_relocatable_schema (string id)
    {
        string [] non_relocatable_schemas;
        string [] relocatable_schemas;

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
        if (path == "/")
            return root;

        SettingObject? dir = root;

        string [] names = path.split ("/");
        uint index = 1;
        while (index < names.length - 1)
        {
            dir = get_folder_from_path_and_name (get_children ((Directory) dir), names [index]);
            if (dir == null)
                return null;
            index++;
        }

        return (Directory) (!) dir;
    }

    public ListStore get_children (Directory parent)
    {
        if (parent.key_model == null)
        {
            GLib.ListStore key_model = new GLib.ListStore (typeof (SettingObject));
            create_child_folders (parent, key_model);
            if (parent.settings_schema != null)
                create_gsettings_keys (parent.full_name, (!) parent.settings_schema, key_model);
            create_dconf_keys (parent.full_name, key_model);
            parent.key_model = key_model;
        }
        return (!) parent.key_model;
    }

    /*\
    * * Child folders creation
    \*/

    private void create_child_folders (Directory parent, GLib.ListStore key_model)
    {
        foreach (string child in parent.get_children ())
            key_model.append ((!) parent.lookup_directory (child));
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
            settings = new GLib.Settings.with_path (settings_schema.get_id (), parent_path);
        else
            settings = new GLib.Settings (settings_schema.get_id ());

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
            if (DConf.is_key (parent_path + item) && get_key_from_path_and_name (key_model, item) == null)
                create_dconf_key (parent_path, item, key_model);
    }

    private void create_dconf_key (string parent_path, string key_id, GLib.ListStore key_model)
    {
        DConfKey new_key = new DConfKey (client, parent_path, key_id);
        client.changed.connect((client, path, items, tag) => {
                foreach (string item in items)
                {
                    string full_name = path + item;
                    if ((!is_key_path (full_name) && new_key.full_name.has_prefix (full_name)) || full_name == new_key.full_name)    // TODO better
                    {
                        new_key.is_ghost = client.read (new_key.full_name) == null;
                        new_key.value_changed ();
                    }
                }
            });
        key_model.append (new_key);
    }

    public SettingObject? get_object (string path)
    {
        if (!is_key_path (path))
            return get_directory (path);
        Directory? parent = get_directory (get_base_path (path));
        if (parent == null)
            return null;
        return get_key_from_path_and_name (get_children ((!) parent), get_name (path));
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

