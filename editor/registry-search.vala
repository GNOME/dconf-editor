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

private class RegistrySearch : RegistryList
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
    * * Simple public calls
    \*/

    internal override void select_first_row ()
    {
        _select_first_row (key_list_box);
    }

    internal bool return_pressed ()
    {
        return _return_pressed (key_list_box);
    }

    internal string? get_copy_path_text ()
    {
        return _get_copy_path_text (key_list_box);
    }

    internal void clean ()
    {
        key_list_box.bind_model (null, null);

        stop_global_search ();

        post_local = -1;
        post_bookmarks = -1;
        post_folders = -1;

        old_term = null;
    }

    internal void set_search_parameters (string current_path, string [] _bookmarks, SortingOptions _sorting_options)
    {
        clean ();

        current_path_if_search_mode = current_path;
        bookmarks = _bookmarks;
        sorting_options = _sorting_options;
    }

    /*\
    * * Updating
    \*/

    private static void ensure_selection (ListBox? key_list_box)    // technical nullability
    {
        if (key_list_box == null)   // suppresses some warnings if the window is closed while the search is processing
            return;                 // TODO see if 5596feae9b51563a33f1bffc6a370e6ba556adb7 fixed that in Gtk 4

        ListBoxRow? selected_row = ((!) key_list_box).get_selected_row ();
        if (selected_row == null)
            _select_first_row ((!) key_list_box);
    }

    private static void _select_first_row (ListBox key_list_box)
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            key_list_box.select_row ((!) row);
        key_list_box.get_adjustment ().set_value (0);
    }

    private static bool _return_pressed (ListBox key_list_box)
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

    private static string? _get_copy_path_text (ListBox key_list_box)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;
        return _get_action_target ((!) selected_row);
    }

    private static string _get_action_target (ListBoxRow selected_row)
    {
        Variant? variant = selected_row.get_action_target_value ();
        if (variant == null)
            assert_not_reached ();

        string action_target;
        if (((!) variant).get_type_string () == "s")    // directory
            action_target = ((!) variant).get_string ();
        else
        {
            uint16 unused;
            ((!) variant).@get ("(sq)", out action_target, out unused);
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

    internal void start_search (string term)
        requires (current_path_if_search_mode != null)
    {
        if ((old_term != null && term == (!) old_term)
         || DConfWindow.is_path_invalid (term))
        {
            ensure_selection (key_list_box);
            return;
        }

        SettingsModel model = modifications_handler.model;
        if (old_term != null && term.has_prefix ((!) old_term))
        {
            pause_global_search (ref search_source);
            refine_local_results (term, ref list_model, ref post_local, ref post_bookmarks, ref post_folders);
            refine_bookmarks_results (term, post_local, ref list_model, ref post_bookmarks, ref post_folders);
            if ((!) old_term == "")
                start_global_search ((!) current_path_if_search_mode, term);
            else
            {
                refine_global_results (term, post_local, ref list_model, ref post_folders);
                resume_global_search ((!) current_path_if_search_mode, term); // update search term
            }

            ensure_selection (key_list_box);

            model.keys_value_push ();
        }
        else
        {
            model.clean_watched_keys ();

            stop_global_search ();

            local_search (model, sorting_options, ModelUtils.get_base_path ((!) current_path_if_search_mode), term, ref list_model);
            post_local = (int) list_model.get_n_items ();
            post_bookmarks = post_local;
            post_folders = post_local;

            bookmark_search (model, (!) current_path_if_search_mode, term, bookmarks, ref list_model, ref post_bookmarks, ref post_folders);
            key_list_box.bind_model (list_model, new_list_box_row);

            _select_first_row (key_list_box);

            model.keys_value_push ();

            if (term != "")
                start_global_search ((!) current_path_if_search_mode, term);
        }
        old_term = term;
    }

    private static void refine_local_results (string term, ref GLib.ListStore list_model, ref int post_local, ref int post_bookmarks, ref int post_folders)
    {
        for (int i = post_local - 1; i >= 0; i--)
        {
            SimpleSettingObject? item = (SimpleSettingObject?) list_model.get_item (i);
            if (item == null)
                assert_not_reached ();
            if (!(term.casefold () in ((!) item).casefolded_name))
            {
                post_local--;
                post_bookmarks--;
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private static void refine_bookmarks_results (string term, int post_local, ref GLib.ListStore list_model, ref int post_bookmarks, ref int post_folders)
    {
        for (int i = post_bookmarks - 1; i >= post_local; i--)
        {
            SimpleSettingObject? item = (SimpleSettingObject?) list_model.get_item (i);
            if (item == null)
                assert_not_reached ();
            if (!(term.casefold () in ((!) item).casefolded_name))
            {
                post_bookmarks--;
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private static void refine_global_results (string term, int post_local, ref GLib.ListStore list_model, ref int post_folders)
    {
        for (int i = (int) list_model.get_n_items () - 1; i >= post_folders; i--)
        {
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
            if (!(term.casefold () in item.casefolded_name))
                list_model.remove (i);
        }
        for (int i = post_folders - 1; i >= post_local; i--)
        {
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
            if (!(term.casefold () in item.casefolded_name))
            {
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private static void local_search (SettingsModel model, SortingOptions sorting_options, string current_path, string term, ref GLib.ListStore list_model)
        requires (ModelUtils.is_folder_path (current_path))
    {
        SettingComparator comparator = sorting_options.get_comparator ();
        GLib.CompareDataFunc compare = (a, b) => comparator.compare ((SimpleSettingObject) a, (SimpleSettingObject) b);

        Variant? key_model = model.get_children (current_path, true, false); // here to update watched keys even coming from RegistryInfo
        if (key_model != null)
        {
            VariantIter iter = new VariantIter ((!) key_model);
            uint16 context_id;
            string name;
            while (iter.next ("(qs)", out context_id, out name))
            {
                if (term.casefold () in name.casefold ())
                {
                    SimpleSettingObject sso = new SimpleSettingObject.from_base_path (context_id, name, current_path);
                    list_model.insert_sorted (sso, compare);
                }
            }
        }
    }

    private static void bookmark_search (SettingsModel model, string current_path, string term, string [] bookmarks, ref GLib.ListStore list_model, ref int post_bookmarks, ref int post_folders)
    {
        foreach (string bookmark in bookmarks)
        {
            if (bookmark == current_path)
                continue;
            if (ModelUtils.get_parent_path (bookmark) == ModelUtils.get_base_path (current_path))
                continue;

            uint16 context_id;
            string name;
            if (!model.get_object (bookmark, out context_id, out name))
                continue;

            if (term.casefold () in name.casefold ())
            {
                post_bookmarks++;
                post_folders++;
                SimpleSettingObject sso = new SimpleSettingObject.from_full_name (context_id, name, bookmark);
                list_model.insert (post_bookmarks - 1, sso);
            }
        }
    }

    private void stop_global_search ()
    {
        pause_global_search (ref search_source);
        search_nodes.clear ();
        list_model.remove_all ();
    }

    private void start_global_search (string current_path, string term)
    {
        search_nodes.push_head ("/");
        resume_global_search (current_path, term);
    }

    private static void pause_global_search (ref uint? search_source)
    {
        if (search_source == null)
            return;
        Source.remove ((!) search_source);
        search_source = null;
    }

    private void resume_global_search (string current_path, string term)
    {
        search_source = Idle.add (() => {
                if (search_nodes.is_empty ())
                {
                    search_source = null;
                    return false;
                }
                global_search_step (current_path, term);
                return true;
            });
    }

    private void global_search_step (string current_path, string term)
    {
        SettingsModel model = modifications_handler.model;

        string next = (!) search_nodes.pop_head ();
        bool local_again = (next == current_path) || (next == ModelUtils.get_base_path (current_path));

        Variant? next_key_model = model.get_children (next, true, false);
        if (next_key_model == null)
            return;

        VariantIter iter = new VariantIter ((!) next_key_model);
        uint16 context_id;
        string name;
        while (iter.next ("(qs)", out context_id, out name))
        {
            if (ModelUtils.is_folder_context_id (context_id))
            {
                string full_name = ModelUtils.recreate_full_name (next, name, true);
                if (!local_again && !(full_name in bookmarks) && term.casefold () in name.casefold ())
                {
                    SimpleSettingObject sso = new SimpleSettingObject.from_full_name (context_id, name, full_name);
                    list_model.insert (post_folders++, sso); // do not move the ++ outside
                }
                search_nodes.push_tail (full_name); // we still search local children
            }
            else
            {
                string full_name = ModelUtils.recreate_full_name (next, name, false);
                if (!local_again && !(full_name in bookmarks) && term.casefold () in name.casefold ())
                {
                    SimpleSettingObject sso = new SimpleSettingObject.from_base_path (context_id, name, next);
                    list_model.append (sso);
                    model.key_value_push (next + name, context_id);
                }
            }
        }

        ensure_selection (key_list_box);
    }

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        string? label_text = get_header_text (row.get_index (), post_local, post_bookmarks, post_folders);
        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }
    private static string? get_header_text (int row_index, int post_local, int post_bookmarks, int post_folders)
    {
        if (row_index == 0 && post_local > 0)
            return _("Current folder");
        if (row_index == post_local && post_local != post_bookmarks)
            return _("Bookmarks");
        if (row_index == post_bookmarks && post_bookmarks != post_folders)
            return _("Folders");
        if (row_index == post_folders)
            return _("Keys");
        return null;
    }
}
