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
    [GtkChild] private unowned ModelButton          search_toggle;      // most window size button
    [GtkChild] private unowned ModelButton          search_button;      // extra-small-window only
    [GtkChild] private unowned Stack                pathwidget_stack;
    [GtkChild] private unowned Grid                 pathbar_grid;
    [GtkChild] private unowned AdaptativePathbar    pathbar;
    [GtkChild] private unowned PathEntry            searchentry;

    [GtkChild] private unowned Revealer             parent_revealer;
    [GtkChild] private unowned ModelButton          parent_button;

    private ThemedIcon search_icon = new ThemedIcon.from_names ({"edit-find-symbolic"});
    private ThemedIcon parent_icon = new ThemedIcon.from_names ({"go-up-symbolic"});
    construct
    {
        search_toggle.icon = search_icon;
        search_button.icon = search_icon;
        parent_button.icon = parent_icon;
    }

    private bool quite_thin_window = false;
    private bool extra_thin_window = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        pathbar.set_window_size (new_size);

        bool _quite_thin_window = AdaptativeWidget.WindowSize.is_quite_thin (new_size);
        bool _extra_thin_window = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (quite_thin_window != _quite_thin_window
         || extra_thin_window != _extra_thin_window)
        {
            quite_thin_window = _quite_thin_window;
            extra_thin_window = _extra_thin_window;
            if (_extra_thin_window)
            {
                search_toggle.hide ();
                search_button.show ();
                parent_revealer.set_reveal_child (true);
            }
            else if (_quite_thin_window)
            {
                search_toggle.hide ();
                search_button.show ();
                parent_revealer.set_reveal_child (false);
            }
            else
            {
                search_button.hide ();
                search_toggle.show ();
                parent_revealer.set_reveal_child (false);
            }
        }

        searchentry.set_window_size (new_size);
    }

    /*\
    * * search mode
    \*/

    [CCode (notify = false)] internal bool search_mode_enabled { internal get; private set; default = false; }

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
    * * proxy calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        pathbar.set_path (type, path);
        searchentry.set_path (type, path);

        bool is_search = type == ViewType.SEARCH;

        if (!is_search)
        {
            if (path != "/")
            {
                Variant path_variant = new Variant.string (path);
                parent_button.set_detailed_action_name ("browser.open-parent(" + path_variant.print (false) + ")");
            }
            else
                parent_button.set_detailed_action_name ("browser.disabled-state-s('/')");
        }

        if (is_search && !search_mode_enabled)
            enter_search_mode ();
        else if (!is_search && search_mode_enabled)
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
    internal void get_complete_path (out string complete_path)
    {
        pathbar.get_complete_path (out complete_path);
    }
    internal void get_fallback_path_and_complete_path (out string fallback_path, out string complete_path)
    {
        pathbar.get_fallback_path_and_complete_path (out fallback_path, out complete_path);
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
    internal void entry_grab_focus ()                       { searchentry.entry_grab_focus (); }
    internal void entry_grab_focus_without_selecting ()     { searchentry.entry_grab_focus_without_selecting (); }

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
    * * sizing; TODO should be set by the center box of the headerbar, not by one of its children...
    \*/

    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH - 46;  // see key-list-box-row.vala
    }
}
