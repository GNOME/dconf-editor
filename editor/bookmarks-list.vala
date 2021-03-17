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

private class BookmarksList : OverlayedList
{
    private HashTable<string, Bookmark> bookmarks_hashtable = new HashTable<string, Bookmark> (str_hash, str_equal);

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    private GLib.Settings settings;
    ulong bookmarks_changed_handler = 0;

    construct
    {
        placeholder_icon = "starred-symbolic";
        /* Translators: placeholder text of the bookmarks list, displayed when the user has no bookmarks */
        placeholder_text = _("Bookmarks will\nbe added here");
        add_placeholder ();

        /* Translators: label of one of the two buttons of the bookmarks list, to switch between using the bookmarks and editing the list; the second is "Edit" */
        first_mode_name = _("Use");
        /* Translators: label of one of the two buttons of the bookmarks list, to switch between using the bookmarks and editing the list; the first is "Use" */
        second_mode_name = _("Edit");
    }

    internal BookmarksList (bool needs_shadows, bool big_placeholder, string edit_mode_action_prefix, string schema_path)
    {
        Object (needs_shadows           : needs_shadows,
                big_placeholder         : big_placeholder,
                edit_mode_action_prefix : edit_mode_action_prefix,
                schema_path             : schema_path);
    }

    internal override void reset ()
    {
    }

    public string schema_path
    {
        internal set
        {
            settings = new GLib.Settings.with_path (schema_id, value);

            bookmarks_changed_handler = settings.changed ["bookmarks"].connect (on_bookmarks_changed);
            ulong bookmarks_writable_handler = settings.writable_changed ["bookmarks"].connect (on_writability_changed);

            Variant bookmarks_variant = settings.get_value ("bookmarks");
            bool is_writable = settings.is_writable ("bookmarks");

            create_bookmark_rows (bookmarks_variant);
            change_editability (is_writable);

            bookmarks_changed (bookmarks_variant, is_writable);

            destroy.connect (() => {
                    settings.disconnect (bookmarks_changed_handler);
                    settings.disconnect (bookmarks_writable_handler);
                });
        }
    }

    internal signal void bookmarks_changed (Variant bookmarks_variant, bool writable);
    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    private void on_bookmarks_changed (GLib.Settings _settings, string key)
    {
        Variant bookmarks_variant = _settings.get_value (key);
        create_bookmark_rows (bookmarks_variant);
        update_bookmarks_icons (bookmarks_variant); // FIXME flickering
        bookmarks_changed (bookmarks_variant, _settings.is_writable (key));
    }

    internal signal void writability_changed (bool writable);
    private void on_writability_changed (GLib.Settings _settings, string key)
    {
        bool is_writable = _settings.is_writable (key);
        writability_changed (is_writable);
        change_editability (is_writable);
    }

