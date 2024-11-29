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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-list.ui")]
private abstract class RegistryList : Box, BrowsableView
{
    [GtkChild] protected unowned ListBox key_list_box;
    [GtkChild] private unowned ScrolledWindow scrolled;
    private Adjustment adjustment;

    [CCode (notify = false)] protected bool search_mode { private get; protected set; }
    protected string? current_path_if_search_mode = null;   // TODO only used in search mode

    protected GLib.ListStore list_model = new GLib.ListStore (typeof (SimpleSettingObject));

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    [CCode (notify = false)] internal ModificationsHandler modifications_handler { protected get; set; }

    protected string placeholder_title { get; set; }
    protected string placeholder_description { get; set; }

    construct
    {
        register_size_allocate ();

        adjustment = (!) key_list_box.get_adjustment ();
    }

    private bool _small_keys_list_rows = false;
    [CCode (notify = false)] internal bool small_keys_list_rows
    {
        set
        {
            _small_keys_list_rows = value;
            // FIXME: ?
            // key_list_box.foreach ((row) => {
            //         Widget? row_child = ((ListBoxRow) row).get_child ();
            //         if (row_child != null && (!) row_child is KeyListBoxRow)
            //             ((KeyListBoxRow) (!) row_child).small_keys_list_rows = value;
            //     });
        }
    }

    // private AdaptativeWidget.WindowSize window_size = AdaptativeWidget.WindowSize.START_SIZE;
    // private void set_window_size (AdaptativeWidget.WindowSize new_size)
    // {
    //     window_size = new_size;
    //     key_list_box.@foreach ((row) => {
    //             Widget? row_child = ((ListBoxRow) row).get_child ();
    //             if (row_child != null && (!) row_child is KeyListBoxRow)
    //                 ((KeyListBoxRow) (!) row_child).set_window_size (new_size);
    //         });
    // }

    private void select_row_and_if_true_grab_focus (ListBoxRow row, bool grab_focus)
    {
        key_list_box.select_row (row);
        if (grab_focus)
            row.grab_focus ();
    }
    internal abstract void select_first_row ();

    private enum ScrollToRowBehaviour {
        CENTER,
        SCROLL_UP,
        SCROLL_DOWN
    }
    private void scroll_to_row (ListBoxRow row, ScrollToRowBehaviour behaviour)
    {
        int adjustment_value = (int) adjustment.get_value ();
        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);

        int row_bottom_limit = row_allocation.y - list_allocation.height;
        int row_top_limit    = row_allocation.y + row_allocation.height;

        if ((adjustment_value < row_bottom_limit)
         || (adjustment_value > row_top_limit))
        {
            adjustment.set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
            return;
        }

        row_bottom_limit += row_allocation.height + 40;
        row_top_limit /* -= row_allocation.height + 40; */ = row_allocation.y - 40;

        switch (behaviour)
        {
            case ScrollToRowBehaviour.CENTER:
                if ((adjustment_value <   row_bottom_limit)
                 || (adjustment_value >   row_top_limit))
                    adjustment.set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
                return;

            case ScrollToRowBehaviour.SCROLL_DOWN:
                if (adjustment_value <    row_bottom_limit)
                    adjustment.set_value (row_bottom_limit);
                return;

            case ScrollToRowBehaviour.SCROLL_UP:
                if (adjustment_value >    row_top_limit)
                    adjustment.set_value (row_top_limit);
                return;

            default:
                assert_not_reached ();
        }
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
        // key_list_box.@foreach ((row_wrapper) => {
        //         ClickableListBoxRow? row = (ClickableListBoxRow) ((ListBoxRowWrapper) row_wrapper).get_child ();
        //         if (row == null)
        //             assert_not_reached ();
        //         if ((!) row is KeyListBoxRow && ((KeyListBoxRow) (!) row).type_string == "b")
        //             ((KeyListBoxRow) row).delay_mode = !show;
        //     });
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

