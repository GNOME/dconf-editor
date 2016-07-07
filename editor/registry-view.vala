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
class RegistryView : Grid
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
        revealer.reload.connect (invalidate_popovers);

        search_entry.get_buffer ().deleted_text.connect (() => { search_next_button.set_sensitive (true); });
        search_bar.connect_entry (search_entry);
        bind_property ("show-search-bar", search_bar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);   // TODO in UI file?
        bind_property ("behaviour", revealer, "behaviour", BindingFlags.BIDIRECTIONAL|BindingFlags.SYNC_CREATE);
    }

    public void init (string path, bool restore_view)
    {
        dir_tree_view.set_model (model);
        dir_tree_view.expand_all ();

        current_path = path;
        if (!restore_view || current_path == "" || !scroll_to_path (current_path))
        {
            current_path = "/";
            if (!scroll_to_path ("/"))
                assert_not_reached ();
        }
    }

    private void update_current_path (string path)
    {
        revealer.path_changed ();
        current_path = path;
        ((DConfWindow) this.get_parent ()).update_hamburger_menu ();
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
        update_current_path (dir.full_name);

        key_list_box.bind_model (key_model, new_list_box_row);
    }

    public bool scroll_to_path (string _full_name)      // TODO for now we assume full_name is a folder; also, don't do all the selection work if the folder didn't change
    {
        string full_name = _full_name.dup ();

        if (!full_name.has_suffix ("/"))
            full_name = DConfWindow.stripped_path (full_name);

        update_current_path (full_name);

        stack.set_visible_child_name ("browse-view");

        invalidate_popovers ();

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
                    dir_tree_selection.select_iter (iter);
                    return true;
                }
            }
            while (get_next_iter (ref iter));
        }
        MessageDialog dialog = new MessageDialog ((Window) this.get_parent (), DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK, _("Oops! Cannot find something at this path."));
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

            ((KeyListBoxRow) row).set_key_value.connect ((variant) => { set_key_value (key, variant); });
            ((KeyListBoxRow) row).change_dismissed.connect (() => { revealer.dismiss_change (key); });

            row.on_row_clicked.connect (() => {
                    if (!properties_view.populate_properties_list_box (revealer, key))
                        return;

                    stack.set_visible_child (properties_view);
                    update_current_path (key.full_name);
                });
            // TODO bug: row is always visually activated after the dialog destruction if mouse is over at this time
        }
        row.button_press_event.connect (on_button_pressed);
        return row;
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;
            row.show_right_click_popover (get_current_delay_mode (), (int) (event.x - row.get_allocated_width () / 2.0));
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
            row.destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
        ((DConfWindow) this.get_parent ()).update_hamburger_menu ();
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
        ((DConfWindow) this.get_parent ()).update_hamburger_menu ();
    }

    private void set_key_value (Key key, Variant? new_value)
    {
        if (get_current_delay_mode ())
            revealer.add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key.has_schema)
            ((GSettingsKey) key).set_to_default ();
        else
            assert_not_reached ();
    }

    /*\
    * * Action entries
    \*/

    public void reset (bool recursively)
    {
        revealer.enter_delay_mode ();
        reset_generic (key_model, recursively);
        invalidate_popovers ();
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
            if (setting_object.is_view)
            {
                if (recursively)
                    reset_generic (((Directory) setting_object).key_model, true);
                continue;
            }
            if (!((Key) setting_object).has_schema)
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

    [GtkCallback]
    private void show_browse_view ()
    {
        if (stack.get_visible_child_name () != "browse-view")
            stack.set_visible_child_name ("browse-view");
    }

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

    public string? get_selected_row_text ()
    {
        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        return selected_row == null ? null : ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
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

            if (!on_first_directory && dir.name.index_of (search_entry.text) >= 0)
            {
                dir_tree_selection.select_iter (iter);
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
                    dir_tree_selection.select_iter (iter);
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
