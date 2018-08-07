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

private class SettingsModel : Object
{
    private SourceManager source_manager = new SourceManager ();
    internal bool refresh_source { get; set; default = true; }

    private DConf.Client client = new DConf.Client ();
    private string? last_change_tag = null;
    internal bool copy_action = false;

    internal bool use_shortpaths { private get; set; default = false; }

    internal signal void paths_changed (GenericSet<string> modified_path_specs, bool internal_changes);
    private bool paths_has_changed = false;

    private HashTable<string, Key> saved_keys = new HashTable<string, Key> (str_hash, str_equal);

    internal void refresh_relocatable_schema_paths (bool    user_schemas,
                                                    bool    built_in_schemas,
                                                    bool    internal_schemas,
                                                    bool    startup_schemas,
                                                    Variant user_paths_variant)
    {
        source_manager.refresh_relocatable_schema_paths (user_schemas,
                                                         built_in_schemas,
                                                         internal_schemas,
                                                         startup_schemas,
                                                         user_paths_variant);
    }

    internal void add_mapping (string schema, string path)
    {
        source_manager.add_mapping (schema, path);
    }

    internal void finalize_model ()
    {
        source_manager.paths_changed.connect ((modified_path_specs) => {
                paths_has_changed = true;
                paths_changed (modified_path_specs, false);
            });
        source_manager.refresh_schema_source ();
        Timeout.add (3000, () => {
                if (refresh_source) // TODO better: stops the I/O, but not the wakeup
                    source_manager.refresh_schema_source ();
                return true;
            });

        client.changed.connect ((client, prefix, changes, tag) => {
                bool internal_changes = copy_action;
                if (copy_action)
                    copy_action = false;
                if (last_change_tag != null && tag != null && (!) last_change_tag == (!) tag)
                {
                    last_change_tag = null;
                    internal_changes = true;
                }

                GenericSet<string> modified_path_specs = new GenericSet<string> (str_hash, str_equal);
                modified_path_specs.add (prefix);
                foreach (string change in changes)
                {
                    string item_path = prefix + change;
                    if (ModelUtils.is_key_path (item_path))
                        modified_path_specs.add (ModelUtils.get_parent_path (item_path));
                    else
                        modified_path_specs.add (item_path);
                }
                GenericSetIter<string> iter = modified_path_specs.iterator ();
                string? path_spec;
                while ((path_spec = iter.next_value ()) != null)
                {
                    if (source_manager.cached_schemas.get_schema_count ((!) path_spec) > 0)
                        iter.remove ();
                }
                paths_changed (modified_path_specs, internal_changes);
            });
        client.watch_sync ("/");
    }

    /*\
    * * Objects requests
    \*/

    private Directory? get_directory (string path)
    {
        if (path == "/")
            return new Directory ("/", "/");

        uint schemas_count = 0;
        uint subpaths_count = 0;
        source_manager.cached_schemas.get_content_count (path, out schemas_count, out subpaths_count);
        if (schemas_count + subpaths_count > 0 || client.list (path).length > 0)
            return new Directory (path, ModelUtils.get_name (path));
        return null;
    }

    private GLib.ListStore get_children_as_liststore (string folder_path)
    {
        GLib.ListStore key_model = new GLib.ListStore (typeof (SettingObject));

        Directory? dir = get_directory (folder_path);
        if (dir == null)
            return key_model;

        bool multiple_schemas;

        lookup_gsettings (folder_path, key_model, out multiple_schemas);
        create_dconf_keys (folder_path, key_model);

        return key_model;
    }

