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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/overlayed-list.ui")]
private abstract class OverlayedList : Overlay, AdaptativeWidget
{
    [GtkChild] protected unowned ListBox        main_list_box;
               private   StyleContext   main_list_box_context;
               protected GLib.ListStore main_list_store = new GLib.ListStore (typeof (Widget));

    [GtkChild] private   unowned ScrolledWindow scrolled;
    [GtkChild] private   unowned Box            edit_mode_box;

    /*\
    * * differed construct
    \*/

    construct
    {
        main_list_box_context = main_list_box.get_style_context ();
        main_context = get_style_context ();
        connect_handlers ();
        main_list_box.bind_model (main_list_store, create_rows);
    }

    private Widget create_rows (Object item)
    {
        return (Widget) item;
    }


    [GtkChild] private unowned ModelButton enter_edit_mode_button;
    [GtkChild] private unowned ModelButton leave_edit_mode_button;
    [CCode (notify = false)] public string edit_mode_action_prefix
    {
        construct
        {
            get_style_context ().add_class ("needs-padding");

            // TODO sanitize "value"
            enter_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(true)");
            leave_edit_mode_button.set_detailed_action_name (value + ".set-edit-mode(false)");
        }
    }
    [CCode (notify = false)] public string first_mode_name   { protected set { leave_edit_mode_button.text = value; }}
    [CCode (notify = false)] public string second_mode_name  { protected set { enter_edit_mode_button.text = value; }}

    [CCode (notify = false)] public bool needs_shadows
    {
        construct
        {
            if (value)
                scrolled.shadow_type = ShadowType.ETCHED_IN;
            else
                scrolled.shadow_type = ShadowType.NONE;
        }
    }

    protected string placeholder_icon;
    protected string placeholder_text;
    [CCode (notify = false)] public bool big_placeholder { private get; internal construct; }
    protected void add_placeholder ()
    {
        RegistryPlaceholder placeholder = new RegistryPlaceholder (placeholder_icon, placeholder_text, big_placeholder);
        main_list_box.set_placeholder (placeholder);
    }

    /*\
    * * responsive design
    \*/

