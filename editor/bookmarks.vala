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

    [GtkChild] private Image bookmarks_icon;
    [GtkChild] private Switch bookmarked_switch;
    public string current_path { get; set; }

    public string schema_id { get; construct; }
    private GLib.Settings settings;
    private GLib.ListStore bookmarks_model;

    public signal bool bookmark_activated (string bookmark);

    construct
    {
        settings = new GLib.Settings (schema_id);
        settings.changed ["bookmarks"].connect (update_bookmarks);
        settings.changed ["bookmarks"].connect (update_icon_and_switch);    // TODO updates switch if switch changed settings...
        notify ["current-path"].connect (update_icon_and_switch);
        bookmarked_switch.notify ["active"].connect (switch_changed_cb);    // TODO activated when current_path changes...
        update_bookmarks ();
        bookmarked_switch.grab_focus ();
    }

    private void update_icon_and_switch ()
    {
        bool is_bookmarked = current_path in settings.get_strv ("bookmarks");
        bookmarks_icon.icon_name = is_bookmarked ? "starred-symbolic" : "non-starred-symbolic";
        bookmarked_switch.active = is_bookmarked;
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
    public string bookmark_name { get; private set; }

    [GtkChild] private Label bookmark_label;
    [GtkChild] public Button destroy_button;

    public Bookmark (string name)
    {
        bookmark_name = name;
        bookmark_label.set_label (name);
    }
}
