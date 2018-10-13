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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/adaptative-pathbar.ui")]
private class AdaptativePathbar : Stack, Pathbar
{
    [GtkChild] private LargePathbar large_pathbar;
    [GtkChild] private ShortPathbar short_pathbar;

    private bool _extra_small_window = false;
    internal bool extra_small_window
    {
        private get { return _extra_small_window; }
        internal set
        {
            _extra_small_window = value;

            if (value)
                set_visible_child (short_pathbar);
            else
                set_visible_child (large_pathbar);
        }
    }

    internal string complete_path { get { return large_pathbar.complete_path; }}

    /*\
    * * keyboard
    \*/

    internal bool has_popover ()
    {
        return large_pathbar.has_popover () || short_pathbar.has_popover ();
    }

    internal void close_menu ()
    {
        large_pathbar.close_menu ();
        short_pathbar.close_menu ();
    }

    internal void toggle_menu ()
    {
        if (_extra_small_window)
            short_pathbar.toggle_menu ();
        else
            large_pathbar.toggle_menu ();
    }

    /*\
    * * main public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        large_pathbar.set_path (type, path);
        short_pathbar.set_path (type, path);
    }

    internal void update_ghosts (string non_ghost_path, bool is_search)
    {
        large_pathbar.update_ghosts (non_ghost_path, is_search);
        short_pathbar.update_ghosts (non_ghost_path, is_search);
    }

    internal string get_selected_child (string current_path)
    {
        return large_pathbar.get_selected_child (current_path);
    }
}

private interface Pathbar
{
    internal static void add_copy_path_entry (ref GLib.Menu section)
    {
        section.append (_("Copy current path"), "kbd.copy-path"); // or "app.copy(\"" + get_action_target_value ().get_string () + "\")"
    }
}
