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

public enum Behaviour {
    UNSAFE,
    SAFE,
    ALWAYS_CONFIRM_IMPLICIT,
    ALWAYS_CONFIRM_EXPLICIT,
    ALWAYS_DELAY
}
public enum ModificationsMode {
    NONE,
    TEMPORARY,
    DELAYED
}

class ModificationsHandler : Object
{
    public ModificationsMode mode { get; set; default=ModificationsMode.NONE; }

    private HashTable<string, Variant?> keys_awaiting_hashtable = new HashTable<string, Variant?> (str_hash, str_equal);

    public uint dconf_changes_count
    {
        get
        {
            uint count = 0;
            keys_awaiting_hashtable.@foreach ((key_path, planned_value) => {
                    Key? key = model.get_key (key_path);
                    if (key != null && (!) key is DConfKey)
                        count++;
                });
            return count;
        }
    }
    public uint gsettings_changes_count
    {
        get
        {
            uint count = 0;
            keys_awaiting_hashtable.@foreach ((key_path, planned_value) => {
                    Key? key = model.get_key (key_path);
                    if (key != null && (!) key is GSettingsKey)
                        count++;
                });
            return count;
        }
    }

    public SettingsModel model { get; construct; }

    public signal void leave_delay_mode ();
    public signal void delayed_changes_changed ();

    public Behaviour behaviour { get; set; }

    public ModificationsHandler (SettingsModel model)
    {
        Object (model: model);
    }

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

    public void add_delayed_setting (string key_path, Variant? new_value)
    {
        keys_awaiting_hashtable.insert (key_path, new_value);

        mode = get_current_delay_mode () ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        delayed_changes_changed ();
    }

    public void dismiss_change (string key_path)
    {
        if (mode == ModificationsMode.NONE)
            mode = behaviour == Behaviour.ALWAYS_DELAY ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        keys_awaiting_hashtable.remove (key_path);

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

        model.apply_key_value_changes (keys_awaiting_hashtable);
        keys_awaiting_hashtable.remove_all ();

        delayed_changes_changed ();
        leave_delay_mode ();
    }

    public void dismiss_delayed_settings ()
    {
        mode = ModificationsMode.NONE;

        keys_awaiting_hashtable.remove_all ();

        delayed_changes_changed ();
        leave_delay_mode ();
    }

    public Variant get_key_custom_value (Key key)
    {
        bool planned_change = key_has_planned_change (key.full_name);
        Variant? planned_value = get_key_planned_value (key.full_name);
        return planned_change && (planned_value != null) ? (!) planned_value : model.get_key_value (key);
    }

    public bool key_value_is_default (GSettingsKey key) // doesn't make sense for DConfKey?
    {
        bool planned_change = key_has_planned_change (key.full_name);
        Variant? planned_value = get_key_planned_value (key.full_name);
        return planned_change ? planned_value == null : model.is_key_default (key);
    }

    public void set_dconf_key_value (string full_name, Variant key_value)
    {
        model.set_dconf_key_value (full_name, key_value);
    }

    public void set_gsettings_key_value (string full_name, string schema_id, Variant key_value)
    {
        model.set_gsettings_key_value (full_name, schema_id, key_value);
    }

    public void erase_dconf_key (string full_name)
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null);
        else if (behaviour != Behaviour.UNSAFE)
        {
            mode = ModificationsMode.DELAYED;   // call only once delayed_changes_changed()
            add_delayed_setting (full_name, null);
        }
        else
            model.erase_key (full_name);
    }

    public void set_to_default (string full_name, string schema_id)
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null);
        else
            model.set_key_to_default (full_name, schema_id);
    }

    public bool key_has_planned_change (string key_path)
    {
        if (keys_awaiting_hashtable.contains (key_path))
            return true;

        bool has_planned_changed = false;
        keys_awaiting_hashtable.@foreach ((key_awaiting, planned_value) => {
                if (key_path == key_awaiting)
                    has_planned_changed = true;
            });
        return has_planned_changed;
    }

    public Variant? get_key_planned_value (string key_path)
    {
        if (keys_awaiting_hashtable.contains (key_path))
            return keys_awaiting_hashtable.lookup (key_path);

        Variant? planned_changed = null;
        keys_awaiting_hashtable.@foreach ((key_awaiting, planned_value) => {
                if (key_path == key_awaiting)
                    planned_changed = planned_value;
            });
        return planned_changed;
    }

    public ListStore get_delayed_settings ()
    {
        ListStore delayed_settings_list = new ListStore (typeof (Key));
        keys_awaiting_hashtable.@foreach ((key_path, planned_value) => {
                Key? key = model.get_key (key_path);
                if (key != null)    // TODO better
                    delayed_settings_list.append ((!) key);
            });
        return delayed_settings_list;
    }
}
