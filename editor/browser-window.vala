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

internal enum ViewType {
    OBJECT,
    FOLDER,
    SEARCH,
    CONFIG;

    internal static uint8 to_byte (ViewType type)
    {
        switch (type)
        {
            case ViewType.OBJECT: return 0;
            case ViewType.FOLDER: return 1;
            case ViewType.SEARCH: return 2;
            case ViewType.CONFIG: return 3;
            default: assert_not_reached ();
        }
    }

    internal static ViewType from_byte (uint8 type)
    {
        switch (type)
        {
            case 0: return ViewType.OBJECT;
            case 1: return ViewType.FOLDER;
            case 2: return ViewType.SEARCH;
            case 3: return ViewType.CONFIG;
            default: assert_not_reached ();
        }
    }

    internal static bool displays_objects_list (ViewType type)
    {
        switch (type)
        {
            case ViewType.OBJECT:
            case ViewType.CONFIG:
                return false;
            case ViewType.FOLDER:
            case ViewType.SEARCH:
                return true;
            default: assert_not_reached ();
        }
    }

    internal static bool displays_object_infos (ViewType type)
    {
        switch (type)
        {
            case ViewType.OBJECT:
            case ViewType.CONFIG:
                return true;
            case ViewType.FOLDER:
            case ViewType.SEARCH:
                return false;
            default: assert_not_reached ();
        }
    }
}

private abstract class BrowserWindow : BaseWindow
{
    protected const string root_path    = "/";   // TODO allow changing that

    protected string    current_path    = root_path;
    protected ViewType  current_type    = ViewType.FOLDER;
    protected ViewType  saved_type      = ViewType.FOLDER;
    protected string    saved_view      = "/";
    protected string    saved_selection = "";

    private BrowserHeaderBar headerbar;
    private BrowserView      main_view;

    construct
    {
        headerbar = (BrowserHeaderBar) nta_headerbar;
        main_view = (BrowserView) base_view;

        this.button_press_event.connect (on_button_press_event);

        install_browser_action_entries ();
        install_key_action_entries ();

        bind_mouse_config ();
    }

    /*\
    * * action entries
    \*/

    private SimpleAction disabled_state_action;
    private SimpleAction open_path_action;

    protected SimpleAction reload_search_action;

    private void install_browser_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (browser_action_entries, this);
        insert_action_group ("browser", action_group);

        disabled_state_action = (SimpleAction) action_group.lookup_action ("disabled-state-s");
        disabled_state_action.set_enabled (false);
        disabled_state_action = (SimpleAction) action_group.lookup_action ("disabled-state-sq");
        disabled_state_action.set_enabled (false);

        open_path_action = (SimpleAction) action_group.lookup_action ("open-path");

