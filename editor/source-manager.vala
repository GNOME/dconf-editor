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
  along with Dconf Editor.  If not, see <https://www.gnu.org/licenses/>.
*/

private class SourceManager : Object
{
    [CCode (notify = false)] internal SchemaPathTree cached_schemas { internal get; private set; default = new SchemaPathTree ("/"); } // prefix tree for quick lookup and diff'ing on changes

    /*\
    * * Schema source
    \*/

    internal signal void paths_changed (GenericSet<string> modified_path_specs);

    private SettingsSchemaSource? settings_schema_source = null;

    internal bool source_is_null ()
    {
        return settings_schema_source == null;
    }

    private string [] previous_empty_schemas = { "ca.desrt.dconf-editor.Demo.Empty", "ca.desrt.dconf-editor.Demo.EmptyRelocatable" };
    internal void refresh_schema_source ()
    {
        SettingsSchemaSource? settings_schema_source = create_schema_source ();
        if (settings_schema_source == null)
            return;

        GenericSet<string> modified_path_specs = new GenericSet<string> (str_hash, str_equal);

        string [] non_relocatable_schemas;
        string [] relocatable_schemas;
        ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);

        string [] empty_schemas = {};
        foreach (string schema_id in non_relocatable_schemas)
        {
            SettingsSchema? settings_schema = ((!) settings_schema_source).lookup (schema_id, true);
            if (settings_schema == null)
                continue;       // TODO better

            if (((!) settings_schema).list_keys ().length == 0 && ((!) settings_schema).list_children ().length == 0)
            {
                empty_schemas += schema_id;
                continue;
            }

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

            if (((!) settings_schema).list_keys ().length == 0 && ((!) settings_schema).list_children ().length == 0)
            {
                empty_schemas += schema_id;
                continue;
            }

            cached_schemas.add_schema_with_path_specs ((!) settings_schema, (!) path_specs, modified_path_specs);
        }

        string [] empty_schemas_needing_warning = {};
        if (empty_schemas.length > 0)
            foreach (string test_string in empty_schemas)
                if (!(test_string in previous_empty_schemas))
                    empty_schemas_needing_warning += test_string;

        // TODO i18n but big warning with plurals; and suggest to report a bug?
        if (empty_schemas_needing_warning.length == 1)
        {
            info ("Schema with id “" + empty_schemas_needing_warning [0] + "” contains neither keys nor children.");
            previous_empty_schemas = empty_schemas;
        }
        else if (empty_schemas_needing_warning.length > 1)
        {
            string warning_string = "The following schemas:\n";
            foreach (string warning_id in empty_schemas_needing_warning)
                warning_string += @"  $warning_id\n";
            warning_string += "contain neither keys nor children.";

            info (warning_string);
            previous_empty_schemas = empty_schemas;
        }

        cached_schemas.remove_unmarked (modified_path_specs);

        this.settings_schema_source = settings_schema_source;

        if (modified_path_specs.length > 0)
            paths_changed (modified_path_specs);
    }

    // We need to create new schema sources in order to detect schema changes, since schema sources cache the info and the default schema source is also a cached instance
    // This code is adapted from GLib (https://gitlab.gnome.org/GNOME/glib/blob/master/gio/gsettingsschema.c#L331)
    private SettingsSchemaSource? create_schema_source ()
    {
        SettingsSchemaSource? source = null;
        string[] system_data_dirs = GLib.Environment.get_system_data_dirs ();
        for (int i = system_data_dirs.length - 1; i >= 0; i--)
            source = try_prepend_dir (source, Path.build_filename (system_data_dirs [i], "glib-2.0", "schemas"));
        string user_data_dir = GLib.Environment.get_user_data_dir ();
        source = try_prepend_dir (source, Path.build_filename (user_data_dir, "glib-2.0", "schemas"));
        string? var_schema_dir = GLib.Environment.get_variable ("GSETTINGS_SCHEMA_DIR");
        if (var_schema_dir != null) {
            string[] extra_schema_dirs = ((!) var_schema_dir).split (Path.SEARCHPATH_SEPARATOR_S);
            for (int i = extra_schema_dirs.length - 1; i >= 0; i--)
                source = try_prepend_dir (source, extra_schema_dirs[i]);
        }
        return source;
    }

    private static SettingsSchemaSource? try_prepend_dir (SettingsSchemaSource? source, string schemas_dir)
    {
        try
        {
            return new SettingsSchemaSource.from_directory (schemas_dir, source, true);
        }
        catch (GLib.Error e)
        {}
        return source;
    }

    /*\
    * * Relocatable schemas
    \*/

    private HashTable<string, GenericSet<string>> relocatable_schema_paths = new HashTable<string, GenericSet<string>> (str_hash, str_equal);
    private HashTable<string, GenericSet<string>> startup_relocatable_schema_paths = new HashTable<string, GenericSet<string>> (str_hash, str_equal);

    internal void refresh_relocatable_schema_paths (bool    user_schemas,
                                                    bool    built_in_schemas,
                                                    bool    internal_schemas,
                                                    bool    startup_schemas,
                                                    Variant user_paths_variant)
    {
        relocatable_schema_paths.remove_all ();
        if (user_schemas)
        {
            VariantIter entries_iter;
            user_paths_variant.@get ("a{ss}", out entries_iter);
            string schema_id;
            string path_spec;
            while (entries_iter.next ("{ss}", out schema_id, out path_spec))
                add_relocatable_schema_info (relocatable_schema_paths, schema_id, path_spec);
        }
        if (built_in_schemas)
        {
            string [,] known_mappings = ConfigurationEditor.known_mappings;
            for (int i = 0; i < known_mappings.length [0]; i++)
                add_relocatable_schema_info (relocatable_schema_paths, known_mappings [i,0], known_mappings [i,1]);
        }
        if (built_in_schemas || internal_schemas)
        {
            string [,] internal_mappings = ConfigurationEditor.internal_mappings;
            for (int i = 0; i < internal_mappings.length [0]; i++)
                add_relocatable_schema_info (relocatable_schema_paths, internal_mappings [i,0], internal_mappings [i,1]);
        }
        if (startup_schemas)
        {
            startup_relocatable_schema_paths.foreach ((schema_id, paths) => {
                    paths.foreach ((path_spec) => add_relocatable_schema_info (relocatable_schema_paths, schema_id, path_spec));
                });
        }
    }

    internal void add_mapping (string schema, string folder_path)
    {
        add_relocatable_schema_info (startup_relocatable_schema_paths, schema, folder_path);
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
}

