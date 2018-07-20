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

    protected bool search_mode { private get; set; }
    protected string? current_path_if_search_mode = null;  // TODO only used in search mode

    protected GLib.ListStore list_model = new GLib.ListStore (typeof (SimpleSettingObject));

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    public ModificationsHandler modifications_handler { protected get; set; }

    private bool _small_keys_list_rows;
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
            return ((SimpleSettingObject) list_model.get_object (position)).full_name;
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
            SimpleSettingObject object = (SimpleSettingObject) list_model.get_object (position);
            if (object.full_name == selected)
            {
                if (!SettingsModel.is_key_path (object.full_name)
                 || object.context == context)
                    return (int) position;
                fallback = position;
            }
            position++;
        }
        return (int) fallback; // selected row may have been removed or context could be ""
    }

    private void set_delayed_icon (KeyListBoxRow row)
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
        if (row.context == ".folder")
            return row.full_name;
        return modifications_handler.model.get_key_copy_text (row.full_name, row.context);
    }
    private Variant get_copy_text_variant (ClickableListBoxRow row)
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

    public bool up_or_down_pressed (bool is_down)
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
            {
                if (search_mode)
                {
                    Container list_box = (Container) ((!) selected_row).get_parent ();
                    scroll_to_row ((!) row, list_box.get_focus_child () != null);
                }
                else
                    scroll_to_row ((!) row, true);
            }
            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }

    /*\
    * * Row creation
    \*/

    protected Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SimpleSettingObject setting_object = (SimpleSettingObject) item;
        string full_name = setting_object.full_name;

        if (search_mode && current_path_if_search_mode == null)
            assert_not_reached ();
        bool search_mode_non_local_result = search_mode && SettingsModel.get_parent_path (full_name) != (!) current_path_if_search_mode;

        if (!SettingsModel.is_key_path (full_name))
        {
            row = new FolderListBoxRow (setting_object.name, full_name, search_mode_non_local_result);
        }
        else
        {
            SettingsModel model = modifications_handler.model;

            Variant? properties = model.get_key_properties (setting_object.full_name, setting_object.context);
            if (properties == null) // key doesn't exist
                assert_not_reached ();

            bool has_schema;
            unowned Variant [] dict_container;
            ((!) properties).get ("(ba{ss})", out has_schema, out dict_container);
            Variant dict = dict_container [0];

            string type_code;       if (!dict.lookup ("type-code",  "s", out type_code))    assert_not_reached ();
            string key_name;        if (!dict.lookup ("key-name",   "s", out key_name))     assert_not_reached ();

            if (has_schema)
            {
                string summary;     if (!dict.lookup ("summary",    "s", out summary))      assert_not_reached ();
                bool italic_summary;
                if (summary == "")
                {
                    summary = _("No summary provided");
                    italic_summary = true;
                }
                else
                    italic_summary = false;

                row = new KeyListBoxRow (type_code,
                                         setting_object.context,
                                         summary,
                                         italic_summary,
                                         modifications_handler.get_current_delay_mode (),
                                         key_name,
                                         full_name,
                                         search_mode_non_local_result);

                bool warning_conflicting_key;
                bool error_hard_conflicting_key;
                model.has_conflicting_keys (full_name, out warning_conflicting_key, out error_hard_conflicting_key);

                if (warning_conflicting_key)
                {
                    if (error_hard_conflicting_key)
                    {
                        row.get_style_context ().add_class ("hard-conflict");
                        ((KeyListBoxRow) row).update_label (_("conflicting keys"), true);
                        if (type_code == "b")
                            ((KeyListBoxRow) row).use_switch (false);
                    }
                    else
                        row.get_style_context ().add_class ("conflict");
                }
            }
            else
            {
                row = new KeyListBoxRow (type_code,
                                         ".dconf",
                                         _("No Schema Found"),
                                         true,
                                         modifications_handler.get_current_delay_mode (),
                                         key_name,
                                         full_name,
                                         search_mode_non_local_result);
            }

            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => set_delayed_icon (key_row));
            set_delayed_icon (key_row);
            row.destroy.connect (() => {
                    modifications_handler.disconnect (delayed_modifications_changed_handler);
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
            wrapper.set_action_target ("(ss)", full_name, setting_object.context);
        }

        return wrapper;
    }

    private void update_gsettings_row (KeyListBoxRow row, string type_string, Variant key_value, bool is_key_default, bool error_hard_conflicting_key)
    {
        if (error_hard_conflicting_key)
            return;

        if (type_string == "b")
        {
            bool key_value_boolean = key_value.get_boolean ();
            Variant switch_variant = new Variant ("(ssbb)", row.full_name, row.context, !key_value_boolean, key_value_boolean ? is_key_default : !is_key_default);
            row.update_switch (key_value_boolean, "bro.toggle-gsettings-key-switch(" + switch_variant.print (false) + ")");
        }

        StyleContext css_context = row.get_style_context ();
        if (is_key_default)
            css_context.remove_class ("edited");
        else
            css_context.add_class ("edited");
        row.update_label (Key.cool_text_value_from_variant (key_value, type_string), false);
    }

    private void update_dconf_row (KeyListBoxRow row, string type_string, Variant? key_value)
    {
        if (key_value == null)
        {
            row.update_label (_("Key erased."), true);
            if (type_string == "b")
                row.use_switch (false);
        }
        else
        {
            if (type_string == "b")
            {
                bool key_value_boolean = ((!) key_value).get_boolean ();
                Variant switch_variant = new Variant ("(sb)", row.full_name, !key_value_boolean);
                row.update_switch (key_value_boolean, "bro.toggle-dconf-key-switch(" + switch_variant.print (false) + ")");
                row.use_switch (true);
            }
            row.update_label (Key.cool_text_value_from_variant ((!) key_value, type_string), false);
        }
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        Container list_box = (Container) list_box_row.get_parent ();
        key_list_box.select_row (list_box_row);

        if (!search_mode)
            list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            if (search_mode && list_box.get_focus_child () != null)
                list_box_row.grab_focus ();

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
        else if (search_mode)
            list_box_row.grab_focus ();

        return false;
    }

    public void gkey_value_push (string full_name, string schema_id, Variant key_value, bool is_key_default)
    {
        KeyListBoxRow? row = get_row_for_key (full_name, schema_id);
        if (row == null)    // TODO make method only called when necessary 1/2
            return;

        bool warning_conflicting_key;
        bool error_hard_conflicting_key;
        modifications_handler.model.has_conflicting_keys (full_name, out warning_conflicting_key, out error_hard_conflicting_key);

        update_gsettings_row ((!) row,
                              ((!) row).type_string,
                              key_value,
                              is_key_default,
                              error_hard_conflicting_key);
        ((!) row).destroy_popover ();
    }

    public void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        KeyListBoxRow? row = get_row_for_key (full_name, ".dconf");
        if (row == null)    // TODO make method only called when necessary 2/2
            return;

        update_dconf_row ((!) row, ((!) row).type_string, key_value_or_null);
        ((!) row).destroy_popover ();
    }

    private KeyListBoxRow? get_row_for_key (string full_name, string context)
    {
        KeyListBoxRow? key_row_child = null;
        key_list_box.foreach ((row) => {
                Widget? row_child = ((ListBoxRow) row).get_child ();
                if (row_child == null)
                    assert_not_reached ();
                if ((!) row_child is KeyListBoxRow
                 && ((KeyListBoxRow) (!) row_child).full_name == full_name
                 && ((KeyListBoxRow) (!) row_child).context == context)
                    key_row_child = (KeyListBoxRow) (!) row_child;
            });
        return key_row_child;
    }

    /*\
    * * Right click popover creation
    \*/

    private void show_right_click_popover (ClickableListBoxRow row, int? event_x)
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

        switch (row.context)
        {
            case ".folder": return generate_folder_popover ((FolderListBoxRow) row);
            case ".dconf" : return generate_dconf_popover ((KeyListBoxRow) row);
            default       : return generate_gsettings_popover ((KeyListBoxRow) row);
        }
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

    private bool generate_gsettings_popover (KeyListBoxRow row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
        string full_name = row.full_name;
        Key? _key = model.get_key (full_name, row.context);   // racy...
        if (_key == null)
            assert_not_reached ();
        GSettingsKey key = (GSettingsKey) (!) _key;
        Variant variant_s = new Variant.string (full_name);
        Variant variant_ss = new Variant ("(ss)", full_name, row.context);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant_s.print (false) + ")");
            popover.new_section ();
        }

        bool error_hard_conflicting_key;
        bool warning_conflicting_key;
        model.has_conflicting_keys (full_name, out warning_conflicting_key, out error_hard_conflicting_key);
        if (error_hard_conflicting_key)
        {
            popover.new_gaction ("detail", "ui.open-object(" + variant_ss.print (false) + ")");
            popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");
            return true; // anything else is value-related, so we are done
        }

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);

        popover.new_gaction ("customize", "ui.open-object(" + variant_ss.print (false) + ")");
        popover.new_gaction ("copy", "app.copy(" + get_copy_text_variant (row).print (false) + ")");

        string type_string = row.type_string;
        if (type_string == "b" || type_string == "<enum>" || type_string == "mb"
            || (
                (type_string == "y" || type_string == "q" || type_string == "u" || type_string == "t")
                && (key.range_type == "range")
                && (Key.get_variant_as_uint64 (key.range_content.get_child_value (1)) - Key.get_variant_as_uint64 (key.range_content.get_child_value (0)) < 13)
               )
            || (
                (type_string == "n" || type_string == "i" || type_string == "h" || type_string == "x")
                && (key.range_type == "range")
                && (Key.get_variant_as_int64 (key.range_content.get_child_value (1)) - Key.get_variant_as_int64 (key.range_content.get_child_value (0)) < 13)
               )
            || type_string == "()")
        {
            popover.new_section ();
            GLib.Action action;
            if (planned_change)
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string,
                                                      modifications_handler.get_key_planned_value (full_name), key.range_content);
            else if (model.is_key_default (key))
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string,
                                                      null, key.range_content);
            else
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string,
                                                      model.get_key_value (key), key.range_content);

            popover.change_dismissed.connect (() => {
                    row.destroy_popover ();
                    row.change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    row.hide_right_click_popover ();
                    Variant key_value = model.get_key_value (key);
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (key_value.get_type_string ()), gvariant)));
                    row.set_key_value (row.context, gvariant);
                });
        }
        else if (!delayed_apply_menu && !planned_change && type_string == "<flags>")
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

            popover.value_changed.connect ((gvariant) => row.set_key_value (row.context, gvariant));
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

    private bool generate_dconf_popover (KeyListBoxRow row)
    {
        if (row.nullable_popover == null)
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
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
            Variant key_value = model.get_dconf_key_value (row.full_name);
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
