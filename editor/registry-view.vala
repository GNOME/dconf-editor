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

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        string full_name = setting_object.full_name;

        if (!SettingsModel.is_key_path (setting_object.full_name))
        {
            row = new FolderListBoxRow (                    setting_object.name, full_name, false);
        }
        else
        {
            SettingsModel model = modifications_handler.model;
            Key key = (Key) setting_object;
            ulong key_value_changed_handler;
            if (setting_object is GSettingsKey)
            {
                GSettingsKey gkey = (GSettingsKey) key;

                bool italic_summary;
                string summary = gkey.summary;
                if (summary == "")
                {
                    summary = _("No summary provided"); // FIXME 1/2
                    italic_summary = true;
                }
                else
                    italic_summary = false;

                row = new KeyListBoxRow (key.type_string,
                                         gkey.schema_id,
                                         summary,
                                         italic_summary,
                                         modifications_handler.get_current_delay_mode (),
                                         setting_object.name,
                                         full_name,
                                         false);

                if (gkey.warning_conflicting_key)
                {
                    if (gkey.error_hard_conflicting_key)
                    {
                        row.get_style_context ().add_class ("hard-conflict");
                        ((KeyListBoxRow) row).update_label (_("conflicting keys"), true);
                        if (key.type_string == "b")
                            ((KeyListBoxRow) row).use_switch (false);
                    }
                    else
                        row.get_style_context ().add_class ("conflict");
                }

                key_value_changed_handler = key.value_changed.connect (() => {
                        update_gsettings_row ((KeyListBoxRow) row,
                                              key.type_string,
                                              model.get_key_value (key),
                                              model.is_key_default (gkey),
                                              gkey.error_hard_conflicting_key);
                        row.destroy_popover ();
                    });
                update_gsettings_row ((KeyListBoxRow) row,
                                      key.type_string,
                                      model.get_key_value (key),
                                      model.is_key_default (gkey),
                                      gkey.error_hard_conflicting_key);
            }
            else
            {
                row = new KeyListBoxRow (key.type_string,
                                         ".dconf",
                                         _("No Schema Found"),
                                         true,
                                         modifications_handler.get_current_delay_mode (),
                                         setting_object.name,
                                         full_name,
                                         false);

                key_value_changed_handler = key.value_changed.connect (() => {
                        if (model.is_key_ghost (full_name)) // fails with the ternary operator 1/4
                            update_dconf_row ((KeyListBoxRow) row, key.type_string, null);
                        else
                            update_dconf_row ((KeyListBoxRow) row, key.type_string, model.get_dconf_key_value (full_name));
                        row.destroy_popover ();
                    });
                if (model.is_key_ghost (full_name))         // fails with the ternary operator 2/4
                    update_dconf_row ((KeyListBoxRow) row, key.type_string, null);
                else
                    update_dconf_row ((KeyListBoxRow) row, key.type_string, model.get_dconf_key_value (full_name));
            }

            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => set_delayed_icon (key_row));
            set_delayed_icon (key_row);
            row.destroy.connect (() => {
                    modifications_handler.disconnect (delayed_modifications_changed_handler);
                    key.disconnect (key_value_changed_handler);
                });
        }

        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);
        row.destroy.connect (() => row.disconnect (button_press_event_handler));

        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();

        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (row.context == ".folder")
        {
            wrapper.get_style_context ().add_class ("folder-row");
            wrapper.action_name = "ui.open-folder";
            wrapper.set_action_target ("s", full_name);
        }
        else
        {
            wrapper.get_style_context ().add_class ("key-row");
            wrapper.action_name = "ui.open-object";
            string context = (setting_object is GSettingsKey) ? ((GSettingsKey) setting_object).schema_id : ".dconf";
            wrapper.set_action_target ("(ss)", full_name, context);
        }

        return wrapper;
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;

            int event_x = (int) event.x;
            if (event.window != widget.get_window ())   // boolean value switch
            {
                int widget_x, unused;
                event.window.get_position (out widget_x, out unused);
                event_x += widget_x;
            }

            show_right_click_popover (row, event_x);
            rows_possibly_with_popover.append (row);
        }

        return false;
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
