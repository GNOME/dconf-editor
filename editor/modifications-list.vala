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

private class ModificationsList : OverlayedList
{
    construct
    {
        get_style_context ().add_class ("delayed-list");

        placeholder_icon = "document-open-recent-symbolic";
        placeholder_text = _("Delayed mode is on\nbut\nno pending changes");
        add_placeholder ();

        first_mode_name = _("Rule all");
        second_mode_name = _("Select");

        main_list_box.set_header_func (delayed_setting_row_update_header);
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
        ListBoxRow? selected_row = main_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        modifications_handler.dismiss_change (((DelayedSettingView) (!) ((!) selected_row).get_child ()).full_name);
        return true;
    }

    internal void bind_model (GLib.ListStore modifications, ListBoxCreateWidgetFunc delayed_setting_row_create)
    {
        main_list_box.bind_model (modifications, delayed_setting_row_create);
        select_first_row (main_list_box);
    }
    private static inline void select_first_row (ListBox main_list_box)
    {
        ListBoxRow? first_row = main_list_box.get_row_at_index (0);
        if (first_row != null)
            main_list_box.select_row ((!) first_row);
    }

    internal string? get_copy_text ()
    {
        List<weak ListBoxRow> selected_rows = main_list_box.get_selected_rows ();
        if (selected_rows.length () != 1)
            return null;
        ListBoxRow row = selected_rows.nth_data (0);
        Widget? child = row.get_child ();
        if (child == null || !((!) child is DelayedSettingView))
            assert_not_reached ();
        return ((DelayedSettingView) (!) child).full_name;  // FIXME row should keep focus
    }

    /*\
    * * Updating values; TODO only works for watched keys...
    \*/

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        main_list_box.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name && row.context_id == context_id)
                    row.update_gsettings_key_current_value (key_value, is_key_default);
            });
    }

    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        main_list_box.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name)
                    row.update_dconf_key_current_value (key_value_or_null);
            });
    }
}
