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
    [GtkChild] private Button root_button;

    public signal bool path_selected (string path);

    construct
    {
        add (new Label ("/"));
    }

    public void set_path_and_notify (string path)
    {
        set_path (path);
        if (!path_selected (path))
            warning ("something has got wrong with pathbar");
    }

    public void set_path (string path)
        requires (path [0] == '/')
    {
        string complete_path = "/";
        string [] split = path.split ("/", /* max tokens disabled */ 0);
        split = split [1:split.length];

        bool destroy_all = false;
        @foreach ((child) => {
                if (child == root_button)
                    return;

                if (!(child is PathBarItem))
                {
                    if (destroy_all)
                        child.destroy ();
                    return;
                }

                if (!destroy_all && ((PathBarItem) child).text_string == split [0])
                {
                    complete_path += split [0] + "/";
                    if (split.length > 0)
                        split = split [1:split.length];
                    return;
                }

                ulong path_bar_item_clicked_handler = ((PathBarItem) child).path_bar_item_clicked_handler;
                if (path_bar_item_clicked_handler != 0)
                    child.disconnect (((PathBarItem) child).path_bar_item_clicked_handler);

                child.destroy ();
                destroy_all = true;
            });

        if (split.length > 0)
        {
            string last = split [split.length - 1];
            bool is_key_path = last != "";

            /* add one item per folder */
            if (split.length > 1)
            {
                uint index = 0;
                foreach (string item in split [0:split.length - 1])
                {
                    complete_path += item + "/";
                    PathBarItem path_bar_item = new PathBarItem (item);
                    if (is_key_path || (index != split.length - 1))
                    {
                        string local_complete_path = complete_path;
                        path_bar_item.path_bar_item_clicked_handler = path_bar_item.clicked.connect (() => set_path_and_notify (local_complete_path));
                    }
                    add (path_bar_item);
                    add (new Label ("/"));
                    index++;
                }
            }

            /* if key path */
            if (is_key_path)
                add (new PathBarItem (last));
        }

        /* only draw when finished, for CSS :last-child rendering */
        show_all ();
    }

    [GtkCallback]
    private void set_root_path ()
    {
        set_path_and_notify ("/");
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar-item.ui")]
private class PathBarItem : Button
{
    public ulong path_bar_item_clicked_handler = 0;

    public string text_string { get; private set; }
    [GtkChild] private Label text_label;

    public PathBarItem (string label)
    {
        text_string = label;
        text_label.set_text (label);
    }
}