    bool view_mode = true;
    internal void enter_edit_mode ()
    {
        main_list_box.grab_focus ();

        main_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (false); });
        main_list_box.set_activate_on_single_click (false);
        main_list_box.set_selection_mode (SelectionMode.MULTIPLE);
        view_mode = false;
    }

    internal bool leave_edit_mode ()
    {
        ListBoxRow? row = (ListBoxRow?) main_list_box.get_focus_child ();  // broken, the child needs to have the global focus...
        bool give_focus_to_switch = row == null;
        if (give_focus_to_switch)
        {
            List<weak ListBoxRow> selected_rows = main_list_box.get_selected_rows ();
            row = selected_rows.nth_data (0);
        }

        main_list_box.@foreach ((widget) => { ((Bookmark) widget).set_actionable (true); });
        main_list_box.set_activate_on_single_click (true);
        main_list_box.set_selection_mode (SelectionMode.SINGLE);
        view_mode = true;

        if (row != null)
            select_row_for_real ((!) row);

        return give_focus_to_switch;
    }

    internal Variant get_bookmarks_as_variant ()
    {
        return settings.get_value ("bookmarks");
    }

    internal string [] get_bookmarks_as_array ()
    {
        string [] all_bookmarks = settings.get_strv ("bookmarks");
        string [] unduplicated_bookmarks = {};
        foreach (string bookmark in all_bookmarks)
        {
            if (BrowserWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;
        }
        return unduplicated_bookmarks;
    }

    internal bool create_bookmark_rows (Variant bookmarks_variant)
    {
        _create_bookmark_rows (bookmarks_variant, view_mode, ref main_list_store, main_list_box, ref bookmarks_hashtable);
        return n_items == 0;
    }
    private static void _create_bookmark_rows (Variant bookmarks_variant, bool view_mode, ref GLib.ListStore main_list_store, ListBox main_list_box, ref HashTable<string, Bookmark> bookmarks_hashtable)
    {
        string saved_bookmark_name = "";
        ListBoxRow? selected_row = main_list_box.get_selected_row ();
        if (selected_row != null && ((!) selected_row) is Bookmark)
            saved_bookmark_name = ((Bookmark) (!) selected_row).bookmark_name;
        selected_row = null;

        main_list_store.remove_all ();
        bookmarks_hashtable.remove_all ();

        string [] bookmarks = bookmarks_variant.get_strv ();
        string [] unduplicated_bookmarks = new string [0];
        foreach (string bookmark in bookmarks)
        {
            if (BrowserWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;

            Bookmark bookmark_row = new Bookmark (bookmark, view_mode);
            main_list_store.append (bookmark_row);
            bookmark_row.show ();
            bookmarks_hashtable.insert (bookmark, bookmark_row);

            if (saved_bookmark_name == bookmark)
                selected_row = bookmark_row;
        }

        if (selected_row == null)
            selected_row = main_list_box.get_row_at_index (0);
        if (selected_row != null)
            main_list_box.select_row ((!) selected_row);
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
    * * remote action entries
    \*/

    internal void trash_bookmark ()
    {
        ListBoxRow? row = (ListBoxRow?) main_list_box.get_focus_child ();
        bool focused_row_will_survive = row != null && !((!) row).is_selected ();

        string [] bookmarks_to_remove = new string [0];
        int upper_index = int.MAX;
        main_list_box.selected_foreach ((_list_box, selected_row) => {
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
            row = main_list_box.get_row_at_index (upper_index + 1);
            if (row == null)
            {
                if (upper_index > 0)
                    row = main_list_box.get_row_at_index (upper_index - 1);
                // TODO else quit mode
            }
        }
        if (row != null)
            main_list_box.select_row ((!) row);

        remove_bookmarks (settings, bookmarks_to_remove);
        update_bookmarks_icons (settings.get_value ("bookmarks"));
    }

    internal void move_top ()
    {
        int [] indices = get_selected_rows_indices ();

        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];

        foreach (int index in indices)
            new_bookmarks += old_bookmarks [index];

        for (int index = 0; index < old_bookmarks.length; index++)
        {
            if (index in indices)
                continue;
            new_bookmarks += old_bookmarks [index];
        }

        set_new_bookmarks (new_bookmarks);
        scroll_top ();
    }

    internal void move_up ()
    {
        int [] indices = get_selected_rows_indices ();
        if (indices.length != 1)
            return; // TODO assert_not_reached?
        int index = indices [0];

        if (index == 0)
            return; // TODO assert_not_reached?

//        ListBoxRow? prev_row = main_list_box.get_row_at_index (index - 1);
//        if (prev_row == null)
//            assert_not_reached ();
//
//        Allocation list_allocation, row_allocation;
//        scrolled.get_allocation (out list_allocation);
//        Widget? row_child = ((!) prev_row).get_child ();    // using prev_row as the allocation is not updated anyway
//        if (row_child == null)
//            assert_not_reached ();
//        ((!) row_child).get_allocation (out row_allocation);
//        Adjustment adjustment = main_list_box.get_adjustment ();
//        int proposed_adjustment_value = row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 3.0);
//        bool should_adjust = adjustment.get_value () > proposed_adjustment_value;

        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];
        uint position = 0;

        foreach (string bookmark in old_bookmarks)
        {
            if (index == position + 1)
                new_bookmarks += old_bookmarks [index];
            if (index != position)
                new_bookmarks += bookmark;
            position++;
        }

        set_new_bookmarks (new_bookmarks);

//        main_list_box.unselect_row ((!) row);

//        SignalHandler.block (main_list_store, content_changed_handler);
//        main_list_store.remove (index - 1);
//        main_list_box.remove ((!) prev_row);

//        if (should_adjust)
//            adjustment.set_value (proposed_adjustment_value);

//        main_list_store.insert (index, (!) prev_row);
//        SignalHandler.unblock (main_list_store, content_changed_handler);

//        main_list_box.select_row ((!) row);

//        update_bookmarks_after_move ();
    }

    internal void move_down ()
    {
        int [] indices = get_selected_rows_indices ();
        if (indices.length != 1)
            return; // TODO assert_not_reached?
        int index = indices [0];

//        ListBoxRow? next_row = main_list_box.get_row_at_index (index + 1);
//        if (next_row == null)
//            return; // TODO assert_not_reached?
//
//        Allocation list_allocation, row_allocation;
//        scrolled.get_allocation (out list_allocation);
//        Widget? row_child = ((!) next_row).get_child ();    // using next_row as the allocation is not updated
//        if (row_child == null)
//            assert_not_reached ();
//        ((!) row_child).get_allocation (out row_allocation);
//        Adjustment adjustment = main_list_box.get_adjustment ();
//        int proposed_adjustment_value = row_allocation.y + (int) (2 * (row_allocation.height - list_allocation.height) / 3.0);
//        bool should_adjust = adjustment.get_value () < proposed_adjustment_value;

        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];
        uint position = 0;

        foreach (string bookmark in old_bookmarks)
        {
            if (index != position)
                new_bookmarks += bookmark;
            if (position == index + 1)
                new_bookmarks += old_bookmarks [index];
            position++;
        }

        set_new_bookmarks (new_bookmarks);

//        main_list_box.unselect_row ((!) row);

//        SignalHandler.block (main_list_store, content_changed_handler);
//        main_list_store.remove (index - 1);
//        main_list_box.remove ((!) next_row);

//        if (should_adjust)
//            adjustment.set_value (proposed_adjustment_value);

//        main_list_store.insert (index, (!) next_row);
//        SignalHandler.unblock (main_list_store, content_changed_handler);

//        main_list_box.select_row ((!) row);

//        update_bookmarks_after_move ();
    }

    internal void move_bottom ()
    {
        int [] indices = get_selected_rows_indices ();

        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];

        for (int index = 0; index < old_bookmarks.length; index++)
        {
            if (index in indices)
                continue;
            new_bookmarks += old_bookmarks [index];
        }

        foreach (int index in indices)
            new_bookmarks += old_bookmarks [index];

        set_new_bookmarks (new_bookmarks);
        scroll_bottom ();
    }

    private void set_new_bookmarks (string [] new_bookmarks)
    {
        SignalHandler.block (main_list_store, content_changed_handler);
        SignalHandler.block (settings, bookmarks_changed_handler);
        settings.set_strv ("bookmarks", new_bookmarks);
        GLib.Settings.sync ();   // TODO better? really needed?
        SignalHandler.unblock (settings, bookmarks_changed_handler);
        SignalHandler.unblock (main_list_store, content_changed_handler);
        on_bookmarks_changed (settings, "bookmarks");
    }

    /*\
    * * Bookmarks management
    \*/

