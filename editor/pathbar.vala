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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar.ui")]
public class PathBar : Box
{
    [GtkChild] private PathBarItem root_button;

    public string complete_path { get; private set; default = ""; }

    construct
    {
        add_slash_label ();
    }

    /*\
    * * public calls
    \*/

    public void set_path (ViewType type, string path)
    {
        if (type == ViewType.SEARCH)
        {
            update_cursors_for_search (path, true);
            return;
        }
        update_cursors_for_search (path, false);

        activate_item (root_button, path == "/");

        complete_path = "";
        string [] split = path.split ("/", /* max tokens disabled */ 0);
        string last = split [split.length - 1];

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

                PathBarItem item = (PathBarItem) child;

                if (maintain_all)
                {
                    complete_path += item.text_string;
                    activate_item (item, false);
                    return;
                }

                if (item == root_button || (!destroy_all && item.text_string == split [0]))
                {
                    complete_path += split [0];
                    split = split [1:split.length];
                    if (split.length == 0 || (split.length == 1 && type == ViewType.FOLDER))
                    {
                        activate_item (item, true);
                        maintain_all = true;
                    }
                    else
                        activate_item (item, false);
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
                    add_path_bar_item (item, complete_path, true, type == ViewType.FOLDER && (index == split.length - 2));
                    add_slash_label ();
                    index++;
                }
            }