private class SchemaPathTree
{
    private string path_segment;
    private HashTable<string, CachedSchemaInfo> schemas = new HashTable<string, CachedSchemaInfo> (str_hash, str_equal);
    private HashTable<string, SchemaPathTree> subtrees = new HashTable<string, SchemaPathTree> (str_hash, str_equal);
    private SchemaPathTree? wildcard_subtree = null;

    internal SchemaPathTree (string path_segment)
    {
        this.path_segment = path_segment;
    }

    internal uint get_schema_count (string path)
    {
        uint schemas_count = 0;
        uint subpaths_count = 0;
        get_content_count (path, out schemas_count, out subpaths_count);
        return schemas_count;
    }

    internal void get_content_count (string path, out uint schemas_count, out uint subpaths_count)
    {
        GenericSet<SettingsSchema> path_schemas;
        GenericSet<string> subpaths;
        lookup (path, out path_schemas, out subpaths);
        schemas_count = path_schemas.length;
        subpaths_count = subpaths.length;
    }

    internal bool lookup (string path, out GenericSet<SettingsSchema> path_schemas, out GenericSet<string> subpaths)
    {
        path_schemas = new GenericSet<SettingsSchema> ((schema) => { return str_hash (schema.get_id ()); },
                                                       (schema1, schema2) => { return str_equal (schema1.get_id (), schema2.get_id ()); });
        subpaths = new GenericSet<string> (str_hash, str_equal);
        return lookup_segments (to_segments (path), 0, ref path_schemas, ref subpaths);
    }

    private bool lookup_segments (string[] path_segments, int matched_prefix_length, ref GenericSet<SettingsSchema> path_schemas, ref GenericSet<string> subpaths)
    {
        if (matched_prefix_length == path_segments.length)
        {
            foreach (CachedSchemaInfo schema_info in schemas.get_values ())
                path_schemas.add (schema_info.schema);
            foreach (SchemaPathTree subtree in subtrees.get_values ())
                if (subtree.has_non_wildcard_content ())
                    subpaths.add (subtree.path_segment);
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

    internal void add_schema (SettingsSchema schema, GenericSet<string> modified_path_specs)
    {
        string? schema_path = schema.get_path ();
        if (schema_path == null)
            return;
        add_schema_to_path_spec (new CachedSchemaInfo (schema), to_segments ((!) schema_path), 0, modified_path_specs);
    }

    internal void add_schema_with_path_specs (SettingsSchema schema, GenericSet<string> path_specs, GenericSet<string> modified_path_specs)
    {
        ulong fingerprint = CachedSchemaInfo.compute_schema_fingerprint (schema);
        path_specs.foreach ((path_spec) => {
                add_schema_to_path_spec (new CachedSchemaInfo (schema, fingerprint), to_segments (path_spec), 0, modified_path_specs);
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
            modified_path_specs.add (to_path (path_spec));
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
                modified_path_specs.add (to_path (path_spec [0:matched_prefix_length]));
            }
            return ((!) existing_subtree).add_schema_to_path_spec (schema_info, path_spec, matched_prefix_length + 1, modified_path_specs);
        }
    }

    internal void remove_unmarked (GenericSet<string> modified_path_specs)
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

    /*\
    * * Path utilities
    \*/

    private static string [] to_segments (string path)
    {
        if (path == "/")
            return new string [0];
        int from = path.has_prefix ("/") ? 1 : 0;
        int to = path.has_suffix ("/") ? -1 : path.length;
        return path [from:to].split ("/");
    }

    private static string to_path (string [] segments)
    {
        if (segments.length == 0)
            return "/";
        return "/" + string.joinv ("/", (string? []?) segments) + "/";
    }
}

private class CachedSchemaInfo
{
    internal SettingsSchema schema;
    internal ulong fingerprint;
    internal bool marked;

    internal static ulong compute_schema_fingerprint (SettingsSchema? schema)
    {
        return 0; // TODO do not take path into consideration, only keys
    }

    internal CachedSchemaInfo (SettingsSchema schema, ulong? fingerprint = null)
    {
        this.schema = schema;
        if (fingerprint != null)
            this.fingerprint = (!) fingerprint;
        else
            this.fingerprint = compute_schema_fingerprint (schema);
        marked = true;
    }
}