    internal void select_row_named (string selected, uint16 context_id, bool grab_focus)
    {
        // check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (list_model, selected, context_id));
        if (row != null)
        {
            select_row_and_if_true_grab_focus ((!) row, grab_focus);
            scroll_to_row ((!) row, ScrollToRowBehaviour.CENTER);
        }
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
            } else if (selected.has_prefix (object.full_name))
            {
                fallback = position;
            }
            position++;
        }
        return (int) fallback; // selected row may have been removed or context could be ""
    }

    private static void set_delayed_icon (ModificationsHandler _modifications_handler, KeyListBoxRow row)
    {
        SettingsModel model = _modifications_handler.model;
        if (_modifications_handler.key_has_planned_change (row.full_name))
        {
            row.add_css_class ("delayed");
            if (!model.key_has_schema (row.full_name))
            {
                if (_modifications_handler.get_key_planned_value (row.full_name) == null)
                    row.add_css_class ("erase");
                else
                    row.remove_css_class ("erase");
            }
        }
        else
        {
            row.remove_css_class ("delayed");
            if (!model.key_has_schema (row.full_name) && model.is_key_ghost (row.full_name))
                row.add_css_class ("erase");
            else
                row.remove_css_class ("erase");
        }
    }

    /*\
    * * close row popover on resize
    \*/

    // private int width = -1;
    // private int height = -1;

    private inline void register_size_allocate ()
    {
        // size_allocate.connect (on_size_allocate);
    }

    // private void on_size_allocate (Allocation allocation)
    // {
    //     if (width != allocation.width)
    //     {
    //         width = allocation.width;
    //         if (height != allocation.height)
    //             height = allocation.height;
    //         hide_right_click_popover ();
    //     }
    //     else if (height != allocation.height)
    //     {
    //         height = allocation.height;
    //         hide_right_click_popover ();
    //     }
    // }

    // private void hide_right_click_popover ()
    // {
    //     ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
    //     if (selected_row == null)
    //         return;

    //     ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

    //     if (row.right_click_popover_visible ())
    //         row.hide_right_click_popover ();
    // }

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
        {
            row.hide_right_click_popover ();
            return true;
        }

        row.show_right_click_popover (0, 0);
        return true;
    }

    internal bool handle_copy_text (out string copy_text) // can compile with "private", but is public 1/2
    {
        // FIXME Can we remove all of this?
        return false;
    }
    // private bool _handle_copy_text (out string copy_text, ListBox key_list_box)
    // {
    //     ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
    //     if (selected_row == null)
    //         return BaseWindow.no_copy_text (out copy_text);

    //     ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

    //     if (ModelUtils.is_folder_context_id (row.context_id)
    //      || ModelUtils.is_undefined_context_id (row.context_id))
    //         copy_text = _get_folder_or_search_copy_text (row);
    //     else
    //         copy_text = _get_key_copy_text (row, modifications_handler);
    //     return true;
    // }

    // private static inline string _get_folder_or_search_copy_text (ClickableListBoxRow row)
    // {
    //     return row.full_name;
    // }

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

    internal void row_grab_focus ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((!) selected_row).grab_focus ();
    }

    internal bool next_match ()
    {
        return next_or_previous_match (true);
    }
    internal bool previous_match ()
    {
        return next_or_previous_match (false);
    }
    private bool next_or_previous_match (bool is_next)
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
            if (!is_next && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_next && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
            {
                scroll_to_row ((!) row, is_next ? ScrollToRowBehaviour.SCROLL_DOWN : ScrollToRowBehaviour.SCROLL_UP);
                if (search_mode)
                {
                    ListBox list_box = (ListBox) ((!) selected_row).get_parent ();
                    select_row_and_if_true_grab_focus ((!) row, list_box.get_focus_child () != null);
                }
                else
                    select_row_and_if_true_grab_focus ((!) row, true);
            }
            return true;
        }
        else if (n_items >= 1)
        {
            selected_row = key_list_box.get_row_at_index (is_next ? 0 : (int) n_items - 1);
            if (selected_row == null)
                return false;
            select_row_and_if_true_grab_focus ((!) selected_row, true);
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
            row = new FolderListBoxRow (setting_object.name, full_name, false, search_mode_non_local_result);
        }
        else
        {
            Variant properties = modifications_handler.model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.HAS_SCHEMA & PropertyQuery.KEY_NAME & PropertyQuery.TYPE_CODE & PropertyQuery.SUMMARY & PropertyQuery.KEY_CONFLICT));

            KeyListBoxRow key_row = create_key_list_box_row (full_name, context_id, properties, modifications_handler.get_current_delay_mode (), search_mode_non_local_result);
            key_row.small_keys_list_rows = _small_keys_list_rows;
            // key_row.set_window_size (window_size);

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect ((_modifications_handler) => set_delayed_icon (_modifications_handler, key_row));
            set_delayed_icon (modifications_handler, key_row);
            key_row.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));

            row = (ClickableListBoxRow) key_row;
        }

        // FIXME This is bad and this is why we should put all the popovers in UI files.
        row.generate_popover_if_needed (modifications_handler);

        // ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);
        // row.destroy.connect (() => row.disconnect (button_press_event_handler));

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
                /* Translators: "subtitle" in the keys list of a key defined by a schema but missing a summary describing the key use */
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
                row.add_css_class ("conflict");
            else if (key_conflict == KeyConflict.HARD)
            {
                row.add_css_class ("hard-conflict");
                /* Translators: means that the key has (at least) one other key defined by a different schema but at the same path and with the same name; used on large windows ("conflict" is used on small windows) */
                row.update_label (_("conflicting keys"), true,

                /* Translators: means that the key has (at least) one other key defined by a different schema but at the same path and with the same name; used on small windows ("conflicting keys" is used on large windows) */
                                  _("conflict"), true);

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
                                      /* Translators: "subtitle" in the keys list of a key not defined by a schema; keys defined by a schema have in place a summary describing the key use */
                                      _("No schema found"),
                                      true,
                                      delay_mode,
                                      key_name,
                                      full_name,
                                      search_mode_non_local_result);
        }
    }

    private static inline ListBoxRowWrapper put_row_in_wrapper (ClickableListBoxRow row)
    {
        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();

        wrapper.set_halign (Align.FILL);
        wrapper.set_child (row);
        if (ModelUtils.is_folder_context_id (row.context_id))
        {
            wrapper.add_css_class ("folder-row");
            if (row is FolderListBoxRow)
            {
                wrapper.action_name = "browser.open-folder";
            }
            else assert_not_reached ();
            wrapper.set_action_target ("s", row.full_name);
        }
        else if (row is KeyListBoxRow)
        {
            wrapper.add_css_class ("key-row");
            wrapper.action_name = "browser.open-object";
            wrapper.set_action_target ("(sq)", row.full_name, row.context_id);
        }
        else assert_not_reached ();

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
            row.update_switch (key_value_boolean, "view.toggle-gsettings-key-switch(" + switch_variant.print (true) + ")");
        }

        if (is_key_default)
            row.remove_css_class ("edited");
        else
            row.add_css_class ("edited");

        string key_value_text = Key.cool_text_value_from_variant (key_value);
        string key_type_label;
        bool key_type_italic;
        get_type_or_value (type_string, key_value_text, out key_type_label, out key_type_italic);

        row.update_label (key_value_text, false, key_type_label, key_type_italic);
    }

    private static void update_dconf_row (KeyListBoxRow row, string type_string, Variant? key_value)
    {
        if (key_value == null)
        {
            /* Translators: means that the key has been erased; used on large windows ("erased" is used on small windows) */
            row.update_label (_("key erased"), true,

            /* Translators: means that the key has been erased; used on small windows ("key erased" is used on large windows) */
                              _("erased"), true);

            if (type_string == "b")
                row.use_switch (false);
        }
        else
        {
            if (type_string == "b")
            {
                bool key_value_boolean = ((!) key_value).get_boolean ();
                Variant switch_variant = new Variant ("(sb)", row.full_name, !key_value_boolean);
                row.update_switch (key_value_boolean, "view.toggle-dconf-key-switch(" + switch_variant.print (false) + ")");
                row.use_switch (true);
            }

            string key_value_text = Key.cool_text_value_from_variant ((!) key_value);
            string key_type_label;
            bool key_type_italic;
            get_type_or_value (type_string, key_value_text, out key_type_label, out key_type_italic);
            row.update_label (key_value_text, false, key_type_label, key_type_italic);
        }
    }

    private static void get_type_or_value (string type_string, string key_value_text, out string key_type_label, out bool key_type_italic)
    {
        // all these types have a value guaranteed to be displayable in a limited (and not too long) number of chars; there is also the empty tuple, but "type “()”" looks even better than "empty tuple"
        if (type_string == "b" || type_string == "mb" || type_string == "y" || type_string == "h" || type_string == "d" || type_string == "n" || type_string == "q" || type_string == "i" || type_string == "u")
        {
            key_type_label = key_value_text;
            key_type_italic = false;
        }
        else
        {
            string label = ModelUtils.key_to_short_description (type_string);
            if ((type_string != "<enum>")
             && (type_string != "<flags>")
             && (label == type_string || label.length > 12))
                /* Translators: displayed on small windows; indicates the data type of the key (the %s is the variant type code) */
                label = _("type “%s”").printf (type_string);

            key_type_label = label;
            key_type_italic = true;
        }
    }

    // private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    // {
    //     ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();    // is a ListBoxRowWrapper
        // ListBox list_box = (ListBox) list_box_row.get_parent ();     // instead of key_list_box

    //     select_row_and_if_true_grab_focus (list_box_row, !search_mode);

    //     if (event.button == Gdk.BUTTON_SECONDARY)
    //     {
    //         if (search_mode && key_list_box.get_focus_child () != null)
    //             list_box_row.grab_focus ();

    //         ClickableListBoxRow row = (ClickableListBoxRow) widget;

    //         int event_x = (int) event.x;
    //         if (event.window != widget.get_window ())   // boolean value switch
    //         {
    //             int widget_x, unused;
    //             event.window.get_position (out widget_x, out unused);
    //             event_x += widget_x;
    //         }

    //         show_right_click_popover (row, event_x);
    //     }
    //     else if (search_mode)
    //         list_box_row.grab_focus ();

    //     return false;
    // }

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

        // FIXME This breaks my shitty popovers. They should instead use a menu model that sorts itself out.
        // ((!) row).destroy_popover ();
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
    * * headers
    \*/

    protected static void update_row_header_with_context (ListBoxRow row, ListBoxRow? before, SettingsModel model, bool local_search_header)
    {
        // FIXME This is absolutely deranged.

        string? label_text = null;
        ClickableListBoxRow? row_content = (ClickableListBoxRow) row.get_child ();
        if (row_content == null)
            assert_not_reached ();

        ClickableListBoxRow? before_content = null;

        if (before != null)
            before_content = (ClickableListBoxRow?) ((!) before).get_child ();

        if ((!) row_content is KeyListBoxRow)
        {
            KeyListBoxRow key_list_box_row = (KeyListBoxRow) (!) row_content;
            uint16 context_id = key_list_box_row.context_id;
            if (before_content == null || ((!) before_content).context_id != context_id)
            {
                if (key_list_box_row.has_schema)
                {
                    if (!model.key_exists (((KeyListBoxRow) ((!) row).get_child ()).full_name, context_id))
                        return; // FIXME that happens when reloading a now-empty folder

                    RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (key_list_box_row.full_name, context_id, (uint16) PropertyQuery.SCHEMA_ID));
                    string schema_id;
                    if (!properties.lookup (PropertyQuery.SCHEMA_ID, "s", out schema_id))
                        assert_not_reached ();
                    if (local_search_header)
                        /* Translators: header displayed in the keys list during a search only; indicates that the schema (the %s is the schema id) is installed at the path where the search has started */
                        label_text = _("%s (local keys)").printf (schema_id);
                    else
                        label_text = schema_id;
                }
                else if (local_search_header)
                    /* Translators: header displayed in the keys list during a search only; indicates that the following non-defined keys are installed at the path where the search has started */
                    label_text = _("Local keys not defined by a schema");

                else
                    /* Translators: header displayed in the keys list during a search or during browsing */
                    label_text = _("Keys not defined by a schema");
            }
        }
        else if ((!) row_content is FolderListBoxRow)
        {
            if (before_content == null || !((!) before_content is FolderListBoxRow))
                /* Translators: header displayed in the keys list during a search or during browsing */
                label_text = _("Subfolders");
        }
        else
            assert_not_reached ();

        if (label_text != null)
            row.set_header (new ListBoxRowHeader (before == null, (!) label_text));
    }
}
