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

private class BookmarksView : BrowserView, AdaptativeWidget
{
    construct
    {
        create_bookmarks_list ();
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);

        bookmarks_list.set_window_size (new_size);
    }

    internal override bool is_in_in_window_mode ()
    {
        return (in_window_bookmarks || base.is_in_in_window_mode ());
    }

    internal override void show_default_view ()
    {
        if (in_window_bookmarks)
        {
            if (in_window_bookmarks_edit_mode)
                leave_bookmarks_edit_mode ();
            in_window_bookmarks = false;
            set_visible_child_name ("main-view");
        }
        else
            base.show_default_view ();
    }

    /*\
    * * bookmarks view
    \*/

    [CCode (notify = false)] internal bool in_window_bookmarks           { internal get; private set; default = false; }
    [CCode (notify = false)] internal bool in_window_bookmarks_edit_mode { internal get; private set; default = false; }

    private BookmarksList bookmarks_list;

    private void create_bookmarks_list ()
    {
        bookmarks_list = new BookmarksList (/* needs shadows            */ false,
                                            /* big placeholder          */ true,
                                            /* edit-mode action prefix  */ "bmk",
                                            /* schema path              */ "/ca/desrt/dconf-editor/");
        bookmarks_list.selection_changed.connect (on_bookmarks_selection_changed);
        bookmarks_list.update_bookmarks_icons.connect (on_update_bookmarks_icons);
        bookmarks_list.show ();
        add (bookmarks_list);
    }

    private string [] old_bookmarks = new string [0];

    internal void show_bookmarks_view (string [] bookmarks)
    {
        if (is_in_in_window_mode ())
            show_default_view ();

        bookmarks_list.reset ();

        if (bookmarks != old_bookmarks)
        {
            Variant variant = new Variant.strv (bookmarks);
            bookmarks_list.create_bookmark_rows (variant);

            old_bookmarks = bookmarks;
        }
        set_visible_child (bookmarks_list);
        in_window_bookmarks = true;
    }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        bookmarks_list.update_bookmark_icon (bookmark, icon);
    }

    /*\
    * * edit mode
    \*/

    internal void enter_bookmarks_edit_mode ()
        requires (in_window_bookmarks == true)
    {
        bookmarks_list.enter_edit_mode ();
        in_window_bookmarks_edit_mode = true;
    }

    internal bool leave_bookmarks_edit_mode ()
        requires (in_window_bookmarks == true)
    {
        in_window_bookmarks_edit_mode = false;
        return bookmarks_list.leave_edit_mode ();
    }

    internal OverlayedList.SelectionState get_bookmarks_selection_state ()
    {
        return bookmarks_list.get_selection_state ();
    }

    internal void trash_bookmark ()
    {
        bookmarks_list.trash_bookmark ();
    }

    internal void move_top ()
    {
        bookmarks_list.move_top ();
    }

    internal void move_up ()
    {
        bookmarks_list.move_up ();
    }

    internal void move_down ()
    {
        bookmarks_list.move_down ();
    }

    internal void move_bottom ()
    {
        bookmarks_list.move_bottom ();
    }

    /*\
    * * callbacks
    \*/

    private void on_bookmarks_selection_changed ()
    {
        if (!in_window_bookmarks)
            return;
        bookmarks_selection_changed ();
    }

    internal signal void bookmarks_selection_changed ();

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    private void on_update_bookmarks_icons (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    /*\
    * * keyboard calls
    \*/

    internal override bool next_match ()
    {
        if (in_window_bookmarks)
            return bookmarks_list.next_match ();
        return base.next_match ();
    }

    internal override bool previous_match ()
    {
        if (in_window_bookmarks)
            return bookmarks_list.previous_match ();
        return base.previous_match ();
    }

    internal override bool handle_copy_text (out string copy_text)
    {
        if (in_window_bookmarks)
            return bookmarks_list.handle_copy_text (out copy_text);
        return base.handle_copy_text (out copy_text);
    }

    internal override bool toggle_row_popover ()     // Menu
    {
        if (in_window_bookmarks)
            return false;
        return base.toggle_row_popover ();
     }
}
