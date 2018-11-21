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
private abstract class OverlayedList : Overlay
{
    [GtkChild] protected ListBox        main_list_box;
               private StyleContext     main_list_box_context;
               protected GLib.ListStore main_list_store = new GLib.ListStore (typeof (Widget));

    [GtkChild] protected ScrolledWindow scrolled;
    [GtkChild] private   Box            edit_mode_box;

    /*\
    * * differed construct
    \*/

    construct
    {
        main_list_box_context = main_list_box.get_style_context ();
        connect_handlers ();
        main_list_box.bind_model (main_list_store, create_rows);
    }

    private Widget create_rows (Object item)
    {
        return (Widget) item;
    }


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
    }
    public string first_mode_name   { protected set { leave_edit_mode_button.text = value; }}
    public string second_mode_name  { protected set { enter_edit_mode_button.text = value; }}

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

    protected string placeholder_icon;
    protected string placeholder_text;
    public bool big_placeholder { private get; internal construct; }
    protected void add_placeholder ()
    {
        RegistryPlaceholder placeholder = new RegistryPlaceholder (placeholder_icon, placeholder_text, big_placeholder);
        main_list_box.set_placeholder (placeholder);
    }

    /*\
    * * keyboard
    \*/

    internal void down_pressed ()
    {
        ListBoxRow? row = main_list_box.get_selected_row ();
        if (row == null)
            row = main_list_box.get_row_at_index (0);
        else
            row = main_list_box.get_row_at_index (((!) row).get_index () + 1);

        if (row == null)
            return;
        main_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    internal void up_pressed ()
    {
        if (n_items == 0)
            return;

        ListBoxRow? row = main_list_box.get_selected_row ();
        if (row == null)
            row = main_list_box.get_row_at_index ((int) n_items - 1);
        else
        {
            int index = ((!) row).get_index ();
            if (index <= 0)
                return;
            row = main_list_box.get_row_at_index (index - 1);
        }

        if (row == null)
            assert_not_reached ();

        main_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
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
        UNIQUE,
        FIRST,
        LAST,
        MIDDLE,
        MULTIPLE
    }

    internal SelectionState get_selection_state ()
    {
        List<weak ListBoxRow> selected_rows = main_list_box.get_selected_rows ();
        uint n_selected_rows = selected_rows.length ();

        if (n_selected_rows == 0)
            return SelectionState.EMPTY;
        if (n_selected_rows >= 2)
            return SelectionState.MULTIPLE;

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

    protected uint n_items { protected get; private set; default = 0; }
    private bool is_editable = false;

    protected void change_editability (bool new_value)
    {
        is_editable = new_value;
        update_edit_mode_box_visibility ();
    }

    private void connect_handlers ()   // connect and disconnect manually or bad things happen on destroy
    {
        content_changed_handler = main_list_store.items_changed.connect (on_content_changed);

        destroy.connect (() => {
                main_list_store.disconnect (content_changed_handler);
            });
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
}
