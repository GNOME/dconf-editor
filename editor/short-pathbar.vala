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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/short-pathbar.ui")]
private class ShortPathbar : Grid, Pathbar  // TODO make MenuButton?
{
    private string non_ghost_path = "";

    private string complete_path = "";
    internal void get_complete_path (out string _complete_path)
    {
        _complete_path = complete_path;
    }
    internal void get_fallback_path_and_complete_path (out string _fallback_path, out string _complete_path)
    {
        if (non_ghost_path != "" && ModelUtils.is_folder_path (non_ghost_path) && complete_path.has_prefix (non_ghost_path))
            _fallback_path = non_ghost_path;
        else
            _fallback_path = complete_path;

        _complete_path = complete_path;
    }

    [GtkChild] private unowned MenuButton   menu_button;
    [GtkChild] private unowned Label        view_label;

    internal ShortPathbar (string complete_path_or_empty, ViewType type, string path)
    {
        complete_path = complete_path_or_empty;
        non_ghost_path = complete_path_or_empty;
        set_path (type, path);
    }

    /*\
    * * callbacks
    \*/

    private int event_x = 0;

    [GtkCallback]
    private bool on_button_press_event (Widget widget, Gdk.EventButton event)
    {
        event_x = (int) event.x;
        return false;
    }

    [GtkCallback]
    private void on_button_clicked (Button button)
    {
        MenuButton menu_button = (MenuButton) button;
        Popover? popover = menu_button.get_popover ();
        if (popover == null)
            assert_not_reached ();

        Allocation allocation;
        menu_button.get_allocated_size (out allocation, null);
        Gdk.Rectangle rect = { x:event_x, y:allocation.height, width:0, height:0 };
        ((!) popover).set_pointing_to (rect);
    }

    /*\
    * * keyboard
    \*/

    internal bool has_popover ()
    {
        return menu_button.active;
    }

    internal void close_menu ()
    {
        menu_button.active = false;
    }

    internal void toggle_menu ()
    {
        menu_button.active = !menu_button.active;
    }

    /*\
    * * main public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        if (type == ViewType.SEARCH)
            return;

        if (complete_path == ""
         || !path.has_suffix ("/")
         || !complete_path.has_prefix (path))
        {
            complete_path = path;
            non_ghost_path = path;
        }

        view_label.set_text (ModelUtils.get_name (path));
        update_menu ();
    }

    internal void update_ghosts (string _non_ghost_path, bool is_search)
    {
        non_ghost_path = _non_ghost_path;
        update_menu ();
    }

    /*\
    * * menu creation
    \*/

    private void update_menu ()
    {
        GLib.Menu menu;
        _update_menu (complete_path, non_ghost_path, out menu);
        menu_button.set_menu_model (menu);
    }
    private static void _update_menu (string complete_path, string non_ghost_path, out GLib.Menu menu)
    {
        menu = new GLib.Menu ();
        GLib.Menu section = new GLib.Menu ();

        string [] split = complete_path.split ("/", /* max tokens disabled */ 0);
        if (split.length < 2)
            assert_not_reached ();
        string last = split [split.length - 1];
        split = split [1:split.length - 1];    // excludes initial "" and either last "" or key name

        // slash folder
        string tmp_path = "/";

        if (complete_path != "/")
            menu.append ("/", "browser.open-path(('/',uint16 " + ModelUtils.folder_context_id_string + "))");

        // other folders
        foreach (string item in split)
        {
            tmp_path += item + "/";
            Variant variant = new Variant ("(sq)", tmp_path, ModelUtils.folder_context_id);
            if (non_ghost_path.has_prefix (tmp_path))
                menu.append (item, "browser.open-path(" + variant.print (true) + ")");  // TODO append or prepend?
            else
                menu.append (item, "browser.disabled-state-sq(" + variant.print (true) + ")");  // TODO append or prepend?
        }

        // key or nothing
        if (last != "")
        {
            bool is_folder = ModelUtils.is_folder_path (complete_path);
            tmp_path += last;
            if (is_folder)
                tmp_path += "/";

            uint16 context_id = is_folder ? ModelUtils.folder_context_id : ModelUtils.undefined_context_id;
            Variant variant = new Variant ("(sq)", tmp_path, context_id);
            if (non_ghost_path.has_prefix (tmp_path))   // FIXME problem if key and folder named similarly
                menu.append (last, "browser.open-path(" + variant.print (true) + ")");
            else
                menu.append (last, "browser.disabled-state-sq(" + variant.print (true) + ")");  // TODO append or prepend?
        }

        section.freeze ();
        menu.append_section (null, section);

        Pathbar.populate_pathbar_menu (/* is folder */ last == "", ref menu);

        menu.freeze ();
    }
}