    private StyleContext main_context;
    internal void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        if (!AdaptativeWidget.WindowSize.is_extra_thin (new_size) && AdaptativeWidget.WindowSize.is_extra_flat (new_size))
            set_horizontal (ref main_context, edit_mode_box);
        else
            set_vertical (ref main_context, edit_mode_box);
    }
    private static inline void set_horizontal (ref StyleContext main_context, Box edit_mode_box)
    {
        main_context.remove_class ("vertical");
        edit_mode_box.halign = Align.END;
        edit_mode_box.valign = Align.CENTER;
        edit_mode_box.orientation = Orientation.VERTICAL;
        edit_mode_box.width_request = 160;
        main_context.add_class ("horizontal");
    }
    private static inline void set_vertical (ref StyleContext main_context, Box edit_mode_box)
    {
        main_context.remove_class ("horizontal");
        edit_mode_box.halign = Align.CENTER;
        edit_mode_box.valign = Align.END;
        edit_mode_box.orientation = Orientation.HORIZONTAL;
        edit_mode_box.width_request = 200;
        main_context.add_class ("vertical");
    }

    /*\
    * * keyboard
    \*/

    internal bool next_match ()
    {
        return _next_match (main_list_box);
    }
    private static inline bool _next_match (ListBox main_list_box)
    {
        ListBoxRow? row = main_list_box.get_selected_row ();    // TODO multiple rows and focus-only lists
        if (row == null)
            row = main_list_box.get_row_at_index (0);
        else
            row = main_list_box.get_row_at_index (((!) row).get_index () + 1);

        if (row == null)
        {
            _scroll_bottom (main_list_box);
            return false;
        }
        main_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
        return true;
    }

    internal bool previous_match ()
    {
        return _previous_match (main_list_box);
    }
    private static inline bool _previous_match (ListBox main_list_box)
    {
        uint n_items = main_list_box.get_children ().length ();  // FIXME OverlayedList.n_items is unreliable
        if (n_items == 0)
            return false;

        ListBoxRow? row = main_list_box.get_selected_row ();    // TODO multiple rows and focus-only lists
        if (row == null)
            row = main_list_box.get_row_at_index ((int) n_items - 1);
        else
        {
            int index = ((!) row).get_index ();
            if (index <= 0)
                return false;
            row = main_list_box.get_row_at_index (index - 1);
        }

        if (row == null)
            assert_not_reached ();

        main_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
        return true;
    }

    internal void select_all ()
    {
        main_list_box.select_all ();
    }

    internal void unselect_all ()
    {
        main_list_box.unselect_all ();
    }

    protected void select_row_for_real (ListBoxRow row)   // ahem...
    {
        main_list_box.unselect_row (row);
        main_list_box.select_row (row);
    }

    /*\
    * * utilities
    \*/

    protected int [] get_selected_rows_indices ()
    {
        return _get_selected_rows_indices (main_list_box);
    }
    private static inline int [] _get_selected_rows_indices (ListBox main_list_box)
    {
        int [] indices = new int [0];
        main_list_box.selected_foreach ((_list_box, selected_row) => {
                int index = selected_row.get_index ();
                if (index < 0)
                    assert_not_reached ();
                indices += index;
            });
        return indices;
    }

    protected void scroll_top ()
    {
        _scroll_top (main_list_box);
    }
    private static inline void _scroll_top (ListBox main_list_box)
    {
        Adjustment adjustment = main_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_lower ());
    }

    protected void scroll_bottom ()
    {
        _scroll_bottom (main_list_box);
    }
    private static inline void _scroll_bottom (ListBox main_list_box)
    {
        Adjustment adjustment = main_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_upper ());
    }

    internal bool handle_copy_text (out string copy_text)
    {
        return _handle_copy_text (out copy_text, main_list_box);
    }
    private static inline bool _handle_copy_text (out string copy_text, ListBox main_list_box)
    {
        List<weak ListBoxRow> selected_rows = main_list_box.get_selected_rows ();
        OverlayedListRow row;
        switch (selected_rows.length ())
        {
            case 0:
                Widget? focus_child = main_list_box.get_focus_child ();
                if (focus_child == null)
                    return BaseWindow.copy_clipboard_text (out copy_text);
                if (BaseWindow.copy_clipboard_text (out copy_text))
                    return true;
                if (!((!) focus_child is OverlayedListRow))
                    assert_not_reached ();
                row = (OverlayedListRow) (!) focus_child;
                break;
            case 1:
                ListBoxRow selected_row = selected_rows.nth_data (0);
                if (!(selected_row is OverlayedListRow))
                    assert_not_reached ();
                row = (OverlayedListRow) selected_row;
                break;
            default:
                return BaseWindow.no_copy_text (out copy_text);
        }
        return row.handle_copy_text (out copy_text);  // FIXME row should keep focus
    }

    /*\
    * * selection state
    \*/

    internal signal void selection_changed ();

    [GtkCallback]
    private void on_selection_changed ()
    {
        selection_changed ();
    }

    internal enum SelectionState {
        EMPTY,
        // one
        UNIQUE,
        FIRST,
        LAST,
        MIDDLE,
        // multiple
        MULTIPLE,
        MULTIPLE_FIRST,
        MULTIPLE_LAST,
        ALL
    }

    internal SelectionState get_selection_state ()
    {
        return _get_selection_state (main_list_box, ref main_list_store);
    }
    private static inline SelectionState _get_selection_state (ListBox main_list_box, ref GLib.ListStore main_list_store)
    {
        List<weak ListBoxRow> selected_rows = main_list_box.get_selected_rows ();
        uint n_selected_rows = selected_rows.length ();

        if (n_selected_rows == 0)
            return SelectionState.EMPTY;
        if (n_selected_rows >= 2)
        {
            uint n_items = main_list_store.get_n_items ();
            if (n_selected_rows == n_items)
                return SelectionState.ALL;
            uint first_items = 0;
            uint last_items = 0;
            uint first_of_the_last_items_index = n_items - n_selected_rows;
            selected_rows.foreach ((row) => {
                    uint index = row.get_index ();
                    if (index < n_selected_rows)
                        first_items++;
                    if (index >= first_of_the_last_items_index)
                        last_items++;
                });
            if (first_items == n_selected_rows)
                return SelectionState.MULTIPLE_FIRST;
            if (last_items == n_selected_rows)
                return SelectionState.MULTIPLE_LAST;
            return SelectionState.MULTIPLE;
        }

        int index = selected_rows.nth_data (0).get_index ();
        bool is_first = index == 0;
        bool is_last = main_list_box.get_row_at_index (index + 1) == null;
        if (is_first && is_last)
            return SelectionState.UNIQUE;
        if (is_first)
            return SelectionState.FIRST;
        if (is_last)
            return SelectionState.LAST;
        return SelectionState.MIDDLE;
    }

    /*\
    * * overlay visibility
    \*/

    protected ulong content_changed_handler = 0;

    [CCode (notify = false)] protected uint n_items { protected get; private set; default = 0; }
    private bool is_editable = false;

    protected void change_editability (bool new_value)
    {
        is_editable = new_value;
        update_edit_mode_box_visibility ();
    }

    private void connect_handlers ()   // connect and disconnect manually or bad things happen on destroy
    {
        content_changed_handler = main_list_store.items_changed.connect (on_content_changed);

        destroy.connect (() => main_list_store.disconnect (content_changed_handler));
    }

    private void on_content_changed (GLib.ListModel main_list_model, uint position, uint removed, uint added)
    {
        n_items += added;
        n_items -= removed;
        update_has_empty_list_class (n_items == 0);
        update_edit_mode_box_visibility ();
    }

    private bool has_empty_list_class = false;
    private void update_has_empty_list_class (bool list_is_empty)
    {
        if (list_is_empty && !has_empty_list_class)
        {
            main_list_box_context.add_class ("empty-list");
            has_empty_list_class = true;
        }
        else if (!list_is_empty && has_empty_list_class)
        {
            has_empty_list_class = false;
            main_list_box_context.remove_class ("empty-list");
        }
    }

    private inline void update_edit_mode_box_visibility ()
    {
        edit_mode_box.visible = is_editable && n_items != 0;
    }

    internal abstract void reset ();
}

private abstract class OverlayedListRow : ListBoxRow
{
    internal abstract bool handle_copy_text (out string copy_text);
}
