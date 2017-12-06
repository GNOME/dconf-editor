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

class ModificationsHandler : Object
{
    public ModificationsMode mode { get; set; default=ModificationsMode.NONE; }

    private DConf.Client dconf_client = new DConf.Client ();

    private HashTable<string, DConfKey>         dconf_keys_awaiting_hashtable = new HashTable<string, DConfKey>     (str_hash, str_equal);
    private HashTable<string, GSettingsKey> gsettings_keys_awaiting_hashtable = new HashTable<string, GSettingsKey> (str_hash, str_equal);
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
        key.planned_change = true;
        key.planned_value = new_value;

        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.insert (key.descriptor, (GSettingsKey) key);
        else
            dconf_keys_awaiting_hashtable.insert (key.descriptor, (DConfKey) key);

        mode = get_current_delay_mode () ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        delayed_changes_changed ();
    }

    public void dismiss_change (Key key)
    {
        if (mode == ModificationsMode.NONE)
            mode = behaviour == Behaviour.ALWAYS_DELAY ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        key.planned_change = false;
        key.planned_value = null;

        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.remove (key.descriptor);
        else
            dconf_keys_awaiting_hashtable.remove (key.descriptor);

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
        gsettings_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                string settings_descriptor = descriptor [0:descriptor.last_index_of_char (' ')]; // strip the key name
                GLib.Settings? settings = delayed_settings_hashtable.lookup (settings_descriptor);
                if (settings == null)
                {
                    settings = key.settings;
                    ((!) settings).delay ();
                    delayed_settings_hashtable.insert (settings_descriptor, (!) settings);
                }

                if (key.planned_value == null)
                {
                    ((!) settings).reset (key.name);
                    if (((!) settings).backend.get_type ().name () == "GDelayedSettingsBackend") // Workaround for https://bugzilla.gnome.org/show_bug.cgi?id=791290
                        ((!) settings).backend.changed (key.full_name, null);
                    // Alternative workaround: key.value_changed ();
                }
                else
                    ((!) settings).set_value (key.name, (!) key.planned_value);
                key.planned_change = false;

                return true;
            });

        delayed_settings_hashtable.foreach_remove ((key_descriptor, schema_settings) => { schema_settings.apply (); return true; });

        /* DConf stuff */

        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        dconf_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                dconf_changeset.set (key.full_name, key.planned_value);

                if (key.planned_value == null)
                    key.is_ghost = true;
                key.planned_change = false;

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

        /* GSettings stuff */

        gsettings_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                key.planned_change = false;
                return true;
            });

        /* DConf stuff */

        dconf_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                key.planned_change = false;
                return true;
            });

        /* reload notably key_editor_child */

        delayed_changes_changed ();
        reload ();
    }

    public Variant get_key_custom_value (Key key)
    {
        return key.planned_change && (key.planned_value != null) ? (!) key.planned_value : key.value;
    }

    public bool key_value_is_default (GSettingsKey key) // doesn't make sense for DConfKey?
    {
        return key.planned_change ? key.planned_value == null : key.is_default;
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
        return key.planned_change;
    }

    public Variant? get_key_planned_value (Key key)
    {
        return key.planned_value;
    }

}
