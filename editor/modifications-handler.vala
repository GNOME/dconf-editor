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

internal enum Behaviour {
    UNSAFE,
    SAFE,
    ALWAYS_CONFIRM_IMPLICIT,
    ALWAYS_CONFIRM_EXPLICIT,
    ALWAYS_DELAY
}
internal enum ModificationsMode {
    NONE,
    TEMPORARY,
    DELAYED
}

private class ModificationsHandler : Object
{
    internal ModificationsMode mode { get; set; default=ModificationsMode.NONE; }

    private HashTable<string, Variant?> keys_awaiting_hashtable = new HashTable<string, Variant?> (str_hash, str_equal);

    private GenericSet<string> dconf_changes_set = new GenericSet<string> (str_hash, str_equal);
    private HashTable<string, string> gsettings_changes_set = new HashTable<string, string> (str_hash, str_equal);
    internal uint dconf_changes_count { get { return dconf_changes_set.length; }}
    internal uint gsettings_changes_count { get { return gsettings_changes_set.length; }}

    public SettingsModel model { internal get; internal construct; }

    internal signal void leave_delay_mode ();
    internal signal void delayed_changes_changed ();

    internal Behaviour behaviour { get; set; }

    internal ModificationsHandler (SettingsModel model)
    {
        Object (model: model);
    }

    /*\
    * * Public calls
    \*/

    internal bool get_current_delay_mode ()
    {
        return mode == ModificationsMode.DELAYED || behaviour == Behaviour.ALWAYS_DELAY;
    }

    internal bool should_delay_apply (string type_string)
    {
        if (get_current_delay_mode () || behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            return true;
        if (behaviour == Behaviour.UNSAFE)
            return false;
        if (behaviour == Behaviour.SAFE)
            return type_string != "b" && type_string != "mb" && type_string != "<enum>" && type_string != "<flags>";
        assert_not_reached ();
    }

    internal void enter_delay_mode ()
    {
        mode = ModificationsMode.DELAYED;

        delayed_changes_changed ();
    }

    internal void add_delayed_setting (string key_path, Variant? new_value, bool has_schema, string schema_id_if_gsettings_key = "")
    {
        if (!keys_awaiting_hashtable.contains (key_path))
        {
            if (has_schema)
                gsettings_changes_set.insert (key_path, schema_id_if_gsettings_key);
            else
                dconf_changes_set.add (key_path);
            keys_awaiting_hashtable.insert (key_path, new_value);
        }
        else
            keys_awaiting_hashtable.replace (key_path, new_value);

        mode = get_current_delay_mode () ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        delayed_changes_changed ();
    }

    internal void dismiss_change (string key_path)
    {
        if (mode == ModificationsMode.NONE)
            mode = behaviour == Behaviour.ALWAYS_DELAY ? ModificationsMode.DELAYED : ModificationsMode.TEMPORARY;

        if (keys_awaiting_hashtable.remove (key_path))
        {
            if (!gsettings_changes_set.remove (key_path)
             && !dconf_changes_set.remove (key_path))
                assert_not_reached ();
        }
        // else...  // happens on the second edit with unparsable value in a KeyEditorChildDefault

        delayed_changes_changed ();
    }

    internal void path_changed ()
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

    internal void apply_delayed_settings ()
    {
        mode = ModificationsMode.NONE;

        model.apply_key_value_changes (keys_awaiting_hashtable);
        gsettings_changes_set.remove_all ();
        dconf_changes_set.remove_all ();
        keys_awaiting_hashtable.remove_all ();

        delayed_changes_changed ();
        leave_delay_mode ();
    }

    internal void dismiss_delayed_settings ()
    {
        mode = ModificationsMode.NONE;

        gsettings_changes_set.remove_all ();
        dconf_changes_set.remove_all ();
        keys_awaiting_hashtable.remove_all ();

        delayed_changes_changed ();
        leave_delay_mode ();
    }

    internal Variant get_key_custom_value (string full_name, string context)
    {
        bool planned_change = key_has_planned_change (full_name);
        Variant? planned_value = get_key_planned_value (full_name);
        if (planned_change && (planned_value != null))
            return (!) planned_value;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context, (uint16) PropertyQuery.KEY_VALUE));
        Variant key_value;
        if (!properties.lookup (PropertyQuery.KEY_VALUE, "v", out key_value))
            assert_not_reached ();
        properties.clear ();
        return key_value;
    }

    internal void set_dconf_key_value (string full_name, Variant key_value)
    {
        model.set_dconf_key_value (full_name, key_value);
    }

    internal void set_gsettings_key_value (string full_name, string schema_id, Variant key_value)
    {
        model.set_gsettings_key_value (full_name, schema_id, key_value);
    }

    internal void erase_dconf_key (string full_name)
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null, false);
        else if (behaviour != Behaviour.UNSAFE)
        {
            mode = ModificationsMode.DELAYED;   // call only once delayed_changes_changed()
            add_delayed_setting (full_name, null, false);
        }
        else
            model.erase_key (full_name);
    }

    internal void set_to_default (string full_name, string schema_id)
        requires (schema_id != ".dconf")
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null, true, schema_id);
        else
            model.set_key_to_default (full_name, schema_id);
    }

    internal bool key_has_planned_change (string key_path)
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

    internal Variant? get_key_planned_value (string key_path)
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

    internal ListStore get_delayed_settings ()
    {
        ListStore delayed_settings_list = new ListStore (typeof (SimpleSettingObject));
        keys_awaiting_hashtable.@foreach ((key_path, planned_value) => {
                if (dconf_changes_set.contains (key_path))
                    delayed_settings_list.append (
                        new SimpleSettingObject (".dconf",
                                                 key_path.slice (key_path.last_index_of_char ('/'), key_path.length),
                                                 key_path));
                else if (gsettings_changes_set.contains (key_path))
                    delayed_settings_list.append (
                        new SimpleSettingObject (gsettings_changes_set.lookup (key_path),
                                                 key_path.slice (key_path.last_index_of_char ('/'), key_path.length),
                                                 key_path));
                else
                    assert_not_reached ();
            });
        return delayed_settings_list;
    }
}
