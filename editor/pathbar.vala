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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar.ui")]
public class PathBar : Box
{
    [GtkChild] Button root_button;

    public signal bool path_selected (string path);

    public void set_path (string path, bool notify = false)
        requires (path [0] == '/')
    {
        @foreach ((child) => {
                if (child != root_button)
                {
                    if (child is PathBarItem)
                    {
                        ulong path_bar_item_clicked_handler = ((PathBarItem) child).path_bar_item_clicked_handler;
                        if (path_bar_item_clicked_handler != 0)
                            child.disconnect (((PathBarItem) child).path_bar_item_clicked_handler);
                    }
                    child.destroy ();
                }
            });

        string [] split = path.split ("/", 0);
        string last = split [split.length - 1];
        bool is_key_path = last != "";

        /* add initial text (set to "settings://"?) */
        string complete_path = "/";
        add (new Label ("/"));

        /* add one item per folder */
        if (split.length > 2)
        {
            uint index = 0;
            foreach (string item in split [1:split.length - 1])
            {
                index++;
                complete_path += item + "/";
                add (new PathBarItem (item, complete_path, is_key_path || (index != split.length - 2)));
                add (new Label ("/"));
            }
        }

        /* if key path */
        if (is_key_path)
            add (new PathBarItem (last, complete_path + last, false));

        /* only draw when finished, for CSS :last-child rendering */
        show_all ();

        /* notify if requested */
        if (notify)
            if (!path_selected (path))
                warning ("something has got wrong with pathbar");
    }

    [GtkCallback]
    private void set_root_path ()
    {
        set_path ("/", true);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar-item.ui")]
private class PathBarItem : Button
{
    public ulong path_bar_item_clicked_handler = 0;

    [GtkChild] private Label text;

    public PathBarItem (string label, string path, bool is_clickable)
    {
        text.set_text (label);
        if (is_clickable)
            path_bar_item_clicked_handler = clicked.connect (() => { ((PathBar) get_parent ()).set_path (path, true); });
    }
}
