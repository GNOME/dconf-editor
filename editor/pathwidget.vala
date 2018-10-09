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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathwidget.ui")]
private class PathWidget : Box
{
    [GtkChild] private ToggleButton search_toggle;
    [GtkChild] private Stack        pathbar_stack;
    [GtkChild] private PathBar      pathbar;
    [GtkChild] private PathEntry    searchentry;

    [GtkChild] private Bookmarks    bookmarks_button;

    internal signal void search_changed ();
    internal signal void search_stopped ();

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    construct
    {
        bookmarks_button.update_bookmarks_icons.connect ((bookmarks_variant) => update_bookmarks_icons (bookmarks_variant));
    }

    /*\
    * * search mode
    \*/

    internal bool search_mode_enabled { get; private set; default = false; }

    private void enter_search_mode ()
    {
        search_mode_enabled = true;
        search_toggle.active = true;
        search_toggle.set_action_target_value (false);
        pathbar_stack.set_visible_child (searchentry);
    }

    private void leave_search_mode ()
    {
        search_mode_enabled = false;
        search_toggle.active = false;
        search_toggle.set_action_target_value (true);
        pathbar_stack.set_visible_child (pathbar);
    }

    /*\
    * * callbacks
    \*/

    [GtkCallback]
    private void search_changed_cb ()
    {
        if (search_mode_enabled)
            search_changed ();
    }

    [GtkCallback]
    private void search_stopped_cb ()
    {
        search_stopped ();
    }

    /*\
    * * phone mode
    \*/

    internal bool extra_small_window
    {
        set
        {
            bookmarks_button.active = false;
        }
    }

    /*\
    * * proxy calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        pathbar.set_path (type, path);
        searchentry.set_path (type, path);
        bookmarks_button.set_path (type, path);

        if (type == ViewType.SEARCH && !search_mode_enabled)
            enter_search_mode ();
        else if (type != ViewType.SEARCH && search_mode_enabled)
            leave_search_mode ();
    }

    internal void close_popovers ()
    {
        if (bookmarks_button.active)
            bookmarks_button.active = false;
        pathbar.close_menu ();
    }

    internal bool has_popover ()
    {
        if (bookmarks_button.active)
            return true;
        if (pathbar.has_popover ())
            return true;
        return false;
    }

    internal void down_pressed ()
    {
        if (bookmarks_button.active)
            bookmarks_button.down_pressed ();
    }
    internal void up_pressed ()
    {
        if (bookmarks_button.active)
            bookmarks_button.up_pressed ();
    }

    /* path bar */
    internal string complete_path { get { return pathbar.complete_path; }}

    internal void update_ghosts (string fallback_path)
    {
        pathbar.update_ghosts (fallback_path, search_mode_enabled);
    }

    internal string get_selected_child (string fallback_path)
    {
        return pathbar.get_selected_child (fallback_path);
    }

    internal void toggle_pathbar_menu ()
    {
        pathbar.toggle_menu ();
    }

    /* path entry */
    internal string text                   { get { return searchentry.text; }}
    internal bool entry_has_focus          { get { return searchentry.entry_has_focus; }}
    internal void entry_grab_focus ()                   { searchentry.entry_grab_focus (); }
    internal void entry_grab_focus_without_selecting () { searchentry.entry_grab_focus_without_selecting (); }

    internal bool handle_event (Gdk.EventKey event)
    {
        searchentry.prepare (PathEntry.SearchMode.SEARCH);
        if (!searchentry.handle_event (event))
            return false;
        enter_search_mode ();
        return true;
    }

    internal void prepare_search (PathEntry.SearchMode mode, string? search)
    {
        searchentry.prepare (mode, search);
    }

    /* bookmarks button */
    internal string [] get_bookmarks ()
    {
        return bookmarks_button.get_bookmarks ();
    }

    internal void click_bookmarks_button ()
    {
        if (bookmarks_button.sensitive)
            bookmarks_button.clicked ();
    }

    internal void   bookmark_current_path () {   bookmarks_button.bookmark_current_path (); }
    internal void unbookmark_current_path () { bookmarks_button.unbookmark_current_path (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        bookmarks_button.update_bookmark_icon (bookmark, icon);
    }

/*      string [] tokens = full_name.split (" ");
        uint index = 0;
        string token;
        while (index < tokens.length)
        {
            token = tokens [index];
            if (token.has_prefix ("/"))
            {
                path_requested (token, pathbar.get_selected_child (token));
                break;
            }
            index++;
        } */

    /*\
    * * sizing
    \*/

    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;  // see key-list-box-row.vala
    }
}
