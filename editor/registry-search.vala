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

    /* Translators: placeholder text of the search list when there's no search results (not used in current design) */
    [CCode (notify = false)] public override string placeholder_label { protected get { return _("No matches"); }}

    construct
    {
        search_mode = true;
        key_list_box.set_header_func (update_row_header);
    }

    /*\
    * * Simple public calls
    \*/

    internal override void select_first_row ()
    {
        if (old_term != null)   //happens when pasting an invalid path
            _select_first_row (key_list_box, (!) old_term);
    }

    internal bool return_pressed ()
    {
        return _return_pressed (key_list_box);
    }

    internal bool handle_alt_copy_text (out string copy_text)
    {
        return _handle_alt_copy_text (out copy_text, key_list_box);
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

    bool is_local = false;
    uint16 fallback_context_id = ModelUtils.undefined_context_id;
    internal void set_search_parameters (bool local_search, string current_path, uint16 current_context_id, string [] _bookmarks, SortingOptions _sorting_options)
    {
        clean ();

        is_local = local_search;
        current_path_if_search_mode = current_path;
        fallback_context_id = current_context_id;
        bookmarks = _bookmarks;
        sorting_options = _sorting_options;
    }

    /*\
    * * Updating
    \*/

    private static void ensure_selection (ListBox? key_list_box, string full_name)    // technical nullability
    {
        if (key_list_box == null)   // suppresses some warnings if the window is closed while the search is processing
            return;                 // TODO see if 5596feae9b51563a33f1bffc6a370e6ba556adb7 fixed that in Gtk 4

        ListBoxRow? selected_row = ((!) key_list_box).get_selected_row ();
        if (selected_row == null)
            _select_first_row ((!) key_list_box, full_name);
    }

    private static void _select_first_row (ListBox key_list_box, string _term)
    {
        string term = _term.strip ();

        ListBoxRow? row;
        if (term.has_prefix ("/"))
        {
            row = _get_first_row (ref key_list_box);

            ClickableListBoxRow? row_child = (ClickableListBoxRow?) ((!) row).get_child ();
            if (row_child != null)
            {
                if (((!) row_child).full_name != term)
                {
                    ListBoxRow? second_row = key_list_box.get_row_at_index (1);
                    if (second_row != null)
                        row = second_row;
                }
            }
        }
        else if (term.length == 0)
            row = _get_first_row (ref key_list_box);
        else
        {
            row = key_list_box.get_row_at_index (1);
            if (row == null)
                row = _get_first_row (ref key_list_box);
        }

        key_list_box.select_row ((!) row);
        key_list_box.get_adjustment ().set_value (0);
    }
    private static ListBoxRow _get_first_row (ref unowned ListBox key_list_box)
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row == null)
            assert_not_reached ();
        return (!) row;
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

    private static bool _handle_alt_copy_text (out string copy_text, ListBox key_list_box)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return BaseWindow.no_copy_text (out copy_text);
        _get_action_target ((!) selected_row, out copy_text);
        return true;
    }

    private static void _get_action_target (ListBoxRow selected_row, out string action_target)
    {
        Variant? variant = selected_row.get_action_target_value ();
        if (variant == null)
            assert_not_reached ();

        if (((!) variant).get_type_string () == "s")    // directory
            action_target = ((!) variant).get_string ();
        else
        {
            uint16 unused;
            ((!) variant).@get ("(sq)", out action_target, out unused);
        }
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

    internal void start_search (string _term)
        requires (current_path_if_search_mode != null)
    {
        string term = _term.strip ();

        if (BrowserWindow.is_path_invalid (term))
        {
            if (old_term != null)
                ensure_selection (key_list_box, (!) old_term);
            return;
        }
        if (old_term != null && term == (!) old_term)
        {
            ensure_selection (key_list_box, (!) old_term);
            return;
        }

        bool old_term_is_term_prefix = old_term != null && term.has_prefix ((!) old_term);
        SettingsModel model = modifications_handler.model;
        if (term.has_prefix ("/"))
        {
            is_local = false;
            if (old_term_is_term_prefix && !(term.slice (((!) old_term).length, term.length).contains ("/")))
            {
                refine_paths_results (term, ref list_model, ref post_local);

                ensure_selection (key_list_box, term);
            }
            else
            {
                search_is_path_search = true;

                model.clean_watched_keys ();
                stop_global_search ();

                current_path_if_search_mode = ModelUtils.get_base_path (term);

                insert_first_row ((!) current_path_if_search_mode, fallback_context_id, ref list_model);

                local_search (model, sorting_options, (!) current_path_if_search_mode, ModelUtils.get_name_or_empty (term), ref list_model);
                post_local = (int) list_model.get_n_items ();

                key_list_box.bind_model (list_model, new_list_box_row);
                _select_first_row (key_list_box, term);
            }
            model.keys_value_push ();
        }
        else
        {
            if (old_term_is_term_prefix)
            {
                pause_global_search (ref search_source);
                refine_local_results (term, ref list_model, ref post_local, ref post_bookmarks, ref post_folders);
                refine_bookmarks_results (term, post_local, ref list_model, ref post_bookmarks, ref post_folders);
                if ((!) old_term == "")
                    start_global_search ((!) current_path_if_search_mode, term);
                else
                {
                    refine_global_results (term, post_bookmarks, is_local, ref list_model, ref post_folders);
                    resume_global_search ((!) current_path_if_search_mode, term); // update search term
                }

                ensure_selection (key_list_box, term);

                model.keys_value_push ();
            }
            else
            {
                search_is_path_search = false;

                model.clean_watched_keys ();
                stop_global_search ();

                insert_first_row ((!) current_path_if_search_mode, fallback_context_id, ref list_model);

                local_search    (model, sorting_options, ModelUtils.get_base_path ((!) current_path_if_search_mode), term, ref list_model);
                post_local      = (int) list_model.get_n_items ();
                post_bookmarks  = post_local;
                bookmark_search (model, (!) current_path_if_search_mode, term, bookmarks, is_local, ref list_model, ref post_bookmarks);
                post_folders    = post_bookmarks;

                key_list_box.bind_model (list_model, new_list_box_row);
                _select_first_row (key_list_box, term);

                model.keys_value_push ();

                if (term != "")
                    start_global_search ((!) current_path_if_search_mode, term);

                if (is_local)
                    insert_global_search_row ((!) current_path_if_search_mode, fallback_context_id, ref list_model);
            }
        }
        old_term = term;
    }
    private static void insert_first_row (string current_path, uint16 _fallback_context_id, ref GLib.ListStore list_model)
    {
        uint16 fallback_context_id = ModelUtils.is_folder_path (current_path) ? ModelUtils.folder_context_id : _fallback_context_id;
        string name = ModelUtils.get_name (current_path);
        SimpleSettingObject sso = new SimpleSettingObject.from_full_name (/* context id */ fallback_context_id,
                                                                          /* name       */ name,
                                                                          /* base path  */ current_path,
                                                                          /* is search  */ false,
                                                                          /* is pinned  */ true);
        list_model.insert (0, sso);
    }
    private static void insert_global_search_row (string current_path, uint16 _fallback_context_id, ref GLib.ListStore list_model)
    {
        uint16 fallback_context_id = ModelUtils.is_folder_path (current_path) ? ModelUtils.folder_context_id : _fallback_context_id;
        SimpleSettingObject sso = new SimpleSettingObject.from_full_name (/* context id */ fallback_context_id,
                                                                          /* name       */ "",
                                                                          /* base path  */ current_path,
                                                                          /* is search  */ true,
                                                                          /* is pinned  */ false);
        list_model.insert (list_model.get_n_items (), sso);
    }

    private static void refine_paths_results (string term, ref GLib.ListStore list_model, ref int post_local)
    {
        if (post_local < 1)
            assert_not_reached ();
        if (post_local == 1)
            return;

        for (int i = post_local - 1; i >= 1; i--)
        {
            SimpleSettingObject? item = (SimpleSettingObject?) list_model.get_item (i);
            if (item == null)
                assert_not_reached ();
            if (!(term in ((!) item).full_name))
            {
                post_local--;
                list_model.remove (i);
            }
        }
    }

    private static void refine_local_results (string term, ref GLib.ListStore list_model, ref int post_local, ref int post_bookmarks, ref int post_folders)
    {
        if (post_local < 1)
            assert_not_reached ();
        if (post_local == 1)
            return;

        for (int i = post_local - 1; i >= 1; i--)
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
        if (post_bookmarks < post_local)
            assert_not_reached ();
        if (post_bookmarks == post_local)
            return;

        for (int i = post_bookmarks - 1; i >= post_local; i--)
        {
            SimpleSettingObject? item = (SimpleSettingObject?) list_model.get_item (i);
            if (item == null)
                assert_not_reached ();
            string name = ((!) item).casefolded_name;
            if (!(term.casefold () in name)
             || (((!) item).is_search && term == name))
            {
                post_bookmarks--;
                post_folders--;
                list_model.remove (i);
            }
        }
    }

    private static void refine_global_results (string term, int post_bookmarks, bool is_local, ref GLib.ListStore list_model, ref int post_folders)
    {
        for (int i = (int) list_model.get_n_items () - (is_local ? 2 : 1); i >= post_folders; i--)
        {
            SimpleSettingObject item = (SimpleSettingObject) list_model.get_item (i);
            if (!(term.casefold () in item.casefolded_name))
                list_model.remove (i);
        }
        for (int i = post_folders - 1; i >= post_bookmarks; i--)
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
        Variant? key_model = model.get_children (current_path, true, false); // here to update watched keys even coming from RegistryInfo
        if (key_model == null)
            return;

        SettingComparator comparator = sorting_options.get_comparator ();
        GLib.CompareDataFunc compare = (a, b) => comparator.compare ((SimpleSettingObject) a, (SimpleSettingObject) b);

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

    private static void bookmark_search (SettingsModel model, string current_path, string term, string [] bookmarks, bool is_local, ref GLib.ListStore list_model, ref int post_bookmarks)
    {
        foreach (string bookmark in bookmarks)
        {
            if (bookmark == current_path)
                continue;
            string bookmark_parent_path = ModelUtils.get_parent_path (bookmark);
            if (bookmark_parent_path == ModelUtils.get_base_path (current_path))
                continue;
            if (bookmark == "?" + term)
                continue;
            if (is_local && !(bookmark_parent_path.has_prefix (ModelUtils.get_base_path (current_path))))
                continue;

            uint16 context_id;
            string name;
            bool is_search = bookmark.has_prefix ("?");
            if (is_search)
            {
                context_id = ModelUtils.undefined_context_id;
                name = ModelUtils.get_name (bookmark.slice (1, bookmark.length));
            }
            else if (!model.get_object (bookmark, out context_id, out name, !(bookmark_parent_path in bookmarks)))
                continue;

            if (term.casefold () in name.casefold ())
            {
                SimpleSettingObject sso = new SimpleSettingObject.from_full_name (context_id, name, bookmark, is_search);
                list_model.insert (post_bookmarks, sso);
                post_bookmarks++;
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
        if (is_local)
            search_nodes.push_head (ModelUtils.get_base_path (current_path));
        else
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
                    list_model.insert (is_local ? list_model.get_n_items () - 1 : list_model.get_n_items (), sso);
                    model.key_value_push (next + name, context_id);
                }
            }
        }

        ensure_selection (key_list_box, term);
    }

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        int row_index = row.get_index ();
        if (is_first_row (row_index, before))
            return;

        if (search_is_path_search)
        {
            update_row_header_with_context (row, (!) before, modifications_handler.model, /* local search header */ false);
            return;
        }

        if (row_index >= 1 && post_local > 1 && row_index < post_local)
        {
            update_row_header_with_context (row, (!) before, modifications_handler.model, /* local search header */ true);
            return;
        }

        if (row_index >= post_folders)
        {
            update_row_header_with_context (row, (!) before, modifications_handler.model, /* local search header */ false);
            return;
        }

        string? label_text = get_header_text (row_index, post_local, post_bookmarks, post_folders);
        row.set_header (new ListBoxRowHeader (false, label_text));
    }
    private static string? get_header_text (int row_index, int post_local, int post_bookmarks, int post_folders)
    {
        if (row_index == post_local && post_local != post_bookmarks)
            /* Translators: header displayed in the keys list during a search only; indicates that the following results are found in the user bookmarks */
            return _("Bookmarks");

        if (row_index == post_bookmarks && post_bookmarks != post_folders)
            /* Translators: header displayed in the keys list during a search only */
            return _("Folders");

        return null;
    }
}
