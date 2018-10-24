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

internal enum BookmarkIcon {
    VALID_FOLDER,
    SEARCH,       /* TODO valid and invalid search; broken thing also, etc. */
    DCONF_OBJECT,
    KEY_DEFAULTS,
    EDITED_VALUE,

    /* same icon */
    EMPTY_FOLDER,
    EMPTY_OBJECT;
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmarks.ui")]
private class Bookmarks : MenuButton
{
    [GtkChild] private ListBox bookmarks_list_box;
    [GtkChild] private ScrolledWindow scrolled;
    [GtkChild] private Popover bookmarks_popover;

    [GtkChild] private Image bookmarks_icon;
    [GtkChild] private Switch bookmarked_switch;
    [GtkChild] private Label switch_label;

    [GtkChild] private Stack edit_mode_stack;
    [GtkChild] private Button rows_size_button;
    [GtkChild] private Image big_rows_icon;
    [GtkChild] private Image small_rows_icon;

    [GtkChild] private Button enter_edit_mode_button;
    [GtkChild] private Button leave_edit_mode_button;

    private string   current_path = "/";
    private ViewType current_type = ViewType.FOLDER;

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    public string schema_path { private get; internal construct; }
    private GLib.Settings settings;
    ulong bookmarks_changed_handler = 0;

    private HashTable<string, Bookmark> bookmarks_hashtable = new HashTable<string, Bookmark> (str_hash, str_equal);
    private Bookmark? last_row = null;
    private uint n_bookmarks = 0;

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);

    construct
    {
        update_switch_label (ViewType.SEARCH, ViewType.FOLDER, ref switch_label); // init text with "Bookmark this Location"

        install_action_entries ();

        settings = new GLib.Settings.with_path (schema_id, schema_path);
        set_css_classes ();

        bookmarks_changed_handler = settings.changed ["bookmarks"].connect (on_bookmarks_changed);
        update_bookmarks (settings.get_value ("bookmarks"));

        ulong bookmarks_writable_handler = settings.writable_changed ["bookmarks"].connect (set_switch_sensitivity);
        set_switch_sensitivity ();

        ulong clicked_handler = clicked.connect (() => { if (active) bookmarked_switch.grab_focus (); });

        destroy.connect (() => {
                settings.disconnect (small_bookmarks_rows_handler);
                settings.disconnect (bookmarks_changed_handler);
                settings.disconnect (bookmarks_writable_handler);
                disconnect (clicked_handler);
            });
    }

    private ulong small_bookmarks_rows_handler = 0;
    private bool has_small_bookmarks_rows_class = false;
    private void set_css_classes ()
    {
        StyleContext context = bookmarks_popover.get_style_context ();
        small_bookmarks_rows_handler = settings.changed ["small-bookmarks-rows"].connect (() => {
                bool small_bookmarks_rows = settings.get_boolean ("small-bookmarks-rows");
                if (small_bookmarks_rows)
                {
                    if (!has_small_bookmarks_rows_class) context.add_class ("small-bookmarks-rows");
                }
                else if (has_small_bookmarks_rows_class) context.remove_class ("small-bookmarks-rows");
                has_small_bookmarks_rows_class = small_bookmarks_rows;
                update_rows_size_button_icon (small_bookmarks_rows);
            });
        has_small_bookmarks_rows_class = settings.get_boolean ("small-bookmarks-rows");
        if (has_small_bookmarks_rows_class)
            context.add_class ("small-bookmarks-rows");
        update_rows_size_button_icon (has_small_bookmarks_rows_class);
    }

    private void on_bookmarks_changed (GLib.Settings _settings, string key)
    {
        Variant bookmarks_variant = _settings.get_value ("bookmarks");
        update_bookmarks (bookmarks_variant);
        update_icon_and_switch (bookmarks_variant);
        set_switch_sensitivity ();
    }

    private void set_switch_sensitivity ()
    {
        if (settings.is_writable ("bookmarks"))
        {
            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-disabled")
                edit_mode_stack.set_visible_child_name ("edit-mode-off");
        }
        else
        {
            edit_mode_stack.set_visible_child_name ("edit-mode-disabled");
            bookmarks_list_box.grab_focus ();
        }
    }

