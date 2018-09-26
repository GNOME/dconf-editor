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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmarks.ui")]
private class Bookmarks : MenuButton
{
    [GtkChild] private ListBox bookmarks_list_box;
    [GtkChild] private Popover bookmarks_popover;

    [GtkChild] private Image bookmarks_icon;
    [GtkChild] private Switch bookmarked_switch;
    [GtkChild] private Label switch_label;
    [GtkChild] private Revealer bookmarks_editable_revealer;

    private string   current_path = "/";
    private ViewType current_type = ViewType.FOLDER;

    private string schema_id = "ca.desrt.dconf-editor.Bookmarks";   // TODO move in a library
    public string schema_path { private get; internal construct; }
    private GLib.Settings settings;

    private HashTable<string, Bookmark> bookmarks_hashtable = new HashTable<string, Bookmark> (str_hash, str_equal);
    private Bookmark? last_row = null;

    construct
    {
        update_switch_label (ViewType.SEARCH, ViewType.FOLDER, ref switch_label); // init text with "Bookmark this Location"

        install_action_entries ();

        settings = new GLib.Settings.with_path (schema_id, schema_path);

        enable_remove = settings.is_writable ("bookmarks");

        ulong bookmarks_changed_handler = settings.changed ["bookmarks"].connect (on_bookmarks_changed);
        update_bookmarks (settings.get_value ("bookmarks"));

        ulong bookmarks_writable_handler = settings.writable_changed ["bookmarks"].connect (set_switch_sensitivity);
        set_switch_sensitivity ();

        ulong clicked_handler = clicked.connect (() => { if (active) bookmarked_switch.grab_focus (); });

        destroy.connect (() => {
                settings.disconnect (bookmarks_changed_handler);
                settings.disconnect (bookmarks_writable_handler);
                disconnect (clicked_handler);
            });
    }

    private void on_bookmarks_changed (GLib.Settings _settings, string key)
    {
        Variant bookmarks_variant = _settings.get_value ("bookmarks");
        update_bookmarks (bookmarks_variant);
        update_icon_and_switch (bookmarks_variant);
        set_switch_sensitivity ();
    }

    bool enable_remove = true;
    private void set_switch_sensitivity ()
    {
        enable_remove = settings.is_writable ("bookmarks");
        switch_label.set_sensitive (enable_remove);
        bookmarked_switch.set_sensitive (enable_remove);
        bookmarks_editable_revealer.set_reveal_child (!enable_remove);
        bookmarks_list_box.@foreach ((widget) => ((Bookmark) widget).set_enable_remove (enable_remove));
    }

