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

public enum ModificationsMode {
    NONE,
    TEMPORARY,
    DELAYED
}

public uint key_hash (Key key)
{
    return str_hash (key.descriptor);
}

public bool key_equal (Key key1, Key key2)
{
    return str_equal (key1.descriptor, key2.descriptor);
}

class ModificationsHandler : Object
{
    public ModificationsMode mode { get; set; default=ModificationsMode.NONE; }

    private DConf.Client dconf_client = new DConf.Client ();

    private HashTable<DConfKey, Variant?>         dconf_keys_awaiting_hashtable = new HashTable<DConfKey, Variant?>     (key_hash, key_equal);
    private HashTable<GSettingsKey, Variant?> gsettings_keys_awaiting_hashtable = new HashTable<GSettingsKey, Variant?> (key_hash, key_equal);
    public uint dconf_changes_count     { get { return dconf_keys_awaiting_hashtable.length; } }
    public uint gsettings_changes_count { get { return gsettings_keys_awaiting_hashtable.length; } }

    public signal void reload ();
    public signal void delayed_changes_changed ();

    public Behaviour behaviour { get; set; }

    /*\
    * * Public calls
    \*/

    public bool get_current_delay_mode ()
    {
        return mode == ModificationsMode.DELAYED || behaviour == Behaviour.ALWAYS_DELAY;
    }

    public bool should_delay_apply (string type_string)
    {
        if (get_current_delay_mode () || behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            return true;
        if (behaviour == Behaviour.UNSAFE)
            return false;
        if (behaviour == Behaviour.SAFE)
            return type_string != "b" && type_string != "mb" && type_string != "<enum>" && type_string != "<flags>";
        assert_not_reached ();
    }

    public void enter_delay_mode ()
    {
        mode = ModificationsMode.DELAYED;

        delayed_changes_changed ();
    }

    public void add_delayed_setting (Key key, Variant? new_value)
    {
        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.insert ((GSettingsKey) key, new_value);
        else
            dconf_keys_awaiting_hashtable.insert ((DConfKey) key, new_value);

        mode = get_current_delay_mode () ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        delayed_changes_changed ();
    }

    public void dismiss_change (Key key)
    {
        if (mode == ModificationsMode.NONE)
            mode = behaviour == Behaviour.ALWAYS_DELAY ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.remove ((GSettingsKey) key);
        else
            dconf_keys_awaiting_hashtable.remove ((DConfKey) key);

        delayed_changes_changed ();
    }

    public void path_changed ()
    {
        if (mode != ModificationsMode.TEMPORARY)
            return;
        if (behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.SAFE)
            apply_delayed_settings ();
        else if (behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            dismiss_delayed_settings ();
        else
            assert_not_reached ();
    }

    public void apply_delayed_settings ()
    {
        mode = ModificationsMode.NONE;

        /* GSettings stuff */

        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        gsettings_keys_awaiting_hashtable.foreach_remove ((key, planned_value) => {
                string key_descriptor = key.descriptor;
                string settings_descriptor = key_descriptor [0:key_descriptor.last_index_of_char (' ')]; // strip the key name
                GLib.Settings? settings = delayed_settings_hashtable.lookup (settings_descriptor);
                if (settings == null)
                {
                    settings = key.settings;
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

                return true;
            });

        delayed_settings_hashtable.foreach_remove ((key_descriptor, schema_settings) => { schema_settings.apply (); return true; });

        /* DConf stuff */

        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        dconf_keys_awaiting_hashtable.foreach_remove ((key, planned_value) => {
                dconf_changeset.set (key.full_name, planned_value);

                if (planned_value == null)
                    key.is_ghost = true;

                return true;
            });

        try {
            dconf_client.change_sync (dconf_changeset);
        } catch (Error error) {
            warning (error.message);
        }

        /* reload the hamburger menu */

        delayed_changes_changed ();
        reload ();
    }

    public void dismiss_delayed_settings ()
    {
        mode = ModificationsMode.NONE;

        gsettings_keys_awaiting_hashtable.remove_all ();
        dconf_keys_awaiting_hashtable.remove_all ();

        /* reload notably key_editor_child */

        delayed_changes_changed ();
        reload ();
    }

    public Variant get_key_custom_value (Key key)
    {
        bool planned_change = key_has_planned_change (key);
        Variant? planned_value = get_key_planned_value (key);
        return planned_change && (planned_value != null) ? (!) planned_value : key.value;
    }

    public bool key_value_is_default (GSettingsKey key) // doesn't make sense for DConfKey?
    {
        bool planned_change = key_has_planned_change (key);
        Variant? planned_value = get_key_planned_value (key);
        return planned_change ? planned_value == null : key.is_default;
    }

    public void set_key_value (Key key, Variant? new_value)
    {
        if (get_current_delay_mode ())
            add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key is GSettingsKey)
            ((GSettingsKey) key).set_to_default ();
        else if (behaviour != Behaviour.UNSAFE)
        {
            enter_delay_mode ();
            add_delayed_setting (key, null);
        }
        else
            ((DConfKey) key).erase ();
    }

    public bool key_has_planned_change (Key key)
    {
        if (key is GSettingsKey)
            return gsettings_keys_awaiting_hashtable.contains ((GSettingsKey) key);
        return dconf_keys_awaiting_hashtable.contains ((DConfKey) key);
    }

    public Variant? get_key_planned_value (Key key)
    {
        if (key is GSettingsKey)
            return gsettings_keys_awaiting_hashtable.lookup ((GSettingsKey) key);
        return dconf_keys_awaiting_hashtable.lookup ((DConfKey) key);
    }

}
