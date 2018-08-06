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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-stack.ui")]
private class BrowserStack : Grid
{
    [GtkChild] private Stack stack;
    [GtkChild] private RegistryView folder_view;
    [GtkChild] private RegistryInfo object_view;
    [GtkChild] private RegistrySearch search_view;

    internal ViewType current_view { get; private set; default = ViewType.FOLDER; }

    internal bool small_keys_list_rows
    {
        set
        {
            folder_view.small_keys_list_rows = value;
            search_view.small_keys_list_rows = value;
        }
    }

    internal ModificationsHandler modifications_handler
    {
        set {
            folder_view.modifications_handler = value;
            object_view.modifications_handler = value;
            search_view.modifications_handler = value;
        }
    }

    /*\
    * * Views
    \*/

    internal string get_selected_row_name ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).get_selected_row_name ();
        return object_view.full_name;
    }

    internal void prepare_folder_view (GLib.ListStore key_model, bool is_ancestor)
    {
        folder_view.set_key_model (key_model);

        stack.set_transition_type (is_ancestor && current_view != ViewType.SEARCH ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
    }

    internal void select_row (string selected, uint16 last_context_id)
        requires (current_view != ViewType.OBJECT)
    {
        if (selected == "")
            ((RegistryList) stack.get_visible_child ()).select_first_row ();
        else
            ((RegistryList) stack.get_visible_child ()).select_row_named (selected, last_context_id, current_view == ViewType.FOLDER);
    }

    internal void prepare_object_view (string full_name, uint16 context_id, Variant properties, bool is_parent)
    {
        object_view.populate_properties_list_box (full_name, context_id, properties);

        stack.set_transition_type (is_parent && current_view != ViewType.SEARCH ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
    }

    internal void set_path (ViewType type, string path)
    {
        // might become “bool clear = type != current_view”, one day…
        bool clean_object_view = type == ViewType.FOLDER;    // note: not on search
        bool clean_search_view = current_view == ViewType.SEARCH && type != ViewType.SEARCH;

        current_view = type;
        if (type == ViewType.FOLDER)
            stack.set_visible_child (folder_view);
        else if (type == ViewType.OBJECT)
            stack.set_visible_child (object_view);
        else // (type == ViewType.SEARCH)
        {
            search_view.start_search (path);
            stack.set_transition_type (StackTransitionType.NONE);
            stack.set_visible_child (search_view);
        }

        if (clean_object_view)
            object_view.clean ();
        if (clean_search_view)
            search_view.clean ();
    }

    internal string? get_copy_text ()
    {
        return ((BrowsableView) stack.get_visible_child ()).get_copy_text ();
    }

    internal string? get_copy_path_text ()
    {
        if (current_view == ViewType.SEARCH)
            return search_view.get_copy_path_text ();

        warning ("BrowserView get_copy_path_text() called but current view is not search results view.");
        return null;
    }

    internal bool toggle_row_popover ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).toggle_row_popover ();
        return false;
    }

    internal void toggle_boolean_key ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).toggle_boolean_key ();
    }

    internal void set_selected_to_default ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).set_selected_to_default ();
    }

    internal void discard_row_popover ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).discard_row_popover ();
    }

    internal void invalidate_popovers ()
    {
        folder_view.invalidate_popovers ();
        search_view.invalidate_popovers ();
    }

    internal void hide_or_show_toggles (bool show)
    {
        folder_view.hide_or_show_toggles (show);
        search_view.hide_or_show_toggles (show);
    }

    /*\
    * * Reload
    \*/

    internal void set_search_parameters (string current_path, string [] bookmarks, SortingOptions sorting_options)
    {
        search_view.set_search_parameters (current_path, bookmarks, sorting_options);
    }

    internal bool check_reload_folder (Variant? fresh_key_model)
    {
        return folder_view.check_reload (fresh_key_model);
    }

    internal bool check_reload_object (uint properties_hash)
    {
        return object_view.check_reload (properties_hash);
    }

    /*\
    * * Values changes  // TODO reloads all the views instead of the current one, because method is called before it is made visible
    \*/

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        folder_view.gkey_value_push (full_name, context_id, key_value, is_key_default);
        search_view.gkey_value_push (full_name, context_id, key_value, is_key_default);
        if (full_name == object_view.full_name && context_id == object_view.context_id)
            object_view.gkey_value_push (key_value, is_key_default);
    }
    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        folder_view.dkey_value_push (full_name, key_value_or_null);
        search_view.dkey_value_push (full_name, key_value_or_null);
        if (full_name == object_view.full_name)
            object_view.dkey_value_push (key_value_or_null);
    }

    /*\
    * * Keyboard calls
    \*/

    internal bool return_pressed ()
        requires (current_view == ViewType.SEARCH)
    {
        return search_view.return_pressed ();
    }

    internal bool up_pressed ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).up_or_down_pressed (false);
        return false;
    }

    internal bool down_pressed ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).up_or_down_pressed (true);
        return false;
    }
}

private interface BrowsableView
{
    internal abstract string? get_copy_text ();
}
