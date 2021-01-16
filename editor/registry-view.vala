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
    /* Translators: placeholder text of the keys list when there's nothing to display in a path (not used in current design) */
    [CCode (notify = false)] public override string placeholder_label { protected get { return _("No keys in this path"); }}

    construct
    {
        search_mode = false;
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
        uint n_items = list_model.get_n_items ();
        if (n_items == 0)
            assert_not_reached ();

        ListBoxRow? row;
        if (n_items == 2)
            row = key_list_box.get_row_at_index (1);
        else
            row = key_list_box.get_row_at_index (0);

        if (row == null)
            assert_not_reached ();
        key_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    /*\
    * * Key ListBox
    \*/

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        if (is_first_row (row.get_index (), before))
            return;
        update_row_header_with_context (row, (!) before, modifications_handler.model, /* local search header */ false);
    }
}
