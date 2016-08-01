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

    public signal void path_selected (string path);

    construct
    {
        add_slash_label ();
        root_button.clicked.connect (() => path_selected ("/"));
    }

    public void set_path (string path)
        requires (path [0] == '/')
    {
        root_button.set_sensitive (path != "/");

        string complete_path = "";
        string [] split = path.split ("/", /* max tokens disabled */ 0);
        string last = split [split.length - 1];
        bool is_key_path = last != "";

        bool destroy_all = false;
        bool maintain_all = false;
        @foreach ((child) => {
                if (child is Label)
                {
                    if (destroy_all)
                        child.destroy ();
                    else
                        complete_path += "/";
                    return;
                }

                if (maintain_all)
                {
                    child.set_sensitive (true);
                    return;
                }

                if (child == root_button || (!destroy_all && ((PathBarItem) child).text_string == split [0]))
                {
                    complete_path += split [0];
                    split = split [1:split.length];
                    if (split.length == 0 || (split.length == 1 && !is_key_path))
                    {
                        child.set_sensitive (false);
                        maintain_all = true;
                    }
                    else
                        child.set_sensitive (true);
                    return;
                }

                child.disconnect (((PathBarItem) child).path_bar_item_clicked_handler);
                child.destroy ();
                destroy_all = true;
            });

        if (split.length > 0)
        {
            /* add one item per folder */
            if (split.length > 1)
            {
                uint index = 0;
                foreach (string item in split [0:split.length - 1])
                {
                    complete_path += item + "/";
                    add_path_bar_item (item, complete_path, !is_key_path && (index == split.length - 2));
                    add_slash_label ();
                    index++;
                }
            }

            /* if key path */
            if (is_key_path)
            {
                complete_path += last;
                add_path_bar_item (last, complete_path, true);
            }
        }

        show_all ();
    }

    /*\
    * * widgets
    \*/

    private void add_slash_label ()
    {
        add (new Label ("/"));
    }

    private void add_path_bar_item (string label, string complete_path, bool block)
    {
        PathBarItem path_bar_item = new PathBarItem (label);

        path_bar_item.path_bar_item_clicked_handler = path_bar_item.clicked.connect (() => path_selected (complete_path));
        path_bar_item.set_sensitive (!block);

        add (path_bar_item);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar-item.ui")]
private class PathBarItem : Button
{
    public ulong path_bar_item_clicked_handler = 0;

    public string text_string { get; construct; }
    [GtkChild] private Label text_label;

    public PathBarItem (string label)
    {
        Object (text_string: label);
        text_label.set_text (label);
    }
}