        reload_search_action = (SimpleAction) action_group.lookup_action ("reload-search");
        reload_search_action.set_enabled (false);
    }

    private const GLib.ActionEntry [] browser_action_entries =
    {
        { "empty",              empty, "*" },
        { "empty-null",         empty },
        { "disabled-state-s",   empty, "s", "''" },
        { "disabled-state-sq",  empty, "(sq)", "('',uint16 65535)" },

        { "open-folder",        open_folder, "s" },
        { "open-object",        open_object, "(sq)" },
        { "open-config",        open_config, "s" },
        { "open-config-local",  open_config_local },
        { "open-search",        open_search, "s" },
        { "open-search-local",  open_search_local },
        { "open-search-global", open_search_global },
        { "open-search-root",   open_search_root },
        { "next-search",        next_search, "s" },
        { "open-parent",        open_parent, "s" },

        { "open-path",          open_path, "(sq)", "('/',uint16 " + ModelUtils.folder_context_id_string + ")" },

        { "reload-folder",      reload_folder },
        { "reload-object",      reload_object },
        { "reload-search",      reload_search },

        { "hide-search",        hide_search },
        { "show-search",        show_search },
        { "toggle-search",      toggle_search, "b", "false" },
        { "search-changed",     search_changed, "ms" }
    };

    private void empty (/* SimpleAction action, Variant? variant */) {}

    private void open_folder (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        close_in_window_panels ();

        string full_name = ((!) path_variant).get_string ();

        request_folder (full_name, "");
    }

    private void open_object (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        close_in_window_panels ();

        string full_name;
        uint16 context_id;
        ((!) path_variant).@get ("(sq)", out full_name, out context_id);

        request_object (full_name, context_id);
    }

    private void open_config (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        headerbar.close_popovers ();

        string full_name = ((!) path_variant).get_string ();    // TODO use current_path instead?

        request_config (full_name);
    }

    private void open_config_local (/* SimpleAction action, Variant? path_variant */)
    {
        headerbar.close_popovers ();

        request_config (current_path);
    }

    private void open_search (SimpleAction action, Variant? search_variant)
        requires (search_variant != null)
    {
        close_in_window_panels ();

        string search = ((!) search_variant).get_string ();

        init_next_search = true;
        request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_ALL, /* search term or null */ search);
    }

    private void open_search_local (/* SimpleAction action, Variant? search_variant */)
    {
        close_in_window_panels ();

        init_next_search = true;
        if (main_view.current_view == ViewType.SEARCH)  // possible call from keyboard, then do not clear entry
            request_search (PathEntry.SearchMode.UNCLEAR, /* search term or null */ null, /* local search */ true);
        else
            request_search (PathEntry.SearchMode.SEARCH, /* search term or null */ null, /* local search */ true);
    }

    private void open_search_global (/* SimpleAction action, Variant? search_variant */)
    {
        close_in_window_panels ();

        init_next_search = true;
        request_search ();
    }

    private void open_search_root (/* SimpleAction action, Variant? search_variant */)
    {
        close_in_window_panels ();

        init_next_search = true;
        request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END, "/");
    }

    private void next_search (SimpleAction action, Variant? search_variant)
        requires (search_variant != null)
    {
        saved_type = ViewType.FOLDER;
        saved_view = ((!) search_variant).get_string ();

        init_next_search = true;
        request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END, /* search term or null */ saved_view);
    }

    private void open_parent (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        close_in_window_panels ();

        string full_name = ((!) path_variant).get_string ();

        request_folder (ModelUtils.get_parent_path (full_name), full_name);
    }

    private void open_path (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        close_in_window_panels ();

        string full_name;
        uint16 context_id;
        ((!) path_variant).@get ("(sq)", out full_name, out context_id);

        action.set_state ((!) path_variant);

        if (ModelUtils.is_folder_context_id (context_id))
            request_folder (full_name, "");
        else
            request_object (full_name, context_id);
    }

    private void reload_folder (/* SimpleAction action, Variant? path_variant */)
    {
        request_folder (current_path, main_view.get_selected_row_name ());
    }

    private void reload_object (/* SimpleAction action, Variant? path_variant */)
    {
        request_object (current_path, ModelUtils.undefined_context_id, false);
    }

    private void reload_search (/* SimpleAction action, Variant? path_variant */)
    {
        init_next_search = true;
        request_search ();
    }

    private void hide_search (/* SimpleAction action, Variant? path_variant */)
    {
        stop_search ();
    }
    protected void stop_search ()
    {
        if (!headerbar.search_mode_enabled)
            return;

        main_view.row_grab_focus ();

        reload_search_action.set_enabled (false);
        if (saved_type == ViewType.FOLDER)
            request_folder (saved_view, saved_selection);
        else
            update_current_path (saved_type, strdup (saved_view));
        init_next_search = true;
    }

    private void show_search (/* SimpleAction action, Variant? path_variant */)
    {
        init_next_search = true;
        if (current_path == "/")
            request_search (PathEntry.SearchMode.SEARCH);
        else
            request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_ALL);
    }

    private void toggle_search (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bool search_request = ((!) path_variant).get_boolean ();
        action.change_state (search_request);
        if (search_request && !headerbar.search_mode_enabled)
        {
            init_next_search = true;
            if (current_path == "/")
                request_search (PathEntry.SearchMode.SEARCH);
            else
                request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_ALL);
        }
        else if (!search_request && headerbar.search_mode_enabled)
            stop_search ();
    }

    string last_search_entry_text = "";
    private void search_changed (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        Variant? variant = ((!) path_variant).get_maybe ();
        if (variant == null)
            stop_search ();
        else
        {
            last_search_entry_text = ((!) variant).get_string ();
            request_search ();
        }
    }

    /*\
    * * actions and callbacks helpers
    \*/

    protected void update_current_path (ViewType type, string path)
    {
        if (type == ViewType.OBJECT || type == ViewType.FOLDER)
        {
            saved_type = type;
            saved_view = path;
            init_next_search = true;
        }
        else if (current_type == ViewType.FOLDER)
            saved_selection = main_view.get_selected_row_name ();
        else if (current_type == ViewType.OBJECT)
            saved_selection = "";

        if (type == ViewType.SEARCH && path != "")
            last_non_empty_search = path;

        current_type = type;
        current_path = path;

        main_view.set_path (type, path);
        headerbar.set_path (type, path);

        Variant variant = new Variant ("(sq)", path, (type == ViewType.FOLDER) || (type == ViewType.CONFIG) ? ModelUtils.folder_context_id : ModelUtils.undefined_context_id);
        open_path_action.set_state (variant);
        disabled_state_action.set_state (variant);
    }

    protected abstract void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true);
    protected abstract void request_object (string full_name, uint16 context_id = ModelUtils.undefined_context_id, bool notify_missing = true, string schema_id = "");
    protected abstract void request_config (string full_name);

    private bool init_next_search = true;
    private void request_search (PathEntry.SearchMode mode = PathEntry.SearchMode.UNCLEAR, string? search = null, bool local_search = false)
    {
        string selected_row = main_view.get_selected_row_name ();
        if (init_next_search)
            init_search (local_search);
        if (mode != PathEntry.SearchMode.UNCLEAR)
            headerbar.prepare_search (mode, search);
        string search_text = search == null ? last_search_entry_text : (!) search;
        update_current_path (ViewType.SEARCH, search_text);
        if (mode != PathEntry.SearchMode.UNCLEAR)
            main_view.select_row (selected_row);
        if (!search_entry_has_focus ())
            headerbar.entry_grab_focus (/* select text */ false); // FIXME keep cursor position
    }
    private void init_search (bool local_search)
    {
        reload_search_action.set_enabled (false);
        reconfigure_search (local_search);
        search_is_local = local_search;
        init_next_search = false;
    }
    protected abstract void reconfigure_search (bool local_search);

    private bool search_entry_has_focus ()
    {
        return get_focus () is BrowserEntry;
    }

    public static bool is_path_invalid (string path)
    {
        return path.has_prefix ("/") && (path.contains ("//") || path.contains (" "));
    }

    /*\
    * * window state
    \*/

    // query
    protected bool is_in_in_window_mode ()
    {
        return main_view.is_in_in_window_mode () || headerbar.in_window_properties;
    }

    protected bool row_action_blocked ()
    {
        if (headerbar.has_popover ())
            return true;
        if (main_view.is_in_in_window_mode ())
            return true;
        return false;
    }

    protected override bool escape_pressed ()
    {
        if (headerbar.in_window_properties)
        {
            show_default_view ();
            return true;
        }
        if (base.escape_pressed ())
            return true;
        if (current_type == ViewType.CONFIG)
        {
            request_folder (current_path);
            return true;
        }
        if (headerbar.search_mode_enabled)
        {
            stop_search ();
            return true;
        }
        return false;
    }

    protected override void show_default_view ()
    {
        if (headerbar.in_window_properties)
            request_folder (current_path);
        else if (in_window_about)
        {
            base.show_default_view ();

            if (current_type == ViewType.CONFIG)
                request_folder (current_path);
        }
        else
            base.show_default_view ();
    }

    /*\
    * * navigation methods
    \*/

    private void go_backward (bool shift)
    {
        if (is_in_in_window_mode ())
            return;

        headerbar.close_popovers ();        // by symmetry with go_forward()
        main_view.close_popovers ();

        if (current_path == root_path && main_view.current_view != ViewType.CONFIG)
            return;
        if (shift)
        {
            if (main_view.current_view == ViewType.SEARCH)
            {
                init_next_search = true;
                request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END, /* search term or null */ "/");
            }
            else
                request_folder (root_path);
        }
        else if (main_view.current_view == ViewType.SEARCH)
        {
            init_next_search = true;
            request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END, /* search term or null */ ModelUtils.get_parent_path (current_path));
        }
        else if (main_view.current_view == ViewType.CONFIG)
            request_folder (current_path);
        else
            request_folder (ModelUtils.get_parent_path (current_path), current_path.dup ());
    }

    private void go_forward (bool shift)
    {
        if (is_in_in_window_mode ())
            return;

        headerbar.close_popovers ();
        main_view.close_popovers ();

        if (main_view.current_view == ViewType.SEARCH)
        {
            init_next_search = false;
            request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END);   // TODO when (!shift), move at next ‘/’
            return;
        }

        string fallback_path;
        string complete_path;
        headerbar.get_fallback_path_and_complete_path (out fallback_path, out complete_path);

        if (current_path == complete_path)  // TODO something?
            return;

        if (shift)
        {
            if (ModelUtils.is_key_path (fallback_path))
                request_object (fallback_path);
            else if (fallback_path != current_path)
                request_folder (fallback_path);
            else if (ModelUtils.is_key_path (complete_path))
                request_object (complete_path);
            else
                request_folder (complete_path);
        }
        else
        {
            int index_of_last_slash = complete_path.index_of ("/", ((!) current_path).length);
            if (index_of_last_slash != -1)
                request_folder (complete_path.slice (0, index_of_last_slash + 1));
            else if (ModelUtils.is_key_path (complete_path))
                request_object (complete_path);
            else
                request_folder (complete_path);
        }
    }

    protected void reload_view ()   // not used by BrowserWindow
    {
        if (main_view.current_view == ViewType.FOLDER)
            request_folder (current_path, main_view.get_selected_row_name ());
        else if (main_view.current_view == ViewType.OBJECT)
            request_object (current_path, ModelUtils.undefined_context_id, false);
        else if (main_view.current_view == ViewType.SEARCH)
        {
            init_next_search = true;
            request_search ();
        }
    }

    /*\
    * * keyboard action entries
    \*/

    private void install_key_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (key_action_entries, this);
        insert_action_group ("key", action_group);
    }

    private const GLib.ActionEntry [] key_action_entries =
    {
        { "next-match",         next_match              },  // <P>g, usual shortcut for "next-match"     in a SearchEntry; see also "Down"
        { "previous-match",     previous_match          },  // <P>G, usual shortcut for "previous-match" in a SearchEntry; see also "Up"

        { "toggle-config",      toggle_config           },  // <P>i

        { "search-global",      search_global,  "b"     },  // <P>f, <P><A>f
        { "search-local",       search_local,   "b"     },  // <P>F, <F><A>F
        { "edit-path-end",      edit_path_end           },  // <P>l
        { "edit-path-last",     edit_path_last          },  // <P>L

        { "open-root",          open_root               },  // <S><A>Up
        { "open-parent",        open_current_parent     },  //    <A>Up
        { "open-child",         open_child              },  //    <A>Down
        { "open-last-child",    open_last_child         },  // <S><A>Down
    };

    /*\
    * * keyboard "Down" and "<Primary>g" (next match), "Up" and "<Primary><Shift>G" (previous match)
    \*/

    // actions; NOTE: no use of method return value
    private void     next_match (/* SimpleAction action, Variant? variant */) {     _next_match (); }
    private void previous_match (/* SimpleAction action, Variant? variant */) { _previous_match (); }

    // real method; NOTE: returns bool
    private bool _next_match ()
    {
        bool interception_result;
        if (intercept_next_match (out interception_result))     // for hypothetical popovers
            return interception_result;
        else
            return main_view.next_match ();                  // for in-window things and main list
    }
    private bool _previous_match ()
    {
        bool interception_result;
        if (intercept_previous_match (out interception_result)) // for hypothetical popovers
            return interception_result;
        else
            return main_view.previous_match ();              // for in-window things and main list
    }

    // override if you know something more has to be done
    protected virtual bool intercept_next_match     (out bool interception_result)
    {
        interception_result = false;    // garbage
        return false;
    }
    protected virtual bool intercept_previous_match (out bool interception_result)
    {
        interception_result = false;    // garbage
        return false;
    }

    /*\
    * * config
    \*/

    private void toggle_config                          (/* SimpleAction action, Variant? variant */)
    {
        if (main_view.current_view == ViewType.CONFIG)
            request_folder (current_path);
        else if (main_view.is_in_in_window_mode ())
            return;
        else if (main_view.current_view == ViewType.FOLDER)
            request_config (current_path);
    }

    /*\
    * * keyboard search actions
    \*/

    private bool search_is_local = false;
    private string last_non_empty_search = "";

    private void search_global                          (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        headerbar.close_popovers ();    // should never be needed if headerbar.search_mode_enabled
        main_view.close_popovers ();   // could be needed if headerbar.search_mode_enabled

        if (!headerbar.search_mode_enabled)
        {
            init_next_search = true;
            if (((!) variant).get_boolean () && last_non_empty_search != "")
                request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_ALL, /* search term or null */ last_non_empty_search);
            else
                request_search (PathEntry.SearchMode.SEARCH);
        }
        else if (!search_entry_has_focus ())
            headerbar.entry_grab_focus (true);
        else if (search_is_local)
        {
            init_next_search = true;
            request_search ();
        }
        else if (last_search_entry_text.has_prefix ("/"))
        {
            init_next_search = true;
            request_search (PathEntry.SearchMode.SEARCH);
        }
        else
            stop_search ();
    }

    private void search_local                           (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        headerbar.close_popovers ();    // should never be needed if headerbar.search_mode_enabled
        main_view.close_popovers ();   // could be needed if headerbar.search_mode_enabled

        if (!headerbar.search_mode_enabled)
        {
            init_next_search = true;
            if (((!) variant).get_boolean () && last_non_empty_search != "")
                request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_ALL,
                                /* search term or null */ last_non_empty_search,
                                /* local search */ current_path != "/");
            else
                request_search (PathEntry.SearchMode.SEARCH,
                                /* search term or null */ null,
                                /* local search */ current_path != "/");
        }
        else if (!search_entry_has_focus ())
            headerbar.entry_grab_focus (true);
        else if (search_is_local)
            stop_search ();
        else if (last_search_entry_text.has_prefix ("/"))
        {
            init_next_search = true;
            request_search (PathEntry.SearchMode.SEARCH, /* search term or null */ null, /* local search */ true);
        }
        else if (saved_view != root_path)
        {
            init_next_search = true;
            request_search (PathEntry.SearchMode.UNCLEAR, /* search term or null */ null, /* local search */ true);
        }
        // do nothing if search is started from root path
    }

    private void edit_path_end                          (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())
            return;

        init_next_search = true;
        request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END);
    }

    private void edit_path_last                         (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())
            return;

        init_next_search = true;
        request_search (PathEntry.SearchMode.EDIT_PATH_SELECT_LAST_WORD);   // TODO make pressing multiple time <ctrl><shift>l select one more parent folder each time
    }

    /*\
    * * keyboard paste actions
    \*/

    protected override void paste_text (string? text)
    {
        init_next_search = true;
        if (text != null)
            request_search (PathEntry.SearchMode.EDIT_PATH_MOVE_END, /* search term or null */ text);
        else
            request_search (PathEntry.SearchMode.SEARCH);
    }

    /*\
    * * keyboard navigation actions
    \*/

    private void open_root                              (/* SimpleAction action, Variant? variant */)
    {
        go_backward (true);
    }

    private void open_current_parent                    (/* SimpleAction action, Variant? variant */)
    {
        go_backward (false);
    }

    private void open_child                             (/* SimpleAction action, Variant? variant */)
    {
        go_forward (false);
    }

    private void open_last_child                        (/* SimpleAction action, Variant? variant */)
    {
        go_forward (true);
    }

    /*\
    * * keyboard open menus actions
    \*/

    protected override void menu_pressed ()
    {
        if (main_view.toggle_row_popover ()) // handles in-window bookmarks
            headerbar.close_popovers ();
        else
        {
            headerbar.toggle_hamburger_menu ();
            main_view.close_popovers ();
        }
    }

    /*\
    * * keyboard callback
    \*/

    protected override bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        if (base.on_key_press_event (widget, event))
            return true;

        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        /* never override that */
        if (keyval == Gdk.Key.Tab || keyval == Gdk.Key.KP_Tab)
            return false;

        /* for changing row during search; cannot use set_accels_for_action() else popovers are not handled anymore */
        if (name == "Down" && (event.state & Gdk.ModifierType.MOD1_MASK) == 0)  // see also <ctrl>g
            return _next_match ();
        if (name == "Up"   && (event.state & Gdk.ModifierType.MOD1_MASK) == 0)  // see also <ctrl>G
            return _previous_match ();

        if (is_in_in_window_mode ())
            return false;

        /* don't use "else if", or some widgets will not be hidden on <ctrl>F10 or such things */
        if (name == "F10" && (event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
        {
            Widget? focus = get_focus ();
            if (focus != null && (((!) focus is Entry) || ((!) focus is TextView))) // && main_view.current_view != ViewType.SEARCH
                return false;

            headerbar.toggle_pathbar_menu ();
            return true;
        }

        if (name == "Return" || name == "KP_Enter")
        {
            if (main_view.current_view == ViewType.SEARCH
             && search_entry_has_focus ()
             && main_view.return_pressed ())
                return true;
            return false;
        }

        if (headerbar.has_popover ())
            return false;

        if (!headerbar.search_mode_enabled &&
            // see gtk_search_entry_is_keynav() in gtk+/gtk/gtksearchentry.c:388
            (keyval == Gdk.Key.Up           || keyval == Gdk.Key.KP_Up          ||
             keyval == Gdk.Key.Down         || keyval == Gdk.Key.KP_Down        ||
             keyval == Gdk.Key.Left         || keyval == Gdk.Key.KP_Left        ||
             keyval == Gdk.Key.Right        || keyval == Gdk.Key.KP_Right       ||
          // keyval == Gdk.Key.Tab          || keyval == Gdk.Key.KP_Tab         ||   // already done
             keyval == Gdk.Key.Home         || keyval == Gdk.Key.KP_Home        ||
             keyval == Gdk.Key.End          || keyval == Gdk.Key.KP_End         ||
             keyval == Gdk.Key.Page_Up      || keyval == Gdk.Key.KP_Page_Up     ||
             keyval == Gdk.Key.Page_Down    || keyval == Gdk.Key.KP_Page_Down   ||
             ((event.state & (Gdk.ModifierType.CONTROL_MASK | Gdk.ModifierType.MOD1_MASK)) != 0) ||
             name == "space" || name == "KP_Space"))
            return false;

        Widget? focus = get_focus ();
        bool focus_is_text_widget = focus != null && (((!) focus is Entry) || ((!) focus is TextView));
        if ((!focus_is_text_widget)
         && (event.is_modifier == 0)
         && (event.length != 0)
//       && (name != "F10")     // else <Shift>F10 toggles the search_entry popup; see if a976aa9740 fixes that in Gtk+ 4
         && (headerbar.handle_event (event)))
            return true;

        return false;
    }

    /*\
    * * mouse callback
    \*/

    [CCode (notify = false)] protected bool mouse_use_extra_buttons  { private get; protected set; default = true; }
    [CCode (notify = false)] protected int  mouse_back_button        { private get; protected set; default = 8; }
    [CCode (notify = false)] protected int  mouse_forward_button     { private get; protected set; default = 9; }

    private void bind_mouse_config ()
    {
        GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");  // FIXME

        settings.bind ("mouse-use-extra-buttons", this,
                       "mouse-use-extra-buttons", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-back-button",       this,
                       "mouse-back-button",       SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-forward-button",    this,
                       "mouse-forward-button",    SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
    }

    private static bool on_button_press_event (Widget widget, Gdk.EventButton event)
    {
        BrowserWindow _this = (BrowserWindow) widget;

        if (!_this.mouse_use_extra_buttons)
            return false;

        if (event.button == _this.mouse_back_button)
        {
            if (_this.mouse_back_button == _this.mouse_forward_button)
            {
                /* Translators: command-line message, when the user uses the backward/forward buttons of the mouse */
                warning (_("The same mouse button is set for going backward and forward. Doing nothing."));
                return false;
            }

            _this.go_backward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
            return true;
        }
        if (event.button == _this.mouse_forward_button)
        {
            _this.go_forward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
            return true;
        }
        return false;
    }
}
