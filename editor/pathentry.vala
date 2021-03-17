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

private class BrowserEntry : SearchEntry
{
    private StyleContext context;

    construct
    {
        context = get_style_context ();
    }

    private bool has_error_class = false;
    internal void check_error (ref string path)
    {
        bool is_invalid = BrowserWindow.is_path_invalid (path);
        if (!has_error_class && is_invalid)
        {
            has_error_class = true;
            context.add_class ("error");
        }
        else if (has_error_class && !is_invalid)
        {
            has_error_class = false;
            context.remove_class ("error");
        }
    }

    internal void set_is_thin_window (bool thin_window)
    {
        if (thin_window)
            set_icon_from_pixbuf (EntryIconPosition.PRIMARY, null);
        else
            set_icon_from_icon_name (EntryIconPosition.PRIMARY, "edit-find-symbolic");
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathentry.ui")]
private class PathEntry : Box, AdaptativeWidget
{
    [GtkChild] private unowned Button       hide_search_button;
    [GtkChild] private unowned Button       reload_search_button;

    [GtkChild] private unowned BrowserEntry search_entry;
    [GtkChild] private unowned Button       search_action_button;

    private string current_path = "";

    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        minimum_width = 72; // the search entry does something wrong that makes the first size_allocate ask for 478px width instead of 349
    }

    private ulong can_reload_handler = 0;
    private bool thin_window = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _thin_window = AdaptativeWidget.WindowSize.is_quite_thin (new_size);
        if (thin_window == _thin_window)
            return;
        thin_window = _thin_window;

        search_entry.set_is_thin_window (_thin_window);

        if (_thin_window)
        {
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

    construct
    {
        search_changed_handler = search_entry.search_changed.connect (() => {
                search_action_button.set_action_target ("ms", search_entry.text);
                search_action_button.clicked ();
            });
        search_entry.stop_search.connect (() => {
                search_action_button.set_action_target ("ms", null);
                search_action_button.clicked ();
            });
    }

    internal void entry_grab_focus_without_selecting ()
    {
        _entry_grab_focus_without_selecting (search_entry);
    }
    private static void _entry_grab_focus_without_selecting (BrowserEntry search_entry)
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

    internal void set_path (ViewType type, string _path)
    {
        string path = _path.strip ();

        search_entry.check_error (ref path);

        current_path = path;
//        if (type == ViewType.SEARCH)
    }

    /*\
    * * prepare call
    \*/

    internal void prepare (SearchMode mode, string? nullable_search = null)
        requires (search_changed_handler != 0)
    {
        SignalHandler.block (search_entry, search_changed_handler);
        _prepare (mode, nullable_search, ref current_path, search_entry);
        SignalHandler.unblock (search_entry, search_changed_handler);
    }

    private static inline void _prepare (SearchMode   mode,
                                         string?      nullable_search,
                                     ref string       current_path,
                                         BrowserEntry search_entry)
    {
        string search;
        switch (mode)
        {
            case SearchMode.EDIT_PATH_MOVE_END:
                search = nullable_search == null ? current_path : (!) nullable_search;
                _prepare_move_end (ref search, search_entry);
                return;

            case SearchMode.EDIT_PATH_SELECT_ALL:
                search = nullable_search == null ? current_path : (!) nullable_search;
                _prepare_search (ref search, search_entry);
                return;

            case SearchMode.EDIT_PATH_SELECT_LAST_WORD:
                search = current_path;
                _prepare_select_last_word (ref search, search_entry);
                return;

            case SearchMode.SEARCH:
                search = "";
                _prepare_search (ref search, search_entry);
                return;

            case SearchMode.UNCLEAR:
            default:
                assert_not_reached ();
        }
    }

    private static inline void _prepare_move_end (ref string text, BrowserEntry search_entry)
    {
        search_entry.text = text;
        _entry_grab_focus_without_selecting (search_entry);
    }

    private static inline void _prepare_search (ref string text, BrowserEntry search_entry)
    {
        search_entry.text = text;
        search_entry.grab_focus ();
    }

    private static inline void _prepare_select_last_word (ref string current_path, BrowserEntry search_entry)
    {
        search_entry.move_cursor (MovementStep.DISPLAY_LINE_ENDS, -1, false);
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
    }
}
