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

class RegistrySearch : RegistryList
{
    private string current_path;
    private string [] bookmarks;
    private SortingOptions sorting_options;

    construct
    {
        placeholder.label = _("No matches");
        key_list_box.set_header_func (update_search_results_header);
    }

    /*\
    * * Updating
    \*/

    private void ensure_selection ()
    {
        ListBoxRow? row = key_list_box.get_selected_row ();
        if (row == null)
            select_first_row ();
    }

    public override void select_first_row ()
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            key_list_box.select_row ((!) row);
        key_list_box.get_adjustment ().set_value (0);
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        string full_name = setting_object.full_name;
        bool is_local_result = SettingsModel.get_parent_path (full_name) == current_path;

        if (!SettingsModel.is_key_path (setting_object.full_name))
        {
            row = new FolderListBoxRow (                    setting_object.name, full_name, !is_local_result);
        }
        else
        {
            SettingsModel model = modifications_handler.model;
            Key key = (Key) setting_object;
            ulong key_value_changed_handler;
            if (setting_object is GSettingsKey)
            {
                GSettingsKey gkey = (GSettingsKey) key;
                bool key_default_value_if_bool = key.type_string == "b" ? gkey.default_value.get_boolean () : false;    // TODO better 4/6
                row = new KeyListBoxRowEditable (           key.type_string,
                                                            gkey,
                                                            gkey.schema_id,
                                                            modifications_handler.get_current_delay_mode (),
                                                            setting_object.name, full_name, !is_local_result);
                key_value_changed_handler = key.value_changed.connect (() => {
                        ((KeyListBoxRowEditable) row).update (model.get_key_value (key),
                                                              model.is_key_default (gkey),
                                                              key_default_value_if_bool);                               // TODO better 5/6
                        row.destroy_popover ();
                    });
                ((KeyListBoxRowEditable) row).update (model.get_key_value (key),
                                                      model.is_key_default (gkey),
                                                      key_default_value_if_bool);                                       // TODO better 6/6
            }
            else
            {
                DConfKey dkey = (DConfKey) setting_object;
                row = new KeyListBoxRowEditableNoSchema (   key.type_string,
                                                            dkey,
                                                            modifications_handler.get_current_delay_mode (),
                                                            setting_object.name, full_name, !is_local_result);
                key_value_changed_handler = key.value_changed.connect (() => {
                        if (model.is_key_ghost (full_name)) // fails with the ternary operator 3/4
                            ((KeyListBoxRowEditableNoSchema) row).update (null);
                        else
                            ((KeyListBoxRowEditableNoSchema) row).update (model.get_key_value (dkey));
                        row.destroy_popover ();
                    });
                if (model.is_key_ghost (full_name))         // fails with the ternary operator 4/4
                    ((KeyListBoxRowEditableNoSchema) row).update (null);
                else
                    ((KeyListBoxRowEditableNoSchema) row).update (model.get_key_value (dkey));
            }

            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => set_delayed_icon (key_row));
            set_delayed_icon (key_row);
            row.destroy.connect (() => {
                    modifications_handler.disconnect (delayed_modifications_changed_handler);
                    key.disconnect (key_value_changed_handler);
                });
        }

        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);
        row.destroy.connect (() => row.disconnect (button_press_event_handler));

        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();

        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (row is FolderListBoxRow)
        {
            wrapper.get_style_context ().add_class ("folder-row");
            wrapper.action_name = "ui.open-folder";
            wrapper.set_action_target ("s", full_name);
        }
        else
        {
            wrapper.get_style_context ().add_class ("key-row");
            wrapper.action_name = "ui.open-object";
            string context = (setting_object is GSettingsKey) ? ((GSettingsKey) setting_object).schema_id : ".dconf";
            wrapper.set_action_target ("(ss)", full_name, context);
        }

        return wrapper;
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        Container list_box = (Container) list_box_row.get_parent ();
        key_list_box.select_row (list_box_row);

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            if (list_box.get_focus_child () != null)
                list_box_row.grab_focus ();

            ClickableListBoxRow row = (ClickableListBoxRow) widget;

            int event_x = (int) event.x;
            if (event.window != widget.get_window ())   // boolean value switch
            {
                int widget_x, unused;
                event.window.get_position (out widget_x, out unused);
                event_x += widget_x;
            }

            show_right_click_popover (row, event_x);
            rows_possibly_with_popover.append (row);
        }
        else
            list_box_row.grab_focus ();

        return false;
    }

    public bool return_pressed ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ((!) selected_row).activate ();
        return true;
    }

    public override bool up_or_down_pressed (bool is_down)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        uint n_items = list_model.get_n_items ();

        if (selected_row != null)
        {
            Widget? row_content = ((!) selected_row).get_child ();
            if (row_content != null && ((ClickableListBoxRow) (!) row_content).right_click_popover_visible ())
                return false;

            int position = ((!) selected_row).get_index ();
            ListBoxRow? row = null;
            if (!is_down && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_down && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
            {
                Container list_box = (Container) ((!) selected_row).get_parent ();
                scroll_to_row ((!) row, list_box.get_focus_child () != null);
            }

            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }

    /*\
    * * Keyboard calls
    \*/

    public string? get_copy_path_text ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;

        Variant variant = ((!) selected_row).get_action_target_value ();
        string action_target;
        if (((!) variant).get_type_string () == "s")    // directory
            action_target = ((!) variant).get_string ();
        else
        {
            string unused;
            ((!) variant).get ("(ss)", out action_target, out unused);
        }
        return action_target;
    }

    /*\
    * * Search
    \*/

    private string? old_term;
    // indices for the start of each section. used to know where to insert search hits and to update the headers
    // must be updated before changing the list model, so that the header function works correctly
    private int post_local;
    private int post_bookmarks;
    private int post_folders;
    private uint? search_source = null;
    private GLib.Queue<string> search_nodes = new GLib.Queue<string> ();

    public void clean ()
    {
        key_list_box.bind_model (null, null);
        stop_global_search ();
        list_model.remove_all ();
        post_local = -1;
        post_bookmarks = -1;
        post_folders = -1;
        old_term = null;
    }

    public void start_search (string term)
    {
        if (old_term != null && term == (!) old_term)
        {
            ensure_selection ();
            return;
        }

        SettingsModel model = modifications_handler.model;
        if (old_term != null && term.has_prefix ((!) old_term))
        {
            pause_global_search ();
            refine_local_results (term);
            refine_bookmarks_results (term);
            if ((!) old_term == "")
                start_global_search (model, current_path, term);
            else
            {
                refine_global_results (term);
                resume_global_search (current_path, term); // update search term
            }

            ensure_selection ();
        }
        else
        {
            stop_global_search ();
            list_model.remove_all ();
            post_local = -1;
            post_folders = -1;

            local_search (model, sorting_options, SettingsModel.get_base_path (current_path), term);
            bookmark_search (model, current_path, term, bookmarks);
            key_list_box.bind_model (list_model, new_list_box_row);

            select_first_row ();

            if (term != "")
                start_global_search (model, current_path, term);
        }
        old_term = term;
    }

    private void refine_local_results (string term)
    {
        for (int i = post_local - 1; i >= 0; i--)
        {
            SettingObject item = (SettingObject) list_model.get_item (i);
            if (!(term in item.name))
            {
                post_local--;
                post_bookmarks--;
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private void refine_bookmarks_results (string term)
    {
        for (int i = post_bookmarks - 1; i >= post_local; i--)
        {
            SettingObject item = (SettingObject) list_model.get_item (i);
            if (!(term in item.name))
            {
                post_bookmarks--;
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private void refine_global_results (string term)
    {
        for (int i = (int) list_model.get_n_items () - 1; i >= post_folders; i--)
        {
            SettingObject item = (SettingObject) list_model.get_item (i);
            if (!(term in item.name))
                list_model.remove (i);
        }
        for (int i = post_folders - 1; i >= post_local; i--)
        {
            SettingObject item = (SettingObject) list_model.get_item (i);
            if (!(term in item.name))
            {
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private bool local_search (SettingsModel model, SortingOptions sorting_options, string current_path, string term)
    {
        SettingComparator comparator = sorting_options.get_comparator ();
        GLib.CompareDataFunc compare = (a, b) => comparator.compare((SettingObject) a, (SettingObject) b);

        if (!SettingsModel.is_key_path (current_path))
        {
            SettingObject [] key_model = model.get_children (current_path);
            for (uint i = 0; i < key_model.length; i++)
            {
                SettingObject item = key_model [i];
                if (term in item.name)
                    list_model.insert_sorted (item, compare);
            }
        }
        post_local = (int) list_model.get_n_items ();
        post_bookmarks = post_local;
        post_folders = post_local;

        if (term == "")
            return false;
        return true;
    }

    private bool bookmark_search (SettingsModel model, string current_path, string term, string [] bookmarks)
    {
        string [] installed_bookmarks = {}; // TODO move check in Bookmarks
        foreach (string bookmark in bookmarks)
        {
            if (bookmark in installed_bookmarks)
                continue;
            installed_bookmarks += bookmark;

            if (bookmark == current_path)
                continue;
            if (SettingsModel.get_parent_path (bookmark) == current_path)
                continue;

            SettingObject? setting_object = model.get_object (bookmark);
            if (setting_object == null)
                continue;

            if (term in ((!) setting_object).name)
            {
                post_bookmarks++;
                post_folders++;
                list_model.insert (post_bookmarks - 1, (!) setting_object);
            }
        }

        return true;
    }

    private void stop_global_search ()
    {
        pause_global_search ();
        search_nodes.clear ();
    }

    private void start_global_search (SettingsModel model, string current_path, string term)
    {
        search_nodes.push_head ("/");
        resume_global_search (current_path, term);
    }

    private void pause_global_search ()
    {
        if (search_source == null)
            return;
        Source.remove ((!) search_source);
        search_source = null;
    }

    private void resume_global_search (string current_path, string term)
    {
        search_source = Idle.add (() => {
                if (global_search_step (current_path, term))
                    return true;
                search_source = null;
                return false;
            });
    }

    private bool global_search_step (string current_path, string term)
    {
        SettingsModel model = modifications_handler.model;
        if (!search_nodes.is_empty ())
        {
            string next = (!) search_nodes.pop_head ();
            bool local_again = next == current_path;

            SettingObject [] next_key_model = model.get_children (next);
            if (next_key_model.length == 0)
                return true;

            for (uint i = 0; i < next_key_model.length; i++)
            {
                SettingObject item = next_key_model [i];
                if (!SettingsModel.is_key_path (item.full_name))
                {
                    if (!local_again && term in item.name)
                        list_model.insert (post_folders++, item);
                    search_nodes.push_tail (item.full_name); // we still search local children
                }
                else
                {
                    if (!local_again && term in item.name)
                        list_model.append (item);
                }
            }

            ensure_selection ();

            return true;
        }

        return false;
    }

    private void update_search_results_header (ListBoxRow row, ListBoxRow? before)
    {
        string? label_text = null;
        if (before == null && post_local > 0)
            label_text = _("Current folder");
        else if (row.get_index () == post_local && post_local != post_bookmarks)
            label_text = _("Bookmarks");
        else if (row.get_index () == post_bookmarks && post_bookmarks != post_folders)
            label_text = _("Folders");
        else if (row.get_index () == post_folders)
            label_text = _("Keys");

        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }

    public void set_search_parameters (string current_path, string [] bookmarks, SortingOptions sorting_options)
    {
        clean ();
        this.current_path = current_path;
        this.bookmarks = bookmarks;
        this.sorting_options = sorting_options;
    }
}
