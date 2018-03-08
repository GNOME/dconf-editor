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

public class SettingsModel : Object
{
    private SourceManager source_manager = new SourceManager ();
    public bool refresh_source { get; set; default = true; }

    private DConf.Client client = new DConf.Client ();
    private string? last_change_tag = null;
    public bool copy_action = false;

    public signal void paths_changed (GenericSet<string> modified_path_specs, bool internal_changes);

    public void refresh_relocatable_schema_paths (bool user_schemas,
                                                  bool built_in_schemas,
                                                  bool internal_schemas,
                                                  bool startup_schemas,
                                                  Variant user_paths_variant)
    {
        source_manager.refresh_relocatable_schema_paths (user_schemas,
                                                         built_in_schemas,
                                                         internal_schemas,
                                                         startup_schemas,
                                                         user_paths_variant);
    }

    public void add_mapping (string schema, string path)
    {
        source_manager.add_mapping (schema, path);
    }

    public void finalize_model ()
    {
        source_manager.paths_changed.connect ((modified_path_specs) => paths_changed (modified_path_specs, false));
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
                    if (is_key_path (item_path))
                        modified_path_specs.add (get_parent_path (item_path));
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

    public Directory get_root_directory ()
    {
        return new Directory ("/", "/");
    }

    private Directory? get_directory (string path)
    {
        if (path == "/")
            return get_root_directory ();

        uint schemas_count = 0;
        uint subpaths_count = 0;
        source_manager.cached_schemas.get_content_count (path, out schemas_count, out subpaths_count);
        if (schemas_count + subpaths_count > 0 || client.list (path).length > 0)
            return new Directory (path, get_name (path));
        return null;
    }

    public GLib.ListStore? get_children (string folder_path)
    {
        Directory? dir = get_directory (folder_path);
        if (dir == null)
            return null;

        GLib.ListStore key_model = new GLib.ListStore (typeof (SettingObject));
        bool multiple_schemas;

        lookup_gsettings (folder_path, key_model, out multiple_schemas);
        create_dconf_keys (folder_path, key_model);

        if (key_model.get_n_items () > 0)
            return key_model;
        else
            return null;
    }

    public SettingObject? get_object (string path)
    {
        if (is_key_path (path))
            return (SettingObject?) get_key (path, "");
        else
            return (SettingObject?) get_directory (path);
    }

    public Key? get_key (string path, string context = "")
    {
        GLib.ListStore? key_model = get_children (get_parent_path (path));
        return get_key_from_path_and_name (key_model, get_name (path), context);
    }

    public bool path_exists (string path)
    {
        if (is_key_path (path))
        {
            GLib.ListStore? key_model = get_children (get_parent_path (path));
            return get_key_from_path_and_name (key_model, get_name (path)) != null;
        }
        else
            return get_directory (path) != null;
    }

    private static Key? get_key_from_path_and_name (GLib.ListStore? key_model, string key_name, string context = "")
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
        GSettingsKey? conflicting_key = (GSettingsKey?) get_key_from_path_and_name (key_model, key_id); // safe cast, no DConfKey's added yet
        if (conflicting_key != null)
        {
            ((!) conflicting_key).warning_conflicting_key = true;
            new_key.warning_conflicting_key = true;
            if (((!) conflicting_key).error_hard_conflicting_key == true
             || new_key.type_string != ((!) conflicting_key).type_string
             || !new_key.default_value.equal (((!) conflicting_key).default_value)
             || new_key.range_type != ((!) conflicting_key).range_type
             || !new_key.range_content.equal (((!) conflicting_key).range_content))
            {
                ((!) conflicting_key).error_hard_conflicting_key = true;
                new_key.error_hard_conflicting_key = true;
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
                create_dconf_key (parent_path, item, key_model);
        }
    }

    private void create_dconf_key (string parent_path, string key_id, GLib.ListStore key_model)
    {
        Variant? key_value = get_dconf_key_value_or_null (parent_path + key_id, client);
        if (key_value == null)
            return;
        DConfKey new_key = new DConfKey (client, parent_path, key_id, ((!) key_value).get_type_string ());
        key_model.append (new_key);
    }

    /*\
    * * Path utilities
    \*/

    public static bool is_key_path (string path)
    {
        return !path.has_suffix ("/");
    }

    public static string get_base_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return path.slice (0, path.last_index_of_char ('/') + 1);
    }

