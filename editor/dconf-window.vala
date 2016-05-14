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

    [GtkChild] private PathBar pathbar;

    public DConfWindow ()
    {
        add_action_entries (action_entries, this);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-fullscreen"))
            fullscreen ();
        else if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        search_bar.connect_entry (search_entry);

        settings.changed["theme"].connect (() => {
                string theme = settings.get_string ("theme");
                StyleContext context = get_style_context ();
                if (theme == "three-twenty-two" && context.has_class ("small-rows"))
                    context.remove_class ("small-rows");
                else if (theme == "small-rows" && !context.has_class ("small-rows"))
                    context.add_class ("small-rows");
            });
        if (settings.get_string ("theme") == "small-rows")
            get_style_context ().add_class ("small-rows");

        dir_tree_view.set_model (model);

        current_path = settings.get_string ("saved-view");
        if (!settings.get_boolean ("restore-view") || current_path == "" || !scroll_to_path (current_path))
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
        Directory dir;
        if (dir_tree_selection.get_selected (null, out iter))
            dir = model.get_directory (iter);
        else
            dir = model.get_root_directory ();

        key_model = dir.key_model;
        current_path = dir.full_name;
        bookmarks_button.current_path = current_path;
        pathbar.set_path (current_path);

        GLib.Menu menu = new GLib.Menu ();
        menu.append (_("Copy current path"), "app.copy(\"" + current_path + "\")");   // TODO protection against some chars in text? 1/2
        GLib.Menu section = new GLib.Menu ();
        section.append (_("Reset visible keys"), "win.reset-visible");
        /* section.append (_("Reset recursively"), "win.reset-recursive"); */
        section.freeze ();
        menu.append_section (null, section);
        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);

        key_list_box.bind_model (key_model, new_list_box_row);
    }

    [GtkCallback]
    private bool scroll_to_path (string full_name)
    {
        if (full_name == "/")
        {
            dir_tree_selection.unselect_all ();
            return true;
        }

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
        ClickableListBoxRow row;
        if (((SettingObject) item).is_view)
        {
            row = new FolderListBoxRow (((SettingObject) item).name, ((SettingObject) item).full_name);
            row.on_row_clicked.connect (() => {
                    if (!scroll_to_path (((SettingObject) item).full_name))
                        warning ("Something got wrong with this folder.");
                });
        }
        else
        {
            Key key = (Key) item;
            if (key.has_schema)
                row = new KeyListBoxRowEditable ((GSettingsKey) key);
            else
                row = new KeyListBoxRowEditableNoSchema ((DConfKey) key);
            row.on_row_clicked.connect (() => { new_key_editor (key); });
            // TODO bug: row is always visually activated after the dialog destruction if mouse is over at this time
        }
        row.button_press_event.connect (on_button_pressed);
        return row;
    }

    private void new_key_editor (Key key)
    {
        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);
        Variant dict = dict_container [0];

        // TODO use VariantDict
        string tmp_string_1, tmp_string_2;

        if (!dict.lookup ("key-name",     "s", out tmp_string_1)) assert_not_reached ();
        if (!dict.lookup ("parent-path",  "s", out tmp_string_2)) assert_not_reached ();

        KeyEditor key_editor = new KeyEditor (has_schema, tmp_string_1, tmp_string_2);

        if (!dict.lookup ("type-code",    "s", out tmp_string_1)) assert_not_reached ();

        if (dict.lookup ("schema-id",     "s", out tmp_string_2)) key_editor.add_row_from_label (_("Schema"),      tmp_string_2);
        if (dict.lookup ("summary",       "s", out tmp_string_2)) key_editor.add_row_from_label (_("Summary"),     tmp_string_2);
        if (dict.lookup ("description",   "s", out tmp_string_2)) key_editor.add_row_from_label (_("Description"), tmp_string_2);
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (dict.lookup ("type-name",     "s", out tmp_string_2)) key_editor.add_row_from_label (_("Type"),        tmp_string_2);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string_2)) key_editor.add_row_from_label (_("Minimum"),     tmp_string_2);
        if (dict.lookup ("maximum",       "s", out tmp_string_2)) key_editor.add_row_from_label (_("Maximum"),     tmp_string_2);
        if (dict.lookup ("default-value", "s", out tmp_string_2)) key_editor.add_row_from_label (_("Default"),     tmp_string_2);

        Widget key_editor_child = create_child (key_editor, key);
        if (has_schema)
        {
            Switch custom_value_switch = new Switch ();
            custom_value_switch.width_request = 100; /* same request than for button_cancel/button_apply on scale 1; TODO better */
            custom_value_switch.halign = Align.END;
            custom_value_switch.hexpand = true;
            custom_value_switch.show ();
            key_editor.add_row_from_widget (_("Use default value"), custom_value_switch, null);

            custom_value_switch.bind_property ("active", key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            GSettingsKey gkey = (GSettingsKey) key;
            custom_value_switch.set_active (gkey.is_default);
            custom_value_switch.notify ["active"].connect (() => { key_editor.switch_is_active (custom_value_switch.get_active ()); });

            key_editor.response.connect ((dialog, response_id) => {
                    if (response_id == ResponseType.APPLY)
                    {
                        if (!custom_value_switch.active)
                        {
                            Variant variant = ((KeyEditorChild) key_editor_child).get_variant ();
                            if (key.value != variant)
                                key.value = variant;
                        }
                        else if (!gkey.is_default)
                            gkey.set_to_default ();
                    }
                    dialog.destroy ();
                });
        }
        else
        {
            key_editor.response.connect ((dialog, response_id) => {
                    if (response_id == ResponseType.APPLY)
                    {
                        Variant variant = ((KeyEditorChild) key_editor_child).get_variant ();
                        if (key.value != variant)
                            key.value = variant;
                    }
                    dialog.destroy ();
                });
        }
        key_editor.add_row_from_widget (_("Custom value"), key_editor_child, tmp_string_1);

        key_editor.set_transient_for (this);
        key_editor.run ();
    }

    private static Widget create_child (KeyEditor dialog, Key key)
    {
        switch (key.type_string)
        {
            case "<enum>":
                return (Widget) new KeyEditorChildEnum (key);
            case "<flags>":
                return (Widget) new KeyEditorChildFlags ((GSettingsKey) key);
            case "b":
                return (Widget) new KeyEditorChildBool (key.value.get_boolean ());
            case "s":
                KeyEditorChildString key_editor_child = new KeyEditorChildString (key.value.get_string ());
                key_editor_child.child_activated.connect (() => { dialog.response (ResponseType.APPLY); });
                return (Widget) key_editor_child;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
            case "d":
            case "h":
                KeyEditorChildNumber key_editor_child = new KeyEditorChildNumber (key);
                key_editor_child.child_activated.connect (() => { dialog.response (ResponseType.APPLY); });
                return (Widget) key_editor_child;
            case "mb":
                return (Widget) new KeyEditorChildNullableBool (key);
            default:    // TODO "o" is a string-only with syntax verification
                KeyEditorChildDefault key_editor_child = new KeyEditorChildDefault (key.type_string, key.value);
                key_editor_child.is_valid.connect ((is_valid) => { dialog.custom_value_is_valid = is_valid; });
                key_editor_child.child_activated.connect (() => { dialog.response (ResponseType.APPLY); });
                return (Widget) key_editor_child;
        }
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();
        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((ClickableListBoxRow) list_box_row.get_child ()).on_row_clicked ();
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

    private void reset_generic (GLib.ListStore? objects, bool recursively)
    {
        if (objects == null)
            return;

        for (uint position = 0;; position++)
        {
            Object? object = ((!) objects).get_object (position);
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

    private void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;
        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
    }

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)     // TODO better?
    {
        string name = Gdk.keyval_name (event.keyval) ?? "";

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            switch (name)
            {
                case "b":
                    if (info_button.active)
                        info_button.active = false;
                    discard_row_popover ();
                    bookmarks_button.clicked ();
                    return true;
                case "d":
                    if (info_button.active)
                        info_button.active = false;
                    discard_row_popover ();
                    bookmarks_button.set_bookmarked (true);
                    return true;
                case "D":
                    if (info_button.active)
                        info_button.active = false;
                    discard_row_popover ();
                    bookmarks_button.set_bookmarked (false);
                    return true;
                case "f":
                    if (bookmarks_button.active)
                        bookmarks_button.active = false;
                    if (info_button.active)
                        info_button.active = false;
                    discard_row_popover ();
                    search_bar.set_search_mode (!search_bar.get_search_mode ());
                    return true;
                case "c":
                    discard_row_popover (); // TODO avoid duplicate get_selected_row () call
                    ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row == null ? current_path : ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ());
                    return true;
                case "C":
                    discard_row_popover ();
                    ((ConfigurationEditor) get_application ()).copy (current_path);
                    return true;
                case "F1":
                    discard_row_popover ();
                    if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                        return false;   // help overlay
                    ((ConfigurationEditor) get_application ()).about_cb ();
                    return true;
                default:
                    break;  // TODO make <ctrl>v work; https://bugzilla.gnome.org/show_bug.cgi?id=762257 is WONTFIX
            }
        }

        /* don't use "else if", or some widgets will not be hidden on <ctrl>F10 or such things */
        if (name == "F10")
        {
            discard_row_popover ();
            if (bookmarks_button.active)
                bookmarks_button.active = false;
            return false;
        }
        else if (name == "Menu")
        {
            ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
            if (selected_row != null)
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                if (info_button.active)
                    info_button.active = false;
                ((ClickableListBoxRow) ((!) selected_row).get_child ()).show_right_click_popover ();
            }
            else if (info_button.active == false)
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                info_button.active = true;
            }
            else
                info_button.active = false;
            return true;
        }

        if (bookmarks_button.active || info_button.active)      // TODO open bug about modal popovers and search_bar
            return false;

        return search_bar.handle_event (event);
    }

    [GtkCallback]
    private void on_menu_button_clicked ()
    {
        discard_row_popover ();
        search_bar.set_search_mode (false);
    }

    [GtkCallback]
    private void find_next_cb ()
    {
        if (!search_bar.get_search_mode ())     // TODO better; switches to next list_box_row when keyboard-activating an entry of the popover
            return;

        TreeIter iter;
        bool on_first_directory;
        int position = 0;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
            if (selected_row != null)
                position = ((!) selected_row).get_index () + 1;

            on_first_directory = true;
        }
        else if (model.get_iter_first (out iter))
            on_first_directory = false;
        else
            return;     // TODO better

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
                SettingObject object = (SettingObject) key_model.get_object (position);
                if (object.name.index_of (search_entry.text) >= 0 || 
                    (!object.is_view && key_matches ((Key) object, search_entry.text)))
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
    }

    private bool key_matches (Key key, string text)
    {
        /* Check in key's metadata */
        if (key.has_schema && ((GSettingsKey) key).search_for (text))
            return true;

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