    /*\
    * * Public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        update_switch_label (current_type, type, ref switch_label);

        current_path = path;
        current_type = type;

        update_icon_and_switch (settings.get_value ("bookmarks"));
    }

    // for search
    internal string [] get_bookmarks ()
    {
        string [] all_bookmarks = settings.get_strv ("bookmarks");
        string [] unduplicated_bookmarks = {};
        foreach (string bookmark in all_bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;
        }
        return unduplicated_bookmarks;
    }

    // keyboard call
    internal void down_pressed ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = bookmarks_list_box.get_row_at_index (0);
        else
            row = bookmarks_list_box.get_row_at_index (((!) row).get_index () + 1);

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }
    internal void up_pressed ()
    {
        ListBoxRow? row = bookmarks_list_box.get_selected_row ();
        if (row == null)
            row = last_row;
        else
        {
            int index = ((!) row).get_index ();
            if (index <= 0)
                return;
            row = bookmarks_list_box.get_row_at_index (index - 1);
        }

        if (row == null)
            return;
        bookmarks_list_box.select_row ((!) row);
        ((!) row).grab_focus ();
    }

    internal void bookmark_current_path ()
    {
        if (bookmarked_switch.get_active ())
            return;
        append_bookmark (settings, current_path, current_type);
    }

    internal void unbookmark_current_path ()
    {
        if (!bookmarked_switch.get_active ())
            return;
        remove_bookmark (settings, current_path, current_type);
    }

    internal void update_bookmark_icon (string bookmark, bool bookmark_exists, bool bookmark_has_schema, bool bookmark_is_default)
    {
        Bookmark? bookmark_row = bookmarks_hashtable.lookup (bookmark);
        if (bookmark_row == null)
            return;
        Widget? bookmark_grid = ((!) bookmark_row).get_child ();
        if (bookmark_grid == null)
            assert_not_reached ();
        _update_bookmark_icon (((!) bookmark_grid).get_style_context (), bookmark_exists, bookmark_has_schema, bookmark_is_default);
    }
    private static inline void _update_bookmark_icon (StyleContext context, bool bookmark_exists, bool bookmark_has_schema, bool bookmark_is_default)
    {
        context.add_class ("key");
        if (!bookmark_exists)
        {
            context.add_class ("dconf-key");
            context.add_class ("erase");
            return;
        }
        if (!bookmark_has_schema)
        {
            context.add_class ("dconf-key");
            return;
        }
        context.add_class ("gsettings-key");
        if (!bookmark_is_default)
            context.add_class ("edited");
    }

    /*\
    * * Action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("bookmarks", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        {   "bookmark",   bookmark, "(sy)" },
        { "unbookmark", unbookmark, "(sy)" }
    };

    private void bookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 1/2

        string bookmark;
        uint8 type;
        ((!) path_variant).@get ("(sy)", out bookmark, out type);
        append_bookmark (settings, bookmark, ViewType.from_byte (type));
    }

    private void unbookmark (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bookmarks_popover.closed ();    // if the popover is visible, the size of the listbox could change 2/2

        string bookmark;
        uint8 type;
        ((!) path_variant).@get ("(sy)", out bookmark, out type);
        remove_bookmark (settings, bookmark, ViewType.from_byte (type));
    }

    /*\
    * * Bookmarks management
    \*/

    private const string bookmark_this_search_text = _("Bookmark this Search");
    private const string bookmark_this_location_text = _("Bookmark this Location");
    private static void update_switch_label (ViewType old_type, ViewType new_type, ref Label switch_label)
    {
        if (new_type == ViewType.SEARCH && old_type != ViewType.SEARCH)
            switch_label.label = bookmark_this_search_text;
        else if (new_type != ViewType.SEARCH && old_type == ViewType.SEARCH)
            switch_label.label = bookmark_this_location_text;
    }