    public static string get_name (string path)
    {
        if (path.length <= 1)
            return "/";
        if (is_key_path (path))
            return path [path.last_index_of_char ('/') + 1 : path.length];
        string tmp = path [0:-1];
        return tmp [tmp.last_index_of_char ('/') + 1 : tmp.length];
    }

    public static string get_parent_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return get_base_path (is_key_path (path) ? path : path [0:-1]);
    }

    /*\
    * * Directory methods
    \*/

    public string get_fallback_path (string path)
    {
        string fallback_path = path;
        if (is_key_path (path))
        {
            Key? key = get_key (path, "");
            if (key != null)
                return path;
            fallback_path = get_parent_path (path);
        }

        Directory? dir = get_directory (fallback_path);
        while (dir == null)
        {
            fallback_path = get_parent_path (fallback_path);
            dir = get_directory (fallback_path);
        }
        return fallback_path;
    }

    /*\
    * * Key value methods
    \*/

    public Variant? get_key_properties (string full_name, string context)
    {
        Key? key = get_key (full_name, context);
        if (key == null)
            return null;

        return ((!) key).properties;
    }

    public string get_key_copy_text (string full_name, string context)
    {
        Key? key = get_key (full_name, context);
        if (key == null)
            return full_name;

        if ((!) key is GSettingsKey)
            return ((!) key).descriptor + " " + get_gsettings_key_value ((GSettingsKey) key).print (false);

        if (!((!) key is DConfKey))
            assert_not_reached ();

        Variant? key_value = get_dconf_key_value_or_null (full_name, client);
        if (key_value == null)
            return _("%s (key erased)").printf (full_name);
        else
            return ((!) key).descriptor + " " + ((!) key_value).print (false);
    }

    public Variant get_key_value (Key key)
    {
        if ((!) key is GSettingsKey)
            return get_gsettings_key_value ((GSettingsKey) key);
        if ((!) key is DConfKey)
            return get_dconf_key_value ((DConfKey) key, client);
        assert_not_reached ();
    }

    private static Variant get_gsettings_key_value (GSettingsKey key)
    {
        return key.settings.get_value (get_name (key.full_name));
    }

    private static Variant get_dconf_key_value (DConfKey key, DConf.Client client)
    {
        Variant? key_value = get_dconf_key_value_or_null (key.full_name, client);
        if (key_value == null)
            assert_not_reached ();
        return (!) key_value;
    }
    private static Variant? get_dconf_key_value_or_null (string full_name, DConf.Client client)
    {
        return client.read (full_name);
    }

    public void set_key_value (Key key, Variant key_value)
    {
        if (key is GSettingsKey)
            ((GSettingsKey) key).settings.set_value (key.name, key_value);
        else
        {
            set_dconf_value (key.full_name, key_value);
            key.value_changed ();
        }
    }

    public void set_gsettings_key_value (string full_name, string schema_id, Variant key_value)
    {
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

    public void set_dconf_key_value (string full_name, Variant key_value)
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

    public void set_key_to_default (string full_name, string schema_id)
    {
        Key? key = get_key (full_name, schema_id);
        if (key == null && !(key is GSettingsKey))
            return; // TODO better

        GLib.Settings settings = ((GSettingsKey) (!) key).settings;
        settings.reset (((!) key).name);
        if (settings.backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
            settings.backend.changed (full_name, null);
        // Alternative workaround: key.value_changed ();
    }

    public void erase_key (string full_name)
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

    public bool is_key_default (GSettingsKey key)
    {
        GLib.Settings settings = key.settings;
        return settings.get_user_value (key.name) == null;
    }

    public bool is_key_ghost (DConfKey key)
    {
        return get_dconf_key_value_or_null (key.full_name, client) == null;
    }

    public void apply_key_value_changes (HashTable<string, Variant?> changes)
    {
        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        changes.foreach ((key_name, planned_value) => {
                Key? key = get_key (key_name);
                if (key == null)
                {
                    // TODO change value anyway?
                }
                else if ((!) key is GSettingsKey)
                {
                    string key_descriptor = ((Key) (!) key).descriptor;
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
}
