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
private class AdaptativePathbar : Stack, Pathbar, AdaptativeWidget
{
    [GtkChild] private LargePathbar large_pathbar;
    [GtkChild] private ShortPathbar short_pathbar;

    private bool thin_window = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _thin_window = AdaptativeWidget.WindowSize.is_thin (new_size);
        if (_thin_window == thin_window)
            return;
        thin_window = _thin_window;

        if (_thin_window)
            set_visible_child (short_pathbar);
        else
            set_visible_child (large_pathbar);
    }

    internal string get_complete_path ()
    {
        return large_pathbar.get_complete_path ();  // or the short_pathbar one; do not require their equality, it warns on window closing
    }

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
        if (thin_window)
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
}

private interface Pathbar
{
    /* simple proxy calls */
    internal abstract bool has_popover ();
    internal abstract void close_menu ();
    internal abstract void toggle_menu ();

    internal abstract void set_path (ViewType type, string path);
    internal abstract void update_ghosts (string non_ghost_path, bool is_search);

    /* complex proxy calls */
    internal abstract string get_complete_path ();

    internal virtual string get_selected_child (string current_path)
    {
        return _get_selected_child (current_path, get_complete_path ());
    }
    private static string _get_selected_child (string current_path, string complete_path)
    {
        if (!complete_path.has_prefix (current_path) || complete_path == current_path)
            return "";
        int index_of_last_slash = complete_path.index_of ("/", current_path.length);
        return index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1);
    }

    /* called from inside the pathbar, by ShortPathbar and LargePathbarItem (so cannot make "protected") */
    internal static void add_copy_path_entry (ref GLib.Menu section)
    {
        section.append (_("Copy current path"), "kbd.copy-path"); // or "app.copy(\"" + get_action_target_value ().get_string () + "\")"
    }
}