            /* if key path */
            if (type == ViewType.OBJECT)
            {
                complete_path += last;
                add_path_bar_item (last, complete_path, false, true);
            }
        }

        show_all ();
    }

    public string get_selected_child (string current_path)
    {
        if (!complete_path.has_prefix (current_path) || complete_path == current_path)
            return "";
        int index_of_last_slash = complete_path.index_of ("/", current_path.length);
        return index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1);
    }

    public void update_ghosts (string non_ghost_path, bool is_search)
    {
        string action_target = "";
        @foreach ((child) => {
                StyleContext context = child.get_style_context ();
                if (child is PathBarItem)
                {
                    PathBarItem item = (PathBarItem) child;
                    Variant? variant = item.get_action_target_value ();
                    if (variant == null)
                        assert_not_reached ();
                    if (((!) variant).get_type_string () == "s")    // directory
                        action_target = ((!) variant).get_string ();
                    else
                    {
                        string unused;
                        ((!) variant).get ("(ss)", out action_target, out unused);
                    }

                    if (context.has_class ("active"))
                    {
                        if (is_search)
                        {
                            item.set_cursor_type (PathBarItem.CursorType.POINTER);
                            item.set_detailed_action_name (item.default_action);
                        }
                        else
                        {
                            item.set_cursor_type (PathBarItem.CursorType.CONTEXT);
                            item.set_action_name ("ui.empty");
                        }
                        context.remove_class ("inexistent");
                    }
                    else if (non_ghost_path.has_prefix (action_target))
                    {
                        item.set_cursor_type (PathBarItem.CursorType.POINTER);
                        item.set_detailed_action_name (item.default_action);
                        context.remove_class ("inexistent");
                    }
                    else
                    {
                        item.set_cursor_type (PathBarItem.CursorType.DEFAULT);
                        item.set_detailed_action_name (item.alternative_action);
                        context.add_class ("inexistent");
                    }
                }
                else if (non_ghost_path.has_prefix (action_target))
                    context.remove_class ("inexistent");
                else
                    context.add_class ("inexistent");
            });
    }

    private void update_cursors_for_search (string current_path, bool is_search)
    {
        if (is_search)
            get_style_context ().add_class ("greyed-pathbar");
        else
            get_style_context ().remove_class ("greyed-pathbar");

        @foreach ((child) => {
                if (!(child is PathBarItem))
                    return;
                StyleContext context = child.get_style_context ();
                if (!context.has_class ("active"))
                    return;
                PathBarItem item = (PathBarItem) child;
                if (is_search)
                {
                    item.set_cursor_type (PathBarItem.CursorType.POINTER);
                    item.set_detailed_action_name (item.default_action);
                }
                else
                {
                    item.set_cursor_type (PathBarItem.CursorType.CONTEXT);
                    item.set_action_name ("ui.empty");
                }
            });
    }

    /*\
    * * widgets management
    \*/

    private void add_slash_label ()
    {
        add (new Label ("/"));
    }

    private void add_path_bar_item (string label, string complete_path, bool is_folder, bool block)
    {
        PathBarItem path_bar_item;
        if (is_folder)
        {
            Variant variant = new Variant.string (complete_path);
            string _variant = variant.print (false);
            path_bar_item = new PathBarItem (label, "ui.open-folder(" + _variant + ")", "ui.notify-folder-emptied(" + _variant + ")");
        }
        else
        {
            Variant variant = new Variant ("(ss)", complete_path, "");
            string _variant = variant.print (false);
            path_bar_item = new PathBarItem (label, "ui.open-object(" + _variant + ")", "ui.notify-object-deleted(" + _variant + ")");
        }
        add (path_bar_item);
        activate_item (path_bar_item, block);   // has to be after add()
    }

    private void activate_item (PathBarItem item, bool state)   // never called when current_view is search
    {
        StyleContext context = item.get_style_context ();
        if (state == context.has_class ("active"))
            return;
        if (state)
        {
            item.set_cursor_type (PathBarItem.CursorType.CONTEXT);
            item.set_action_name ("ui.empty");
            context.add_class ("active");
        }
        else
        {
            item.set_cursor_type (PathBarItem.CursorType.POINTER);
            item.set_detailed_action_name (item.default_action);
            context.remove_class ("active");
        }
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/pathbar-item.ui")]
private class PathBarItem : Button
{
    public string alternative_action { get; construct; }
    public string default_action { get; construct; }
    public string text_string { get; construct; }
    [GtkChild] private Label text_label;

    public enum CursorType {
        DEFAULT,
        POINTER,
        CONTEXT
    }
    private CursorType cursor_type = CursorType.POINTER;

    private bool hover = false; // there’s probably a function for that

    construct
    {
        enter_notify_event.connect (() => { hover = true;  set_new_cursor_type (cursor_type); });
        leave_notify_event.connect (() => { hover = false; set_new_cursor_type (CursorType.DEFAULT); });
    }

    public void set_cursor_type (CursorType cursor_type)
    {
        this.cursor_type = cursor_type;
        if (hover)
            set_new_cursor_type (cursor_type);
    }

    private void set_new_cursor_type (CursorType new_cursor_type)
    {
        Gdk.Window? gdk_window = get_window ();
        Gdk.Display? display = Gdk.Display.get_default ();
        if (gdk_window == null || display == null)
            return;

        Gdk.Cursor? cursor = null;
        switch (new_cursor_type)
        {
            case CursorType.DEFAULT: cursor = null; break;
            case CursorType.POINTER: cursor = new Gdk.Cursor.from_name ((!) display, "pointer"); break;
            case CursorType.CONTEXT: cursor = new Gdk.Cursor.from_name ((!) display, "context-menu"); break;
        }
        ((!) gdk_window).set_cursor (cursor);
    }

    [GtkCallback]
    private void update_cursor ()
    {
        if (get_style_context ().has_class ("inexistent"))
            return;

        if (cursor_type != CursorType.CONTEXT)
        {
            cursor_type = CursorType.CONTEXT;
            set_new_cursor_type (cursor_type);
            return;
        }

        GLib.Menu menu = new GLib.Menu ();
        menu.append (_("Copy current path"), "ui.copy-path"); // or "app.copy(\"" + get_action_target_value ().get_string () + "\")"
        menu.freeze ();

        Popover popover_test = new Popover.from_model (this, (MenuModel) menu);
        popover_test.popup ();
    }

    public PathBarItem (string label, string _default_action, string _alternative_action)
    {
        Object (text_string: label, default_action: _default_action, alternative_action: _alternative_action);
        text_label.set_text (label);
        set_detailed_action_name (_default_action);
    }
}
