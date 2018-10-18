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
private class ShortPathbar : Grid, Pathbar
{
    private string complete_path = "";
    internal string get_complete_path ()
    {
        return complete_path;
    }

    [GtkChild] private MenuButton   menu_button;
    [GtkChild] private Label        view_label;

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

        if (!path.has_suffix ("/")
         || !complete_path.has_prefix (path))
            complete_path = path;

        view_label.set_text (ModelUtils.get_name (path));

        GLib.Menu menu = new GLib.Menu ();
        GLib.Menu section = new GLib.Menu ();

        string [] split = complete_path.split ("/", /* max tokens disabled */ 0);
        if (split.length < 2)
            assert_not_reached ();
        string last = split [split.length - 1];
        split = split [1:split.length - 1];    // excludes initial "" and either last "" or key name

        // slash folder
        string tmp_path = "/";

        if (complete_path != "/")
            menu.append ("/", "ui.open-path(('/',uint16 " + ModelUtils.folder_context_id_string + "))");

        // other folders
        foreach (string item in split)
        {
            tmp_path += item + "/";
            Variant variant = new Variant ("(sq)", tmp_path, ModelUtils.folder_context_id);
            menu.append (item, "ui.open-path(" + variant.print (true) + ")");  // TODO append or prepend?
        }

        // key or nothing
        if (last != "")
        {
            bool is_folder = ModelUtils.is_folder_path (complete_path);
            uint16 context_id = is_folder ? ModelUtils.folder_context_id : ModelUtils.undefined_context_id;
            tmp_path += last;
            if (is_folder)
                tmp_path += "/";
            Variant variant = new Variant ("(sq)", tmp_path, context_id);
            menu.append (last, "ui.open-path(" + variant.print (true) + ")");
        }

        section.freeze ();
        menu.append_section (null, section);

        section = new GLib.Menu ();

        Pathbar.add_copy_path_entry (ref section);

        section.freeze ();
        menu.append_section (null, section);

        menu.freeze ();
        menu_button.set_menu_model (menu);
    }

    internal void update_ghosts (string non_ghost_path, bool is_search)
    {
    }
}
