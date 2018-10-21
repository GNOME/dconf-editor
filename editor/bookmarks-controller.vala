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
    [GtkChild] private Image big_rows_icon;
    [GtkChild] private Image small_rows_icon;

    [GtkChild] private Button rows_size_button;
    public bool show_rows_size_button { private get; construct; default = false; }

    construct
    {
        if (show_rows_size_button)      // TODO construct instead of hiding
            rows_size_button.show ();
        else
            rows_size_button.hide ();
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
