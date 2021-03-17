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
    [GtkChild] private unowned Image                bookmarks_icon;
    [GtkChild] private unowned Popover              bookmarks_popover;
    [GtkChild] private unowned Stack                edit_mode_stack;
    [GtkChild] private unowned BookmarksList        bookmarks_list;
    [GtkChild] private unowned Switch               bookmarked_switch;
    [GtkChild] private unowned Label                switch_label;
    [GtkChild] private unowned BookmarksController  bookmarks_controller;

    private string   current_path = "/";
    private ViewType current_type = ViewType.FOLDER;

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    GLib.Settings settings;
    [CCode (notify = false)] public string schema_path
    {
        construct
        {
            bookmarks_list.schema_path = value;

            settings = new GLib.Settings.with_path (schema_id, value);

            StyleContext context = bookmarks_popover.get_style_context ();
            bool has_small_bookmarks_rows_class = false;
            ulong small_bookmarks_rows_handler = settings.changed ["small-bookmarks-rows"].connect (() => {
                    bool small_bookmarks_rows = settings.get_boolean ("small-bookmarks-rows");
                    if (small_bookmarks_rows)
                    {
                        if (!has_small_bookmarks_rows_class) context.add_class ("small-bookmarks-rows");
                    }
                    else if (has_small_bookmarks_rows_class) context.remove_class ("small-bookmarks-rows");
                    has_small_bookmarks_rows_class = small_bookmarks_rows;
                    bookmarks_controller.update_rows_size_button_icon (small_bookmarks_rows);
                });

            has_small_bookmarks_rows_class = settings.get_boolean ("small-bookmarks-rows");
            if (has_small_bookmarks_rows_class)
                context.add_class ("small-bookmarks-rows");
            bookmarks_controller.update_rows_size_button_icon (has_small_bookmarks_rows_class);

            destroy.connect (() => settings.disconnect (small_bookmarks_rows_handler));
        }
    }

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    [GtkCallback]
    private void on_update_bookmarks_icons (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    construct
    {
        update_switch_label (ViewType.SEARCH, ViewType.FOLDER, switch_label); // init text with "Bookmark this Location"

        install_action_entries ();

        clicked.connect (() => { if (active) bookmarked_switch.grab_focus (); });
    }

    internal Bookmarks (string _schema_path)
    {
        Object (schema_path: _schema_path);
    }

    [GtkCallback]
    private void on_bookmarks_changed (Variant bookmarks_variant, bool writable)
    {
        set_detailed_action_name ("bw.update-bookmarks-icons(" + bookmarks_variant.print (true) + ")");  // TODO disable action on popover closed

        if (bookmarks_variant.get_strv ().length == 0)
        {
            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-on")
                leave_edit_mode ();
        }

        update_icon_and_switch (bookmarks_variant);
        set_switch_sensitivity (writable);
    }

    [GtkCallback]
    private void on_writability_changed (bool writable)
    {
        set_switch_sensitivity (writable);
    }

    private void set_switch_sensitivity (bool writable)
    {
        if (writable)
        {
            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-disabled")
                edit_mode_stack.set_visible_child_name ("edit-mode-off");
        }
        else
        {
            edit_mode_stack.set_visible_child_name ("edit-mode-disabled");
            bookmarks_list.grab_focus ();
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
                    bookmarks_list.select_all ();
                    return true;
                }
                if (name == "A")
                {
                    bookmarks_list.unselect_all ();
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
        if (actions_init_done)
            update_actions ();
    }

    /*\
    * * Public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        update_switch_label (current_type, type, switch_label);

        current_path = path;
        current_type = type;

        update_icon_and_switch (bookmarks_list.get_bookmarks_as_variant ());
    }

    // for search
    internal string [] get_bookmarks ()
    {
        return bookmarks_list.get_bookmarks_as_array ();
    }

    // keyboard call

    internal bool next_match ()
        requires (active)
    {
        return bookmarks_list.next_match ();
    }

    internal bool previous_match ()
        requires (active)
    {
        return bookmarks_list.previous_match ();
    }

    internal bool handle_copy_text (out string copy_text)
    {
        return bookmarks_list.handle_copy_text (out copy_text);
    }

    internal void bookmark_current_path ()
    {
        if (bookmarked_switch.get_active ())
            return;
        bookmarks_list.append_bookmark (current_type, current_path);
    }

    internal void unbookmark_current_path ()
    {
        if (!bookmarked_switch.get_active ())
            return;
        bookmarks_list.remove_bookmark (current_type, current_path);
    }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        bookmarks_list.update_bookmark_icon (bookmark, icon);
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
    private SimpleAction edit_mode_state_action;

    private void update_actions ()
        requires (actions_init_done)
    {
        _update_actions (bookmarks_list.get_selection_state (), ref move_top_action, ref move_up_action, ref move_down_action, ref move_bottom_action, ref trash_bookmark_action);
    }

    internal static void _update_actions (OverlayedList.SelectionState selection_state, ref SimpleAction move_top_action, ref SimpleAction move_up_action, ref SimpleAction move_down_action, ref SimpleAction move_bottom_action, ref SimpleAction trash_bookmark_action)
    {
        trash_bookmark_action.set_enabled (selection_state != OverlayedList.SelectionState.EMPTY);

        bool one_middle_selection = selection_state == OverlayedList.SelectionState.MIDDLE;
        bool enable_move_up_action      = one_middle_selection || (selection_state == OverlayedList.SelectionState.LAST);
        bool enable_move_down_action    = one_middle_selection || (selection_state == OverlayedList.SelectionState.FIRST);
        move_up_action.set_enabled     (enable_move_up_action);
        move_down_action.set_enabled   (enable_move_down_action);

        bool multiple_middle_selections = selection_state == OverlayedList.SelectionState.MULTIPLE;
        move_top_action.set_enabled    ((selection_state == OverlayedList.SelectionState.MULTIPLE_LAST)
                                        || multiple_middle_selections
                                        || enable_move_up_action);
        move_bottom_action.set_enabled ((selection_state == OverlayedList.SelectionState.MULTIPLE_FIRST)
                                        || multiple_middle_selections
                                        || enable_move_down_action);
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
        edit_mode_state_action  = (SimpleAction) action_group.lookup_action ("set-edit-mode");
        actions_init_done = true;
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "set-edit-mode", set_edit_mode, "b", "false" },

        { "trash-bookmark", trash_bookmark },
        { "set-small-rows", set_small_rows },

        { "move-top",    move_top    },
        { "move-up",     move_up     },
        { "move-down",   move_down   },
        { "move-bottom", move_bottom },

        {   "bookmark",    bookmark, "(ys)" },
        { "unbookmark",  unbookmark, "(ys)" }
    };

    private void set_edit_mode (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        bool new_state = ((!) variant).get_boolean ();
        action.set_state (new_state);

        if (new_state)
            enter_edit_mode ();
        else
            leave_edit_mode ();
    }

    private void enter_edit_mode ()
    {
        edit_mode_state_action.set_state (true);

        edit_mode_stack.set_visible_child_name ("edit-mode-on");
        bookmarks_list.enter_edit_mode ();
    }

    [GtkCallback]
    private void leave_edit_mode (/* used both as action and callback */)
    {
        edit_mode_state_action.set_state (false);

        bool give_focus_to_switch = bookmarks_list.leave_edit_mode ();
        edit_mode_stack.set_visible_child_name ("edit-mode-off");

        if (give_focus_to_switch)
            bookmarked_switch.grab_focus ();
    }

    private void trash_bookmark (/* SimpleAction action, Variant? variant */)
    {
        bookmarks_list.trash_bookmark ();
    }

    private void set_small_rows (/* SimpleAction action, Variant? variant */)
    {
        settings.set_boolean ("small-bookmarks-rows", bookmarks_controller.get_small_rows_state ());
    }

    private void move_top       (/* SimpleAction action, Variant? variant */)
    {
        bookmarks_list.move_top ();
    }

    private void move_up        (/* SimpleAction action, Variant? variant */)
    {
        bookmarks_list.move_up ();
    }

    private void move_down      (/* SimpleAction action, Variant? variant */)
    {
        bookmarks_list.move_down ();
    }

    private void move_bottom    (/* SimpleAction action, Variant? variant */)
    {
        bookmarks_list.move_bottom ();
    }

    private void bookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 1/2

        uint8 type;
        string bookmark;
        ((!) path_variant).@get ("(ys)", out type, out bookmark);
        bookmarks_list.append_bookmark (ViewType.from_byte (type), bookmark);
    }

    private void unbookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 2/2

        uint8 type;
        string bookmark;
        ((!) path_variant).@get ("(ys)", out type, out bookmark);
        bookmarks_list.remove_bookmark (ViewType.from_byte (type), bookmark);
    }

    /*\
    * * Bookmarks management
    \*/

    private static void update_switch_label (ViewType old_type, ViewType new_type, Label switch_label)
    {
        if (new_type == ViewType.SEARCH && old_type != ViewType.SEARCH)
            switch_label.label = bookmark_this_search_text;
        else if (new_type != ViewType.SEARCH && old_type == ViewType.SEARCH)
            switch_label.label = bookmark_this_location_text;
    }

    /* Translators: label of the switch in the bookmarks popover, when searching */
    private const string bookmark_this_search_text = _("Bookmark this Search");

    /* Translators: label of the switch in the bookmarks popover, when browsing */
    private const string bookmark_this_location_text = _("Bookmark this Location");

    private void update_icon_and_switch (Variant bookmarks_variant)
    {
        Variant variant = new Variant ("(ys)", ViewType.to_byte (current_type), current_path);
        string bookmark_name = BookmarksList.get_bookmark_name (current_type, current_path);
        if (bookmark_name in bookmarks_variant.get_strv ())
        {
            if (bookmarks_icon.icon_name != "starred-symbolic")
                bookmarks_icon.icon_name = "starred-symbolic";
            update_switch_state (true, bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.unbookmark(" + variant.print (true) + ")");
        }
        else
        {
            if (bookmarks_icon.icon_name != "non-starred-symbolic")
                bookmarks_icon.icon_name = "non-starred-symbolic";
            update_switch_state (false, bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.bookmark(" + variant.print (true) + ")");
        }
    }
    private static void update_switch_state (bool bookmarked, Switch bookmarked_switch)
    {
        if (bookmarked == bookmarked_switch.active)
            return;
        bookmarked_switch.set_detailed_action_name ("browser.empty((byte 255,''))");
        bookmarked_switch.active = bookmarked;
    }
}
