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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-view.ui")]
class RegistryView : Grid, PathElement
{
    public string current_path { get; private set; }
    public bool show_search_bar { get; set; }
    public Behaviour behaviour { get; set; }

    private SettingsModel model = new SettingsModel ();
    [GtkChild] private TreeView dir_tree_view;
    [GtkChild] private TreeSelection dir_tree_selection;

    [GtkChild] private Stack stack;
    [GtkChild] private RegistryInfo properties_view;

    [GtkChild] private ListBox key_list_box;
    private GLib.ListStore? key_model = null;

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    [GtkChild] private ModificationsRevealer revealer;

    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;
    [GtkChild] private Button search_next_button;

    construct
    {
        ulong revealer_reload_handler = revealer.reload.connect (invalidate_popovers);

        EntryBuffer buffer = search_entry.get_buffer ();
        ulong search_entry_buffer_deleted_text_handler = buffer.deleted_text.connect (() => search_next_button.set_sensitive (true));
        search_bar.connect_entry (search_entry);
        bind_property ("show-search-bar", search_bar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);   // TODO in UI file?
        bind_property ("behaviour", revealer, "behaviour", BindingFlags.BIDIRECTIONAL|BindingFlags.SYNC_CREATE);

        destroy.connect (() => {
                revealer.disconnect (revealer_reload_handler);
                buffer.disconnect (search_entry_buffer_deleted_text_handler);

                base.destroy ();
            });
    }

    public void init (string path, bool restore_view)   // TODO check path format
    {
        dir_tree_view.set_model (model);
        dir_tree_view.expand_all ();

        current_path = (restore_view && path != "" && path [0] == '/') ? path : "/";
        path_requested (current_path, null);
    }

    /*\
    * * Stack switching
    \*/

    private void show_browse_view (string path, string? selected, bool grab = true)
    {
        stack.set_transition_type (current_path.has_prefix (path) ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        update_current_path (path);
        stack.set_visible_child_name ("browse-view");
        if (selected != null)
        {
            check_resize ();
            ListBoxRow? row = key_list_box.get_row_at_index (get_row_position ((!) selected));
            if (row == null)
                assert_not_reached ();
            scroll_to_row ((!) row, grab);
        }
        else
        {
            ListBoxRow? row = key_list_box.get_row_at_index (0);
            if (row != null)
                scroll_to_row ((!) row, grab);
        }
        properties_view.clean ();
    }
    private int get_row_position (string selected)
        requires (key_model != null)
    {
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject object = (SettingObject) ((!) key_model).get_object (position);
            if (object.full_name == selected)
                return (int) position;
            position++;
        }
        assert_not_reached ();
    }
    private void scroll_to_row (ListBoxRow row, bool grab)
    {
        key_list_box.select_row (row);
        if (grab)
            row.grab_focus ();

        Allocation list_allocation, row_allocation;
        stack.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }


    private void show_properties_view (string path)
    {
        stack.set_transition_type (path.has_prefix (current_path) && current_path.length == path.last_index_of_char ('/') + 1 ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        update_current_path (path);
        stack.set_visible_child (properties_view);
    }

    private void update_current_path (string path)
    {
        revealer.path_changed ();
        current_path = path;
        get_dconf_window ().update_path_elements ();
        invalidate_popovers ();
    }

    /*\
    * * Dir TreeView
    \*/

    [GtkCallback]
    private void dir_selected_cb ()
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 1/2
        key_model = get_selected_directory ().key_model;
        key_list_box.bind_model (key_model, new_list_box_row);
    }

    private Directory get_selected_directory ()
    {
        TreeIter iter;
        if (dir_tree_selection.get_selected (null, out iter))
            return model.get_directory (iter);
        else
            return model.get_root_directory ();
    }