    internal Variant? get_children (string folder_path, bool update_watch = false)
    {
        if (update_watch)
            clean_watched_keys ();

        GLib.ListStore list_store = get_children_as_liststore (folder_path);
        uint n_items = list_store.get_n_items ();
        if (n_items == 0)
            return null;

        VariantBuilder builder = new VariantBuilder (new VariantType ("a(qs)"));
        uint position = 0;
        Object? object = list_store.get_item (0);
        do
        {
            SettingObject base_object = (SettingObject) (!) object;
            if (base_object is Key)
            {
                if (update_watch)
                    add_watched_key ((Key) base_object);

                builder.add ("(qs)", get_context_id_from_key ((Key) base_object), base_object.name);
            }
            else if (base_object is Directory)
            {
                if (!use_shortpaths)
                    builder.add ("(qs)", ModelUtils.folder_context_id, base_object.name);
                else
                {
                    string base_full_name = base_object.full_name;
                    GLib.ListStore child_list_store = get_children_as_liststore (base_full_name);
                    if (child_list_store.get_n_items () != 1)
                        builder.add ("(qs)", ModelUtils.folder_context_id, base_object.name);
                    else
                    {
                        SettingObject test_object = (SettingObject) child_list_store.get_item (0);
                        string test_full_name = test_object.full_name;
                        if (ModelUtils.is_key_path (test_full_name))
                            builder.add ("(qs)", ModelUtils.folder_context_id, base_object.name);
                        else
                        {
                            string name = base_object.name;
                            do
                            {
                                base_full_name = test_full_name;
                                name += "/" + test_object.name;
                                child_list_store = get_children_as_liststore (test_object.full_name);
                                test_object = (SettingObject) child_list_store.get_item (0);
                                test_full_name = test_object.full_name;
                            }
                            while (ModelUtils.is_folder_path (test_full_name) && child_list_store.get_n_items () == 1);
                            builder.add ("(qs)", ModelUtils.folder_context_id, name);
                        }
                    }
                }
            }
            else assert_not_reached ();

            position++;
            object = list_store.get_item (position);
        }
        while (object != null);
        return builder.end ();
    }

    internal bool get_object (string path, out uint16 context_id, out string name)
    {
        SettingObject? object;
        if (ModelUtils.is_key_path (path))
            object = (SettingObject?) get_key (path, "");
        else
            object = (SettingObject?) get_directory (path);

        if (object == null)
        {
            context_id = ModelUtils.undefined_context_id;   // garbage 1/2
            name = "";                                      // garbage 2/2
            return false;
        }

        context_id = get_context_id_from_object ((!) object);
        name = ((!) object).name;
        return true;
    }

    internal bool key_exists (string path, uint16 context_id)
    {
        Key? key = get_key (path, get_key_context_from_id (context_id));
        return key != null;
    }

    private Key? get_key (string path, string context)
    {
        if (paths_has_changed == false)
        {
            Key? key = saved_keys.lookup (path);
            if (key != null)
            {
                switch (context)
                {
                    case ""      : if ((!) key is GSettingsKey || !_is_key_ghost (path))                          return key; else break;
                    case ".dconf": if ((!) key is DConfKey     && !_is_key_ghost (path))                          return key; else break;
                    default      : if ((!) key is GSettingsKey && ((GSettingsKey) (!) key).schema_id == context)  return key; else break;
                }
            }
        }

        GLib.ListStore key_model = get_children_as_liststore (ModelUtils.get_parent_path (path));
        return get_key_from_path_and_name (key_model, ModelUtils.get_name (path), context);
    }

