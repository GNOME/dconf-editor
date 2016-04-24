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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    private const GLib.ActionEntry [] action_entries =
    {
        /* { "reset-recursive", reset_recursively }, */
        { "reset-visible", reset }
    };

    private string current_path = "/";
    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_fullscreen = false;

    private SettingsModel model = new SettingsModel ();
    [GtkChild] private TreeView dir_tree_view;
    [GtkChild] private TreeSelection dir_tree_selection;

    [GtkChild] private ListBox key_list_box;
    private GLib.ListStore? key_model = null;

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");
    [GtkChild] private Bookmarks bookmarks_button;

    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;
    [GtkChild] private Button search_next_button;

    [GtkChild] private MenuButton info_button;

    public DConfWindow ()
    {
        add_action_entries (action_entries, this);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-fullscreen"))
            fullscreen ();
        else if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        search_bar.connect_entry (search_entry);

        dir_tree_view.set_model (model);

        current_path = settings.get_string ("saved-view");
        if (!settings.get_boolean ("restore-view") || current_path == "/" || current_path == "" || !scroll_to_path (current_path))
        {
            TreeIter iter;
            if (model.get_iter_first (out iter))
                dir_tree_selection.select_iter (iter);
        }
    }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private void on_show ()
    {
        if (!settings.get_boolean ("show-warning"))
            return;

        Gtk.MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.INFO, ButtonsType.NONE, _("Thanks for using Dconf Editor for editing your settings!"));
        dialog.format_secondary_text (_("Don't forget that some options may break applications, so be careful."));
        dialog.add_buttons (_("I'll be careful."), ResponseType.ACCEPT);

        // TODO don't show box if the user explicitely said she wanted to see the dialog next time?
        Box box = (Box) dialog.get_message_area ();
        CheckButton checkbutton = new CheckButton.with_label (_("Show this dialog next time."));
        checkbutton.visible = true;
        checkbutton.active = true;
        checkbutton.margin_top = 5;
        box.add (checkbutton);

        dialog.response.connect (() => { if (!checkbutton.active) settings.set_boolean ("show-warning", false); });
        dialog.run ();
        dialog.destroy ();
    }

    [GtkCallback]
    private bool on_window_state_event (Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        if ((event.changed_mask & Gdk.WindowState.FULLSCREEN) != 0)
            window_is_fullscreen = (event.new_window_state & Gdk.WindowState.FULLSCREEN) != 0;

        return false;
    }

    [GtkCallback]
    private void on_size_allocate ()
    {
        if (window_is_maximized || window_is_fullscreen)
            return;
        get_size (out window_width, out window_height);
    }

    [GtkCallback]
    private void on_destroy ()
    {
        get_application ().withdraw_notification ("copy");

        settings.set_string ("saved-view", current_path);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.set_boolean ("window-is-fullscreen", window_is_fullscreen);

        base.destroy ();
    }

    /*\
    * * Dir TreeView
    \*/

    [GtkCallback]
    private void dir_selected_cb ()
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 1/2

        key_model = null;

        TreeIter iter;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            key_model = model.get_directory (iter).key_model;
            current_path = model.get_directory (iter).full_name;
            bookmarks_button.current_path = current_path;

            GLib.Menu menu = new GLib.Menu ();
            menu.append (_("Copy current path"), "app.copy(\"" + current_path + "\")");   // TODO protection against some chars in text? 1/2
            GLib.Menu section = new GLib.Menu ();
            section.append (_("Reset visible keys"), "win.reset-visible");
            /* section.append (_("Reset recursively"), "win.reset-recursive"); */
            section.freeze ();
            menu.append_section (null, section);
            menu.freeze ();
            info_button.set_menu_model ((MenuModel) menu);
        }

        key_list_box.bind_model (key_model, new_list_box_row);
    }

    [GtkCallback]
    private bool scroll_to_path (string full_name)
    {
        TreeIter iter;
        if (model.get_iter_first (out iter))
        {
            do
            {
                Directory dir = model.get_directory (iter);

                if (dir.full_name == full_name)
                {
                    select_dir (iter);
                    return true;
                }
            }
            while (get_next_iter (ref iter));
        }
        MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK, _("Oops! Cannot find something at this path."));
        dialog.run ();
        dialog.destroy ();
        return false;
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        if (((Key) item).has_schema)
        {
            KeyListBoxRowEditable key_list_box_row = new KeyListBoxRowEditable ((GSettingsKey) item);
            key_list_box_row.button_press_event.connect (on_button_pressed);
            key_list_box_row.show_dialog.connect (() => {
                    KeyEditor key_editor = new KeyEditor ((GSettingsKey) item);
                    key_editor.set_transient_for (this);
                    key_editor.run ();
                });
            return key_list_box_row;
        }
        else
        {
            KeyListBoxRowEditableNoSchema key_list_box_row = new KeyListBoxRowEditableNoSchema ((DConfKey) item);
            key_list_box_row.button_press_event.connect (on_button_pressed);
            key_list_box_row.show_dialog.connect (() => {
                    KeyEditorNoSchema key_editor = new KeyEditorNoSchema ((DConfKey) item);
                    key_editor.set_transient_for (this);
                    key_editor.run ();
                });
            return key_list_box_row;
        }
        // TODO bug: list_box_row is always activated after the dialog destruction if mouse is over at this time
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) ((KeyListBoxRow) widget).get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();
        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((KeyListBoxRow) list_box_row.get_child ()).show_dialog ();
    }

    /*\
    * * Action entries
    \*/

    private void reset ()
    {
        reset_generic (key_model, false);
    }

    /* private void reset_recursively ()
    {
        reset_generic (key_model, true);
    } */

    private void reset_generic (GLib.ListStore objects, bool recursively)
    {
        for (uint position = 0;; position++)
        {
            Object? object = objects.get_object (position);
            if (object == null)
                return;

            SettingObject setting_object = (SettingObject) ((!) object);
            /* if (recursively && setting_object.is_view)
                reset_generic (((Directory) setting_object).key_model, true);
            else */ if (setting_object.is_view || !((Key) setting_object).has_schema)
                continue;
            ((GSettingsKey) setting_object).set_to_default ();
        }
    }

    /*\
    * * Search box
    \*/

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)     // TODO better?
    {
        string name = Gdk.keyval_name (event.keyval);

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            switch (name)
            {
                case "b":
                    if (info_button.active)
                        info_button.active = false;
                    bookmarks_button.clicked ();
                    return true;
                case "d":
                    if (info_button.active)
                        info_button.active = false;
                    bookmarks_button.set_bookmarked (true);
                    return true;
                case "D":
                    if (info_button.active)
                        info_button.active = false;
                    bookmarks_button.set_bookmarked (false);
                    return true;
                case "f":
                    if (bookmarks_button.active)
                        bookmarks_button.active = false;
                    if (info_button.active)
                        info_button.active = false;
                    search_bar.set_search_mode (!search_bar.get_search_mode ());
                    return true;
                case "c":
                    ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row == null ? current_path : ((KeyListBoxRow) ((!) selected_row).get_child ()).get_text ());
                    return true;
                case "C":
                    ((ConfigurationEditor) get_application ()).copy (current_path);
                    return true;
                case "F1":
                    if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                        return false;   // help overlay
                    ((ConfigurationEditor) get_application ()).about_cb ();
                    return true;
                default:
                    break;  // TODO make <ctrl>v work; https://bugzilla.gnome.org/show_bug.cgi?id=762257 is WONTFIX
            }
        }
        else if (name == "F10")
        {
            bookmarks_button.active = false;
            return false;
        }
        else if (name == "plus"   || name == "minus" ||
                 name == "KP_Add" || name == "KP_Subtract")     // https://bugzilla.gnome.org/show_bug.cgi?id=762256 is WONTFIX
            return false;                                       // TODO GtkTreeView has a weird behaviour if expanding without children

        if (bookmarks_button.active || info_button.active)      // TODO open bug about modal popovers and search_bar
            return false;

        return search_bar.handle_event (event);
    }

    [GtkCallback]
    private void on_menu_button_clicked ()
    {
        search_bar.set_search_mode (false);
    }

    [GtkCallback]
    private void find_next_cb ()
    {
        if (!search_bar.get_search_mode ())     // TODO better; switches to next list_box_row when keyboard-activating an entry of the popover
            return;

        TreeIter iter;
        int position = 0;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
            if (selected_row != null)
                position = ((!) selected_row).get_index () + 1;
        }
        else if (!model.get_iter_first (out iter))      // TODO doesn't that reset iter?
            return;     // TODO better

        bool on_first_directory = true;
        do
        {
            Directory dir = model.get_directory (iter);

            if (!on_first_directory && dir.name.index_of (search_entry.text) >= 0)
            {
                select_dir (iter);
                return;
            }
            on_first_directory = false;

            /* Select next key that matches */
            GLib.ListStore key_model = dir.key_model;
            while (position < key_model.get_n_items ())
            {
                Key key = (Key) key_model.get_object (position);
                if (key_matches (key, search_entry.text))
                {
                    select_dir (iter);
                    key_list_box.select_row (key_list_box.get_row_at_index (position));
                    // TODO select key in ListBox
                    return;
                }
                position++;
            }

            position = 0;
        }
        while (get_next_iter (ref iter));

        search_next_button.set_sensitive (false);
    }

    private void select_dir (TreeIter iter)
    {
        dir_tree_view.expand_to_path (model.get_path (iter));
        dir_tree_selection.select_iter (iter);
        dir_tree_view.scroll_to_cell (model.get_path (iter), null, false, 0, 0);
    }

    private bool key_matches (Key key, string text)
    {
        /* Check key name */
        if (key.name.index_of (text) >= 0)
            return true;

        /* Check key schema (description) */
        if (key.has_schema)
        {
            if (((GSettingsKey) key).summary.index_of (text) >= 0)
                return true;
            if (((GSettingsKey) key).description.index_of (text) >= 0)
                return true;
        }

        /* Check key value */
        if (key.value.is_of_type (VariantType.STRING) && key.value.get_string ().index_of (text) >= 0)
            return true;

        return false;
    }

    private bool get_next_iter (ref TreeIter iter)
    {
        /* Search children next */
        if (model.iter_has_child (iter))
        {
            model.iter_nth_child (out iter, iter, 0);
            return true;
        }

        /* Move to the next branch */
        while (!model.iter_next (ref iter))
        {
            /* Otherwise move to the parent and onto the next iter */
            if (!model.iter_parent (out iter, iter))
                return false;
        }

        return true;
    }
}
