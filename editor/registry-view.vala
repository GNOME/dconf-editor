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

using Gtk;

private class RegistryView : RegistryList
{
    construct
    {
        search_mode = false;
        placeholder.label = _("No keys in this path");
        key_list_box.set_header_func (update_row_header);
    }

    /*\
    * * Updating
    \*/

    internal void set_key_model (GLib.ListStore key_model)
    {
        list_model = key_model;
        key_list_box.bind_model (list_model, new_list_box_row);
        modifications_handler.model.keys_value_push ();
    }

    internal bool check_reload (Variant? fresh_key_model)
    {
        if (fresh_key_model == null)
            return true;
        VariantIter iter = new VariantIter ((!) fresh_key_model);

        uint n_items = (uint) iter.n_children ();
        if (list_model.get_n_items () != n_items)
            return true;

        bool [] skip = new bool [n_items];
        for (uint i = 0; i < n_items; i++)
            skip [i] = false;
        uint16 context_id;
        string name;
        while (iter.next ("(qs)", out context_id, out name))
        {
            bool found = false;
            for (uint i = 0; i < list_model.get_n_items (); i++)
            {
                if (skip [i] == true)
                    continue;

                SimpleSettingObject? setting_object = (SimpleSettingObject) list_model.get_item (i);
                if (setting_object == null)
                    assert_not_reached ();

                if (((!) setting_object).context_id != context_id)
                    continue;
                if (((!) setting_object).name != name)
                    continue;

/* FIXME                // TODO compare other visible info (i.e. key type_string or summary [if not directories])
                if (SettingsModel.is_key_path (fresh_key_model [j,2]))
                {
                    if (((Key) (!) setting_object).type_string != ((Key) fresh_key_model [j]).type_string)
                        continue;
                } */
                found = true;
                skip [i] = true;
                break;
            }
            if (!found)
                return true;
        }
        for (uint i = 0; i < n_items; i++)
            if (skip [i] == false)
                return true;
        return false;
    }

    internal override void select_first_row ()
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            scroll_to_row ((!) row, true);
    }

    /*\
    * * Key ListBox
    \*/

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        _update_row_header (row, before, modifications_handler.model);
    }
    private static void _update_row_header (ListBoxRow row, ListBoxRow? before, SettingsModel model)
    {
        string? label_text = null;
        if (row.get_child () is KeyListBoxRow)  // no header for folders
        {
            uint16 context_id = ((ClickableListBoxRow) row.get_child ()).context_id;
            if (before == null || ((ClickableListBoxRow) ((!) before).get_child ()).context_id != context_id)
            {
                if (((KeyListBoxRow) row.get_child ()).has_schema)
                {
                    if (!model.key_exists (((KeyListBoxRow) ((!) row).get_child ()).full_name, context_id))
                        return; // FIXME that happens when reloading a now-empty folder

                    RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (((KeyListBoxRow) row.get_child ()).full_name, context_id, (uint16) PropertyQuery.SCHEMA_ID));
                    string schema_id;
                    if (!properties.lookup (PropertyQuery.SCHEMA_ID, "s", out schema_id))
                        assert_not_reached ();
                    label_text = schema_id;
                }
                else
                    label_text = _("Keys not defined by a schema");
            }
        }

        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }
}
