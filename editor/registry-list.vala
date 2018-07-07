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
            show_right_click_popover (row, null);
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

    /*\
    * * Right click popover creation
    \*/

    protected void show_right_click_popover (ClickableListBoxRow row, int? event_x)
    {
        if (row.nullable_popover == null)
        {
            row.nullable_popover = new ContextPopover ();
            if (!generate_popover (row))    // done that way for rows without popovers, but that never happens in current design
            {
                ((!) row.nullable_popover).destroy ();  // TODO better, again
                row.nullable_popover = null;
                return;
            }

            ((!) row.nullable_popover).destroy.connect (() => { row.nullable_popover = null; });

            ((!) row.nullable_popover).set_relative_to (row);
            ((!) row.nullable_popover).position = PositionType.BOTTOM;     // TODO better
        }
        else if (((!) row.nullable_popover).visible)
            warning ("show_right_click_popover() called but popover is visible");   // TODO is called on multi-right-click or long Menu key press

        if (event_x == null)
            event_x = (int) (row.get_allocated_width () / 2.0);

        Gdk.Rectangle rect = { x:(!) event_x, y:row.get_allocated_height (), width:0, height:0 };
        ((!) row.nullable_popover).set_pointing_to (rect);
        ((!) row.nullable_popover).popup ();
    }

    private bool generate_popover (ClickableListBoxRow row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        if (row is FolderListBoxRow)
            return generate_folder_popover ((FolderListBoxRow) row);
        if (row is KeyListBoxRowEditable)
            return generate_gsettings_popover ((KeyListBoxRowEditable) row);
        if (row is KeyListBoxRowEditableNoSchema)
            return generate_dconf_popover ((KeyListBoxRowEditableNoSchema) row);
        assert_not_reached ();
    }

    private bool generate_folder_popover (FolderListBoxRow row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        ContextPopover popover = (!) row.nullable_popover;
        Variant variant = new Variant.string (row.full_name);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant.print (false) + ")");
            popover.new_section ();
        }

        popover.new_gaction ("open", "ui.open-folder(" + variant.print (false) + ")");
        popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");

        popover.new_section ();
        popover.new_gaction ("recursivereset", "ui.reset-recursive(" + variant.print (false) + ")");

        return true;
    }

    private bool generate_gsettings_popover (KeyListBoxRowEditable row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
        GSettingsKey key = row.key;
        Variant variant_s = new Variant.string (row.full_name);
        Variant variant_ss = new Variant ("(ss)", row.full_name, row.schema_id);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant_s.print (false) + ")");
            popover.new_section ();
        }

        if (key.error_hard_conflicting_key)
        {
            popover.new_gaction ("detail", "ui.open-object(" + variant_ss.print (false) + ")");
            popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");
            return true; // anything else is value-related, so we are done
        }

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (row.full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (row.full_name);

        popover.new_gaction ("customize", "ui.open-object(" + variant_ss.print (false) + ")");
        popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");

        if (row.type_string == "b" || row.type_string == "<enum>" || row.type_string == "mb"
            || (
                (row.type_string == "y" || row.type_string == "q" || row.type_string == "u" || row.type_string == "t")
                && (key.range_type == "range")
                && (Key.get_variant_as_uint64 (key.range_content.get_child_value (1)) - Key.get_variant_as_uint64 (key.range_content.get_child_value (0)) < 13)
               )
            || (
                (row.type_string == "n" || row.type_string == "i" || row.type_string == "h" || row.type_string == "x")
                && (key.range_type == "range")
                && (Key.get_variant_as_int64 (key.range_content.get_child_value (1)) - Key.get_variant_as_int64 (key.range_content.get_child_value (0)) < 13)
               )
            || row.type_string == "()")
        {
            popover.new_section ();
            GLib.Action action;
            if (planned_change)
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, row.type_string,
                                                      modifications_handler.get_key_planned_value (row.full_name), key.range_content);
            else if (model.is_key_default (key))
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, row.type_string,
                                                      null, key.range_content);
            else
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, row.type_string,
                                                      model.get_key_value (key), key.range_content);

            popover.change_dismissed.connect (() => {
                    row.destroy_popover ();
                    row.change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    row.hide_right_click_popover ();
                    Variant key_value = model.get_key_value (key);
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (key_value.get_type_string ()), gvariant)));
                    row.set_key_value (row.schema_id, gvariant);
                });
        }
        else if (!delayed_apply_menu && !planned_change && row.type_string == "<flags>")
        {
            popover.new_section ();

            if (!model.is_key_default (key))
                popover.new_gaction ("default2", "bro.set-to-default(" + variant_ss.print (false) + ")");

            string [] all_flags = key.range_content.get_strv ();
            popover.create_flags_list (key.settings.get_strv (row.key_name), all_flags);
            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                    string [] active_flags = modifications_handler.get_key_custom_value (key).get_strv ();
                    foreach (string flag in all_flags)
                        popover.update_flag_status (flag, flag in active_flags);
                });
            popover.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));

            popover.value_changed.connect ((gvariant) => row.set_key_value (row.schema_id, gvariant));
        }
        else if (planned_change)
        {
            popover.new_section ();
            popover.new_gaction ("dismiss", "ui.dismiss-change(" + variant_s.print (false) + ")");

            if (planned_value != null)
                popover.new_gaction ("default1", "bro.set-to-default(" + variant_ss.print (false) + ")");
        }
        else if (!model.is_key_default (key))
        {
            popover.new_section ();
            popover.new_gaction ("default1", "bro.set-to-default(" + variant_ss.print (false) + ")");
        }
        return true;
    }

    private bool generate_dconf_popover (KeyListBoxRowEditableNoSchema row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
        DConfKey key = row.key;
        Variant variant_s = new Variant.string (row.full_name);
        Variant variant_ss = new Variant ("(ss)", row.full_name, ".dconf");

        if (model.is_key_ghost (row.full_name))
        {
            popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");
            return true;
        }

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant_s.print (false) + ")");
            popover.new_section ();
        }

        popover.new_gaction ("customize", "ui.open-object(" + variant_ss.print (false) + ")");
        popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");

        bool planned_change = modifications_handler.key_has_planned_change (row.full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (row.full_name);

        if (row.type_string == "b" || row.type_string == "mb" || row.type_string == "()")
        {
            popover.new_section ();
            bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
            Variant key_value = model.get_key_value (key);
            GLib.Action action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, row.type_string,
                                                              planned_change ? planned_value : key_value, null);

            popover.change_dismissed.connect (() => {
                    row.destroy_popover ();
                    row.change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    row.hide_right_click_popover ();
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (row.type_string), gvariant)));
                    row.set_key_value ("", gvariant);
                });

            if (!delayed_apply_menu)
            {
                popover.new_section ();
                popover.new_gaction ("erase", "ui.erase(" + variant_s.print (false) + ")");
            }
        }
        else
        {
            if (planned_change)
            {
                popover.new_section ();
                popover.new_gaction (planned_value == null ? "unerase" : "dismiss", "ui.dismiss-change(" + variant_s.print (false) + ")");
            }

            if (!planned_change || planned_value != null) // not &&
            {
                popover.new_section ();
                popover.new_gaction ("erase", "ui.erase(" + variant_s.print (false) + ")");
            }
        }
        return true;
    }
}