    private void update_icon_and_switch (Variant bookmarks_variant)
    {
        Variant variant = new Variant ("(sy)", current_path, ViewType.to_byte (current_type));
        string bookmark_name = get_bookmark_name (current_path, current_type);
        if (bookmark_name in bookmarks_variant.get_strv ())
        {
            if (bookmarks_icon.icon_name != "starred-symbolic")
                bookmarks_icon.icon_name = "starred-symbolic";
            update_switch_state (true, ref bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.unbookmark(" + variant.print (true) + ")");
            bookmarked_switch.set_sensitive (enable_remove);
        }
        else
        {
            if (bookmarks_icon.icon_name != "non-starred-symbolic")
                bookmarks_icon.icon_name = "non-starred-symbolic";
            update_switch_state (false, ref bookmarked_switch);
            bookmarked_switch.set_detailed_action_name ("bookmarks.bookmark(" + variant.print (true) + ")");
            bookmarked_switch.set_sensitive (enable_remove);
        }
    }
    private static void update_switch_state (bool bookmarked, ref Switch bookmarked_switch)
    {
        if (bookmarked == bookmarked_switch.active)
            return;
        bookmarked_switch.set_detailed_action_name ("ui.empty(('',byte 255))");
        bookmarked_switch.active = bookmarked;
    }

    private void update_bookmarks (Variant bookmarks_variant)
    {
        set_detailed_action_name ("ui.update-bookmarks-icons(" + bookmarks_variant.print (true) + ")");  // TODO disable action on popover closed
        create_bookmark_rows (bookmarks_variant, enable_remove, ref bookmarks_list_box, ref bookmarks_hashtable, ref last_row);
    }
    private static void create_bookmark_rows (Variant bookmarks_variant, bool enable_remove, ref ListBox bookmarks_list_box, ref HashTable<string, Bookmark> bookmarks_hashtable, ref Bookmark? last_row)
    {
        bookmarks_list_box.@foreach ((widget) => widget.destroy ());
        bookmarks_hashtable.remove_all ();
        last_row = null;

        string [] bookmarks = bookmarks_variant.get_strv ();
        string [] unduplicated_bookmarks = new string [0];
        foreach (string bookmark in bookmarks)
        {
            if (DConfWindow.is_path_invalid (bookmark))
                continue;
            if (bookmark in unduplicated_bookmarks)
                continue;
            unduplicated_bookmarks += bookmark;

            Bookmark bookmark_row = create_bookmark_row (bookmark, enable_remove);
            bookmarks_list_box.add (bookmark_row);
            bookmarks_hashtable.insert (bookmark, bookmark_row);
            last_row = bookmark_row;
        }
        ListBoxRow? first_row = bookmarks_list_box.get_row_at_index (0);
        if (first_row != null)
            bookmarks_list_box.select_row ((!) first_row);
    }
    private static inline Bookmark create_bookmark_row (string bookmark, bool enable_remove)
    {
        Bookmark bookmark_row = new Bookmark (bookmark);
        if (bookmark.has_prefix ("?"))
        {
            Variant variant = new Variant.string (bookmark.slice (1, bookmark.length));
            bookmark_row.set_detailed_action_name ("ui.open-search(" + variant.print (false) + ")");
        }
        else if (ModelUtils.is_key_path (bookmark))
        {
            Variant variant = new Variant ("(sq)", bookmark, ModelUtils.undefined_context_id);
            bookmark_row.set_detailed_action_name ("ui.open-object(" + variant.print (true) + ")");    // TODO save context
        }
        else
        {
            Variant variant = new Variant.string (bookmark);
            bookmark_row.set_detailed_action_name ("ui.open-folder(" + variant.print (false) + ")");
        }
        bookmark_row.set_enable_remove (enable_remove); // put it here as setting detailed action name makes the button sensitive
        bookmark_row.show ();
        return bookmark_row;
    }

    private static void append_bookmark (GLib.Settings settings, string path, ViewType type)
    {
        string bookmark_name = get_bookmark_name (path, type);
        string [] bookmarks = settings.get_strv ("bookmarks");
        if (bookmark_name in bookmarks)
            return;

        bookmarks += bookmark_name;
        settings.set_strv ("bookmarks", bookmarks);
    }

    private static void remove_bookmark (GLib.Settings settings, string path, ViewType type)
    {
        string bookmark_name = get_bookmark_name (path, type);
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        if (!(bookmark_name in old_bookmarks))
            return;

        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != bookmark_name && !(bookmark in new_bookmarks))
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }

    private static inline string get_bookmark_name (string path, ViewType type)
    {
        if (type == ViewType.SEARCH)
            return "?" + path;
        else
            return path;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : ListBoxRow
{
    [GtkChild] private Grid main_grid;
    [GtkChild] private Label bookmark_label;
    [GtkChild] private Button destroy_button;

    internal Bookmark (string bookmark_name)
    {
        string   bookmark_text;
        ViewType bookmark_type;
        if (bookmark_name.has_prefix ("?"))
        {
            bookmark_text = bookmark_name.slice (1, bookmark_name.length);
            bookmark_type = ViewType.SEARCH;
            main_grid.get_style_context ().add_class ("search");
        }
        else
        {
            bookmark_text = bookmark_name;
            if (ModelUtils.is_folder_path (bookmark_text))  // class is updated elsewhere for keys
            {
                main_grid.get_style_context ().add_class ("folder");
                bookmark_type = ViewType.FOLDER;
            }
            else
                bookmark_type = ViewType.OBJECT;
        }
        bookmark_label.set_label (bookmark_text);
        Variant variant = new Variant ("(sy)", bookmark_text, ViewType.to_byte (bookmark_type));
        destroy_button.set_detailed_action_name ("bookmarks.unbookmark(" + variant.print (true) + ")");
    }

    internal void set_enable_remove (bool new_sensitivity)
    {
        destroy_button.set_sensitive (new_sensitivity);
    }
}
