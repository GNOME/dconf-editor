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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    public string current_path { get; set; default = "/"; } // not synced bidi, needed for saving on destroy, even after child destruction

    private SettingsModel model;
    private ModificationsHandler modifications_handler;

    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_tiled = false;

    public bool mouse_extra_buttons { private get; set; default = true; }
    public int mouse_back_button { private get; set; default = 8; }
    public int mouse_forward_button { private get; set; default = 9; }

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    [GtkChild] private Bookmarks bookmarks_button;
    [GtkChild] private MenuButton info_button;
    [GtkChild] private PathBar pathbar;
    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;

    [GtkChild] private BrowserView browser_view;

    [GtkChild] private Revealer notification_revealer;
    [GtkChild] private Label notification_label;

    private bool _highcontrast = false;
    private bool highcontrast {
        set {
            if (_highcontrast == value)
                return;
            _highcontrast = value;
            if (value)
                get_style_context ().add_class ("hc-theme");
            else
                get_style_context ().remove_class ("hc-theme");
        }
    }

    private ulong behaviour_changed_handler = 0;
    private ulong modifications_handler_reload_handler = 0;
    private ulong small_keys_list_rows_handler = 0;
    private ulong small_bookmarks_rows_handler = 0;

    public DConfWindow (bool disable_warning, string? schema, string? path, string? key_name)
    {
        install_action_entries ();

        model = new SettingsModel (settings);
        pathbar.model = model;
        modifications_handler = new ModificationsHandler (model);
        browser_view.modifications_handler = modifications_handler;
        modifications_handler_reload_handler = modifications_handler.reload.connect (invalidate_popovers);

        model.paths_changed.connect ((_model, modified_path_specs, internal_changes) => {
                bool need_reload = browser_view.check_reload ();
                if (need_reload)
                {
                    if (internal_changes)
                        reload_view (false);
                    else
                        browser_view.show_hard_reload_warning ();
                }
                pathbar.set_path (current_path); // update "ghost" status
            });

        behaviour_changed_handler = settings.changed ["behaviour"].connect (invalidate_popovers);

        if (!disable_warning && settings.get_boolean ("show-warning"))
            show.connect (show_initial_warning);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        StyleContext context = get_style_context ();
        small_keys_list_rows_handler = settings.changed ["small-keys-list-rows"].connect (() => {
                bool small_rows = settings.get_boolean ("small-keys-list-rows");
                if (small_rows)
                {
                    if (!context.has_class ("small-keys-list-rows")) context.add_class ("small-keys-list-rows");
                }
                else if (context.has_class ("small-keys-list-rows")) context.remove_class ("small-keys-list-rows");
                browser_view.small_keys_list_rows = small_rows;
            });
        small_bookmarks_rows_handler = settings.changed ["small-bookmarks-rows"].connect (() => {
                if (settings.get_boolean ("small-bookmarks-rows"))
                {
                    if (!context.has_class ("small-bookmarks-rows")) context.add_class ("small-bookmarks-rows");
                }
                else if (context.has_class ("small-bookmarks-rows")) context.remove_class ("small-bookmarks-rows");
            });
        bool small_rows = settings.get_boolean ("small-keys-list-rows");
        if (small_rows)
            context.add_class ("small-keys-list-rows");
        browser_view.small_keys_list_rows = small_rows;
        if (settings.get_boolean ("small-bookmarks-rows"))
            context.add_class ("small-bookmarks-rows");

        search_bar.connect_entry (search_entry);
        search_bar.notify ["search-mode-enabled"].connect (search_changed);

        browser_view.bind_property ("current-path", this, "current-path");    // TODO in UI file?

        settings.bind ("mouse-use-extra-buttons", this, "mouse-extra-buttons", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-back-button", this, "mouse-back-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-forward-button", this, "mouse-forward-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        /* init current_path */
        bool strict = false;
        string? first_path = path;
        if (schema == null)
        {
            if (key_name != null)
                assert_not_reached ();

            if (first_path == null && settings.get_boolean ("restore-view"))
                first_path = settings.get_string ("saved-view");
        }
        else if (model.is_relocatable_schema ((!) schema))
        {
            if (first_path == null)
            {
                warning (_("Schema is relocatable, a path is needed."));
                if (settings.get_boolean ("restore-view"))
                    first_path = settings.get_string ("saved-view");
            }
            else
            {
                strict = true;
                model.add_mapping ((!) schema, (!) first_path);
                if (key_name != null)
                    first_path = (!) first_path + (!) key_name;
            }
        }
        else if (model.is_non_relocatable_schema ((!) schema))
        {
            string? schema_path = model.get_schema_path ((!) schema);
            if (schema_path == null)    // something wrong is happening
                assert_not_reached (); // TODO warning?
            else if (first_path != null && first_path != schema_path)
            {
                warning (_("Schema is not installed on given path."));
                if (settings.get_boolean ("restore-view"))
                    first_path = settings.get_string ("saved-view");
            }
            else if (key_name == null)
                first_path = schema_path;
            else
            {
                strict = true;
                first_path = (!) schema_path + (!) key_name;
            }
        }
        else
        {
            warning ("Unknown schema %s.".printf ((!) schema));
            if (settings.get_boolean ("restore-view"))
                first_path = settings.get_string ("saved-view");
        }

        model.finalize_model ();

        if (first_path == null)
            first_path = "/";

        request_path ((!) first_path, true, strict);
    }

    public static Widget _get_parent (Widget widget)
    {
        Widget? parent = widget.get_parent ();
        if (parent == null)
            assert_not_reached ();
        return (!) parent;
    }

    public string[] get_bookmarks ()
    {
        return settings.get_strv ("bookmarks");
    }

    /*\
    * * Window management callbacks
    \*/

    private void show_initial_warning ()
    {
        Gtk.MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.INFO, ButtonsType.NONE, _("Thanks for using Dconf Editor for editing your settings!"));
        dialog.format_secondary_text (_("Don’t forget that some options may break applications, so be careful."));
        dialog.add_buttons (_("I’ll be careful."), ResponseType.ACCEPT);

        // TODO don't show box if the user explicitely said she wanted to see the dialog next time?
        Box box = (Box) dialog.get_message_area ();
        CheckButton checkbutton = new CheckButton.with_label (_("Show this dialog next time."));
        checkbutton.visible = true;
        checkbutton.active = true;
        checkbutton.margin_top = 5;
        box.add (checkbutton);

        ulong dialog_response_handler = dialog.response.connect (() => { if (!checkbutton.active) settings.set_boolean ("show-warning", false); });
        dialog.run ();
        dialog.disconnect (dialog_response_handler);
        dialog.destroy ();
    }

    [GtkCallback]
    private bool on_window_state_event (Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        /* We don’t save this state, but track it for saving size allocation */
        if ((event.changed_mask & Gdk.WindowState.TILED) != 0)
            window_is_tiled = (event.new_window_state & Gdk.WindowState.TILED) != 0;

        return false;
    }

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        /* responsive design */

        StyleContext context = get_style_context ();
        if (allocation.width > MAX_ROW_WIDTH + 42)
            context.add_class ("large-window");
        else
            context.remove_class ("large-window");

        /* save size */

        if (window_is_maximized || window_is_tiled)
            return;
        int? _window_width = null;
        int? _window_height = null;
        get_size (out _window_width, out _window_height);
        if (_window_width == null || _window_height == null)
            return;
        window_width = (!) _window_width;
        window_height = (!) _window_height;
    }

    [GtkCallback]
    private void on_destroy ()
    {
        ((ConfigurationEditor) get_application ()).clean_copy_notification ();

        modifications_handler.disconnect (modifications_handler_reload_handler);

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (small_keys_list_rows_handler);
        settings.disconnect (small_bookmarks_rows_handler);

        settings.delay ();
        settings.set_string ("saved-view", current_path);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();

        base.destroy ();
    }

    /*\
    * * Action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("ui", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "open-path", open_path, "s" },
        { "open-path-with-selection", open_path_with_selection, "(ss)" },
        { "reload", reload },

        { "reset-recursive", reset_recursively, "s" },
        { "reset-visible", reset_visible },
        { "enter-delay-mode", enter_delay_mode }
    };

    private void open_path (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        if (bookmarks_button.active)
            bookmarks_button.active = false;
        request_path (((!) path_variant).get_string ());
    }

    private void open_path_with_selection (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        string selection;
        ((!) path_variant).@get ("(ss)", out full_name, out selection);
        request_path (selection);   // TODO better
        request_path (full_name);
    }

    private void reload (/* SimpleAction action, Variant? path_variant */)
    {
        reload_view (true);
    }

    private void reset_recursively (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        reset_path (((!) path_variant).get_string (), true);
    }

    private void reset_visible (/* SimpleAction action, Variant? path_variant */)
    {
        reset_path (current_path, false);
    }

    private void reset_path (string path, bool recursively)
    {
        enter_delay_mode ();
        browser_view.reset_objects (model.get_children (model.get_directory (path)), recursively);
    }

    private void enter_delay_mode (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.enter_delay_mode ();
        invalidate_popovers ();
    }

    /*\
    * * Directories tree
    \*/

    private void request_path (string full_name, bool notify_missing = true, bool strict = true)
    {
//        browser_view.set_search_mode (false);  // TODO not useful when called from bookmark
        Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings != null)
            highcontrast = ("HighContrast" in ((!) gtk_settings).gtk_theme_name);

        SettingObject? found_object = model.get_object (full_name, strict);
        bool not_found = found_object == null;

        string fallback_path = full_name;
        while (found_object == null)
        {
            fallback_path = SettingsModel.get_parent_path (fallback_path);
            found_object = model.get_object (fallback_path);
        }

        if (found_object is Key)
        {
            Directory parent_directory = (!) model.get_directory (SettingsModel.get_parent_path (full_name));
            browser_view.prepare_properties_view ((Key) found_object, full_name, parent_directory.warning_multiple_schemas);
            update_current_path (full_name);
        }
        else
            set_directory ((Directory) found_object, pathbar.get_selected_child (full_name));

        if (not_found && notify_missing)
        {
            if (SettingsModel.is_key_path (full_name))
                show_notification (_("Cannot find key “%s”.").printf (full_name));
            else
                show_notification (_("Cannot find folder “%s”.").printf (full_name));
        }

        search_bar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    private void set_directory (Directory directory, string? selected)
    {
        GLib.ListStore? key_model = model.get_children (directory);
        if (key_model == null)
            return;
        browser_view.prepare_browse_view ((!) key_model, directory.full_name, directory.warning_multiple_schemas);
        update_current_path (directory.full_name);
        browser_view.select_row (selected);
    }

    private void reload_view (bool notify_missing)
    {
        if (browser_view.current_view_is_browse_view ())
        {
            Directory? directory = model.get_directory (current_path);
            if (directory == null)
                request_path (current_path, notify_missing); // rely on fallback detection
            else
            {
                string? saved_selection = browser_view.get_selected_row_name ();
                set_directory ((!) directory, saved_selection);
            }
        }
        else if (browser_view.current_view_is_properties_view ())
            request_path (current_path, notify_missing);
        else if (browser_view.current_view_is_search_results_view ())
            browser_view.reload_search ();
    }

    /*\
    * * Path changing
    \*/

    private void update_current_path (string path)
    {
        browser_view.set_path (path);
        bookmarks_button.set_path (path);
        pathbar.set_path (path);
        invalidate_popovers_without_reload ();
    }

    private void update_hamburger_menu ()
    {
        GLib.Menu section;

        GLib.Menu menu = new GLib.Menu ();

        if (SettingsModel.is_key_path (current_path))   // mainly here for ensuring menu is never empty
        {
            SettingObject? object = model.get_object (current_path);
            if (object != null && (!) object is Key)
                menu.append (_("Copy descriptor"), "app.copy(\"" + model.get_key_copy_text ((Key) (!) object) + "\")");   // TODO what happens on multiple schemas defining one key?..
            else    // fallback that should never be reached
                menu.append (_("Copy current path"), "app.copy(\"" + current_path.escape (null).escape (null) + "\")");
        }
        else
        {
            section = new GLib.Menu ();
            Variant variant = new Variant.string (current_path);
            section.append (_("Reset visible keys"), "ui.reset-visible");
            section.append (_("Reset view recursively"), "ui.reset-recursive(" + variant.print (false) + ")");
            section.freeze ();
            menu.append_section (null, section);
        }

        if (!modifications_handler.get_current_delay_mode ())
        {
            section = new GLib.Menu ();
            section.append (_("Enter delay mode"), "ui.enter-delay-mode");
            section.freeze ();
            menu.append_section (null, section);
        }

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
    }

    private void invalidate_popovers ()
    {
        invalidate_popovers_without_reload ();
        reload_view (false);    // TODO better
    }
    private void invalidate_popovers_without_reload ()
    {
        browser_view.invalidate_popovers ();
        update_hamburger_menu ();
    }

    /*\
    * * Search
    \*/

    public void select_search_entry ()
    {
        if (!browser_view.current_view_is_search_results_view ())
            return;
        search_entry.grab_focus_without_selecting ();
    }

    [GtkCallback]
    private void search_changed ()
    {
        if (search_bar.search_mode_enabled)
            browser_view.show_search_view (search_entry.text);
        else
            browser_view.hide_search_view ();
    }

    [GtkCallback]
    private void search_cancelled ()
    {
        browser_view.hide_search_view ();
    }

    /*\
    * * Other callbacks
    \*/

    [GtkCallback]
    private bool on_button_press_event (Widget widget, Gdk.EventButton event)
    {
        if (!mouse_extra_buttons)
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

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)     // TODO better?
    {
        string name = (!) (Gdk.keyval_name (event.keyval) ?? "");

        Widget? focus = get_focus ();
        if (!(focus is Entry) && !(focus is TextView)) // why is this needed?
            if (name != "F10")                         // else <Shift>F10 toggles the search_entry popup
                if (search_bar.handle_event (event))
                    return true;

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            switch (name)
            {
                case "b":
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    if (bookmarks_button.sensitive)
                        bookmarks_button.clicked ();
                    return true;
                case "d":
                    if (bookmarks_button.sensitive == false)
                        return true;
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (true);
                    return true;
                case "D":
                    if (bookmarks_button.sensitive == false)
                        return true;
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (false);
                    return true;
                case "f":
                    if (bookmarks_button.active)
                        bookmarks_button.active = false;
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    if (!search_bar.search_mode_enabled)
                        search_bar.search_mode_enabled = true;
                    else if (!search_entry.has_focus)
                        search_entry.grab_focus ();
                    else
                        search_bar.search_mode_enabled = false;
                    return true;
                case "c":
                    browser_view.discard_row_popover (); // TODO avoid duplicate get_selected_row () call
                    string? selected_row_text = browser_view.get_copy_text ();
                    if (selected_row_text == null)
                    {
                        SettingObject? setting_object = model.get_object (current_path);
                        if (setting_object != null && (!) setting_object is Key)
                            selected_row_text = model.get_key_copy_text ((Key) (!) setting_object);
                    }
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row_text == null ? current_path : (!) selected_row_text);
                    return true;
                case "C":
                    browser_view.discard_row_popover ();
                    ((ConfigurationEditor) get_application ()).copy (current_path);
                    return true;
                case "F1":
                    browser_view.discard_row_popover ();
                    if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                        return false;   // help overlay
                    ((ConfigurationEditor) get_application ()).about_cb ();
                    return true;
                case "Return":
                case "KP_Enter":
                    if (info_button.active || bookmarks_button.active)
                        return false;
                    browser_view.discard_row_popover ();
                    browser_view.toggle_boolean_key ();
                    return true;
                // case "BackSpace":    // ?
                case "Delete":
                case "KP_Delete":
                case "decimalpoint":
                case "period":
                case "KP_Decimal":
                    if (info_button.active || bookmarks_button.active)
                        return false;
                    browser_view.discard_row_popover ();
                    string? selected_row = browser_view.get_selected_row_name ();
                    if (selected_row != null && ((!) selected_row).has_suffix ("/"))
                        reset_path ((!) selected_row, true);
                    else
                        browser_view.set_to_default ();
                    return true;
                default:
                    break;  // TODO make <ctrl>v work; https://bugzilla.gnome.org/show_bug.cgi?id=762257 is WONTFIX
            }
        }

        if (((event.state & Gdk.ModifierType.MOD1_MASK) != 0))
        {
            if (name == "Up")
            {
                go_backward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
                return true;
            }
            if (name == "Down")
            {
                go_forward ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0);
                return true;
            }
        }

        /* don't use "else if", or some widgets will not be hidden on <ctrl>F10 or such things */
        if (name == "F10")
        {
            browser_view.discard_row_popover ();
            if (bookmarks_button.active)
                bookmarks_button.active = false;
            return false;
        }

        if (name == "Up"
         && bookmarks_button.active == false
         && info_button.active == false)
            return browser_view.up_pressed (!search_bar.get_search_mode ());
        if (name == "Down"
         && bookmarks_button.active == false
         && info_button.active == false)
            return browser_view.down_pressed (!search_bar.get_search_mode ());

        if ((name == "Return" || name == "KP_Enter")
         && browser_view.current_view_is_search_results_view ()
         && search_entry.has_focus
         && browser_view.return_pressed ())
        {
            search_bar.set_search_mode (false);
            return true;
        }

        if (name == "Menu")
        {
            if (browser_view.show_row_popover ())
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                if (info_button.active)
                    info_button.active = false;
            }
            else if (info_button.sensitive == false)
                return true;
            else if (info_button.active == false)
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                browser_view.discard_row_popover ();
                info_button.active = true;
            }
            else
                info_button.active = false;
            return true;
        }

        if (bookmarks_button.active || info_button.active)
            return false;

        return false;    // browser_view.handle_search_event (event);
    }

    private void go_backward (bool shift)
    {
        browser_view.discard_row_popover ();
        if (current_path == "/")
            return;
        if (shift)
            request_path ("/");
        else
            request_path (SettingsModel.get_parent_path (current_path));
    }
    private void go_forward (bool shift)
    {
        string complete_path = pathbar.complete_path;

        browser_view.discard_row_popover ();
        if (shift)
        {
            request_path (complete_path);
            return;
        }
        if (current_path == complete_path)
            return;

        int index_of_last_slash = complete_path.index_of ("/", ((!) current_path).length);
        request_path (index_of_last_slash == -1 ? complete_path : complete_path.slice (0, index_of_last_slash + 1));
    }

    /*\
    * * Non-existant path notifications
    \*/

    private void show_notification (string notification)
    {
        notification_label.set_text (notification);
        notification_revealer.set_reveal_child (true);
    }

    [GtkCallback]
    private void hide_notification ()
    {
        notification_revealer.set_reveal_child (false);
    }
}