    /*\
    * * Callbacks
    \*/

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        string? visible_child_name = edit_mode_stack.get_visible_child_name ();
        bool edit_mode_on = visible_child_name != null && (!) visible_child_name == "edit-mode-on";

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            if (edit_mode_on)
            {
                if (name == "a")
                {
                    bookmarks_list_box.select_all ();
                    return true;
                }
                if (name == "A")
                {
                    bookmarks_list_box.unselect_all ();
                    return true;
                }
            }
        }

        if (keyval == Gdk.Key.Escape && edit_mode_on)
        {
            leave_edit_mode ();
            return true;
        }
        return false;
    }

    [GtkCallback]
    private void on_selection_changed ()
    {
        string? visible_child_name = edit_mode_stack.get_visible_child_name ();         // TODO edit_mode_on private boolean
        if (visible_child_name == null || (!) visible_child_name == "edit-mode-off")
            return;
        update_actions ();
    }

    /*\
    * * Public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        update_switch_label (current_type, type, ref switch_label);

        current_path = path;
        current_type = type;

        update_icon_and_switch (settings.get_value ("bookmarks"));
    }

    // for search
    internal string [] get_bookmarks ()
    {
        string [] all_bookmarks = settings.get_strv ("bookmarks");
        string [] unduplicated_bookmarks = {};
        foreach (string bookmark in all_bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;
        }
        return unduplicated_bookmarks;
    }

    // keyboard call

    internal void down_pressed ()
        requires (active)
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = bookmarks_list_box.get_row_at_index (0);
        else
            row = bookmarks_list_box.get_row_at_index (((!) row).get_index () + 1);

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }
    internal void up_pressed ()
        requires (active)
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = last_row;
        else
        {
            int index = ((!) row).get_index ();
            if (index <= 0)
                return;
            row = bookmarks_list_box.get_row_at_index (index - 1);
        }

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    internal void bookmark_current_path ()
    {
        if (bookmarked_switch.get_active ())
            return;
        append_bookmark (settings, get_bookmark_name (current_path, current_type));
    }

    internal void unbookmark_current_path ()
    {
        if (!bookmarked_switch.get_active ())
            return;
        remove_bookmark (settings, get_bookmark_name (current_path, current_type));
    }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        Bookmark? bookmark_row = bookmarks_hashtable.lookup (bookmark);
        if (bookmark_row == null)
            return;
        Widget? bookmark_grid = ((!) bookmark_row).get_child ();
        if (bookmark_grid == null)
            assert_not_reached ();
        _update_bookmark_icon (((!) bookmark_grid).get_style_context (), icon);
    }
    private static inline void _update_bookmark_icon (StyleContext context, BookmarkIcon icon)
    {
        switch (icon)
        {
            case BookmarkIcon.VALID_FOLDER: context.add_class ("folder");
                return;
            case BookmarkIcon.EMPTY_FOLDER: context.add_class ("folder");
                                            context.add_class ("erase");
                return;
            case BookmarkIcon.SEARCH:       context.add_class ("search");
                return;
            case BookmarkIcon.EMPTY_OBJECT: context.add_class ("key");
                                            context.add_class ("dconf-key");
                                            context.add_class ("erase");
                return;
            case BookmarkIcon.DCONF_OBJECT: context.add_class ("key");
                                            context.add_class ("dconf-key");
                return;
            case BookmarkIcon.KEY_DEFAULTS: context.add_class ("key");
                                            context.add_class ("gsettings-key");
                return;
            case BookmarkIcon.EDITED_VALUE: context.add_class ("key");
                                            context.add_class ("gsettings-key");
                                            context.add_class ("edited");
                return;
            default: assert_not_reached ();
        }
    }

    /*\
    * * Action entries
    \*/

    bool actions_init_done = false;
    private SimpleAction move_top_action;
    private SimpleAction move_up_action;
    private SimpleAction move_down_action;
    private SimpleAction move_bottom_action;
    private SimpleAction trash_bookmark_action;

    private void update_actions ()
        requires (actions_init_done)
    {
        List<weak ListBoxRow> selected_rows = bookmarks_list_box.get_selected_rows ();
        uint n_selected_rows = selected_rows.length ();

        bool has_selected_items = n_selected_rows > 0;
        bool has_one_selected_item = n_selected_rows == 1;

        bool enable_move_top_action     = has_one_selected_item;    // TODO has_selected_items;
        bool enable_move_up_action      = has_one_selected_item;
        bool enable_move_down_action    = has_one_selected_item;
        bool enable_move_bottom_action  = has_one_selected_item;    // TODO has_selected_items;

        if (has_one_selected_item)
        {
            int index = selected_rows.nth_data (0).get_index ();
            if (index == 0)
            {
                enable_move_top_action = false;
                enable_move_up_action = false;
            }
            if (bookmarks_list_box.get_row_at_index (index + 1) == null)
            {
                enable_move_down_action = false;
                enable_move_bottom_action = false;
            }
        }

               move_up_action.set_enabled (enable_move_up_action);
              move_top_action.set_enabled (enable_move_top_action);
             move_down_action.set_enabled (enable_move_down_action);
           move_bottom_action.set_enabled (enable_move_bottom_action);
        trash_bookmark_action.set_enabled (has_selected_items);
    }

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("bookmarks", action_group);

        move_top_action         = (SimpleAction) action_group.lookup_action ("move-top");
        move_up_action          = (SimpleAction) action_group.lookup_action ("move-up");
        move_down_action        = (SimpleAction) action_group.lookup_action ("move-down");
        move_bottom_action      = (SimpleAction) action_group.lookup_action ("move-bottom");
        trash_bookmark_action   = (SimpleAction) action_group.lookup_action ("trash-bookmark");
        actions_init_done = true;
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "enter-edit-mode", enter_edit_mode },
        { "leave-edit-mode", leave_edit_mode },

        { "trash-bookmark", trash_bookmark },
        { "set-small-rows", set_small_rows },

        { "move-top",    move_top    },
        { "move-up",     move_up     },
        { "move-down",   move_down   },
        { "move-bottom", move_bottom },

        {   "bookmark",    bookmark, "(sy)" },
        { "unbookmark",  unbookmark, "(sy)" }
    };

    private void enter_edit_mode (/* SimpleAction action, Variant? variant */)
    {
        enter_edit_mode_button.hide ();
        bookmarks_popover.get_style_context ().add_class ("edit-mode");
        update_actions ();

        edit_mode_stack.set_visible_child_name ("edit-mode-on");
        leave_edit_mode_button.grab_focus ();

        bookmarks_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (false); });
        bookmarks_list_box.set_activate_on_single_click (false);
        bookmarks_list_box.set_selection_mode (SelectionMode.MULTIPLE);
    }

    private void leave_edit_mode (/* used both as action and method */)
    {
        ListBoxRow? row = (ListBoxRow?) bookmarks_list_box.get_focus_child ();  // broken, the child needs to have the global focus...
        bool give_focus_to_switch = row == null;
        if (give_focus_to_switch)
        {
            List<weak ListBoxRow> selected_rows = bookmarks_list_box.get_selected_rows ();
            row = selected_rows.nth_data (0);
        }

        bookmarks_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (true); });
        bookmarks_list_box.set_activate_on_single_click (true);
        bookmarks_list_box.set_selection_mode (SelectionMode.SINGLE);

        edit_mode_stack.set_visible_child_name ("edit-mode-off");

        bookmarks_popover.get_style_context ().remove_class ("edit-mode");
        enter_edit_mode_button.show ();

        if (row != null)
            select_row_for_real ((!) row);
        if (give_focus_to_switch)
            bookmarked_switch.grab_focus ();
    }

    private void trash_bookmark (/* SimpleAction action, Variant? variant */)
    {
        ListBoxRow? row = (ListBoxRow?) bookmarks_list_box.get_focus_child ();
        bool focused_row_will_survive = row != null && !((!) row).is_selected ();

        string [] bookmarks_to_remove = new string [0];
        int upper_index = int.MAX;
        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {
                if (!(selected_row is Bookmark))
                    assert_not_reached ();
                bookmarks_to_remove += ((Bookmark) selected_row).bookmark_name;

                if (focused_row_will_survive)
                    return;

                int index = selected_row.get_index ();
                if (upper_index > index)
                    upper_index = index;
            });
        if (upper_index == int.MAX)
            assert_not_reached ();

        if (!focused_row_will_survive)
        {
            row = bookmarks_list_box.get_row_at_index (upper_index + 1);
            if (row == null)
            {
                if (upper_index > 0)
                    row = bookmarks_list_box.get_row_at_index (upper_index - 1);
                // TODO else quit mode
            }
        }
        if (row != null)
            bookmarks_list_box.select_row ((!) row);

        remove_bookmarks (settings, bookmarks_to_remove);
        update_bookmarks_icons (settings.get_value ("bookmarks"));
    }

    private void set_small_rows (/* SimpleAction action, Variant? variant */)
    {
        settings.set_boolean ("small-bookmarks-rows", rows_size_button.get_image () == small_rows_icon);
    }
    private void update_rows_size_button_icon (bool small_bookmarks_rows)
    {
        if (small_bookmarks_rows)
            rows_size_button.set_image (big_rows_icon);
        else
            rows_size_button.set_image (small_rows_icon);
    }

    private void move_top       (/* SimpleAction action, Variant? variant */)
    {
//        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {

        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        if (index == 0)
            return;
        bookmarks_list_box.remove ((!) row);
        bookmarks_list_box.prepend ((!) row);
        select_row_for_real ((!) row);

        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_lower ());

        update_bookmarks_after_move ();
    }

    private void move_up        (/* SimpleAction action, Variant? variant */)
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        if (index == 0)
            return;

        ListBoxRow? prev_row = bookmarks_list_box.get_row_at_index (index - 1);
        if (prev_row == null)
            assert_not_reached ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        Widget? row_child = ((!) prev_row).get_child ();    // using prev_row as the allocation is not updated anyway
        if (row_child == null)
            assert_not_reached ();
        ((!) row_child).get_allocation (out row_allocation);
        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        int proposed_adjustemnt_value = row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 3.0);
        bool should_adjust = adjustment.get_value () > proposed_adjustemnt_value;

        bookmarks_list_box.unselect_row ((!) row);
        bookmarks_list_box.remove ((!) prev_row);

        if (should_adjust)
            adjustment.set_value (proposed_adjustemnt_value);

        bookmarks_list_box.insert ((!) prev_row, index);
        bookmarks_list_box.select_row ((!) row);

        update_bookmarks_after_move ();
    }

    private void move_down      (/* SimpleAction action, Variant? variant */)
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        ListBoxRow? next_row = bookmarks_list_box.get_row_at_index (index + 1);
        if (next_row == null)
            return;

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        Widget? row_child = ((!) next_row).get_child ();    // using next_row as the allocation is not updated
        if (row_child == null)
            assert_not_reached ();
        ((!) row_child).get_allocation (out row_allocation);
        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        int proposed_adjustemnt_value = row_allocation.y + (int) (2 * (row_allocation.height - list_allocation.height) / 3.0);
        bool should_adjust = adjustment.get_value () < proposed_adjustemnt_value;

        bookmarks_list_box.unselect_row ((!) row);
        bookmarks_list_box.remove ((!) next_row);

        if (should_adjust)
            adjustment.set_value (proposed_adjustemnt_value);

        bookmarks_list_box.insert ((!) next_row, index);
        bookmarks_list_box.select_row ((!) row);

        update_bookmarks_after_move ();
    }

    private void move_bottom    (/* SimpleAction action, Variant? variant */)
    {
//        bookmarks_list_box.selected_foreach ((_list_box, selected_row) => {

        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            return; // TODO assert_not_reached?

        int index = ((!) row).get_index ();
        if (index < 0)
            assert_not_reached ();

        bookmarks_list_box.remove ((!) row);
        bookmarks_list_box.insert ((!) row, -1);
        select_row_for_real ((!) row);

        Adjustment adjustment = bookmarks_list_box.get_adjustment ();
        adjustment.set_value (adjustment.get_upper ());

        update_bookmarks_after_move ();
    }
    private void select_row_for_real (ListBoxRow row)   // ahem...
    {
        bookmarks_list_box.unselect_row (row);
        bookmarks_list_box.select_row (row);
    }

    private void bookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 1/2

        string bookmark;
        uint8 type;
        ((!) path_variant).@get ("(sy)", out bookmark, out type);
        append_bookmark (settings, get_bookmark_name (bookmark, ViewType.from_byte (type)));
    }

    private void unbookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 2/2

        string bookmark;
        uint8 type;
        ((!) path_variant).@get ("(sy)", out bookmark, out type);
        remove_bookmark (settings, get_bookmark_name (bookmark, ViewType.from_byte (type)));
    }

    /*\
    * * Bookmarks management
    \*/

    private void update_bookmarks_after_move ()
    {
        string [] new_bookmarks = new string [0];
        bookmarks_list_box.@foreach ((widget) => { new_bookmarks += ((Bookmark) widget).bookmark_name; });

        string [] old_bookmarks = settings.get_strv ("bookmarks");  // be cool :-)
        foreach (string bookmark in old_bookmarks)
            if (!(bookmark in new_bookmarks))
                new_bookmarks += bookmark;

        SignalHandler.block (settings, bookmarks_changed_handler);
        settings.set_strv ("bookmarks", new_bookmarks);
        GLib.Settings.sync ();   // TODO better? really needed?
        SignalHandler.unblock (settings, bookmarks_changed_handler);
    }

    private const string bookmark_this_search_text = _("Bookmark this Search");
    private const string bookmark_this_location_text = _("Bookmark this Location");
    private static void update_switch_label (ViewType old_type, ViewType new_type, ref Label switch_label)
    {
        if (new_type == ViewType.SEARCH && old_type != ViewType.SEARCH)
            switch_label.label = bookmark_this_search_text;
        else if (new_type != ViewType.SEARCH && old_type == ViewType.SEARCH)
            switch_label.label = bookmark_this_location_text;
    }

    private void update_icon_and_switch (Variant bookmarks_variant)
    {
        Variant variant = new Variant ("(sy)", current_path, ViewType.to_byte (current_type));
        string bookmark_name = get_bookmark_name (current_path, current_type);
        if (bookmark_name in bookmarks_variant.get_strv ())
        {
            if (bookmarks_icon.icon_name != "starred-symbolic")
                bookmarks_icon.icon_name = "starred-symbolic";
            update_switch_state (true, ref bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.unbookmark(" + variant.print (true) + ")");
        }
        else
        {
            if (bookmarks_icon.icon_name != "non-starred-symbolic")
                bookmarks_icon.icon_name = "non-starred-symbolic";
            update_switch_state (false, ref bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.bookmark(" + variant.print (true) + ")");
        }
    }
    private static void update_switch_state (bool bookmarked, ref Switch bookmarked_switch)
    {
        if (bookmarked == bookmarked_switch.active)
            return;
        bookmarked_switch.set_detailed_action_name ("ui.empty(('',byte 255))");
        bookmarked_switch.active = bookmarked;
    }

    private bool has_empty_list_class = false;
    private void update_bookmarks (Variant bookmarks_variant)
    {
        set_detailed_action_name ("ui.update-bookmarks-icons(" + bookmarks_variant.print (true) + ")");  // TODO disable action on popover closed
        create_bookmark_rows (bookmarks_variant, ref bookmarks_list_box, ref bookmarks_hashtable, ref last_row, ref n_bookmarks);
        if (n_bookmarks == 0)
        {
            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-on")
                leave_edit_mode ();

            if (!has_empty_list_class)
            {
                bookmarks_list_box.get_style_context ().add_class ("empty-list");
                has_empty_list_class = true;
            }

            enter_edit_mode_button.hide ();
        }
        else
        {
            if (has_empty_list_class)
            {
                bookmarks_list_box.get_style_context ().remove_class ("empty-list");
                has_empty_list_class = false;
            }

            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-off")
                enter_edit_mode_button.show ();
        }
    }
    private static void create_bookmark_rows (Variant bookmarks_variant, ref ListBox bookmarks_list_box, ref HashTable<string, Bookmark> bookmarks_hashtable, ref Bookmark? last_row, ref uint n_bookmarks)
    {
        string saved_bookmark_name = "";
        ListBoxRow? selected_row = bookmarks_list_box.get_selected_row ();
        if (selected_row != null && ((!) selected_row) is Bookmark)
            saved_bookmark_name = ((Bookmark) (!) selected_row).bookmark_name;
        selected_row = null;

        bookmarks_list_box.@foreach ((widget) => widget.destroy ());
        bookmarks_hashtable.remove_all ();
        last_row = null;
        n_bookmarks = 0;

        string [] bookmarks = bookmarks_variant.get_strv ();
        string [] unduplicated_bookmarks = new string [0];
        foreach (string bookmark in bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;

            Bookmark bookmark_row = new Bookmark (bookmark);
            bookmarks_list_box.add (bookmark_row);
            bookmark_row.show ();
            bookmarks_hashtable.insert (bookmark, bookmark_row);
            last_row = bookmark_row;

            if (saved_bookmark_name == bookmark)
                selected_row = bookmark_row;
            n_bookmarks ++;
        }

        if (selected_row == null)
            selected_row = bookmarks_list_box.get_row_at_index (0);
        if (selected_row != null)
            bookmarks_list_box.select_row ((!) selected_row);
    }

    private static void append_bookmark (GLib.Settings settings, string bookmark_name)
    {
        string [] bookmarks = settings.get_strv ("bookmarks");
        if (bookmark_name in bookmarks)
            return;

        bookmarks += bookmark_name;
        settings.set_strv ("bookmarks", bookmarks);
    }

    private static void remove_bookmark (GLib.Settings settings, string bookmark_name)
    {
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        if (!(bookmark_name in old_bookmarks))
            return;

        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != bookmark_name && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }

    private static void remove_bookmarks (GLib.Settings settings, string [] bookmarks_to_remove)
    {
        string [] old_bookmarks = settings.get_strv ("bookmarks");

        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (!(bookmark in bookmarks_to_remove) && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }

    internal static inline string get_bookmark_name (string path, ViewType type)
    {
        if (type == ViewType.SEARCH)
            return "?" + path;
        else
            return path;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : ListBoxRow
{
    [GtkChild] private Label bookmark_label;

    public string bookmark_name { internal get; internal construct; }

    construct
    {
        string bookmark_text;
        ViewType bookmark_type;
        parse_bookmark_name (bookmark_name, out bookmark_text, out bookmark_type);

        construct_actions_names (bookmark_text, bookmark_type, out detailed_action_name, out inactive_action_name);
        set_actionable (true);

        bookmark_label.set_label (bookmark_text);
    }

    internal Bookmark (string bookmark_name)
    {
        Object (bookmark_name: bookmark_name);
    }

    internal void set_actionable (bool actionable)
    {
        if (actionable)
            set_detailed_action_name (detailed_action_name);
        else
            set_detailed_action_name (inactive_action_name);
    }

    /*\
    * * Actions names
    \*/

    private string detailed_action_name;
    private string inactive_action_name;

    private static void construct_actions_names (string     bookmark_text,
                                                 ViewType   bookmark_type,
                                             out string     detailed_action_name,
                                             out string     inactive_action_name)
    {
        switch (bookmark_type)
        {
            case ViewType.SEARCH:
                Variant variant = new Variant.string (bookmark_text);
                detailed_action_name = "ui.open-search(" + variant.print (false) + ")";
                inactive_action_name = "ui.empty('')";
                return;

            case ViewType.FOLDER:
                Variant variant = new Variant.string (bookmark_text);
                detailed_action_name = "ui.open-folder(" + variant.print (false) + ")";
                inactive_action_name = "ui.empty('')";
                return;

            case ViewType.OBJECT:
                Variant variant = new Variant ("(sq)", bookmark_text, ModelUtils.undefined_context_id);  // TODO save context
                detailed_action_name = "ui.open-object(" + variant.print (true) + ")";
                inactive_action_name = "ui.empty(('',uint16 65535))";
                return;

            case ViewType.CONFIG:
            default: assert_not_reached ();
        }
    }

    private static void parse_bookmark_name (string     bookmark_name,
                                         out string     bookmark_text,
                                         out ViewType   bookmark_type)
    {
        if (bookmark_name.has_prefix ("?"))
        {
            bookmark_text = bookmark_name.slice (1, bookmark_name.length);
            bookmark_type = ViewType.SEARCH;
        }
        else if (ModelUtils.is_folder_path (bookmark_name))
        {
            bookmark_text = bookmark_name;
            bookmark_type = ViewType.FOLDER;
        }
        else
        {
            bookmark_text = bookmark_name;
            bookmark_type = ViewType.OBJECT;
        }
    }
}
