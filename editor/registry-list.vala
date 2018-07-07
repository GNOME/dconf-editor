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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-view.ui")]
private abstract class RegistryList : Grid, BrowsableView
{
    [GtkChild] protected ListBox key_list_box;
    [GtkChild] protected RegistryPlaceholder placeholder;
    [GtkChild] private ScrolledWindow scrolled;

    protected GLib.ListStore list_model = new GLib.ListStore (typeof (SettingObject));

    protected GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    public ModificationsHandler modifications_handler { protected get; set; }

    protected bool _small_keys_list_rows;
    public bool small_keys_list_rows
    {
        set
        {
            _small_keys_list_rows = value;
            key_list_box.foreach ((row) => {
                    Widget? row_child = ((ListBoxRow) row).get_child ();
                    if (row_child != null && (!) row_child is KeyListBoxRow)
                        ((KeyListBoxRow) (!) row_child).small_keys_list_rows = value;
                });
        }
    }

    protected void scroll_to_row (ListBoxRow row, bool grab_focus)
    {
        key_list_box.select_row (row);
        if (grab_focus)
            row.grab_focus ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }

    public void invalidate_popovers ()
    {
        uint position = 0;
        ClickableListBoxRow? row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (0);
        while (row != null)
        {
            ((!) row).destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
    }

    public void hide_or_show_toggles (bool show)
    {
        key_list_box.@foreach ((row_wrapper) => {
                ClickableListBoxRow? row = (ClickableListBoxRow) ((ListBoxRowWrapper) row_wrapper).get_child ();
                if (row == null)
                    assert_not_reached ();
                if ((!) row is KeyListBoxRow && ((KeyListBoxRow) (!) row).type_string == "b")
                    ((KeyListBoxRow) row).delay_mode = !show;
            });
    }

    public string get_selected_row_name ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            return ((SettingObject) list_model.get_object (position)).full_name;
        }
        else
            return "";
    }

    public abstract void select_first_row ();

    public void select_row_named (string selected, string context, bool grab_focus)
    {
        check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (selected, context));
        if (row != null)
            scroll_to_row ((!) row, grab_focus);
    }
    private int get_row_position (string selected, string context)
    {
        uint position = 0;
        uint fallback = 0;
        while (position < list_model.get_n_items ())
        {
            SettingObject object = (SettingObject) list_model.get_object (position);
            if (object.full_name == selected)
            {
                if (!SettingsModel.is_key_path (object.full_name)
                 || context == ".dconf" && object is DConfKey // theorical?
                 || object is GSettingsKey && ((GSettingsKey) object).schema_id == context)
                    return (int) position;
                fallback = position;
            }
            position++;
        }
        return (int) fallback; // selected row may have been removed or context could be ""
    }

    public abstract bool up_or_down_pressed (bool is_down);

    protected void set_delayed_icon (KeyListBoxRow row)
    {
        SettingsModel model = modifications_handler.model;
        StyleContext context = row.get_style_context ();
        if (modifications_handler.key_has_planned_change (row.full_name))
        {
            context.add_class ("delayed");
            if (!model.key_has_schema (row.full_name))
            {
                if (modifications_handler.get_key_planned_value (row.full_name) == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
        {
            context.remove_class ("delayed");
            if (!model.key_has_schema (row.full_name) && model.is_key_ghost (row.full_name))
                context.add_class ("erase");
            else
                context.remove_class ("erase");
        }
    }

    /*\
    * * Keyboard calls
    \*/

    public bool show_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

        if (row.right_click_popover_visible ())
            row.hide_right_click_popover ();
        else
        {
            row.show_right_click_popover (get_copy_text_variant (row), modifications_handler);
            rows_possibly_with_popover.append (row);
        }
        return true;
    }

    public string? get_copy_text () // can compile with "private", but is public 1/2
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;

        return _get_copy_text ((ClickableListBoxRow) ((!) selected_row).get_child ());
    }
    private string _get_copy_text (ClickableListBoxRow row)
    {
        if (row is FolderListBoxRow)
            return row.full_name;
        // (row is KeyListBoxRow)
        SettingsModel model = modifications_handler.model;
        if (row is KeyListBoxRowEditable)
            return model.get_key_copy_text (row.full_name, ((KeyListBoxRowEditable) row).schema_id);
        // (row is KeyListBoxRowEditableNoSchema)
        return model.get_key_copy_text (row.full_name, ".dconf");
    }
    protected Variant get_copy_text_variant (ClickableListBoxRow row)
    {
        return new Variant.string (_get_copy_text (row));
    }

    public void toggle_boolean_key ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            return;

        ((KeyListBoxRow) ((!) selected_row).get_child ()).toggle_boolean_key ();
    }

    public void set_selected_to_default ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            assert_not_reached ();

        ((KeyListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).destroy_popover ();
    }
}
