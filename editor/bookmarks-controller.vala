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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmarks-controller.ui")]
private class BookmarksController : Grid
{
    [GtkChild] private unowned Image big_rows_icon;
    [GtkChild] private unowned Image small_rows_icon;

    [GtkChild] private unowned Button rows_size_button;
    [CCode (notify = false)] public bool show_rows_size_button { private get; construct; default = false; }

    [GtkChild] private unowned Button trash_bookmark_button;
    [GtkChild] private unowned Button move_top_button;
    [GtkChild] private unowned Button move_up_button;
    [GtkChild] private unowned Button move_down_button;
    [GtkChild] private unowned Button move_bottom_button;
    [CCode (notify = false)] public string controller_action_prefix
    {
        construct
        {
            // TODO sanitize "value"
            trash_bookmark_button.set_detailed_action_name (value + ".trash-bookmark");
            move_top_button.set_detailed_action_name (value + ".move-top");
            move_up_button.set_detailed_action_name (value + ".move-up");
            move_down_button.set_detailed_action_name (value + ".move-down");
            move_bottom_button.set_detailed_action_name (value + ".move-bottom");
        }
    }

    construct
    {
        if (show_rows_size_button)      // TODO construct instead of hiding
            rows_size_button.show ();
        else
            rows_size_button.hide ();
    }

    internal BookmarksController (string _controller_action_prefix, bool _show_rows_size_button)
    {
        Object (controller_action_prefix: _controller_action_prefix, show_rows_size_button: _show_rows_size_button);
    }

    internal void update_rows_size_button_icon (bool small_bookmarks_rows)
    {
        if (small_bookmarks_rows)
            rows_size_button.set_image (big_rows_icon);
        else
            rows_size_button.set_image (small_rows_icon);
    }

    internal bool get_small_rows_state ()
    {
        return rows_size_button.get_image () == small_rows_icon;
    }
}
