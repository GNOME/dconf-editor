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
class BrowserStack : Grid
{
    [GtkChild] private Stack stack;
    [GtkChild] private RegistryView folder_view;
    [GtkChild] private RegistryInfo object_view;
    [GtkChild] private RegistrySearch search_view;

    public ViewType current_view { get; private set; default = ViewType.FOLDER; }

    public bool small_keys_list_rows
    {
        set
        {
            folder_view.small_keys_list_rows = value;
            search_view.small_keys_list_rows = value;
        }
    }

    public ModificationsHandler modifications_handler
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

    public string get_selected_row_name ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).get_selected_row_name ();
        return object_view.full_name;
    }

    public void prepare_folder_view (GLib.ListStore key_model, bool is_ancestor)
    {
        folder_view.set_key_model (key_model);

        stack.set_transition_type (is_ancestor && current_view != ViewType.SEARCH ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
    }

    public void select_row (string selected, string last_context)
        requires (current_view != ViewType.OBJECT)
    {
        if (selected == "")
            ((RegistryList) stack.get_visible_child ()).select_first_row ();
        else
            ((RegistryList) stack.get_visible_child ()).select_row_named (selected, last_context, current_view == ViewType.FOLDER);
    }

    public void prepare_object_view (Key key, bool is_parent)
    {
        object_view.populate_properties_list_box (key);

        stack.set_transition_type (is_parent && current_view != ViewType.SEARCH ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
    }

    public void set_path (ViewType type, string path)
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

    public string? get_copy_text ()
    {
        return ((BrowsableView) stack.get_visible_child ()).get_copy_text ();
    }

    public string? get_copy_path_text ()
    {
        if (current_view == ViewType.SEARCH)
            return search_view.get_copy_path_text ();

        warning ("BrowserView get_copy_path_text() called but current view is not search results view.");
        return null;
    }

    public bool show_row_popover ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).show_row_popover ();
        return false;
    }

    public void toggle_boolean_key ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).toggle_boolean_key ();
    }

    public void set_selected_to_default ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).set_selected_to_default ();
    }

    public void discard_row_popover ()
    {
        if (current_view != ViewType.OBJECT)
            ((RegistryList) stack.get_visible_child ()).discard_row_popover ();
    }

    public void invalidate_popovers ()
    {
        folder_view.invalidate_popovers ();
        search_view.invalidate_popovers ();
    }

    /*\
    * * Reload
    \*/

    public void set_search_parameters (string current_path, string [] bookmarks, SortingOptions sorting_options)
    {
        search_view.set_search_parameters (current_path, bookmarks, sorting_options);
    }

    public bool check_reload_folder (GLib.ListStore fresh_key_model)
    {
        return folder_view.check_reload (fresh_key_model);
    }

    public bool check_reload_object (Variant properties)
    {
        return object_view.check_reload (properties);
    }

    /*\
    * * Keyboard calls
    \*/

    public bool return_pressed ()
        requires (current_view == ViewType.SEARCH)
    {
        return search_view.return_pressed ();
    }

    public bool up_pressed ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).up_or_down_pressed (false);
        return false;
    }

    public bool down_pressed ()
    {
        if (current_view != ViewType.OBJECT)
            return ((RegistryList) stack.get_visible_child ()).up_or_down_pressed (true);
        return false;
    }
}

public interface BrowsableView
{
    public abstract string? get_copy_text ();
}
