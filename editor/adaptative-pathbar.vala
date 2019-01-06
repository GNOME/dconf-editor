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

private class AdaptativePathbar : Stack, Pathbar, AdaptativeWidget
{
    construct
    {
        hexpand = true;
        hhomogeneous = false;
    }

    /*\
    * * pathbars creation
    \*/

    private bool start_infos_not_given = true;
    private bool window_size_not_given = true;

    private bool large_pathbar_created = false;
    private bool short_pathbar_created = false;

    private LargePathbar large_pathbar;
    private ShortPathbar short_pathbar;

    private void create_large_pathbar ()
    {
        large_pathbar = new LargePathbar (complete_path, current_type, current_path);
        large_pathbar.valign = Align.FILL;
        large_pathbar.vexpand = true;
        large_pathbar.show ();
        add (large_pathbar);
        large_pathbar_created = true;
    }

    private void create_short_pathbar ()
    {
        short_pathbar = new ShortPathbar (complete_path, current_type, current_path);
        short_pathbar.valign = Align.CENTER;
        short_pathbar.show ();
        add (short_pathbar);
        short_pathbar_created = true;
    }

    private void create_initial_pathbar ()
    {
        if (thin_window)
        {
            create_short_pathbar ();
            set_visible_child (short_pathbar);
        }
        else
        {
            create_large_pathbar ();
            set_visible_child (large_pathbar);
        }
    }

    /*\
    * * window size state
    \*/

    private bool thin_window = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        if (window_size_not_given)
        {
            thin_window = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
            window_size_not_given = false;
            if (start_infos_not_given)
                return;
            create_initial_pathbar ();
            return;
        }

        bool _thin_window = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (thin_window == _thin_window)
            return;
        thin_window = _thin_window;

        if (start_infos_not_given)
            return;

        if (_thin_window)
        {
            if (!short_pathbar_created)
                create_short_pathbar ();
            set_visible_child (short_pathbar);
        }
        else
        {
            if (!large_pathbar_created)
                create_large_pathbar ();
            set_visible_child (large_pathbar);
        }
    }

    /*\
    * * current path state
    \*/

    private ViewType current_type;
    private string current_path;
    private string complete_path = "";

    internal void set_path (ViewType type, string path)
    {
        current_type = type;
        current_path = path;

        if (complete_path == ""
         || !path.has_suffix ("/")
         || !complete_path.has_prefix (path))
            complete_path = path;

        if (start_infos_not_given)
        {
            start_infos_not_given = false;
            if (window_size_not_given)
                return;
            create_initial_pathbar ();
            return;
        }

        if (window_size_not_given)
            return;

        if (large_pathbar_created)
            large_pathbar.set_path (type, path);
        if (short_pathbar_created)
            short_pathbar.set_path (type, path);
    }

    /*\
    * * keyboard
    \*/

    internal bool has_popover ()
    {
        return (large_pathbar_created && large_pathbar.has_popover ())
            || (short_pathbar_created && short_pathbar.has_popover ());
    }

    internal void close_menu ()
    {
        if (large_pathbar_created)
            large_pathbar.close_menu ();
        if (short_pathbar_created)
            short_pathbar.close_menu ();
    }

    internal void toggle_menu ()
    {
        if (thin_window)
        {
            if (!short_pathbar_created)
                assert_not_reached ();
            short_pathbar.toggle_menu ();
        }
        else
        {
            if (!large_pathbar_created)
                assert_not_reached ();
            large_pathbar.toggle_menu ();
        }
    }

    /*\
    * * public calls
    \*/

    internal void get_complete_path (out string _complete_path)
    {
        _complete_path = complete_path;
    }

    internal void get_fallback_path_and_complete_path (out string _fallback_path, out string _complete_path)
    {
        if (large_pathbar_created)
            large_pathbar.get_fallback_path_and_complete_path (out _fallback_path, out _complete_path);
        else if (short_pathbar_created)
            short_pathbar.get_fallback_path_and_complete_path (out _fallback_path, out _complete_path);
        else
            assert_not_reached ();
    }

    internal void update_ghosts (string non_ghost_path, bool is_search)
    {
        if (large_pathbar_created)
            large_pathbar.update_ghosts (non_ghost_path, is_search);
        if (short_pathbar_created)
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
    internal abstract void get_complete_path (out string _complete_path);
    internal abstract void get_fallback_path_and_complete_path (out string _fallback_path, out string _complete_path);

    internal virtual string get_selected_child (string current_path)
    {
        string complete_path;
        get_complete_path (out complete_path);
        return _get_selected_child (current_path, complete_path);
    }
    private static string _get_selected_child (string current_path, string complete_path)
    {
        if (!complete_path.has_prefix (current_path) || complete_path == current_path)
            return "";
        int index_of_last_slash = complete_path.index_of ("/", current_path.length);
        return index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1);
    }

    /* called from inside the pathbar, by ShortPathbar and LargePathbar*Item* (so cannot make "protected") */
    internal static void populate_pathbar_menu (bool is_folder, ref GLib.Menu menu)
    {
        add_copy_path_section (ref menu);
        if (is_folder)
            add_open_config_section (ref menu);
    }

    private static void add_copy_path_section (ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();
        /* Translators: menu entry of the pathbar menu */
        section.append (_("Copy current path"), "base.copy-alt");
        // or "app.copy(\"" + get_action_target_value ().get_string () + "\")"
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void add_open_config_section (ref GLib.Menu menu)
    {
        // method "disabled" for now
        return;

        GLib.Menu section = new GLib.Menu ();
        /* Translators: menu entry of the pathbar menu (not displayed for now) */
        section.append (_("Show properties"), "browser.open-config-local");
        section.freeze ();
        menu.append_section (null, section);
    }
}