    public void path_requested (string _full_name, string? selected)
    {
        string full_name = _full_name.dup ();
        string folder_name;
        if (full_name.has_suffix ("/"))
            folder_name = full_name;
        else
            folder_name = DConfWindow.stripped_path (full_name);

        if (!select_folder (folder_name))
        {
            get_dconf_window ().show_notification (_("Cannot find folder \"%s\".").printf (folder_name));
            current_path = "/";
            show_browse_view ("/", null);
            return;
        }

        if (full_name == folder_name)
        {
            show_browse_view (full_name, selected);
            return;
        }

        string [] names = full_name.split ("/");
        string key_name = names [names.length - 1];
        Key? key = get_key_from_name (key_name);
        if (key == null)
        {
            show_browse_view (folder_name, null);
            get_dconf_window ().show_notification (_("Cannot find key \"%s\" here.").printf (key_name));
            return;
        }
        if (((!) key) is DConfKey && ((DConfKey) ((!) key)).is_ghost)
        {
            show_browse_view (folder_name, folder_name + key_name);
            get_dconf_window ().show_notification (_("Key \"%s\" has been removed.").printf (key_name));
            return;
        }

        properties_view.populate_properties_list_box ((!) key);
        show_properties_view (full_name);
        return;
    }
    private bool select_folder (string full_name)
    {
        if (full_name == "/")
        {
            dir_tree_selection.unselect_all ();
            return true;
        }

        TreeIter iter;
        Directory dir;

        if (dir_tree_selection.get_selected (null, out iter))
        {
            dir = model.get_directory (iter);
            if (dir.full_name == full_name)
                return true;
        }

        if (model.get_iter_first (out iter))
        {
            do
            {
                dir = model.get_directory (iter);

                if (dir.full_name == full_name)
                {
                    dir_tree_selection.select_iter (iter);
                    return true;
                }
            }
            while (get_next_iter (ref iter));
        }
        else
            assert_not_reached ();
        return false;
    }
    private Key? get_key_from_name (string key_name)
        requires (key_model != null)
    {
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject object = (SettingObject) ((!) key_model).get_object (position);
            if (object is Key && object.name == key_name)
                return (Key) object;
            position++;
        }
        return null;
    }

    private DConfWindow get_dconf_window ()
    {
        return (DConfWindow) DConfWindow._get_parent (DConfWindow._get_parent (this));
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;

        if (setting_object is Directory)
            row = new FolderListBoxRow (setting_object.name, setting_object.full_name);
        else
        {
            if (setting_object is GSettingsKey)
                row = new KeyListBoxRowEditable ((GSettingsKey) setting_object);
            else
                row = new KeyListBoxRowEditableNoSchema ((DConfKey) setting_object);

            Key key = (Key) setting_object;
            KeyListBoxRow key_row = (KeyListBoxRow) row;
            ulong set_key_value_handler = key_row.set_key_value.connect ((variant) => { set_key_value (key, variant); set_delayed_icon (row, key); });
            ulong change_dismissed_handler = key_row.change_dismissed.connect (() => revealer.dismiss_change (key));

            ulong key_planned_change_handler = key.notify ["planned-change"].connect (() => set_delayed_icon (row, key));
            ulong key_planned_value_handler = key.notify ["planned-value"].connect (() => set_delayed_icon (row, key));
            set_delayed_icon (row, key);

            row.destroy.connect (() => {
                    key_row.disconnect (set_key_value_handler);
                    key_row.disconnect (change_dismissed_handler);
                    key.disconnect (key_planned_change_handler);
                    key.disconnect (key_planned_value_handler);
                });
        }

        ulong on_row_clicked_handler = row.on_row_clicked.connect (() => request_path (setting_object.full_name));
        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);

        row.destroy.connect (() => {
                row.disconnect (on_row_clicked_handler);
                row.disconnect (button_press_event_handler);
            });

        return row;
    }

    private void set_delayed_icon (ClickableListBoxRow row, Key key)
    {
        if (key.planned_change)
        {
            StyleContext context = row.get_style_context ();
            context.add_class ("delayed");
            if (key is DConfKey)
            {
                if (key.planned_value == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
            row.get_style_context ().remove_class ("delayed");
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;
            row.show_right_click_popover (get_current_delay_mode (), (int) (event.x));
            rows_possibly_with_popover.append (row);
        }

        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((ClickableListBoxRow) list_box_row.get_child ()).on_row_clicked ();
    }

    public void invalidate_popovers ()
    {
        uint position = 0;
        ClickableListBoxRow? row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (0);
        while (row != null)
        {
            ((!) row).destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
        get_dconf_window ().update_hamburger_menu ();
    }

    /*\
    * * Revealer stuff
    \*/

    public bool get_current_delay_mode ()
    {
        return revealer.get_current_delay_mode ();
    }

    public void enter_delay_mode ()
    {
        revealer.enter_delay_mode ();
        invalidate_popovers ();
    }

    private void set_key_value (Key key, Variant? new_value)
    {
        if (get_current_delay_mode ())
            revealer.add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key is GSettingsKey)
            ((GSettingsKey) key).set_to_default ();
        else if (behaviour != Behaviour.UNSAFE)
        {
            enter_delay_mode ();
            revealer.add_delayed_setting (key, null);
        }
        else
            ((DConfKey) key).erase ();
    }

    /*\
    * * Action entries
    \*/

    public void reset (bool recursively)
    {
        enter_delay_mode ();
        reset_generic (key_model, recursively);
        revealer.warn_if_no_planned_changes ();
    }

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
            if (setting_object is Directory)
            {
                if (recursively)
                    reset_generic (((Directory) setting_object).key_model, true);
                continue;
            }
            if (setting_object is DConfKey)
            {
                if (!((DConfKey) setting_object).is_ghost)
                    revealer.add_delayed_setting ((Key) setting_object, null);
            }
            else if (!((GSettingsKey) setting_object).is_default)
                revealer.add_delayed_setting ((Key) setting_object, null);
        }
    }

    /*\
    * * Search box
    \*/

    public void set_search_mode (bool? mode)    // mode is never 'true'...
    {
        if (mode == null)
            search_bar.set_search_mode (!search_bar.get_search_mode ());
        else
            search_bar.set_search_mode ((!) mode);
    }

    public bool handle_search_event (Gdk.EventKey event)
    {
        if (stack.get_visible_child_name () != "browse-view")
            return false;

        return search_bar.handle_event (event);
    }

    public bool show_row_popover ()
    {
        if (stack.get_visible_child_name () != "browse-view")
            return false;

        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();
        row.show_right_click_popover (get_current_delay_mode ());
        rows_possibly_with_popover.append (row);
        return true;
    }

    public string? get_copy_text ()
    {
        if (stack.get_visible_child_name () != "browse-view")
            return properties_view.get_copy_text ();
        else
        {
            ListBoxRow? selected_row = key_list_box.get_selected_row ();
            if (selected_row == null)
                return null;
            else
                return ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
        }
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;
        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
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

            if (!on_first_directory)
            {
                if (dir.name.index_of (search_entry.text) >= 0)
                {
                    dir_tree_selection.select_iter (iter);
                    show_browse_view (dir.full_name, null, false);
                    return;
                }
            }
            else
                on_first_directory = false;

            /* Select next key that matches */
            GLib.ListStore key_model = dir.key_model;
            while (position < key_model.get_n_items ())
            {
                SettingObject object = (SettingObject) key_model.get_object (position);
                if (object.name.index_of (search_entry.text) >= 0)
                {
                    dir_tree_selection.select_iter (iter);
                    key_list_box.select_row (key_list_box.get_row_at_index (position));
                    show_browse_view (dir.full_name, object.full_name, false);
                    return;
                }
                else if (object is Key)
                {
                    Key key = (Key) object;
                    if ((key is GSettingsKey || !((DConfKey) key).is_ghost) && key_matches (key, search_entry.text))
                    {   // TODO use request_path (object.full_name); problem with hiding or not the pathbar
                        properties_view.populate_properties_list_box (key);
                        dir_tree_selection.select_iter (iter);
                        key_list_box.select_row (key_list_box.get_row_at_index (position));
                        show_properties_view (object.full_name);
                        return;
                    }
                }
                position++;
            }

            position = 0;
        }
        while (get_next_iter (ref iter));

        search_next_button.set_sensitive (false);
    }

    private bool key_matches (Key key, string text)
    {
        /* Check in key's metadata */
        if (key is GSettingsKey && ((GSettingsKey) key).search_for (text))
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
