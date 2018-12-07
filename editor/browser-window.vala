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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-window.ui")]
private abstract class BrowserWindow : AdaptativeWindow, AdaptativeWidget
{
    private const string root_path = "/";   // TODO allow changing that

    protected string    current_path    = root_path;
    protected ViewType  current_type    = ViewType.FOLDER;
    protected ViewType  saved_type      = ViewType.FOLDER;
    protected string    saved_view      = "/";
    protected string    saved_selection = "";

    [GtkChild] protected BrowserHeaderBar headerbar;
    [GtkChild] protected BrowserView      browser_view;
    [GtkChild] protected Grid             main_grid;

    construct
    {
        install_browser_action_entries ();
        install_key_action_entries ();

        init_night_mode ();
        bind_mouse_config ();

        adaptative_children.append (headerbar);
        adaptative_children.append (browser_view);
        adaptative_children.append (notifications_revealer);
        adaptative_children.append (this);
    }

    /*\
    * * action entries
    \*/

    private SimpleAction disabled_state_action;
    private SimpleAction open_path_action;

    protected SimpleAction reload_search_action;
    protected bool reload_search_next = true;

    private void install_browser_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (browser_action_entries, this);
        insert_action_group ("browser", action_group);

        disabled_state_action = (SimpleAction) action_group.lookup_action ("disabled-state");
        disabled_state_action.set_enabled (false);

        open_path_action = (SimpleAction) action_group.lookup_action ("open-path");

