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
public class PathBar : Box, PathElement
{
    [GtkChild] private Button root_button;

    private string complete_path = "";

    construct
    {
        add_slash_label ();
    }

    /*\
    * * public calls
    \*/

    public void set_path (string path)
        requires (path [0] == '/')
    {
        activate_item (root_button, path == "/");

        complete_path = "";
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
                    complete_path += ((PathBarItem) child).text_string;
                    activate_item (child, false);
                    return;
                }

                if (child == root_button || (!destroy_all && ((PathBarItem) child).text_string == split [0]))
                {
                    complete_path += split [0];
                    split = split [1:split.length];
                    if (split.length == 0 || (split.length == 1 && !is_key_path))
                    {
                        activate_item (child, true);
                        maintain_all = true;
                    }
                    else
                        activate_item (child, false);
                    return;
                }

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

    public bool open_child (string? current_path)
    {
        if (current_path == null)
        {
            request_path (complete_path);
            return true;
        }
        if (current_path == complete_path)
            return false;
        int index_of_last_slash = complete_path.index_of ("/", ((!) current_path).length);
        request_path (index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1));
        return true;
    }

    public string? get_selected_child (string current_path)
    {
        if (!complete_path.has_prefix (current_path) || complete_path == current_path)
            return null;
        int index_of_last_slash = complete_path.index_of ("/", current_path.length);
        return index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1);
    }

    /*\
    * * widgets management
    \*/

    private void add_slash_label ()
    {
        add (new Label ("/"));
    }

    private void add_path_bar_item (string label, string complete_path, bool block)
    {
        PathBarItem path_bar_item = new PathBarItem (label);
        path_bar_item.action_target = new Variant.string (complete_path);

        add (path_bar_item);
        activate_item (path_bar_item, block);   // has to be after add()
    }

    private void activate_item (Widget item, bool state)
    {
        StyleContext context = item.get_style_context ();
        if (state == context.has_class ("active"))
            return;
        if (state)
            context.add_class ("active");
        else
            context.remove_class ("active");
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar-item.ui")]
private class PathBarItem : Button
{
    public string text_string { get; construct; }
    [GtkChild] private Label text_label;

    public PathBarItem (string label)
    {
        Object (text_string: label);
        text_label.set_text (label);
    }
}
