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
    [CCode (notify = false)] internal ModificationsMode mode { internal get; private set; default = ModificationsMode.NONE; }

    private HashTable<string, Variant?> keys_awaiting_hashtable = new HashTable<string, Variant?> (str_hash, str_equal);

    private GenericSet<string> dconf_changes_set = new GenericSet<string> (str_hash, str_equal);
    private HashTable<string, uint16> gsettings_changes_set = new HashTable<string, uint16> (str_hash, str_equal);
    [CCode (notify = false)] internal uint dconf_changes_count     { internal get { return dconf_changes_set.length; }}
    [CCode (notify = false)] internal uint gsettings_changes_count { internal get { return gsettings_changes_set.length; }}

    public SettingsModel model { internal get; internal construct; }

    internal signal void leave_delay_mode ();
    internal signal void delayed_changes_changed ();

    [CCode (notify = false)] internal Behaviour behaviour { internal get; internal set; }

    internal ModificationsHandler (SettingsModel model)
    {
        Object (model: model);
    }

    /*\
    * * Public calls
    \*/

    internal bool has_pending_changes ()
    {
        return dconf_changes_count + gsettings_changes_count != 0;
    }

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

    internal void add_delayed_setting (string key_path, Variant? new_value, uint16 context_id)
        requires (!ModelUtils.is_folder_context_id (context_id))
    {
        if (!keys_awaiting_hashtable.contains (key_path))
        {
            if (ModelUtils.is_dconf_context_id (context_id))
                dconf_changes_set.add (key_path);
            else
                gsettings_changes_set.insert (key_path, context_id);
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

    internal Variant get_key_custom_value (string full_name, uint16 context_id)
    {
        bool planned_change = key_has_planned_change (full_name);
        Variant? planned_value = get_key_planned_value (full_name);
        if (planned_change && (planned_value != null))
            return (!) planned_value;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) PropertyQuery.KEY_VALUE));
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

    internal void set_gsettings_key_value (string full_name, uint16 context_id, Variant key_value)
    {
        model.set_gsettings_key_value (full_name, context_id, key_value);
    }

    internal void erase_dconf_key (string full_name)
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null, ModelUtils.dconf_context_id);
        else if (behaviour != Behaviour.UNSAFE)
        {
            mode = ModificationsMode.DELAYED;   // call only once delayed_changes_changed()
            add_delayed_setting (full_name, null, ModelUtils.dconf_context_id);
        }
        else
            model.erase_key (full_name);
    }

    internal void set_to_default (string full_name, uint16 context_id)
        requires (!ModelUtils.is_folder_context_id (context_id))
        requires (!ModelUtils.is_dconf_context_id (context_id))
    {
        if (get_current_delay_mode ())
            add_delayed_setting (full_name, null, context_id);
        else
            model.set_key_to_default (full_name, context_id);
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
                        new SimpleSettingObject.from_full_name (ModelUtils.dconf_context_id,
                                                                key_path.slice (key_path.last_index_of_char ('/') + 1, key_path.length),
                                                                key_path));
                else if (gsettings_changes_set.contains (key_path))
                    delayed_settings_list.append (
                        new SimpleSettingObject.from_full_name (gsettings_changes_set.lookup (key_path),
                                                                key_path.slice (key_path.last_index_of_char ('/') + 1, key_path.length),
                                                                key_path));
                else
                    assert_not_reached ();
            });
        return delayed_settings_list;
    }
}
