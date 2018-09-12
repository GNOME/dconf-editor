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

    internal void prepare_search (PathEntry.SearchMode mode)
    {
        searchentry.prepare (mode);
    }

    /* bookmarks button */
    internal bool is_bookmarks_button_sensitive { get { return bookmarks_button.sensitive;  }}
    internal bool is_bookmarks_button_active    { get { return bookmarks_button.active;     }}

    internal string [] get_bookmarks ()
    {
        return bookmarks_button.get_bookmarks ();
    }

    internal void set_bookmarked (string path, bool new_state)
    {
        bookmarks_button.set_bookmarked (path, new_state);
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
    * * bookmarks
    \*/

    construct
    {
        // TODO here again, allow to use in UI file "bind-property" without "bind-source", using the instanciated object as source
        bind_property ("search-mode-enabled", bookmarks_button, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);
    }

    internal void close_popovers ()
    {
        if (bookmarks_button.active)
            bookmarks_button.active = false;
    }

    internal void click_bookmarks_button ()
    {
        if (bookmarks_button.sensitive)
            bookmarks_button.clicked ();
    }

    internal void update_bookmark_icon (string bookmark, bool bookmark_exists, bool bookmark_has_schema = false, bool bookmark_is_default = false)
    {
        bookmarks_button.update_bookmark_icon (bookmark, bookmark_exists, bookmark_has_schema, bookmark_is_default);
    }

    /*\
    * * sizing
    \*/

    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;  // see key-list-box-row.vala
    }
}
