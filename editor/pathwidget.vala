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
private class PathWidget : Box, AdaptativeWidget
{
    [GtkChild] private ModelButton          search_toggle;      // most window size button
    [GtkChild] private ModelButton          search_button;      // extra-small-window only
    [GtkChild] private Stack                pathwidget_stack;
    [GtkChild] private Grid                 pathbar_grid;
    [GtkChild] private AdaptativePathbar    pathbar;
    [GtkChild] private PathEntry            searchentry;

    internal signal void search_changed ();
    internal signal void search_stopped ();

    private ThemedIcon search_icon = new ThemedIcon.from_names ({"edit-find-symbolic"});
    construct
    {
        search_toggle.icon = search_icon;
        search_button.icon = search_icon;
    }

    private bool thin_window;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        pathbar.set_window_size (new_size);

        bool _thin_window = AdaptativeWidget.WindowSize.is_thin (new_size);
        if (thin_window != _thin_window)
        {
            thin_window = _thin_window;
            if (thin_window)
            {
                search_toggle.hide ();
                search_button.show ();
            }
            else
            {
                search_button.hide ();
                search_toggle.show ();
            }
        }

        searchentry.set_window_size (new_size);
    }

    /*\
    * * search mode
    \*/

    internal bool search_mode_enabled { get; private set; default = false; }

    private void enter_search_mode ()
    {
        search_mode_enabled = true;
        search_toggle.set_action_target_value (false);
        pathwidget_stack.set_visible_child (searchentry);
    }

    private void leave_search_mode ()
    {
        search_mode_enabled = false;
        search_toggle.set_action_target_value (true);
        pathwidget_stack.set_visible_child (pathbar_grid);
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

        if (type == ViewType.SEARCH && !search_mode_enabled)
            enter_search_mode ();
        else if (type != ViewType.SEARCH && search_mode_enabled)
            leave_search_mode ();
    }

    internal void close_popovers ()
    {
        pathbar.close_menu ();
    }

    internal bool has_popover ()
    {
        if (pathbar.has_popover ())
            return true;
        return false;
    }

    /* path bar */
    internal string get_complete_path ()
    {
        return pathbar.get_complete_path ();
    }

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
    * * sizing; TODO should be set by the center box of the headerbar, not by one of its child...
    \*/

    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH - 38;  // see key-list-box-row.vala
    }
}
