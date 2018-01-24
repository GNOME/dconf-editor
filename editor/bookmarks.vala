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

    private string current_path = "/";
    public void set_path (string path)
    {
        if (current_path != path)
            current_path = path;
        update_icon_and_switch ();
    }

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    public string schema_path { get; construct; }
    private GLib.Settings settings;

    private ulong switch_active_handler = 0;

    construct
    {
        settings = new GLib.Settings.with_path (schema_id, schema_path);

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

    public string [] get_bookmarks ()
    {
        return settings.get_strv ("bookmarks");
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
        string [] unduplicated_bookmarks = new string [0];
        foreach (string bookmark in bookmarks)
        {
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;

            Bookmark bookmark_row = new Bookmark (bookmark);
            if (SettingsModel.is_key_path (bookmark))
            {
                Variant variant = new Variant ("(ss)", bookmark, "");
                bookmark_row.set_detailed_action_name ("ui.open-object(" + variant.print (false) + ")");    // TODO save context
            }
            else
            {
                Variant variant = new Variant.string (bookmark);
                bookmark_row.set_detailed_action_name ("ui.open-folder(" + variant.print (false) + ")");
            }
            ulong destroy_button_clicked_handler = bookmark_row.destroy_button.clicked.connect (() => remove_bookmark (bookmark));
            bookmark_row.destroy_button.destroy.connect (() => bookmark_row.destroy_button.disconnect (destroy_button_clicked_handler));
            bookmark_row.show ();
            bookmarks_list_box.add (bookmark_row);
        }
    }

    private void switch_changed_cb ()
    {
        bookmarks_popover.closed ();

        if (!bookmarked_switch.get_active ())
            remove_bookmark (current_path);
        else
            bookmark_current_path ();
    }

    private void bookmark_current_path ()
    {
        string [] bookmarks = settings.get_strv ("bookmarks");
        if (!(current_path in bookmarks))
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

    private void remove_bookmark (string bookmark_name)
    {
        bookmarks_popover.closed ();
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        if (!(bookmark_name in old_bookmarks))
            return;
        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != bookmark_name && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : ListBoxRow
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
