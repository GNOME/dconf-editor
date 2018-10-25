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
    [GtkChild] private Image                bookmarks_icon;
    [GtkChild] private Popover              bookmarks_popover;
    [GtkChild] private Stack                edit_mode_stack;
    [GtkChild] private BookmarksList        bookmarks_list;
    [GtkChild] private Switch               bookmarked_switch;
    [GtkChild] private Label                switch_label;
    [GtkChild] private BookmarksController  bookmarks_controller;

    private string   current_path = "/";
    private ViewType current_type = ViewType.FOLDER;

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    public string schema_path { private get; internal construct; }
    private GLib.Settings settings;
    ulong bookmarks_changed_handler = 0;

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
                bookmarks_controller.update_rows_size_button_icon (small_bookmarks_rows);
            });
        has_small_bookmarks_rows_class = settings.get_boolean ("small-bookmarks-rows");
        if (has_small_bookmarks_rows_class)
            context.add_class ("small-bookmarks-rows");
        bookmarks_controller.update_rows_size_button_icon (has_small_bookmarks_rows_class);
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
        bookmarks_list.down_pressed ();
    }

    internal void up_pressed ()
        requires (active)
    {
        bookmarks_list.up_pressed ();
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
        BookmarksList.SelectionState selection_state = bookmarks_list.get_selection_state ();

        bool has_selected_items = selection_state != BookmarksList.SelectionState.EMPTY;
        bool has_one_selected_item = has_selected_items && (selection_state != BookmarksList.SelectionState.MULTIPLE);

        bool enable_move_top_action     = has_one_selected_item;    // TODO has_selected_items;
        bool enable_move_up_action      = has_one_selected_item;
        bool enable_move_down_action    = has_one_selected_item;
        bool enable_move_bottom_action  = has_one_selected_item;    // TODO has_selected_items;

        if (has_one_selected_item)
        {
            if (selection_state == BookmarksList.SelectionState.UNIQUE || selection_state == BookmarksList.SelectionState.FIRST)
            {
                enable_move_top_action = false;
                enable_move_up_action = false;
            }
            if (selection_state == BookmarksList.SelectionState.UNIQUE || selection_state == BookmarksList.SelectionState.LAST)
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

        {   "bookmark",    bookmark, "(sy)" },
        { "unbookmark",  unbookmark, "(sy)" }
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

        update_actions ();

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
        string [] bookmarks_to_remove;
        bookmarks_list.trash_bookmark (out bookmarks_to_remove);

        remove_bookmarks (settings, bookmarks_to_remove);
        update_bookmarks_icons (settings.get_value ("bookmarks"));
    }

    private void set_small_rows (/* SimpleAction action, Variant? variant */)
    {
        settings.set_boolean ("small-bookmarks-rows", bookmarks_controller.get_small_rows_state ());
    }

    private void move_top       (/* SimpleAction action, Variant? variant */)
    {
        if (bookmarks_list.move_top ())
            return;
        update_bookmarks_after_move ();
    }

    private void move_up        (/* SimpleAction action, Variant? variant */)
    {
        if (bookmarks_list.move_up ())
            return;
        update_bookmarks_after_move ();
    }

    private void move_down      (/* SimpleAction action, Variant? variant */)
    {
        if (bookmarks_list.move_down ())
            return;
        update_bookmarks_after_move ();
    }

    private void move_bottom    (/* SimpleAction action, Variant? variant */)
    {
        if (bookmarks_list.move_bottom ())
            return;
        update_bookmarks_after_move ();
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
        string [] new_bookmarks = bookmarks_list.get_bookmarks ();

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

    private void update_bookmarks (Variant bookmarks_variant)
    {
        set_detailed_action_name ("ui.update-bookmarks-icons(" + bookmarks_variant.print (true) + ")");  // TODO disable action on popover closed
        bool no_bookmarks = bookmarks_list.create_bookmark_rows (bookmarks_variant);
        if (no_bookmarks)
        {
            string? visible_child_name = edit_mode_stack.get_visible_child_name (); // do it like that
            if (visible_child_name != null && (!) visible_child_name == "edit-mode-on")
                leave_edit_mode ();
        }
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
