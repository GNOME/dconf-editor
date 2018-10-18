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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathentry.ui")]
private class PathEntry : Box, AdaptativeWidget
{
    [GtkChild] private Button       hide_search_button;
    [GtkChild] private Button       reload_search_button;

    [GtkChild] private SearchEntry  search_entry;

    private string current_path = "";

    internal string text { get { return search_entry.text; }}
    internal bool entry_has_focus { get { return search_entry.has_focus; }}

    private ulong can_reload_handler = 0;
    private void set_extra_small_window_state (bool new_value)
    {
        if (new_value)
        {
            search_entry.set_icon_from_pixbuf (EntryIconPosition.PRIMARY, null);

            can_reload_handler = reload_search_button.notify ["sensitive"].connect (() => {
                    if (reload_search_button.sensitive)
                    {
                        hide_search_button.hide ();
                        reload_search_button.show ();
                    }
                    else
                    {
                        reload_search_button.hide ();
                        hide_search_button.show ();
                    }
                });

            if (!reload_search_button.sensitive)
            {
                reload_search_button.hide ();
                hide_search_button.show ();
            }
        }
        else
        {
            search_entry.set_icon_from_icon_name (EntryIconPosition.PRIMARY, "edit-find-symbolic");

            reload_search_button.disconnect (can_reload_handler);

            hide_search_button.hide ();
            reload_search_button.show ();
        }
    }

    internal enum SearchMode {
        UNCLEAR,
        EDIT_PATH_MOVE_END,
        EDIT_PATH_SELECT_ALL,
        EDIT_PATH_SELECT_LAST_WORD,
        SEARCH
    }

    private ulong search_changed_handler = 0;
    internal signal void search_changed ();
    internal signal void search_stopped ();

    construct
    {
        search_changed_handler = search_entry.search_changed.connect (() => search_changed ()); 
        search_entry.stop_search.connect (() => search_stopped ());
    }

    internal void entry_grab_focus_without_selecting ()
    {
        if (search_entry.text_length != 0)
        {
            if (search_entry.cursor_position == search_entry.text_length)
                search_entry.move_cursor (MovementStep.DISPLAY_LINE_ENDS, -1, false);
            search_entry.move_cursor (MovementStep.DISPLAY_LINE_ENDS, 1, false);
        }
        search_entry.grab_focus_without_selecting ();
    }
    internal void entry_grab_focus ()
    {
        search_entry.grab_focus ();
    }
    internal bool handle_event (Gdk.EventKey event)
    {
        return search_entry.handle_event (event);
    }

    private bool has_error_class = false;
    internal void set_path (ViewType type, string _path)
    {
        string path = _path.strip ();

        if (!has_error_class && DConfWindow.is_path_invalid (path))
        {
            has_error_class = true;
            search_entry.get_style_context ().add_class ("error");
        }
        else if (has_error_class && !DConfWindow.is_path_invalid (path))
        {
            has_error_class = false;
            search_entry.get_style_context ().remove_class ("error");
        }

        current_path = path;
//        if (type == ViewType.SEARCH)
    }

    internal void prepare (SearchMode mode, string? search = null)
        requires (search_changed_handler != 0)
    {
        SignalHandler.block (search_entry, search_changed_handler);
        _prepare (mode, search);
        SignalHandler.unblock (search_entry, search_changed_handler);
    }
    private inline void _prepare (SearchMode mode, string? search)
    {
        switch (mode)
        {
            case SearchMode.EDIT_PATH_MOVE_END:
                search_entry.text = search == null ? current_path : (!) search;
                entry_grab_focus_without_selecting ();
                return;

            case SearchMode.EDIT_PATH_SELECT_ALL:
                search_entry.text = search == null ? current_path : (!) search;
                search_entry.grab_focus ();
                return;

            case SearchMode.EDIT_PATH_SELECT_LAST_WORD:
                search_entry.text = current_path;
                if (search_entry.text_length == 1)  // root
                {
                    search_entry.grab_focus ();
                    return;
                }
                if (search_entry.text_length != 0)
                {
                    if (search_entry.cursor_position == search_entry.text_length)
                        search_entry.move_cursor (MovementStep.DISPLAY_LINE_ENDS, -1, false);
                    search_entry.move_cursor (MovementStep.VISUAL_POSITIONS, ModelUtils.get_parent_path (current_path).length, false);
                    search_entry.move_cursor (MovementStep.DISPLAY_LINE_ENDS, 1, true);
                }
                search_entry.grab_focus_without_selecting ();
                return;

            case SearchMode.SEARCH:
                search_entry.text = "";
                search_entry.grab_focus ();
                return;

            case SearchMode.UNCLEAR:
            default:
                assert_not_reached ();
        }
    }
}