    private Key get_specific_key (string full_name, uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
    {
        if (ModelUtils.is_dconf_context_id (context_id))
        {
            Key? nullable_key = get_key (full_name, ".dconf");
            if (nullable_key == null || !((!) nullable_key is DConfKey))
                assert_not_reached ();
            return (!) nullable_key;
        }
        else
            return (Key) get_specific_gsettings_key (full_name, context_id);
    }

    private GSettingsKey get_specific_gsettings_key (string full_name, uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
        requires (!ModelUtils.is_dconf_context_id (context_id))
    {
        string schema_id = get_schema_id_from_context_id (context_id);
        Key? key = get_key (full_name, schema_id);
        if (key == null || !((!) key is GSettingsKey) || ((GSettingsKey) (!) key).schema_id != schema_id)
            assert_not_reached ();
        return (GSettingsKey) (!) key;
    }

    private static Key? get_key_from_path_and_name (GLib.ListStore key_model, string key_name, string context = "")
    {
        uint n_items = key_model.get_n_items ();
        if (n_items == 0)
            return null;
        uint position = 0;
        while (position < n_items)
        {
            SettingObject? object = (SettingObject?) ((!) key_model).get_object (position);
            if (object == null)
                assert_not_reached ();
            if ((!) object is Key && ((!) object).name == key_name)
            {
                // assumes for now you cannot have both a dconf key and a gsettings key with the same name
                if (context == "")
                    return (Key) (!) object;
                if ((!) object is GSettingsKey && context == ((GSettingsKey) (!) object).schema_id)
                    return (Key) (!) object;
                if ((!) object is DConfKey && context == ".dconf")  // return key even if not DConfKey?
                    return (Key) (!) object;
            }
            position++;
        }
        return null;
    }

    private static Directory? get_folder_from_path_and_name (GLib.ListStore? key_model, string folder_name)
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
    * * Coding contexts
    \*/

    private uint16 context_index = 2;    // 0 is undefined, 1 is folder, 2 is dconf; uint16.MAX (== 65535) is for too much contexts
    private HashTable<string, uint16> contexts_hashtable_1 = new HashTable<string, uint16> (str_hash, str_equal);
    private HashTable<uint16, string> contexts_hashtable_2 = new HashTable<uint16, string> ((a) => { return a; }, (a, b) => { return a == b; });
    bool _case_sensitive = false;
    private List<uint16> contexts_list = new List<uint16> ();

    private uint16 get_context_id_from_object (SettingObject object)
    {
        if (object is Directory)
            return ModelUtils.folder_context_id;
        if (object is Key)
            return get_context_id_from_key ((Key) object);
        assert_not_reached ();
    }

    private uint16 get_context_id_from_key (Key key)
    {
        if (key is GSettingsKey)
            return get_context_id_from_gsettings_key ((GSettingsKey) key, true);
        if (key is DConfKey)
            return ModelUtils.dconf_context_id;
        assert_not_reached ();
    }

    private uint16 get_context_id_from_gsettings_key (GSettingsKey gkey, bool create_context_if_needed)
    {
        string schema_id = gkey.schema_id;

        // TODO report bug: should return uint16? and be null if not found, but lookup returns 0 instead
        uint16 context_id = contexts_hashtable_1.lookup (schema_id);

        if (!ModelUtils.is_undefined_context_id (context_id))
            return context_id;

        if (!create_context_if_needed)
            assert_not_reached ();

        if (context_index == uint16.MAX)
        {
            warning ("max number of contexts reached");
            return context_index;
        }
        context_index += 1;

        contexts_hashtable_1.insert (schema_id, context_index);
        contexts_hashtable_2.insert (context_index, schema_id);

        contexts_list.insert_sorted_with_data (context_index, (a, b) => sort_context_ids (a, b));

        return context_index;
    }

    private string get_key_context_from_id (uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
        requires (context_id != uint16.MAX)
    {
        if (ModelUtils.is_dconf_context_id (context_id))
            return ".dconf";
        return get_schema_id_from_context_id (context_id);
    }

    private string get_schema_id_from_context_id (uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
        requires (!ModelUtils.is_dconf_context_id (context_id))
        requires (context_id != uint16.MAX)
    {
        string? nullable_schema_id = contexts_hashtable_2.lookup (context_id);
        if (nullable_schema_id == null) // TODO test if that really works
            assert_not_reached ();
        return (!) nullable_schema_id;
    }

    internal uint16 [] get_sorted_context_id (bool case_sensitive)
    {
        if (case_sensitive != _case_sensitive)
        {
            _case_sensitive = case_sensitive;
            contexts_list.sort_with_data ((a, b) => sort_context_ids (a, b));
        }

        uint length = contexts_list.length ();
        uint16 [] contexts_array = new uint16 [length];
        for (uint i = 0; i < length; i++)
            contexts_array [contexts_list.nth_data (i) - ModelUtils.special_context_id_number] = (uint16) i;
        return contexts_array;
    }

    internal int sort_context_ids (uint16 a, uint16 b)
    {
        string a_str = get_schema_id_from_context_id (a);
        string b_str = get_schema_id_from_context_id (b);

        if (!_case_sensitive)
        {
            int insensitive_sort = (a_str.casefold ()).collate (b_str.casefold ());
            if (insensitive_sort != 0)
                return insensitive_sort;
        }

        return strcmp (a_str, b_str);
    }

    /*\
    * * GSettings keys creation
    \*/

    private void lookup_gsettings (string path, GLib.ListStore key_model, out bool multiple_schemas)
    {
        multiple_schemas = false;
        if (source_manager.source_is_null ())
            return;

        GenericSet<SettingsSchema> schemas;
        GenericSet<string> folders;
        source_manager.cached_schemas.lookup (path, out schemas, out folders);
        if (schemas.length > 0)
            foreach (SettingsSchema schema in schemas.get_values ())
                create_gsettings_keys (path, (!) schema, key_model);

        foreach (string folder in folders.get_values ())
        {
            if (get_folder_from_path_and_name (key_model, folder) == null)
            {
                Directory child = new Directory (path + folder + "/", folder);
                key_model.append (child);
            }
        }
    }

    private void create_gsettings_keys (string parent_path, GLib.SettingsSchema settings_schema, GLib.ListStore key_model)
    {
        string [] gsettings_key_map = settings_schema.list_keys ();
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

        RangeType range_type = RangeType.get_from_string (settings_schema_key.get_range ().get_child_value (0).get_string ()); // don’t put it in the switch, or it fails
        string type_string;
        switch (range_type)
        {
            case RangeType.ENUM:    type_string = "<enum>"; break;  // <choices> or enum="", and hopefully <aliases>
            case RangeType.FLAGS:   type_string = "<flags>"; break; // flags=""
            default:
            case RangeType.OTHER:
            case RangeType.RANGE:
            case RangeType.TYPE:    type_string = settings_schema_key.get_value_type ().dup_string (); break;
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
        GSettingsKey? conflicting_key = (GSettingsKey?) get_key_from_path_and_name (key_model, key_id); // safe cast, no DConfKey's added yet
        if (conflicting_key != null)
        {
            if (((!) conflicting_key).key_conflict == KeyConflict.HARD
             || new_key.type_string != ((!) conflicting_key).type_string
             || !new_key.default_value.equal (((!) conflicting_key).default_value)
             || new_key.range_type != ((!) conflicting_key).range_type
             || !new_key.range_content.equal (((!) conflicting_key).range_content))
            {
                ((!) conflicting_key).key_conflict = KeyConflict.HARD;
                new_key.key_conflict = KeyConflict.HARD;
            }
            else
            {
                ((!) conflicting_key).key_conflict = KeyConflict.SOFT;
                new_key.key_conflict = KeyConflict.SOFT;
            }
        }
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
                create_dconf_key (parent_path + item, item, key_model);
        }
    }

    private void create_dconf_key (string full_name, string key_id, GLib.ListStore key_model)
    {
        Variant? key_value = get_dconf_key_value_or_null (full_name, client);
        if (key_value == null)
            return;
        DConfKey new_key = new DConfKey (full_name, key_id, ((!) key_value).get_type_string ());
        key_model.append (new_key);
    }

    /*\
    * * Watched keys
    \*/

    internal signal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default);
    internal signal void dkey_value_push (string full_name, Variant? key_value_or_null);

    private GLib.ListStore watched_keys = new GLib.ListStore (typeof (Key));

    internal void keys_value_push ()
    {
        uint position = 0;
        Object? object = watched_keys.get_item (0);
        while (object != null)
        {
            if ((!) object is GSettingsKey)
                push_gsettings_key_value ((GSettingsKey) (!) object);
            else if ((!) object is DConfKey)
                push_dconf_key_value (((Key) (!) object).full_name, client);
            position++;
            object = watched_keys.get_item (position);
        };
    }

    private void add_watched_key (Key key)
    {
        if (key is GSettingsKey)
        {
            ((GSettingsKey) key).connect_settings ();
            key.key_value_changed_handler = key.value_changed.connect (() => push_gsettings_key_value ((GSettingsKey) key));
        }
        else if (key is DConfKey)
        {
            ((DConfKey) key).connect_client (client);
            key.key_value_changed_handler = key.value_changed.connect (() => push_dconf_key_value (key.full_name, client));
        }
        else assert_not_reached ();

        watched_keys.append (key);
        saved_keys.insert (key.full_name, key);
    }

    private void clean_watched_keys ()
    {
        uint position = 0;
        Object? object = watched_keys.get_item (0);
        Key key;
        while (object != null)
        {
            key = (Key) (!) object;

            if (key is GSettingsKey)
                ((GSettingsKey) key).disconnect_settings ();
            else if (key is DConfKey)
                ((DConfKey) key).disconnect_client (client);
            else assert_not_reached ();

            key.disconnect (key.key_value_changed_handler);
            key.key_value_changed_handler = 0;

            position++;
            object = watched_keys.get_item (position);
        };
        watched_keys.remove_all ();
        saved_keys.remove_all ();
        paths_has_changed = false;
    }

    private inline void push_gsettings_key_value (GSettingsKey gkey)
    {
        gkey_value_push (gkey.full_name,
                         get_context_id_from_gsettings_key (gkey, false),
                         get_gsettings_key_value (gkey),
                         is_key_default (gkey));
    }

    private inline void push_dconf_key_value (string full_name, DConf.Client client)
    {
        dkey_value_push (full_name,
                         get_dconf_key_value_or_null (full_name, client));
    }

    /*\
    * * Path methods
    \*/

    internal string get_fallback_path (string path)
    {
        string fallback_path = path;
        if (ModelUtils.is_key_path (path))
        {
            Key? key = get_key (path, "");
            if (key != null)
                return path;
            fallback_path = ModelUtils.get_parent_path (path);
        }

        Directory? dir = get_directory (fallback_path);
        while (dir == null)
        {
            fallback_path = ModelUtils.get_parent_path (fallback_path);
            dir = get_directory (fallback_path);
        }
        return fallback_path;
    }

    internal string get_startup_path_fallback (string path)   // TODO take context and check that also
    {
        // folder: let the get_fallback_path method do its usual job if needed
        if (ModelUtils.is_folder_path (path))
            return path;

        // key: return if exists
        GLib.ListStore key_model = get_children_as_liststore (ModelUtils.get_parent_path (path));
        Key? key = get_key_from_path_and_name (key_model, ModelUtils.get_name (path));
        if (key != null)
            return path;

        // test if the user forgot the last '/' in a folder path
        string new_path = path + "/";
        if (get_directory (new_path) != null)
            return new_path;

        // let the usual fallback methods do their job if needed
        return path;
    }

    internal uint16 get_fallback_context (string full_name, uint16 context_id, string schema_id = "")
    {
        string context;
        if (schema_id != "")
            context = schema_id;
        else if (ModelUtils.is_undefined_context_id (context_id))
            context = "";
        else
            context = get_key_context_from_id (context_id);

        Key? found_object = get_key (full_name, context);
        if (found_object == null && context != "")  // TODO warn about missing context
            found_object = get_key (full_name, "");

        if (found_object == null)
            return ModelUtils.undefined_context_id;

        clean_watched_keys ();
        add_watched_key ((!) found_object);

        return get_context_id_from_object ((!) found_object);
    }

    /*\
    * * Key value methods
    \*/

    private static Variant get_gsettings_key_value (GSettingsKey key)
    {
        return key.settings.get_value (key.name);
    }

    private static Variant get_dconf_key_value (string full_name, DConf.Client client)
    {
        Variant? key_value = get_dconf_key_value_or_null (full_name, client);
        if (key_value == null)
            assert_not_reached ();
        return (!) key_value;
    }
    private static Variant? get_dconf_key_value_or_null (string full_name, DConf.Client client)
    {
        return client.read (full_name);
    }

    internal void set_gsettings_key_value (string full_name, uint16 context_id, Variant key_value)
    {
        string schema_id = get_schema_id_from_context_id (context_id);

        Key? key = get_key (full_name, schema_id);
        if (key == null)
        {
            warning ("Non-existing key gsettings set-value request.");
            set_dconf_value (full_name, key_value);
        }
        else if ((!) key is GSettingsKey)
            ((GSettingsKey) (!) key).settings.set_value (((!) key).name, key_value);
        else if ((!) key is DConfKey)               // should not happen for now
        {
            warning ("Key without schema gsettings set-value request.");
            set_dconf_value (full_name, key_value);
            ((!) key).value_changed ();
        }
        else
            assert_not_reached ();
    }

    internal void set_dconf_key_value (string full_name, Variant key_value)
    {
        Key? key = get_key (full_name, "");
        set_dconf_value (full_name, key_value);

        if (key == null)
            warning ("Non-existing key dconf set-value request.");
        else
        {
            if (!(((!) key) is DConfKey))
                warning ("Non-DConfKey key dconf set-value request.");
            ((Key) (!) key).value_changed ();
        }
    }
    private void set_dconf_value (string full_name, Variant? key_value)
    {
        try
        {
            client.write_sync (full_name, key_value, out last_change_tag);
        }
        catch (Error error)
        {
            warning (error.message);
        }
    }

    internal void set_key_to_default (string full_name, uint16 context_id)
    {
        GSettingsKey key = get_specific_gsettings_key (full_name, context_id);
        GLib.Settings settings = key.settings;
        settings.reset (key.name);
        if (settings.backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
            settings.backend.changed (full_name, null);
        // Alternative workaround: key.value_changed ();
    }

    internal void erase_key (string full_name)
    {
        Key? key = get_key (full_name, "");
        set_dconf_value (full_name, null);

        if (key == null)
            warning ("Non-existing key erase request.");
        else
        {
            if (!(((!) key) is DConfKey))
                warning ("Non-DConfKey key erase request.");
            ((Key) (!) key).value_changed ();
        }
    }

    private static inline bool is_key_default (GSettingsKey key)
    {
        return key.settings.get_user_value (key.name) == null;
    }

    internal bool key_has_schema (string full_name)
    {
        if (ModelUtils.is_folder_path (full_name))
            assert_not_reached ();

        Key? key = get_key (full_name, "");
        return key != null && (!) key is GSettingsKey;
    }

    internal bool is_key_ghost (string full_name)
    {
        // we're "sure" the key is a DConfKey, but that might have changed since
        if (key_has_schema (full_name))
            warning (@"Function is_key_ghost called for path:\n  $full_name\nbut key found there has a schema.");

        return _is_key_ghost (full_name);
    }
    private bool _is_key_ghost (string full_name)
    {
        return get_dconf_key_value_or_null (full_name, client) == null;
    }

    internal void apply_key_value_changes (HashTable<string, Variant?> changes)
    {
        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        changes.foreach ((key_name, planned_value) => {
                Key? key = get_key (key_name, "");
                if (key == null)
                {
                    // TODO change value anyway?
                }
                else if ((!) key is GSettingsKey)
                {
                    string key_descriptor = ((GSettingsKey) (!) key).descriptor;
                    string settings_descriptor = key_descriptor [0:key_descriptor.last_index_of_char (' ')]; // strip the key name
                    GLib.Settings? settings = delayed_settings_hashtable.lookup (settings_descriptor);
                    if (settings == null)
                    {
                        settings = ((GSettingsKey) (!) key).settings;
                        ((!) settings).delay ();
                        delayed_settings_hashtable.insert (settings_descriptor, (!) settings);
                    }

                    if (planned_value == null)
                    {
                        ((!) settings).reset (((!) key).name);
                        if (((!) settings).backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
                            ((!) settings).backend.changed (((!) key).full_name, null);
                        // Alternative workaround: key.value_changed ();
                    }
                    else
                        ((!) settings).set_value (((!) key).name, (!) planned_value);
                }
                else if ((!) key is DConfKey)
                    dconf_changeset.set (((!) key).full_name, planned_value);
                else
                    assert_not_reached ();
            });

        delayed_settings_hashtable.foreach_remove ((key_descriptor, schema_settings) => { schema_settings.apply (); return true; });

        try
        {
            client.change_sync (dconf_changeset, out last_change_tag);
        }
        catch (Error error)
        {
            warning (error.message);
        }
    }

    /*\
    * * Key properties methods
    \*/

    internal Variant get_key_properties (string full_name, uint16 context_id, uint16 _query)
    {
        Key key = get_specific_key (full_name, context_id);

        PropertyQuery query = (PropertyQuery) _query;

        Variant key_properties;
        if (PropertyQuery.HASH in query)
            key_properties = ((!) key).get_fixed_properties (0);    // ensures hash is generated

        key_properties = ((!) key).get_fixed_properties (query);

        bool all_properties_queried = query == 0;
        RegistryVariantDict variantdict = new RegistryVariantDict.from_aqv (key_properties);

        if (all_properties_queried || PropertyQuery.HASH                in query)
            variantdict.insert_value (PropertyQuery.HASH,                           new Variant.uint32 (((!) key).key_hash));
        if (all_properties_queried ||     PropertyQuery.KEY_VALUE       in query)
        {
            if (key is GSettingsKey)
                variantdict.insert_value (PropertyQuery.KEY_VALUE,                  new Variant.variant (get_gsettings_key_value ((GSettingsKey) (!) key)));
            else // (key is DConfKey)
                variantdict.insert_value (PropertyQuery.KEY_VALUE,                  new Variant.variant (get_dconf_key_value (((!) key).full_name, client)));
        }
        if (key is GSettingsKey)
        {
            if (all_properties_queried || PropertyQuery.KEY_CONFLICT    in query)
                variantdict.insert_value (PropertyQuery.KEY_CONFLICT,               new Variant.byte ((uint8) ((GSettingsKey) (!) key).key_conflict));
            if (all_properties_queried || PropertyQuery.IS_DEFAULT      in query)
                variantdict.insert_value (PropertyQuery.IS_DEFAULT,                 new Variant.boolean (((GSettingsKey) (!) key).settings.get_user_value (((!) key).name) == null));
        }
        return variantdict.end ();
    }

    internal string get_key_copy_text (string full_name, uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
    {
        if (ModelUtils.is_dconf_context_id (context_id))
            return get_dconf_key_copy_text (full_name, client);

        GSettingsKey key = get_specific_gsettings_key (full_name, context_id);
        return get_gsettings_key_copy_text (key);
    }
    private static inline string get_gsettings_key_copy_text (GSettingsKey key)
    {
        return key.descriptor + " " + get_gsettings_key_value (key).print (false);
    }
    private static inline string get_dconf_key_copy_text (string full_name, DConf.Client client)
    {
        Variant? key_value = get_dconf_key_value_or_null (full_name, client);
        if (key_value == null)
            return _("%s (key erased)").printf (full_name);
        else
            return full_name + " " + ((!) key_value).print (false);
    }
}
