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
    private string [] bookmarks;
    private SortingOptions sorting_options;

    construct
    {
        search_mode = true;
        placeholder.label = _("No matches");
        key_list_box.set_header_func (update_row_header);
    }

    /*\
    * * Updating
    \*/

    private void ensure_selection ()
    {
        if (!(key_list_box is ListBox)) // suppresses some warnings if the window is closed while the search is processing
            return;

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

    public bool return_pressed ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ((!) selected_row).activate ();
        return true;
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
        requires (current_path_if_search_mode != null)
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
                start_global_search (model, (!) current_path_if_search_mode, term);
            else
            {
                refine_global_results (term);
                resume_global_search ((!) current_path_if_search_mode, term); // update search term
            }

            ensure_selection ();
        }
        else
        {
            stop_global_search ();
            list_model.remove_all ();
            post_local = -1;
            post_folders = -1;

            local_search (model, sorting_options, SettingsModel.get_base_path ((!) current_path_if_search_mode), term);
            bookmark_search (model, (!) current_path_if_search_mode, term, bookmarks);
            key_list_box.bind_model (list_model, new_list_box_row);

            select_first_row ();

            if (term != "")
                start_global_search (model, (!) current_path_if_search_mode, term);
        }
        old_term = term;
        model.keys_value_push ();
    }

    private void refine_local_results (string term)
    {
        for (int i = post_local - 1; i >= 0; i--)
        {
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
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
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
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
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
            if (!(term in item.name))
                list_model.remove (i);
        }
        for (int i = post_folders - 1; i >= post_local; i--)
        {
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
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
        GLib.CompareDataFunc compare = (a, b) => comparator.compare ((SimpleSettingObject) a, (SimpleSettingObject) b);

        if (SettingsModel.is_folder_path (current_path))
        {
            string [,]? key_model = model.get_children (current_path);
            if (key_model != null)
            {
                for (uint i = 0; i < key_model.length [0]; i++)
                {
                    if (term in ((!) key_model) [i, 1])
                    {
                        SimpleSettingObject sso = new SimpleSettingObject (((!) key_model) [i, 0],
                                                                           ((!) key_model) [i, 1],
                                                                           ((!) key_model) [i, 2]);
                        list_model.insert_sorted (sso, compare);
                    }
                }
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

            string context = "";
            string name = "";
            if (!model.get_object (bookmark, ref context, ref name))
                continue;

            if (term in name)
            {
                post_bookmarks++;
                post_folders++;
                SimpleSettingObject sso = new SimpleSettingObject (context, name, bookmark);
                list_model.insert (post_bookmarks - 1, sso);
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

            string [,]? next_key_model = model.get_children (next);
            if (next_key_model == null)
                return true;

            for (uint i = 0; i < ((!) next_key_model).length [0]; i++)
            {
                string name      = ((!) next_key_model) [i, 1];
                string full_name = ((!) next_key_model) [i, 2];
                if (SettingsModel.is_folder_path (full_name))
                {
                    if (!local_again && term in name)
                    {
                        SimpleSettingObject sso = new SimpleSettingObject (((!) next_key_model) [i, 0],
                                                                           ((!) next_key_model) [i, 1],
                                                                           ((!) next_key_model) [i, 2]);
                        list_model.insert (post_folders++, sso);
                    }
                    search_nodes.push_tail (full_name); // we still search local children
                }
                else
                {
                    if (!local_again && term in name)
                    {
                        SimpleSettingObject sso = new SimpleSettingObject (((!) next_key_model) [i, 0],
                                                                           ((!) next_key_model) [i, 1],
                                                                           ((!) next_key_model) [i, 2]);
                        list_model.append (sso);
                    }
                }
            }

            ensure_selection ();

            return true;
        }

        return false;
    }

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
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
        current_path_if_search_mode = current_path;
        this.bookmarks = bookmarks;
        this.sorting_options = sorting_options;
    }
}
