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

private abstract class SettingsModelCore : Object
{
    private SourceManager source_manager = new SourceManager ();
    [CCode (notify = false)] internal bool refresh_source { private get; internal set; default = true; }

    private DConf.Client client = new DConf.Client ();
    private string? last_change_tag = null;
    protected bool copy_action = false;
    private bool gsettings_change = false;

    [CCode (notify = false)] internal bool use_shortpaths { private get; internal set; default = false; }

    internal signal void paths_changed (GenericSet<string> modified_path_specs, bool internal_changes);
    private bool paths_has_changed = false;

    private HashTable<string, Key> saved_keys = new HashTable<string, Key> (str_hash, str_equal);

    protected void _refresh_relocatable_schema_paths (bool    user_schemas,
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

    protected void _add_mapping (string schema, string folder_path)
    {
        source_manager.add_mapping (schema, folder_path);
    }

    protected void _finalize_model ()
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
                bool internal_changes = copy_action || gsettings_change;
                if (copy_action)
                    copy_action = false;
                if (gsettings_change)
                    gsettings_change = false;
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

    protected Variant? _get_children (string folder_path, bool watch, bool clean_watched)
    {
        if (clean_watched)
            _clean_watched_keys ();

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
                if (watch)
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

    protected bool _get_object (string path, out uint16 context_id, out string name, bool watch)
    {
        SettingObject? object;
        bool is_folder_path = ModelUtils.is_folder_path (path);
        if (is_folder_path)
            object = (SettingObject?) get_directory (path);
        else
            object = (SettingObject?) get_key (path, "");

        if (object == null)
        {
            if (is_folder_path)
                context_id = ModelUtils.folder_context_id;
            else
                context_id = ModelUtils.undefined_context_id;   // garbage 1/2
            name = "";                                          // garbage 2/2
            return false;
        }

        if (watch && (!) object is Key)
            add_watched_key ((Key) (!) object);

        context_id = get_context_id_from_object ((!) object);
        name = ((!) object).name;
        return true;
    }

    protected bool _key_exists (string key_path, uint16 key_context_id)
    {
        Key? key = get_key (key_path, get_key_context_from_id (key_context_id));
        return key != null;
    }

    protected bool _key_exists_2 (string key_path)
    {
        Key? key = get_key (key_path, "");
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

    private Key get_specific_key (string key_path, uint16 key_context_id)
    {
        if (ModelUtils.is_dconf_context_id (key_context_id))
        {
            Key? nullable_key = get_key (key_path, ".dconf");
            if (nullable_key == null || !((!) nullable_key is DConfKey))
                assert_not_reached ();
            return (!) nullable_key;
        }
        else
            return (Key) get_specific_gsettings_key (key_path, key_context_id);
    }

    private GSettingsKey get_specific_gsettings_key (string key_path, uint16 gkey_context_id)
    {
        string schema_id = get_schema_id_from_gkey_context_id (gkey_context_id);
        Key? key = get_key (key_path, schema_id);
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
        uint n_items = ((!) key_model).get_n_items ();
        while (position < n_items)
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

        contexts_list.insert_sorted_with_data (context_index, (a, b) => sort_context_ids (get_schema_id_from_gkey_context_id (a),
                                                                                          get_schema_id_from_gkey_context_id (b),
                                                                                          _case_sensitive));
        return context_index;
    }

    private string get_key_context_from_id (uint16 context_id)
        requires (!ModelUtils.is_undefined_context_id (context_id))
        requires (!ModelUtils.is_folder_context_id (context_id))
        requires (context_id != uint16.MAX)
    {
        if (ModelUtils.is_dconf_context_id (context_id))
            return ".dconf";
        return get_schema_id_from_gkey_context_id (context_id);
    }

    private string get_schema_id_from_gkey_context_id (uint16 context_id)
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

    protected uint16 [] _get_sorted_context_id ()
    {
        uint length = contexts_list.length ();
        uint16 [] contexts_array = new uint16 [length];
        for (uint i = 0; i < length; i++)
            contexts_array [contexts_list.nth_data (i) - ModelUtils.special_context_id_number] = (uint16) i;
        return contexts_array;
    }

    protected void sort_contexts_list (bool case_sensitive)
    {
        if (case_sensitive == _case_sensitive)
            return;

        _case_sensitive = case_sensitive;
        contexts_list.sort_with_data ((a, b) => sort_context_ids (get_schema_id_from_gkey_context_id (a),
                                                                  get_schema_id_from_gkey_context_id (b),
                                                                  case_sensitive));
    }
    private static int sort_context_ids (string a_str, string b_str, bool case_sensitive)
    {
        if (!case_sensitive)
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

    protected void _keys_value_push ()
    {
        uint position = 0;
        Object? object = watched_keys.get_item (0);
        while (object != null)
        {
            if ((!) object is GSettingsKey)
                push_gsettings_key_value ((GSettingsKey) (!) object);
            else if ((!) object is DConfKey)
                push_dconf_key_value (((Key) (!) object).full_name, client);
            else assert_not_reached ();
            position++;
            object = watched_keys.get_item (position);
        };
    }

    protected void _key_value_push (string key_path, uint16 key_context_id)
    {
        uint position = 0;
        Object? object = watched_keys.get_item (0);
        while (object != null)
        {
            if (((Key) (!) object).full_name == key_path
             && get_context_id_from_key ((Key) (!) object) == key_context_id)
            {
                if ((!) object is GSettingsKey)
                    push_gsettings_key_value ((GSettingsKey) (!) object);
                else if ((!) object is DConfKey)
                    push_dconf_key_value (((Key) (!) object).full_name, client);
                else assert_not_reached ();
                return;
            }
            position++;
            object = watched_keys.get_item (position);
        };
    }

    private void add_watched_key (Key key)
    {
        if (key is GSettingsKey)
        {
            ((GSettingsKey) key).connect_settings ();
            key.key_value_changed_handler = key.value_changed.connect (on_gkey_value_changed);
        }
        else if (key is DConfKey)
        {
            ((DConfKey) key).connect_client (client);
            key.key_value_changed_handler = key.value_changed.connect (on_dkey_value_changed);
        }
        else assert_not_reached ();

        watched_keys.append (key);
        saved_keys.insert (key.full_name, key);
    }
    private void on_gkey_value_changed (Key key) { push_gsettings_key_value ((GSettingsKey) key); }
    private void on_dkey_value_changed (Key key) { push_dconf_key_value (key.full_name, client); }

    protected void _clean_watched_keys ()
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

            if (key.key_value_changed_handler != 0) // FIXME happens since editable paths 3/3
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

    private inline void push_dconf_key_value (string key_path, DConf.Client client)
    {
        dkey_value_push (key_path,
                         get_dconf_key_value_or_null (key_path, client));
    }

    /*\
    * * Path methods
    \*/

    protected string _get_folder_fallback_path (string folder_path)
    {
        string fallback_path = folder_path;
        Directory? dir = get_directory (folder_path);
        while (dir == null)
        {
            fallback_path = ModelUtils.get_parent_path (fallback_path);
            dir = get_directory (fallback_path);
        }
        return fallback_path;
    }

    protected string _get_startup_path_fallback (string path)   // TODO take context and check that also
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

    protected uint16 _get_fallback_context (string key_path, uint16 context_id, string schema_id)
    {
        string context;
        if (schema_id != "")
            context = schema_id;
        else if (ModelUtils.is_undefined_context_id (context_id))
            context = "";
        else
            context = get_key_context_from_id (context_id);

        Key? found_object = get_key (key_path, context);
        if (found_object == null && context != "")  // TODO warn about missing context
            found_object = get_key (key_path, "");

        if (found_object == null)
            return ModelUtils.undefined_context_id;

        _clean_watched_keys ();
        add_watched_key ((!) found_object);

        return get_context_id_from_object ((!) found_object);
    }

    /*\
    * * Key value methods
    \*/

    private static Variant get_gsettings_key_value (GSettingsKey gkey)
    {
        return gkey.settings.get_value (gkey.name);
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

    protected void _set_gsettings_key_value (string key_path, uint16 gkey_context_id, Variant key_value)
    {
        string schema_id = get_schema_id_from_gkey_context_id (gkey_context_id);

        Key? key = get_key (key_path, schema_id);
        if (key == null)
        {
            warning ("Non-existing key gsettings set-value request.");
            set_dconf_value (key_path, key_value);
        }
        else if ((!) key is GSettingsKey)
            ((GSettingsKey) (!) key).settings.set_value (((!) key).name, key_value);
        else if ((!) key is DConfKey)               // should not happen for now
        {
            warning ("Key without schema gsettings set-value request.");
            set_dconf_value (key_path, key_value);
            ((!) key).value_changed ();
        }
        else
            assert_not_reached ();
    }

    protected void _set_dconf_key_value (string full_name, Variant? key_value)
    {
        Key? key = get_key (full_name, "");
        set_dconf_value (full_name, key_value);

        if (key == null)
        {
            if (key_value == null)  warning ("Non-existing key erase request.");
            else                    warning ("Non-existing key dconf set-value request.");
            return;
        }
        if (!(((!) key) is DConfKey))
        {
            if (key_value == null)  warning ("Non-DConfKey key erase request.");
            else                    warning ("Non-DConfKey key dconf set-value request.");
        }

        ((Key) (!) key).value_changed ();
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

    protected void _set_key_to_default (string key_path, uint16 gkey_context_id)
    {
        GSettingsKey gkey = get_specific_gsettings_key (key_path, gkey_context_id);
        GLib.Settings settings = gkey.settings;
        settings.reset (gkey.name);
        if (settings.backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
            settings.backend.changed (key_path, null);
        // Alternative workaround: key.value_changed ();
    }

    private static inline bool is_key_default (GSettingsKey gkey)
    {
        return gkey.settings.get_user_value (gkey.name) == null;
    }

    protected bool _key_has_schema (string key_path)
    {
        Key? key = get_key (key_path, "");
        return key != null && (!) key is GSettingsKey;
    }

    protected bool _is_key_ghost (string key_path)
    {
        return get_dconf_key_value_or_null (key_path, client) == null;
    }

    protected void _apply_key_value_changes (HashTable<string, Variant?> changes)
    {
        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        bool dconf_changeset_has_change = false;
        changes.foreach ((key_path, planned_value) => {
                Key? key = get_key (key_path, "");
                if (key == null || (!) key is DConfKey) // TODO assert_not_reached() if no key found?
                {
                    dconf_changeset_has_change = true;
                    dconf_changeset.set (((!) key).full_name, planned_value);
                }
                else if ((!) key is GSettingsKey)
                {
                    gsettings_change = true;
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
                else
                    assert_not_reached ();
            });

        delayed_settings_hashtable.foreach_remove ((key_descriptor, schema_settings) => { schema_settings.apply (); return true; });

        if (dconf_changeset_has_change)
        {
            try
            {
                client.change_sync (dconf_changeset, out last_change_tag);
            }
            catch (Error error)
            {
                warning (error.message);
            }
        }
    }

    /*\
    * * Key properties
    \*/

    protected Variant _get_key_properties (string key_path, uint16 key_context_id, uint16 _query)
    {
        Key key = get_specific_key (key_path, key_context_id);

        PropertyQuery query = (PropertyQuery) _query;
        bool all_properties_queried = query == 0;

        if ((all_properties_queried || PropertyQuery.HASH in query) && key.all_fixed_properties == null)
            Key.generate_key_fixed_properties (key);

        RegistryVariantDict variantdict;

        // fixed properties
        if (all_properties_queried)
            variantdict = new RegistryVariantDict.from_aqv ((!) key.all_fixed_properties);
        else
        {
            variantdict = new RegistryVariantDict ();
            Key.get_key_fixed_properties (key, query, ref variantdict);
        }

        // special case
        if (all_properties_queried || PropertyQuery.HASH                in query)
            variantdict.insert_value (PropertyQuery.HASH,                           new Variant.uint32 (key.key_hash));

        // variable properties
        if (all_properties_queried ||     PropertyQuery.KEY_VALUE       in query)
        {
            if (key is GSettingsKey)
                variantdict.insert_value (PropertyQuery.KEY_VALUE,                  new Variant.variant (get_gsettings_key_value ((GSettingsKey) key)));
            else if (key is DConfKey)
                variantdict.insert_value (PropertyQuery.KEY_VALUE,                  new Variant.variant (get_dconf_key_value (key_path, client)));
            else assert_not_reached ();
        }
        if (key is GSettingsKey)
        {
            if (all_properties_queried || PropertyQuery.KEY_CONFLICT    in query)
                variantdict.insert_value (PropertyQuery.KEY_CONFLICT,               new Variant.byte ((uint8) ((GSettingsKey) key).key_conflict));
            if (all_properties_queried || PropertyQuery.IS_DEFAULT      in query)
                variantdict.insert_value (PropertyQuery.IS_DEFAULT,                 new Variant.boolean (((GSettingsKey) key).settings.get_user_value (key.name) == null));
        }
        return variantdict.end ();
    }

    protected string get_suggested_gsettings_key_copy_text (string key_path, uint16 gkey_context_id)
    {
        GSettingsKey gkey = get_specific_gsettings_key (key_path, gkey_context_id);
        return _get_suggested_gsettings_key_copy_text (gkey);
    }
    private static inline string _get_suggested_gsettings_key_copy_text (GSettingsKey gkey)
    {
        return gkey.descriptor + " " + get_gsettings_key_value (gkey).print (false);
    }

    protected string get_suggested_dconf_key_copy_text (string key_path)
    {
        return _get_suggested_dconf_key_copy_text (key_path, client);
    }
    private static inline string _get_suggested_dconf_key_copy_text (string key_path, DConf.Client client)
    {
        Variant? key_value = get_dconf_key_value_or_null (key_path, client);
        if (key_value == null)
            /* Translators: text copied when the users request a copy while an erased key is selected; the %s is the key path */
            return _("%s (key erased)").printf (key_path);
        else
            return key_path + " " + ((!) key_value).print (false);
    }
}

private class SettingsModel : SettingsModelCore
{
    /*\
    * * Init
    \*/

    internal void refresh_relocatable_schema_paths (bool    user_schemas,
                                                    bool    built_in_schemas,
                                                    bool    internal_schemas,
                                                    bool    startup_schemas,
                                                    Variant user_paths_variant)
    {
        _refresh_relocatable_schema_paths (user_schemas,
                                           built_in_schemas,
                                           internal_schemas,
                                           startup_schemas,
                                           user_paths_variant);
    }

    internal void add_mapping (string schema, string folder_path)
        requires (ModelUtils.is_folder_path (folder_path))
    {
        _add_mapping (schema, folder_path);
    }

    internal void finalize_model ()
    {
        _finalize_model ();
    }

    /*\
    * * Directories information
    \*/

    internal Variant _get_folder_properties (string folder_path)
    {
        RegistryVariantDict variantdict = new RegistryVariantDict ();

        variantdict.insert_value (PropertyQuery.KEY_NAME, new Variant.string (ModelUtils.get_name (folder_path)));
        return variantdict.end ();
    }

    internal Variant? get_children (string folder_path, bool watch = false, bool clean_watched = false)
        requires (ModelUtils.is_folder_path (folder_path))
    {
        return _get_children (folder_path, watch, clean_watched);
    }

    internal uint16 [] get_sorted_context_id (bool case_sensitive)
    {
        sort_contexts_list (case_sensitive);
        return _get_sorted_context_id ();
    }

    internal void keys_value_push ()
    {
        _keys_value_push ();
    }

    internal void key_value_push (string key_path, uint16 key_context_id)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (key_context_id))
        requires (!ModelUtils.is_folder_context_id (key_context_id))
    {
        _key_value_push (key_path, key_context_id);
    }

    /*\
    * * Weird things
    \*/

    internal void clean_watched_keys ()
    {
        _clean_watched_keys ();
    }

    internal void copy_action_called ()
    {
        copy_action = true;
    }

    internal bool get_object (string path, out uint16 context_id, out string name, bool watch = true)
    {
        return _get_object (path, out context_id, out name, watch);
    }

    internal string get_fallback_path (string path)
    {
        // folder
        if (ModelUtils.is_folder_path (path))
            return _get_folder_fallback_path (path);
        // key
        if (_key_exists_2 (path))
            return path;
        else
            return _get_folder_fallback_path (ModelUtils.get_parent_path (path));
    }

    internal string get_startup_path_fallback (string path)   // TODO take context and check that also
    {
        return _get_startup_path_fallback (path);
    }

    internal uint16 get_fallback_context (string key_path, uint16 context_id, string schema_id = "")
        requires (ModelUtils.is_key_path (key_path))
    {
        return _get_fallback_context (key_path, context_id, schema_id);
    }

    /*\
    * * GSettingsKey manipulation
    \*/

    internal void set_gsettings_key_value (string key_path, uint16 gkey_context_id, Variant key_value)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (gkey_context_id))
        requires (!ModelUtils.is_folder_context_id (gkey_context_id))
        requires (!ModelUtils.is_dconf_context_id (gkey_context_id))
    {
        _set_gsettings_key_value (key_path, gkey_context_id, key_value);
    }

    internal void set_key_to_default (string key_path, uint16 gkey_context_id)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (gkey_context_id))
        requires (!ModelUtils.is_folder_context_id (gkey_context_id))
        requires (!ModelUtils.is_dconf_context_id (gkey_context_id))
    {
        _set_key_to_default (key_path, gkey_context_id);
    }

    /*\
    * * DConfKey manipulation
    \*/

    internal void set_dconf_key_value (string key_path, Variant key_value)
        requires (ModelUtils.is_key_path (key_path))
    {
        _set_dconf_key_value (key_path, key_value);
    }

    internal void erase_key (string key_path)
        requires (ModelUtils.is_key_path (key_path))
    {
        _set_dconf_key_value (key_path, null);
    }

    internal void apply_key_value_changes (HashTable<string, Variant?> changes)
    {
        _apply_key_value_changes (changes);
    }

    /*\
    * * Key existence tests
    \*/

    internal bool key_exists (string key_path, uint16 key_context_id)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (key_context_id))
        requires (!ModelUtils.is_folder_context_id (key_context_id))
    {
        return _key_exists (key_path, key_context_id); // TODO make ModelUtils.is_dconf_context_id() test here
    }

    internal bool key_has_schema (string key_path)
        requires (ModelUtils.is_key_path (key_path))
    {
        return _key_has_schema (key_path);
    }

    internal bool is_key_ghost (string key_path)
        requires (ModelUtils.is_key_path (key_path))
    {
        // we're "sure" the key is a DConfKey, but that might have changed since
        if (_key_has_schema (key_path))
            warning (@"Function is_key_ghost called for path:\n  $key_path\nbut key found there has a schema.");

        return _is_key_ghost (key_path);
    }

    /*\
    * * Keys properties
    \*/

    internal Variant get_folder_properties (string folder_path)
        requires (ModelUtils.is_folder_path (folder_path))
    {
        return _get_folder_properties (folder_path);
    }

    internal Variant get_key_properties (string key_path, uint16 key_context_id, uint16 query)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (key_context_id))
        requires (!ModelUtils.is_folder_context_id (key_context_id))
        // PropertyQuery has the same number of values than uint16
    {
        return _get_key_properties (key_path, key_context_id, query);
    }

    internal string get_suggested_key_copy_text (string key_path, uint16 key_context_id)
        requires (ModelUtils.is_key_path (key_path))
        requires (!ModelUtils.is_undefined_context_id (key_context_id))
        requires (!ModelUtils.is_folder_context_id (key_context_id))
    {
        if (ModelUtils.is_dconf_context_id (key_context_id))
            return get_suggested_dconf_key_copy_text (key_path);
        else
            return get_suggested_gsettings_key_copy_text (key_path, key_context_id);
    }
}