/*    private void update_bookmarks_after_move ()
    {
        string [] new_bookmarks = get_bookmarks_list (ref main_list_box);

        string [] old_bookmarks = settings.get_strv ("bookmarks");  // be cool :-)
        foreach (string bookmark in old_bookmarks)
            if (!(bookmark in new_bookmarks))
                new_bookmarks += bookmark;

        SignalHandler.block (settings, bookmarks_changed_handler);
        settings.set_strv ("bookmarks", new_bookmarks);
        GLib.Settings.sync ();   // TODO better? really needed?
        SignalHandler.unblock (settings, bookmarks_changed_handler);
    }
    private static string [] get_bookmarks_list (ref ListBox main_list_box)
    {
        string [] bookmarks = new string [0];
        main_list_box.@foreach ((widget) => { bookmarks += ((Bookmark) widget).bookmark_name; });
        return bookmarks;
    } */

    internal void append_bookmark (ViewType type, string bookmark)
    {
        _append_bookmark (settings, get_bookmark_name (type, bookmark));
    }
    private static void _append_bookmark (GLib.Settings settings, string bookmark_name)
    {
        string [] bookmarks = settings.get_strv ("bookmarks");
        if (bookmark_name in bookmarks)
            return;

        bookmarks += bookmark_name;
        settings.set_strv ("bookmarks", bookmarks);
    }

    internal void remove_bookmark (ViewType type, string bookmark)
    {
        _remove_bookmark (settings, get_bookmark_name (type, bookmark));
    }
    private static void _remove_bookmark (GLib.Settings settings, string bookmark_name)
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

    internal static inline string get_bookmark_name (ViewType type, string path)
    {
        if (type == ViewType.SEARCH)
            return "?" + path;
        else
            return path;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : OverlayedListRow
{
    [GtkChild] private unowned Label bookmark_label;

    [CCode (notify = false)] public string bookmark_name { internal get; internal construct; }

    construct
    {
        string bookmark_text;
        ViewType bookmark_type;
        parse_bookmark_name (bookmark_name, out bookmark_text, out bookmark_type);

        construct_actions_names (bookmark_text, bookmark_type, out detailed_action_name, out inactive_action_name);

        bookmark_label.set_label (bookmark_text);
    }

    internal Bookmark (string bookmark_name, bool view_mode)
    {
        Object (bookmark_name: bookmark_name);
        set_actionable (view_mode);
    }

    internal void set_actionable (bool actionable)
    {
        if (actionable)
            set_detailed_action_name (detailed_action_name);
        else
            set_detailed_action_name (inactive_action_name);
    }

    internal override bool handle_copy_text (out string copy_text)
    {
        copy_text = bookmark_name;
        return true;
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
                detailed_action_name = "browser.open-search(" + variant.print (false) + ")";
                inactive_action_name = "browser.empty('')";
                return;

            case ViewType.FOLDER:
                Variant variant = new Variant.string (bookmark_text);
                detailed_action_name = "browser.open-folder(" + variant.print (false) + ")";
                inactive_action_name = "browser.empty('')";
                return;

            case ViewType.OBJECT:
                Variant variant = new Variant ("(sq)", bookmark_text, ModelUtils.undefined_context_id);  // TODO save context
                detailed_action_name = "browser.open-object(" + variant.print (true) + ")";
                inactive_action_name = "browser.empty(('',uint16 65535))";
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
