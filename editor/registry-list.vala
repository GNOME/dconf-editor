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

    internal ModificationsHandler modifications_handler { protected get; set; }

    private bool _small_keys_list_rows;
    internal bool small_keys_list_rows
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

    internal void invalidate_popovers ()
    {
        _invalidate_popovers (rows_possibly_with_popover);
    }
    private static void _invalidate_popovers (GLib.ListStore rows_possibly_with_popover)
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

    internal void hide_or_show_toggles (bool show)
    {
        _hide_or_show_toggles (key_list_box, show);
    }
    private static void _hide_or_show_toggles (ListBox key_list_box, bool show)
    {
        key_list_box.@foreach ((row_wrapper) => {
                ClickableListBoxRow? row = (ClickableListBoxRow) ((ListBoxRowWrapper) row_wrapper).get_child ();
                if (row == null)
                    assert_not_reached ();
                if ((!) row is KeyListBoxRow && ((KeyListBoxRow) (!) row).type_string == "b")
                    ((KeyListBoxRow) row).delay_mode = !show;
            });
    }

    internal string get_selected_row_name ()
    {
        return _get_selected_row_name (key_list_box, list_model);
    }
    private static string _get_selected_row_name (ListBox key_list_box, GLib.ListStore list_model)
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return "";

        int position = ((!) selected_row).get_index ();
        return ((SimpleSettingObject) list_model.get_object (position)).full_name;
    }

    internal abstract void select_first_row ();

    internal void select_row_named (string selected, uint16 context_id, bool grab_focus)
    {
        check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (list_model, selected, context_id));
        if (row != null)
            scroll_to_row ((!) row, grab_focus);
    }
    private static int get_row_position (GLib.ListStore list_model, string selected, uint16 context_id)
    {
        uint position = 0;
        uint fallback = 0;
        uint n_items = list_model.get_n_items ();
        while (position < n_items)
        {
            SimpleSettingObject object = (SimpleSettingObject) list_model.get_object (position);
            if (object.full_name == selected)
            {
                if (ModelUtils.is_folder_context_id (object.context_id)
                 || object.context_id == context_id)
                    return (int) position;
                fallback = position;
            }
            position++;
        }
        return (int) fallback; // selected row may have been removed or context could be ""
    }

    private static void set_delayed_icon (ModificationsHandler _modifications_handler, KeyListBoxRow row)
    {
        SettingsModel model = _modifications_handler.model;
        StyleContext context = row.get_style_context ();
        if (_modifications_handler.key_has_planned_change (row.full_name))
        {
            context.add_class ("delayed");
            if (!model.key_has_schema (row.full_name))
            {
                if (_modifications_handler.get_key_planned_value (row.full_name) == null)
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

    internal bool toggle_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

        if (row.right_click_popover_visible ())
            row.hide_right_click_popover ();
        else
            show_right_click_popover (row, null);
        return true;
    }

    internal string? get_copy_text () // can compile with "private", but is public 1/2
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

        if (ModelUtils.is_folder_context_id (row.context_id))
            return _get_folder_copy_text (row);
        else
            return _get_key_copy_text (row, modifications_handler);
    }
    private static inline string _get_folder_copy_text (ClickableListBoxRow row)
    {
        return row.full_name;
    }
    private static inline string _get_key_copy_text (ClickableListBoxRow row, ModificationsHandler modifications_handler)
    {
        return modifications_handler.model.get_suggested_key_copy_text (row.full_name, row.context_id);
    }

    internal void toggle_boolean_key ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            return;

        ((KeyListBoxRow) ((!) selected_row).get_child ()).toggle_boolean_key ();
    }

    internal void set_selected_to_default ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            assert_not_reached ();

        ((KeyListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    internal void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).destroy_popover ();
    }

    internal bool up_or_down_pressed (bool is_down)
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
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
        uint16 context_id = setting_object.context_id;

        if (search_mode && current_path_if_search_mode == null)
            assert_not_reached ();
        bool search_mode_non_local_result = search_mode && ModelUtils.get_parent_path (full_name) != (!) current_path_if_search_mode;

        if (ModelUtils.is_folder_context_id (context_id))
        {
            row = new FolderListBoxRow (setting_object.name, full_name, search_mode_non_local_result);
        }
        else
        {
            Variant properties = modifications_handler.model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.HAS_SCHEMA & PropertyQuery.KEY_NAME & PropertyQuery.TYPE_CODE & PropertyQuery.SUMMARY & PropertyQuery.KEY_CONFLICT));

            KeyListBoxRow key_row = create_key_list_box_row (full_name, context_id, properties, modifications_handler.get_current_delay_mode (), search_mode_non_local_result);
            key_row.small_keys_list_rows = _small_keys_list_rows;

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect ((_modifications_handler) => set_delayed_icon (_modifications_handler, key_row));
            set_delayed_icon (modifications_handler, key_row);
            key_row.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));

            row = (ClickableListBoxRow) key_row;
        }

        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);
        row.destroy.connect (() => row.disconnect (button_press_event_handler));

        return put_row_in_wrapper (row);
    }

    private static KeyListBoxRow create_key_list_box_row (string full_name, uint16 context_id, Variant aqv, bool delay_mode, bool search_mode_non_local_result)
    {
        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (aqv);
        string key_name, type_code;
        bool has_schema;

        if (!properties.lookup (PropertyQuery.KEY_NAME,             "s",    out key_name))
            assert_not_reached ();

        if (!properties.lookup (PropertyQuery.TYPE_CODE,            "s",    out type_code))
            assert_not_reached ();

        if (!properties.lookup (PropertyQuery.HAS_SCHEMA,           "b",    out has_schema))
            assert_not_reached ();

        if (has_schema)
        {
            string summary = "";
            if (!properties.lookup (PropertyQuery.SUMMARY,          "s",    out summary))
                assert_not_reached ();

            bool italic_summary;
            if (summary == "")
            {
                summary = _("No summary provided");
                italic_summary = true;
            }
            else
                italic_summary = false;

            KeyListBoxRow row = new KeyListBoxRow (true,
                                                   type_code,
                                                   context_id,
                                                   summary,
                                                   italic_summary,
                                                   delay_mode,
                                                   key_name,
                                                   full_name,
                                                   search_mode_non_local_result);

            uint8 _key_conflict;
            if (!properties.lookup (PropertyQuery.KEY_CONFLICT,     "y",    out _key_conflict))
                assert_not_reached ();
            KeyConflict key_conflict = (KeyConflict) _key_conflict;

            if (key_conflict == KeyConflict.SOFT)
                row.get_style_context ().add_class ("conflict");
            else if (key_conflict == KeyConflict.HARD)
            {
                row.get_style_context ().add_class ("hard-conflict");
                row.update_label (_("conflicting keys"), true);
                if (type_code == "b")
                    row.use_switch (false);
            }

            properties.clear ();
            return row;
        }
        else
        {
            properties.clear ();
            return new KeyListBoxRow (false,
                                      type_code,
                                      ModelUtils.dconf_context_id,
                                      _("No Schema Found"),
                                      true,
                                      delay_mode,
                                      key_name,
                                      full_name,
                                      search_mode_non_local_result);
        }
    }

    private static ListBoxRowWrapper put_row_in_wrapper (ClickableListBoxRow row)
    {
        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();

        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (ModelUtils.is_folder_context_id (row.context_id))
        {
            wrapper.get_style_context ().add_class ("folder-row");
            wrapper.action_name = "ui.open-folder";
            wrapper.set_action_target ("s", row.full_name);
        }
        else
        {
            wrapper.get_style_context ().add_class ("key-row");
            wrapper.action_name = "ui.open-object";
            wrapper.set_action_target ("(sq)", row.full_name, row.context_id);
        }

        return wrapper;
    }

    private static void update_gsettings_row (KeyListBoxRow row, string type_string, Variant key_value, bool is_key_default, bool error_hard_conflicting_key)
    {
        if (error_hard_conflicting_key)
            return;

        if (type_string == "b")
        {
            bool key_value_boolean = key_value.get_boolean ();
            Variant switch_variant = new Variant ("(sqbb)", row.full_name, row.context_id, !key_value_boolean, key_value_boolean ? is_key_default : !is_key_default);
            row.update_switch (key_value_boolean, "bro.toggle-gsettings-key-switch(" + switch_variant.print (true) + ")");
        }

        StyleContext css_context = row.get_style_context ();
        if (is_key_default)
            css_context.remove_class ("edited");
        else
            css_context.add_class ("edited");
        row.update_label (Key.cool_text_value_from_variant (key_value), false);
    }

    private static void update_dconf_row (KeyListBoxRow row, string type_string, Variant? key_value)
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
            row.update_label (Key.cool_text_value_from_variant ((!) key_value), false);
        }
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();    // is a ListBoxRowWrapper
        // ListBox list_box = (ListBox) list_box_row.get_parent ();     // instead of key_list_box
        key_list_box.select_row (list_box_row);

        if (!search_mode)
            list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            if (search_mode && key_list_box.get_focus_child () != null)
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
        }
        else if (search_mode)
            list_box_row.grab_focus ();

        return false;
    }

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        KeyListBoxRow? row = get_row_for_key (key_list_box, full_name, context_id);
        if (row == null)    // TODO make method only called when necessary 1/2
            return;

        SettingsModel model = modifications_handler.model;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.TYPE_CODE & PropertyQuery.KEY_CONFLICT)));
        string type_code;
        uint8 _key_conflict;
        if (!properties.lookup (PropertyQuery.TYPE_CODE,    "s", out type_code))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.KEY_CONFLICT, "y", out _key_conflict))
            assert_not_reached ();
        KeyConflict key_conflict = (KeyConflict) _key_conflict;
        properties.clear ();

        update_gsettings_row ((!) row,
                              type_code,
                              key_value,
                              is_key_default,
                              key_conflict == KeyConflict.HARD);
        ((!) row).destroy_popover ();
    }

    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        KeyListBoxRow? row = get_row_for_key (key_list_box, full_name, ModelUtils.dconf_context_id);
        if (row == null)    // TODO make method only called when necessary 2/2
            return;

        update_dconf_row ((!) row, ((!) row).type_string, key_value_or_null);
        ((!) row).destroy_popover ();
    }

    private static KeyListBoxRow? get_row_for_key (ListBox key_list_box, string full_name, uint16 context_id)
    {
        int position = 0;
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        while (row != null)
        {
            Widget? row_child = ((ListBoxRow) (!) row).get_child ();
            if (row_child == null)
                assert_not_reached ();

            if ((!) row_child is KeyListBoxRow
             && ((KeyListBoxRow) (!) row_child).full_name == full_name
             && ((KeyListBoxRow) (!) row_child).context_id == context_id)
                return (KeyListBoxRow) (!) row_child;

            row = key_list_box.get_row_at_index (++position);
        }
        return null;
    }

    /*\
    * * Right click popover creation
    \*/

    private void show_right_click_popover (ClickableListBoxRow row, int? nullable_event_x)
    {
        generate_popover_if_needed (row, modifications_handler);
        place_popover (row, nullable_event_x);
        rows_possibly_with_popover.append (row);
    }
    private static void place_popover (ClickableListBoxRow row, int? nullable_event_x)
    {
        int event_x;
        if (nullable_event_x == null)
            event_x = (int) (((int) row.get_allocated_width ()) / 2.0);
        else
            event_x = (!) nullable_event_x;

        Gdk.Rectangle rect = { x:event_x, y:row.get_allocated_height (), width:0, height:0 };
        ((!) row.nullable_popover).set_pointing_to (rect);
        ((!) row.nullable_popover).popup ();
    }

    private static void generate_popover_if_needed (ClickableListBoxRow row, ModificationsHandler modifications_handler)
    {
        if (row.nullable_popover == null)
        {
            row.nullable_popover = new ContextPopover ();
            // boolean test for rows without popovers, but that never happens in current design
            if (!generate_popover (row, modifications_handler))
            {
                ((!) row.nullable_popover).destroy ();  // TODO better, again
                row.nullable_popover = null;
                return;
            }

            ((!) row.nullable_popover).destroy.connect_after (() => { row.nullable_popover = null; });

            ((!) row.nullable_popover).set_relative_to (row);
            ((!) row.nullable_popover).position = PositionType.BOTTOM;     // TODO better
        }
        else if (((!) row.nullable_popover).visible)
            warning ("generate_popover_if_needed() called but popover is visible");   // TODO is called on multi-right-click
    }

    private static bool generate_popover (ClickableListBoxRow row, ModificationsHandler modifications_handler)
        requires (row.nullable_popover != null)
    {
        switch (row.context_id)
        {
            case ModelUtils.undefined_context_id:
                assert_not_reached ();

            case ModelUtils.folder_context_id:
                return generate_folder_popover (row);

            case ModelUtils.dconf_context_id:
                if (modifications_handler.model.is_key_ghost (row.full_name))
                    return generate_ghost_popover (row, _get_key_copy_text_variant (row, modifications_handler));
                else
                    return generate_dconf_popover ((KeyListBoxRow) row, modifications_handler, _get_key_copy_text_variant (row, modifications_handler));

            default:
                return generate_gsettings_popover ((KeyListBoxRow) row, modifications_handler, _get_key_copy_text_variant (row, modifications_handler));
        }
    }

    private static bool generate_folder_popover (ClickableListBoxRow row)
    {
        if (row.nullable_popover == null)   // do not place in requires 1/4
            assert_not_reached ();

        ContextPopover popover = (!) row.nullable_popover;
        Variant variant = new Variant.string (row.full_name);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant.print (false) + ")");
            popover.new_section ();
        }

        popover.new_gaction ("open", "ui.open-folder(" + variant.print (false) + ")");
        popover.new_gaction ("copy", "app.copy(" + _get_folder_copy_text_variant (row).print (false) + ")");

        popover.new_section ();
        popover.new_gaction ("recursivereset", "ui.reset-recursive(" + variant.print (false) + ")");

        return true;
    }

    private static bool generate_gsettings_popover (KeyListBoxRow row, ModificationsHandler modifications_handler, Variant copy_text_variant)
    {
        if (row.nullable_popover == null)   // do not place in requires 2/4
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
        string full_name = row.full_name;
        uint16 context_id = row.context_id;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.TYPE_CODE & PropertyQuery.RANGE_TYPE & PropertyQuery.RANGE_CONTENT & PropertyQuery.IS_DEFAULT & PropertyQuery.KEY_CONFLICT & PropertyQuery.KEY_VALUE)));

        string type_string;
        uint8 _range_type, _key_conflict;
        Variant range_content;
        bool is_key_default;
        if (!properties.lookup (PropertyQuery.TYPE_CODE,            "s",    out type_string))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.RANGE_TYPE,           "y",    out _range_type))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.RANGE_CONTENT,        "v",    out range_content))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.IS_DEFAULT,           "b",    out is_key_default))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.KEY_CONFLICT,         "y",    out _key_conflict))
            assert_not_reached ();
        RangeType range_type = (RangeType) _range_type;
        KeyConflict key_conflict = (KeyConflict) _key_conflict;

        Variant variant_s = new Variant.string (full_name);
        Variant variant_sq = new Variant ("(sq)", full_name, context_id);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant_s.print (false) + ")");
            popover.new_section ();
        }

        if (key_conflict == KeyConflict.HARD)
        {
            popover.new_gaction ("detail", "ui.open-object(" + variant_sq.print (true) + ")");
            popover.new_gaction ("copy", "app.copy(" + copy_text_variant.print (false) + ")");
            properties.clear ();
            return true; // anything else is value-related, so we are done
        }

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);

        popover.new_gaction ("customize", "ui.open-object(" + variant_sq.print (true) + ")");
        popover.new_gaction ("copy", "app.copy(" + copy_text_variant.print (false) + ")");

        if (type_string == "b" || type_string == "<enum>" || type_string == "mb"
            || (
                (type_string == "y" || type_string == "q" || type_string == "u" || type_string == "t")
                && (range_type == RangeType.RANGE)
                && (Key.get_variant_as_uint64 (range_content.get_child_value (1)) - Key.get_variant_as_uint64 (range_content.get_child_value (0)) < 13)
               )
            || (
                (type_string == "n" || type_string == "i" || type_string == "x")    // the handle type cannot have range
                && (range_type == RangeType.RANGE)
                && (Key.get_variant_as_int64 (range_content.get_child_value (1)) - Key.get_variant_as_int64 (range_content.get_child_value (0)) < 13)
               )
            || type_string == "()")
        {
            popover.new_section ();
            GLib.Action action;
            if (planned_change)
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content,
                                                      modifications_handler.get_key_planned_value (full_name));
            else if (is_key_default)
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content,
                                                      null);
            else
            {
                Variant key_value;
                if (!properties.lookup (PropertyQuery.KEY_VALUE,    "v",    out key_value))
                    assert_not_reached ();
                action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content, key_value);
            }

            popover.change_dismissed.connect (() => on_popover_change_dismissed (row));
            popover.value_changed.connect ((gvariant) => on_popover_value_change (row, gvariant, action));
        }
        else if (!delayed_apply_menu && !planned_change && type_string == "<flags>")
        {
            popover.new_section ();

            if (!is_key_default)
                popover.new_gaction ("default2", "bro.set-to-default(" + variant_sq.print (true) + ")");

            string [] all_flags = range_content.get_strv ();
            popover.create_flags_list (modifications_handler.get_key_custom_value (full_name, context_id).get_strv (), all_flags);
            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                    string [] active_flags = modifications_handler.get_key_custom_value (full_name, context_id).get_strv ();
                    foreach (string flag in all_flags)
                        popover.update_flag_status (flag, flag in active_flags);
                });
            popover.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));

            popover.value_changed.connect ((gvariant) => row.set_key_value (gvariant));
        }
        else if (planned_change)
        {
            popover.new_section ();
            popover.new_gaction ("dismiss", "ui.dismiss-change(" + variant_s.print (false) + ")");

            if (planned_value != null)
                popover.new_gaction ("default1", "bro.set-to-default(" + variant_sq.print (true) + ")");
        }
        else if (!is_key_default)
        {
            popover.new_section ();
            popover.new_gaction ("default1", "bro.set-to-default(" + variant_sq.print (true) + ")");
        }
        properties.clear ();
        return true;
    }

    private static bool generate_ghost_popover (ClickableListBoxRow row, Variant copy_text_variant)
    {
        if (row.nullable_popover == null)   // do not place in requires 3/4
            assert_not_reached ();

        ContextPopover popover = (!) row.nullable_popover;
        popover.new_gaction ("copy", "app.copy(" + copy_text_variant.print (false) + ")");
        return true;
    }

    private static bool generate_dconf_popover (KeyListBoxRow row, ModificationsHandler modifications_handler, Variant copy_text_variant)
    {
        if (row.nullable_popover == null)   // do not place in requires 4/4
            assert_not_reached ();

        SettingsModel model = modifications_handler.model;
        ContextPopover popover = (!) row.nullable_popover;
        Variant variant_s = new Variant.string (row.full_name);
        Variant variant_sq = new Variant ("(sq)", row.full_name, ModelUtils.dconf_context_id);

        if (row.search_result_mode)
        {
            popover.new_gaction ("open_parent", "ui.open-parent(" + variant_s.print (false) + ")");
            popover.new_section ();
        }

        popover.new_gaction ("customize", "ui.open-object(" + variant_sq.print (true) + ")");
        popover.new_gaction ("copy", "app.copy(" + copy_text_variant.print (false) + ")");

        bool planned_change = modifications_handler.key_has_planned_change (row.full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (row.full_name);

        if (row.type_string == "b" || row.type_string == "mb" || row.type_string == "()")
        {
            popover.new_section ();
            bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
            RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (row.full_name, ModelUtils.dconf_context_id, (uint16) PropertyQuery.KEY_VALUE));
            Variant key_value;
            if (!properties.lookup (PropertyQuery.KEY_VALUE,        "v",    out key_value))
                assert_not_reached ();
            properties.clear ();
            GLib.Action action = popover.create_buttons_list (true, delayed_apply_menu, planned_change, row.type_string, null,
                                                              planned_change ? planned_value : key_value);

            popover.change_dismissed.connect (() => on_popover_change_dismissed (row));
            popover.value_changed.connect ((gvariant) => on_popover_value_change (row, gvariant, action));

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

    private static void on_popover_change_dismissed (KeyListBoxRow row)
    {
        row.destroy_popover ();
        row.change_dismissed ();
    }
    private static void on_popover_value_change (KeyListBoxRow row, Variant? gvariant, GLib.Action action)
    {
        row.hide_right_click_popover ();
        VariantType variant_type = row.type_string == "<enum>" ? VariantType.STRING : new VariantType (row.type_string);
        action.change_state (new Variant.maybe (null, new Variant.maybe (variant_type, gvariant)));
        row.set_key_value (gvariant);
    }

    private static inline Variant _get_folder_copy_text_variant (ClickableListBoxRow row)
    {
        return new Variant.string (_get_folder_copy_text (row));
    }
    private static inline Variant _get_key_copy_text_variant (ClickableListBoxRow row, ModificationsHandler modifications_handler)
    {
        return new Variant.string (_get_key_copy_text (row, modifications_handler));
    }
}
