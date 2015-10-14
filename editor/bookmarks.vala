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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmarks.ui")]
public class Bookmarks : MenuButton
{
    [GtkChild] private ListBox bookmarks_list_box;
    [GtkChild] private Popover bookmarks_popover;

    public string schema { get; construct; }
    private GLib.Settings settings;
    private GLib.ListStore bookmarks_model;

    public signal string get_current_path ();
    public signal bool bookmark_activated (string bookmark);

    construct
    {
        settings = new GLib.Settings (schema);
        settings.changed ["bookmarks"].connect (update_bookmarks);
        update_bookmarks ();
    }

    private void update_bookmarks ()
    {
        bookmarks_model = new GLib.ListStore (typeof (Bookmark));
        string [] bookmarks = settings.get_strv ("bookmarks");
        foreach (string bookmark in bookmarks)
        {
            Bookmark bookmark_row = new Bookmark (bookmark);
            bookmark_row.destroy_button.clicked.connect (() => { remove_bookmark (bookmark); });
            bookmarks_model.append (bookmark_row);
        }
        bookmarks_list_box.bind_model (bookmarks_model, new_bookmark_row);
    }

    [GtkCallback]
    private void add_bookmark_cb ()
    {
        bookmarks_popover.closed ();

        string path = get_current_path ();

        string [] bookmarks = settings.get_strv ("bookmarks");
        bookmarks += path;
        settings.set_strv ("bookmarks", bookmarks);
    }

    private Widget new_bookmark_row (Object item)
    {
        return (Bookmark) item;
    }

    [GtkCallback]
    private void bookmark_activated_cb (ListBoxRow list_box_row)
    {
        bookmarks_popover.closed ();
        string bookmark = ((Bookmark) list_box_row.get_child ()).bookmark_name;
        if (!bookmark_activated (bookmark))
            warning ("broken bookmark: %s", bookmark);
    }

    private void remove_bookmark (string bookmark_name)
    {
        bookmarks_popover.closed ();
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != bookmark_name)
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : Grid
{
    public string bookmark_name { get; private set; }

    [GtkChild] private Label bookmark_label;
    [GtkChild] public Button destroy_button;

    public Bookmark (string name)
    {
        bookmark_name = name;
        bookmark_label.set_label (name);
    }
}
