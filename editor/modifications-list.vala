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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/modifications-list.ui")]
private class ModificationsList : Overlay
{
    [GtkChild] private ScrolledWindow   scrolled;
    [GtkChild] private ListBox          delayed_settings_listbox;
/*    [GtkChild] private Box              edit_mode_box;

    [GtkChild] private ModelButton enter_edit_mode_button;
    [GtkChild] private ModelButton leave_edit_mode_button;
    public string edit_mode_action_prefix
    {
        construct
        {
            // TODO sanitize "value"
            enter_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(true)");
            leave_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(false)");
        }
    } */

    public bool needs_shadows
    {
        construct
        {
            if (value)
                scrolled.shadow_type = ShadowType.ETCHED_IN;
            else
                scrolled.shadow_type = ShadowType.NONE;
        }
    }

    [GtkChild] private RegistryPlaceholder placeholder;
    public bool big_placeholder { internal construct { placeholder.big = value; }}

    construct
    {
        delayed_settings_listbox.set_header_func (delayed_setting_row_update_header);
    }

    private static void delayed_setting_row_update_header (ListBoxRow row, ListBoxRow? before)
    {
        string row_key_name = ((DelayedSettingView) row.get_child ()).full_name;
        bool add_location_header = false;
        if (before == null)
            add_location_header = true;
        else
        {
            string before_key_name = ((DelayedSettingView) ((!) before).get_child ()).full_name;

            if (ModelUtils.get_parent_path (row_key_name) != ModelUtils.get_parent_path (before_key_name))
                add_location_header = true;
        }

        if (add_location_header)
        {
            Grid location_header = new Grid ();
            location_header.show ();
            location_header.orientation = Orientation.VERTICAL;

            Label location_header_label = new Label (ModelUtils.get_parent_path (row_key_name));
            location_header_label.show ();
            location_header_label.hexpand = true;
            location_header_label.halign = Align.START;

            StyleContext context = location_header_label.get_style_context ();
            context.add_class ("dim-label");
            context.add_class ("bold-label");
            context.add_class ("list-row-header");

            location_header.add (location_header_label);

            Separator separator_header = new Separator (Orientation.HORIZONTAL);
            separator_header.show ();
            location_header.add (separator_header);

            row.set_header (location_header);
        }
        else
        {
            Separator separator_header = new Separator (Orientation.HORIZONTAL);
            separator_header.show ();
            row.set_header (separator_header);
        }
    }

    /*\
    * * Modifications list public functions
    \*/

    internal bool dismiss_selected_modification (ModificationsHandler modifications_handler)
    {
        ListBoxRow? selected_row = delayed_settings_listbox.get_selected_row ();
        if (selected_row == null)
            return false;

        modifications_handler.dismiss_change (((DelayedSettingView) (!) ((!) selected_row).get_child ()).full_name);
        return true;
    }

    internal void bind_model (GLib.ListStore modifications, ListBoxCreateWidgetFunc delayed_setting_row_create)
    {
        delayed_settings_listbox.bind_model (modifications, delayed_setting_row_create);
        select_first_row (delayed_settings_listbox);
    }
    private static inline void select_first_row (ListBox delayed_settings_listbox)
    {
        ListBoxRow? first_row = delayed_settings_listbox.get_row_at_index (0);
        if (first_row != null)
            delayed_settings_listbox.select_row ((!) first_row);
    }

    /*\
    * * Updating values; TODO only works for watched keys...
    \*/

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        delayed_settings_listbox.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name && row.context_id == context_id)
                    row.update_gsettings_key_current_value (key_value, is_key_default);
            });
    }

    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        delayed_settings_listbox.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name)
                    row.update_dconf_key_current_value (key_value_or_null);
            });
    }
}
