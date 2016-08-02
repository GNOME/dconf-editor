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
public class Bookmarks : MenuButton, PathElement
{
    [GtkChild] private ListBox bookmarks_list_box;
    [GtkChild] private Popover bookmarks_popover;

    [GtkChild] private Image bookmarks_icon;
    [GtkChild] private Switch bookmarked_switch;

    private string current_path = "/";
    public void set_path (string path)
    {
        if (current_path != path)
            current_path = path;
        update_icon_and_switch ();
    }

    public string schema_id { get; construct; }
    private GLib.Settings settings;

    private ulong switch_active_handler = 0;

    construct
    {
        settings = new GLib.Settings (schema_id);

        switch_active_handler = bookmarked_switch.notify ["active"].connect (switch_changed_cb);
        ulong bookmarks_changed_handler = settings.changed ["bookmarks"].connect (() => {
                update_bookmarks ();
                update_icon_and_switch ();
            });

        update_bookmarks ();
        bookmarked_switch.grab_focus ();

        destroy.connect (() => settings.disconnect (bookmarks_changed_handler));
        bookmarked_switch.destroy.connect (() => bookmarked_switch.disconnect (switch_active_handler));
    }

    private void update_icon_and_switch ()
    {
        if (current_path in settings.get_strv ("bookmarks"))
        {
            if (bookmarks_icon.icon_name != "starred-symbolic")
                bookmarks_icon.icon_name = "starred-symbolic";
            update_switch (true);
        }
        else
        {
            if (bookmarks_icon.icon_name != "non-starred-symbolic")
                bookmarks_icon.icon_name = "non-starred-symbolic";
            update_switch (false);
        }
    }
    private void update_switch (bool bookmarked)
        requires (switch_active_handler != 0)
    {
        if (bookmarked == bookmarked_switch.active)
            return;
        SignalHandler.block (bookmarked_switch, switch_active_handler);
        bookmarked_switch.active = bookmarked;
        SignalHandler.unblock (bookmarked_switch, switch_active_handler);
    }

    private void update_bookmarks ()
    {
        bookmarks_list_box.@foreach ((widget) => widget.destroy ());

        string [] bookmarks = settings.get_strv ("bookmarks");
        foreach (string bookmark in bookmarks)
        {
            Bookmark bookmark_row = new Bookmark (bookmark);
            ulong destroy_button_clicked_handler = bookmark_row.destroy_button.clicked.connect (() => remove_bookmark (bookmark));
            bookmark_row.destroy_button.destroy.connect (() => bookmark_row.destroy_button.disconnect (destroy_button_clicked_handler));
            bookmark_row.show ();
            bookmarks_list_box.add (bookmark_row);
        }
    }

    private void switch_changed_cb ()
    {
        bookmarks_popover.closed ();

        string [] bookmarks = settings.get_strv ("bookmarks");

        if (!bookmarked_switch.get_active ())
            remove_bookmark (current_path);
        else if (!(current_path in bookmarks))
        {
            bookmarks += current_path;
            settings.set_strv ("bookmarks", bookmarks);
        }
    }

    public void set_bookmarked (bool new_state)
    {
        if (bookmarked_switch.get_active () != new_state)
            bookmarked_switch.set_active (new_state);
    }

    [GtkCallback]
    private void bookmark_activated_cb (ListBoxRow list_box_row)
    {
        bookmarks_popover.closed ();
        string bookmark = ((Bookmark) list_box_row.get_child ()).bookmark_name;
        request_path (bookmark);
    }

    private void remove_bookmark (string bookmark_name)
    {
        bookmarks_popover.closed ();
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        if (!(bookmark_name in old_bookmarks))
            return;
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
    public string bookmark_name { get; construct; }

    [GtkChild] private Label bookmark_label;
    [GtkChild] public Button destroy_button;

    construct
    {
        bookmark_label.set_label (bookmark_name);
    }

    public Bookmark (string bookmark_name)
    {
        Object (bookmark_name: bookmark_name);
    }
}
