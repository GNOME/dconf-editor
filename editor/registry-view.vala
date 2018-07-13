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

class RegistryView : RegistryList
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

    public void set_key_model (GLib.ListStore key_model)
    {
        list_model = key_model;
        key_list_box.bind_model (list_model, new_list_box_row);
    }

    public bool check_reload (SettingObject [] fresh_key_model)
    {
        if (list_model.get_n_items () != fresh_key_model.length)
            return true;
        bool [] skip = new bool [fresh_key_model.length];
        for (uint i = 0; i < fresh_key_model.length; i++)
            skip [i] = false;
        for (uint i = 0; i < list_model.get_n_items (); i++)
        {
            SettingObject? setting_object = (SettingObject) list_model.get_item (i);
            if (setting_object == null)
                assert_not_reached ();
            bool found = false;
            for (uint j = 0; j < fresh_key_model.length; j++)
            {
                if (skip [j] == true)
                    continue;
                SettingObject fresh_setting_object = fresh_key_model [j];
                if (((!) setting_object).full_name != fresh_setting_object.full_name)
                    continue;
                // TODO compare other visible info (i.e. key type_string or summary [if not directories])
                if (SettingsModel.is_key_path (fresh_setting_object.full_name))
                {
                    if (((Key) (!) setting_object).type_string != ((Key) fresh_setting_object).type_string)
                        continue;
                }
                found = true;
                skip [j] = true;
                break;
            }
            if (!found)
                return true;
        }
        for (uint i = 0; i < fresh_key_model.length; i++)
            if (skip [i] == false)
                return true;
        return false;
    }

    public override void select_first_row ()
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
        string? label_text = null;
        if (((ClickableListBoxRow) row.get_child ()).context == ".dconf")
        {
            if (before == null || !(((ClickableListBoxRow) ((!) before).get_child ()).context == ".dconf"))
                label_text = _("Keys not defined by a schema");
        }
        else if (((ClickableListBoxRow) row.get_child ()).context != ".folder")
        {
            string schema_id = ((ClickableListBoxRow) row.get_child ()).context;
            if (before == null || ((ClickableListBoxRow) ((!) before).get_child ()).context != schema_id)
                label_text = schema_id;
        }

        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }

    public override bool up_or_down_pressed (bool is_down)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        uint n_items = list_model.get_n_items ();

        if (selected_row != null)
        {
            Widget? row_content = ((!) selected_row).get_child ();
            if (row_content != null && ((ClickableListBoxRow) (!) row_content).right_click_popover_visible ())
                return false;

            int position = ((!) selected_row).get_index ();
            ListBoxRow? row = null;
            if (!is_down && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_down && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
                scroll_to_row ((!) row, true);

            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }
}