        reload_search_action = (SimpleAction) action_group.lookup_action ("reload-search");
        reload_search_action.set_enabled (false);
    }

    private const GLib.ActionEntry [] browser_action_entries =
    {
        { "empty",          empty, "*" },
        { "empty-null",     empty },
        { "disabled-state", empty, "(sq)", "('',uint16 65535)" },

        { "open-folder", open_folder, "s" },
        { "open-object", open_object, "(sq)" },
        { "open-config", open_config, "s" },
        { "open-search", open_search, "s" },
        { "next-search", next_search, "s" },
        { "open-parent", open_parent, "s" },

        { "open-path", open_path, "(sq)", "('/',uint16 " + ModelUtils.folder_context_id_string + ")" },

        { "reload-folder", reload_folder },
        { "reload-object", reload_object },
        { "reload-search", reload_search },

        { "hide-search",   hide_search },
        { "show-search",   show_search },
        { "toggle-search", toggle_search, "b", "false" },

        { "hide-in-window-about",           hide_in_window_about },
        { "about",                          about }
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

    private void open_search (SimpleAction action, Variant? search_variant)
        requires (search_variant != null)
    {
        close_in_window_panels ();

        string search = ((!) search_variant).get_string ();

        request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_ALL, search);
    }

    private void next_search (SimpleAction action, Variant? search_variant)
        requires (search_variant != null)
    {
        saved_type = ViewType.FOLDER;
        saved_view = ((!) search_variant).get_string ();

        request_search (true, PathEntry.SearchMode.EDIT_PATH_MOVE_END, saved_view);
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
        request_folder (current_path, browser_view.get_selected_row_name ());
    }

    private void reload_object (/* SimpleAction action, Variant? path_variant */)
    {
        request_object (current_path, ModelUtils.undefined_context_id, false);
    }

    private void reload_search (/* SimpleAction action, Variant? path_variant */)
    {
        request_search (true);
    }

    private void hide_search (/* SimpleAction action, Variant? path_variant */)
    {
        stop_search ();
    }
    protected void stop_search ()
    {
        if (headerbar.search_mode_enabled)
            search_stopped_cb ();
    }

    private void show_search (/* SimpleAction action, Variant? path_variant */)
    {
        request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_ALL);
    }

    private void toggle_search (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bool search_request = ((!) path_variant).get_boolean ();
        action.change_state (search_request);
        if (search_request && !headerbar.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_ALL);
        else if (!search_request && headerbar.search_mode_enabled)
            stop_search ();
    }

    /*\
    * * global callbacks
    \*/

    [GtkCallback]
    private void on_destroy ()
    {
        before_destroy ();
        base.destroy ();
    }

    protected abstract void before_destroy ();

    /*\
    * * adaptative stuff
    \*/

    private bool disable_popovers = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (in_window_about)
                hide_in_window_about ();
        }

        chain_set_window_size (new_size);
    }

    protected abstract void chain_set_window_size (AdaptativeWidget.WindowSize new_size);

    /*\
    * * actions and callbacks helpers
    \*/

    protected void update_current_path (ViewType type, string path)
    {
        if (type == ViewType.OBJECT || type == ViewType.FOLDER)
        {
            saved_type = type;
            saved_view = path;
            reload_search_next = true;
        }
        else if (current_type == ViewType.FOLDER)
            saved_selection = browser_view.get_selected_row_name ();
        else if (current_type == ViewType.OBJECT)
            saved_selection = "";

        current_type = type;
        current_path = path;

        browser_view.set_path (type, path);
        headerbar.set_path (type, path);

        Variant variant = new Variant ("(sq)", path, (type == ViewType.FOLDER) || (type == ViewType.CONFIG) ? ModelUtils.folder_context_id : ModelUtils.undefined_context_id);
        open_path_action.set_state (variant);
        disabled_state_action.set_state (variant);
    }

    protected abstract void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true);
    protected abstract void request_object (string full_name, uint16 context_id = ModelUtils.undefined_context_id, bool notify_missing = true, string schema_id = "");
    protected abstract void request_config (string full_name);

    protected void request_search (bool reload, PathEntry.SearchMode mode = PathEntry.SearchMode.UNCLEAR, string? search = null)
    {
        string selected_row = browser_view.get_selected_row_name ();
        if (reload)
        {
            reload_search_action.set_enabled (false);
            browser_view.set_search_parameters (saved_view, headerbar.get_bookmarks ());
            reload_search_next = false;
        }
        if (mode != PathEntry.SearchMode.UNCLEAR)
            headerbar.prepare_search (mode, search);
        string search_text = search == null ? headerbar.text : (!) search;
        update_current_path (ViewType.SEARCH, search_text);
        if (mode != PathEntry.SearchMode.UNCLEAR)
            browser_view.select_row (selected_row);
        if (!headerbar.entry_has_focus)
            headerbar.entry_grab_focus (false);
    }

    /*\
    * * window state
    \*/

    // query
    protected bool is_in_in_window_mode ()
    {
        return browser_view.is_in_in_window_mode ();
    }

    private bool navigation_blocked ()
    {
        if (headerbar.search_mode_enabled)
            return true;
        if (browser_view.is_in_in_window_mode ())
            return true;
        return false;
    }

    protected bool row_action_blocked ()
    {
        if (headerbar.has_popover ())
            return true;
        if (browser_view.is_in_in_window_mode ())
            return true;
        return false;
    }

    // action
    protected virtual void close_in_window_panels ()
    {
        headerbar.close_popovers ();
        if (in_window_about)
            hide_in_window_about ();
    }

    /*\
    * * search callbacks
    \*/

    [GtkCallback]
    private void search_changed_cb ()
    {
        request_search (reload_search_next);
    }

    [GtkCallback]
    private void search_stopped_cb ()
    {
        browser_view.row_grab_focus ();

        reload_search_action.set_enabled (false);
        if (saved_type == ViewType.FOLDER)
            request_folder (saved_view, saved_selection);
        else
            update_current_path (saved_type, strdup (saved_view));
        reload_search_next = true;
    }

    /*\
    * * navigation methods
    \*/

    private void go_backward (bool shift)
    {
        if (navigation_blocked ())
            return;

        headerbar.close_popovers ();        // by symmetry with go_forward()
        browser_view.discard_row_popover ();

        if (current_path == root_path)
            return;
        if (shift)
            request_folder (root_path);
        else
            request_folder (ModelUtils.get_parent_path (current_path), current_path.dup ());
    }

    private void go_forward (bool shift)
    {
        if (navigation_blocked ())
            return;

        string fallback_path;
        string complete_path;
        headerbar.get_fallback_path_and_complete_path (out fallback_path, out complete_path);

        headerbar.close_popovers ();
        browser_view.discard_row_popover ();

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
        if (browser_view.current_view == ViewType.FOLDER)
            request_folder (current_path, browser_view.get_selected_row_name ());
        else if (browser_view.current_view == ViewType.OBJECT)
            request_object (current_path, ModelUtils.undefined_context_id, false);
        else if (browser_view.current_view == ViewType.SEARCH)
            request_search (true);
    }

    /*\
    * * keyboad action entries
    \*/

    private void install_key_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (key_action_entries, this);
        insert_action_group ("key", action_group);
    }

    private const GLib.ActionEntry [] key_action_entries =
    {
        { "copy",               copy                },  // <P>c
        { "copy-path",          copy_path           },  // <P>C

        { "next-match",         next_match          },  // <P>g // usual shortcut for "next-match"     in a SearchEntry; see also "Down"
        { "previous-match",     previous_match      },  // <P>G // usual shortcut for "previous-match" in a SearchEntry; see also "Up"

        { "request-config",     _request_config     },  // <P>i // TODO fusion with ui.open-config?

        { "toggle-search",      _toggle_search      },  // <P>f // TODO unduplicate (at least name)
        { "edit-path-end",      edit_path_end       },  // <P>l
        { "edit-path-last",     edit_path_last      },  // <P>L

        { "paste",              paste               },  // <P>v
        { "paste-force",        paste_force         },  // <P>V

        { "open-root",          open_root           },  // <S><A>Up
        { "open-parent",        open_current_parent },  //    <A>Up
        { "open-child",         open_child          },  //    <A>Down
        { "open-last-child",    open_last_child     },  // <S><A>Down

        { "toggle-hamburger",   toggle_hamburger    },  // F10
        { "menu",               menu_pressed        },  // Menu
    };

    /*\
    * * keyboard copy actions
    \*/

    protected abstract string get_copy_text ();
    protected abstract string get_copy_path_text ();

    private void copy                                   (/* SimpleAction action, Variant? path_variant */)
    {
        Widget? focus = get_focus ();
        if (focus != null)
        {
            if ((!) focus is Entry)
            {
                ((Entry) (!) focus).copy_clipboard ();
                return;
            }
            if ((!) focus is TextView)
            {
                ((TextView) (!) focus).copy_clipboard ();
                return;
            }
        }

        browser_view.discard_row_popover ();

        _copy (get_copy_text ());
    }

    private void copy_path                              (/* SimpleAction action, Variant? path_variant */)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        browser_view.discard_row_popover ();

        _copy (get_copy_path_text ());
    }

    private inline void _copy (string text)
    {
        ((ConfigurationEditor) get_application ()).copy (text);
    }

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
            return browser_view.next_match ();                  // for in-window things and main list
    }
    private bool _previous_match ()
    {
        bool interception_result;
        if (intercept_previous_match (out interception_result)) // for hypothetical popovers
            return interception_result;
        else
            return browser_view.previous_match ();              // for in-window things and main list
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

    private void _request_config                        (/* SimpleAction action, Variant? variant */)  // TODO unduplicate method name
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        if (browser_view.current_view == ViewType.FOLDER)
            request_config (current_path);
    }

    /*\
    * * keyboard search actions
    \*/

    private void _toggle_search                         (/* SimpleAction action, Variant? variant */)   // TODO unduplicate?
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        headerbar.close_popovers ();    // should never be needed if headerbar.search_mode_enabled
        browser_view.discard_row_popover ();   // could be needed if headerbar.search_mode_enabled

        if (!headerbar.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.SEARCH);
        else if (!headerbar.entry_has_focus)
            headerbar.entry_grab_focus (true);
        else if (headerbar.text.has_prefix ("/"))
            request_search (true, PathEntry.SearchMode.SEARCH);
        else
            stop_search ();
    }

    private void edit_path_end                          (/* SimpleAction action, Variant? variant */)
    {
        if (navigation_blocked ())
            return;

        request_search (true, PathEntry.SearchMode.EDIT_PATH_MOVE_END);
    }

    private void edit_path_last                         (/* SimpleAction action, Variant? variant */)
    {
        if (navigation_blocked ())
            return;

        request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_LAST_WORD);
    }

    /*\
    * * keyboard paste actions
    \*/

    private void paste                                  (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())
            return;

        Widget? focus = get_focus ();
        if (focus != null)
        {
            if ((!) focus is Entry)
            {
                ((Entry) (!) focus).paste_clipboard ();
                return;
            }
            if ((!) focus is TextView)
            {
                ((TextView) (!) focus).paste_clipboard ();
                return;
            }
        }

        search_clipboard_content ();
    }

    private void paste_force                            (/* SimpleAction action, Variant? variant */)
    {
        close_in_window_panels ();
        search_clipboard_content ();
    }

    private void search_clipboard_content ()
    {
        Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null)    // ?
            return;

        string? clipboard_content = Clipboard.get_default ((!) display).wait_for_text ();
        if (clipboard_content != null)
            request_search (true, PathEntry.SearchMode.EDIT_PATH_MOVE_END, clipboard_content);
        else
            request_search (true, PathEntry.SearchMode.SEARCH);
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
        if (browser_view.current_view == ViewType.CONFIG)   // assumes "navigation_blocked () == false"
            request_folder (current_path);
        else
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

    private void toggle_hamburger                       (/* SimpleAction action, Variant? variant */)
    {
        headerbar.toggle_hamburger_menu ();
    }

    private void menu_pressed                           (/* SimpleAction action, Variant? variant */)
    {
        if (browser_view.toggle_row_popover ()) // handles in-window bookmarks
            headerbar.close_popovers ();
        else
        {
            headerbar.toggle_hamburger_menu ();
            browser_view.discard_row_popover ();
        }
    }

    /*\
    * * about dialog or in-window panel
    \*/

    private void about (/* SimpleAction action, Variant? path_variant */)
    {
        if (!AdaptativeWidget.WindowSize.is_phone_size (window_size)
         && !AdaptativeWidget.WindowSize.is_extra_thin (window_size))
            show_about_dialog ();       // TODO hide the dialog if visible
        else
            toggle_in_window_about ();
    }

    private void show_about_dialog ()
    {
        string [] authors = AboutDialogInfos.authors;
        Gtk.show_about_dialog (this,
                               "program-name",          AboutDialogInfos.program_name,
                               "version",               AboutDialogInfos.version,
                               "comments",              AboutDialogInfos.comments,
                               "copyright",             AboutDialogInfos.copyright,
                               "license-type",          AboutDialogInfos.license_type,
                               "wrap-license", true,
                               "authors",               authors,
                               "translator-credits",    AboutDialogInfos.translator_credits,
                               "logo-icon-name",        AboutDialogInfos.logo_icon_name,
                               "website",               AboutDialogInfos.website,
                               "website-label",         AboutDialogInfos.website_label,
                               null);
    }

    // in-window about
    protected bool in_window_about { protected get; private set; default = false; }

    private void toggle_in_window_about ()
    {
        if (in_window_about)
            hide_in_window_about ();
        else
            show_in_window_about ();
    }

    private inline void show_in_window_about ()
        requires (in_window_about == false)
    {
        in_window_about = true;
        headerbar.show_in_window_about ();
        browser_view.show_in_window_about ();
    }

    protected void hide_in_window_about (/* SimpleAction action, Variant? path_variant */)
        requires (in_window_about == true)
    {
        in_window_about = false;
        headerbar.hide_in_window_about ();
        browser_view.hide_in_window_about ();
    }

    /*\
    * * keyboard callback
    \*/

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        if (name == "F1") // TODO fix dance done with the F1 & <Primary>F1 shortcuts that show help overlay
        {
            browser_view.discard_row_popover ();
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                return false;   // help overlay
            about ();
            return true;
        }

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
            if (focus != null && (((!) focus is Entry) || ((!) focus is TextView))) // && browser_view.current_view != ViewType.SEARCH
                return false;

            headerbar.toggle_pathbar_menu ();
            return true;
        }

        if (name == "Return" || name == "KP_Enter")
        {
            if (browser_view.current_view == ViewType.SEARCH
             && headerbar.entry_has_focus
             && browser_view.return_pressed ())
                return true;
            return false;
        }

        if (headerbar.has_popover ())
            return false;

        if (!headerbar.search_mode_enabled &&
            // see gtk_search_entry_is_keynav() in gtk+/gtk/gtksearchentry.c:388
            (keyval == Gdk.Key.Tab          || keyval == Gdk.Key.KP_Tab         ||
             keyval == Gdk.Key.Up           || keyval == Gdk.Key.KP_Up          ||
             keyval == Gdk.Key.Down         || keyval == Gdk.Key.KP_Down        ||
             keyval == Gdk.Key.Left         || keyval == Gdk.Key.KP_Left        ||
             keyval == Gdk.Key.Right        || keyval == Gdk.Key.KP_Right       ||
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

    protected bool mouse_use_extra_buttons  { private get; protected set; default = true; }
    protected int  mouse_back_button        { private get; protected set; default = 8; }
    protected int  mouse_forward_button     { private get; protected set; default = 9; }

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

    [GtkCallback]
    private bool on_button_press_event (Widget widget, Gdk.EventButton event)
    {
        if (!mouse_use_extra_buttons)
            return false;

        if (event.button == mouse_back_button)
        {
            if (mouse_back_button == mouse_forward_button)
            {
                warning (_("The same mouse button is set for going backward and forward. Doing nothing."));
                return false;
            }

            go_backward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
            return true;
        }
        if (event.button == mouse_forward_button)
        {
            go_forward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
            return true;
        }
        return false;
    }

    /*\
    * * night mode
    \*/

    // for construct only
    public bool initial_night_time           { private get; protected construct; }
    public bool initial_dark_theme           { private get; protected construct; }
    public bool initial_automatic_night_mode { private get; protected construct; }

    private void init_night_mode ()
    {
        headerbar.night_time           = initial_night_time;
        headerbar.dark_theme           = initial_dark_theme;
        headerbar.automatic_night_mode = initial_automatic_night_mode;
        // menu is already updated three times at startup, let's not add one
    }

    // for updates
    internal void night_time_changed (Object nlm, ParamSpec thing)
    {
        headerbar.night_time = NightLightMonitor.NightTime.should_use_dark_theme (((NightLightMonitor) nlm).night_time);
        headerbar.update_hamburger_menu ();
    }

    internal void dark_theme_changed (Object nlm, ParamSpec thing)
    {
        headerbar.dark_theme = ((NightLightMonitor) nlm).dark_theme;
        headerbar.update_hamburger_menu ();
    }

    internal void automatic_night_mode_changed (Object nlm, ParamSpec thing)
    {
        headerbar.automatic_night_mode = ((NightLightMonitor) nlm).automatic_night_mode;
        // update menu not needed
    }

    /*\
    * * notifications
    \*/

    [GtkChild] private NotificationsRevealer notifications_revealer;

    protected void show_notification (string notification)
    {
        notifications_revealer.show_notification (notification);
    }
}
