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

[Flags]
enum RelocatableSchemasEnabledMappings
{
    USER,
    BUILT_IN,
    INTERNAL,
    STARTUP
}

public enum ViewType {
    OBJECT,
    FOLDER,
    SEARCH
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    private ViewType current_type = ViewType.FOLDER;
    private string current_path = "/";
    private ViewType saved_type = ViewType.FOLDER;
    private string saved_view = "/";
    private string saved_selection = "";

    private SettingsModel model = new SettingsModel ();
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
    [GtkChild] private ModificationsRevealer revealer;

    [GtkChild] private Revealer notification_revealer;
    [GtkChild] private Label notification_label;

    private ulong behaviour_changed_handler = 0;

    public DConfWindow (bool disable_warning, string? schema, string? path, string? key_name)
    {
        install_action_entries ();

        modifications_handler = new ModificationsHandler (model);
        revealer.modifications_handler = modifications_handler;
        browser_view.modifications_handler = modifications_handler;

        behaviour_changed_handler = settings.changed ["behaviour"].connect_after (invalidate_popovers);
        settings.bind ("behaviour", modifications_handler, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        if (!disable_warning && settings.get_boolean ("show-warning"))
            show.connect (show_initial_warning);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        set_css_styles ();

        search_bar.connect_entry (search_entry);
        search_bar.notify ["search-mode-enabled"].connect (search_changed);

        settings.bind ("mouse-use-extra-buttons", this, "mouse-extra-buttons", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-back-button", this, "mouse-back-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-forward-button", this, "mouse-forward-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        /* init current_path */
        SchemasUtility schemas_utility = new SchemasUtility ();
        bool strict = false;
        string? first_path = path;
        if (schema == null)
        {
            if (key_name != null)
                assert_not_reached ();

            if (first_path == null && settings.get_boolean ("restore-view"))
                first_path = settings.get_string ("saved-view");
        }
        else if (schemas_utility.is_relocatable_schema ((!) schema))
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

                RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) settings.get_flags ("relocatable-schemas-enabled-mappings");
                if (!(RelocatableSchemasEnabledMappings.STARTUP in enabled_mappings_flags))
                {
                    warning (_("Startup mappings are disabled."));
                    first_path = "/";
                }
                else if (key_name != null)
                    first_path = (!) first_path + (!) key_name;
            }
        }
        else if (schemas_utility.is_non_relocatable_schema ((!) schema))
        {
            string? schema_path = schemas_utility.get_schema_path ((!) schema);
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
            if ((!) schema != "")
                warning (_("Unknown schema “%s”.").printf ((!) schema));
            if (settings.get_boolean ("restore-view"))
                first_path = settings.get_string ("saved-view");
        }

        prepare_model ();

        if (first_path == null)
            first_path = "/";

        if (!SettingsModel.is_key_path ((!) first_path))
            request_folder ((!) first_path);
        else if (schema != null && model.path_exists ((!) first_path))
            request_object ((!) first_path, (!) schema);
        else if (model.path_exists ((!) first_path))
            request_object ((!) first_path);
        else if (model.path_exists ((!) first_path + "/"))
            request_folder ((!) first_path + "/");
        else
            request_object ((!) first_path);
    }

    private void prepare_model ()
    {
        settings.changed ["relocatable-schemas-user-paths"].connect (() => {
                RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) settings.get_flags ("relocatable-schemas-enabled-mappings");
                if (!(RelocatableSchemasEnabledMappings.USER in enabled_mappings_flags))
                    return;

                model.refresh_relocatable_schema_paths (true,
                                                        RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.INTERNAL in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.STARTUP  in enabled_mappings_flags,
                                                        settings.get_value ("relocatable-schemas-user-paths"));
            });
        settings.changed ["relocatable-schemas-enabled-mappings"].connect (() => {
                RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) settings.get_flags ("relocatable-schemas-enabled-mappings");
                model.refresh_relocatable_schema_paths (RelocatableSchemasEnabledMappings.USER     in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.INTERNAL in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.STARTUP  in enabled_mappings_flags,
                                                        settings.get_value ("relocatable-schemas-user-paths"));
            });

        RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) settings.get_flags ("relocatable-schemas-enabled-mappings");
        model.refresh_relocatable_schema_paths (RelocatableSchemasEnabledMappings.USER     in enabled_mappings_flags,
                                                RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags,
                                                RelocatableSchemasEnabledMappings.INTERNAL in enabled_mappings_flags,
                                                RelocatableSchemasEnabledMappings.STARTUP  in enabled_mappings_flags,
                                                settings.get_value ("relocatable-schemas-user-paths"));

        settings.bind ("refresh-settings-schema-source", model, "refresh-source", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        model.finalize_model ();

        model.paths_changed.connect ((_model, modified_path_specs, internal_changes) => {
                if (current_type == ViewType.SEARCH)
                {
                    if (!internal_changes)
                        reload_search_action.set_enabled (true);
                }
                else if (browser_view.check_reload (current_type, current_path, !internal_changes))    // handle infobars in needed
                    reload_view ();

                pathbar.update_ghosts (_model.get_fallback_path (pathbar.complete_path), search_bar.search_mode_enabled);
            });
    }

    /*\
    * * CSS styles
    \*/

    private ulong small_keys_list_rows_handler = 0;
    private ulong small_bookmarks_rows_handler = 0;

    private void set_css_styles ()
    {
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

        Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings == null)
            return;
        ((!) gtk_settings).notify ["gtk-theme-name"].connect (update_highcontrast_state);
        update_highcontrast_state ();
    }

    private bool highcontrast_state = false;
    private void update_highcontrast_state ()
    {
        Gtk.Settings? gtk_settings = Gtk.Settings.get_default ();
        if (gtk_settings == null)
            return;

        bool highcontrast_new_state = "HighContrast" in ((!) gtk_settings).gtk_theme_name;
        if (highcontrast_new_state == highcontrast_state)
            return;
        highcontrast_state = highcontrast_new_state;
        if (highcontrast_state)
            get_style_context ().add_class ("hc-theme");
        else
            get_style_context ().remove_class ("hc-theme");
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

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (small_keys_list_rows_handler);
        settings.disconnect (small_bookmarks_rows_handler);

        settings.delay ();
        settings.set_string ("saved-view", saved_view);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();

        base.destroy ();
    }

    /*\
    * * Action entries
    \*/

    private SimpleAction reload_search_action;
    private bool reload_search_next = true;

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("ui", action_group);

        reload_search_action = (SimpleAction) action_group.lookup_action ("reload-search");
        reload_search_action.set_enabled (false);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "empty", empty, "*" },

        { "notify-folder-emptied", notify_folder_emptied, "s" },
        { "notify-object-deleted", notify_object_deleted, "(ss)" },

        { "open-folder", open_folder, "s" },
        { "open-object", open_object, "(ss)" },
        { "open-parent", open_parent, "s" },

        { "reload-folder", reload_folder },
        { "reload-object", reload_object },
        { "reload-search", reload_search },

        { "reset-recursive", reset_recursively, "s" },
        { "reset-visible", reset_visible, "s" },

        { "enter-delay-mode", enter_delay_mode },
        { "apply-delayed-settings", apply_delayed_settings },
        { "dismiss-delayed-settings", dismiss_delayed_settings },

        { "dismiss-change", dismiss_change, "s" },  // here because needs to be accessed from DelayedSettingView rows
        { "erase", erase_dconf_key, "s" },          // here because needs a reload_view as we enter delay_mode

        { "copy-path", copy_path },
        { "hide-notification", hide_notification }
    };

    private void empty (/* SimpleAction action, Variant? variant */) {}

    private void notify_folder_emptied (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name = ((!) path_variant).get_string ();

        show_notification (_("Folder “%s” is now empty.").printf (full_name));
    }

    private void notify_object_deleted (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        string unused;  // GAction parameter type switch is a little touchy, see pathbar.vala
        ((!) path_variant).@get ("(ss)", out full_name, out unused);

        show_notification (_("Key “%s” has been deleted.").printf (full_name));
    }

    private void open_folder (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        if (bookmarks_button.active)
            bookmarks_button.active = false;

        string full_name = ((!) path_variant).get_string ();

        request_folder (full_name, "");
    }

    private void open_object (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        if (bookmarks_button.active)
            bookmarks_button.active = false;
        revealer.hide_modifications_list ();

        string full_name;
        string context;
        ((!) path_variant).@get ("(ss)", out full_name, out context);

        request_object (full_name, context);
    }

    private void open_parent (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name = ((!) path_variant).get_string ();
        request_folder (SettingsModel.get_parent_path (full_name), full_name);
    }

    private void reload_folder (/* SimpleAction action, Variant? path_variant */)
    {
        request_folder (current_path, browser_view.get_selected_row_name ());
    }

    private void reload_object (/* SimpleAction action, Variant? path_variant */)
    {
        request_object (current_path, "", false);
    }

    private void reload_search (/* SimpleAction action, Variant? path_variant */)
    {
        request_search (true);
    }

    private void reset_recursively (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        reset_path (((!) path_variant).get_string (), true);
    }

    private void reset_visible (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        reset_path (((!) path_variant).get_string (), false);
    }

    private void reset_path (string path, bool recursively)
    {
        enter_delay_mode ();
        revealer.reset_objects (model.get_children (path), recursively);
    }

    private void enter_delay_mode (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.enter_delay_mode ();
        invalidate_popovers ();
    }

    private void apply_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.apply_delayed_settings ();
        invalidate_popovers ();
    }

    private void dismiss_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.dismiss_delayed_settings ();
        invalidate_popovers ();
    }

    private void dismiss_change (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        modifications_handler.dismiss_change (((!) path_variant).get_string ());
        browser_view.invalidate_popovers ();
        reload_view ();
    }

    private void erase_dconf_key (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        modifications_handler.erase_dconf_key (((!) path_variant).get_string ());
        invalidate_popovers ();
    }

    private void copy_path (/* SimpleAction action, Variant? path_variant */)
    {
        browser_view.discard_row_popover ();

        if (search_bar.search_mode_enabled)
        {
            model.copy_action = true;
            string selected_row_text = browser_view.get_copy_path_text () ?? saved_view;
            ((ConfigurationEditor) get_application ()).copy (selected_row_text);
        }
        else
            ((ConfigurationEditor) get_application ()).copy (current_path);
    }

    private void hide_notification (/* SimpleAction action, Variant? variant */)
    {
        notification_revealer.set_reveal_child (false);
    }

    /*\
    * * Path requests
    \*/

    private void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true)
    {
        string fallback_path = model.get_fallback_path (full_name);

        if (notify_missing && (fallback_path != full_name))
            cannot_find_folder (full_name); // do not place after, full_name is in some cases changed by set_directory()...

        GLib.ListStore? key_model = model.get_children (fallback_path);
        if (key_model != null)
        {
            browser_view.prepare_folder_view ((!) key_model, current_path.has_prefix (fallback_path));
            update_current_path (ViewType.FOLDER, fallback_path);

            if (selected_or_empty == "")
                browser_view.select_row (pathbar.get_selected_child (fallback_path));
            else
                browser_view.select_row (selected_or_empty);
        }

        search_bar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    private void request_object (string full_name, string context = "", bool notify_missing = true)
    {
        Key? found_object = model.get_key (full_name, context);
        if (found_object == null)   // TODO warn about missing context
            found_object = model.get_key (full_name, "");

        if (found_object == null)
        {
            if (notify_missing)
            {
                if (SettingsModel.is_key_path (full_name))
                    cannot_find_key (full_name);
                else
                    cannot_find_folder (full_name);
            }
            request_folder (SettingsModel.get_parent_path (full_name), full_name, false);
            pathbar.update_ghosts (model.get_fallback_path (pathbar.complete_path), false);
        }
        else
        {
            browser_view.prepare_object_view ((!) found_object, current_path == SettingsModel.get_parent_path (full_name));
            update_current_path (ViewType.OBJECT, strdup (full_name));
        }

        search_bar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    private void request_search (bool reload)
    {
        string selected_row = browser_view.get_selected_row_name ();
        if (reload)
        {
            reload_search_action.set_enabled (false);
            browser_view.set_search_parameters (saved_view, bookmarks_button.get_bookmarks ());
            reload_search_next = false;
        }
        update_current_path (ViewType.SEARCH, search_entry.text);
        browser_view.select_row (selected_row);
        if (!search_entry.has_focus)
            search_entry.grab_focus_without_selecting ();
    }

    private void reload_view ()
    {
        if (browser_view.current_view == ViewType.FOLDER)
            request_folder (current_path, browser_view.get_selected_row_name ());
        else if (browser_view.current_view == ViewType.OBJECT)
            request_object (current_path, "", false);
        else if (browser_view.current_view == ViewType.SEARCH)
            request_search (true);
    }

    /*\
    * * Path changing
    \*/

    private void update_current_path (ViewType type, string path)
    {
        if (type != ViewType.SEARCH)
        {
            saved_type = type;
            saved_view = path;
        }
        else if (current_type == ViewType.FOLDER)
            saved_selection = browser_view.get_selected_row_name ();
        else if (current_type == ViewType.OBJECT)
            saved_selection = "";

        current_type = type;
        current_path = path;

        browser_view.set_path (type, path);
        bookmarks_button.set_path (type, path);
        pathbar.set_path (type, path);
        invalidate_popovers_without_reload ();
    }

    private void update_hamburger_menu ()
    {
        if (search_bar.search_mode_enabled)
            return;

        GLib.Menu section;

        GLib.Menu menu = new GLib.Menu ();

        if (current_type == ViewType.OBJECT)   // mainly here for ensuring menu is never empty
        {
            Variant variant = new Variant.string (model.get_key_copy_text (current_path, browser_view.last_context));
            menu.append (_("Copy descriptor"), "app.copy(" + variant.print (false) + ")");
        }
        else
        {
            section = new GLib.Menu ();
            Variant variant = new Variant.string (current_path);
            section.append (_("Reset visible keys"), "ui.reset-visible(" + variant.print (false) + ")");
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
        reload_view ();     // TODO better
    }
    private void invalidate_popovers_without_reload ()
    {
        browser_view.invalidate_popovers ();
        update_hamburger_menu ();
    }

    /*\
    * * Search callbacks
    \*/

    [GtkCallback]
    private void search_changed ()
    {
        if (search_bar.search_mode_enabled)
            request_search (reload_search_next);
        else
            hide_search_view ();
    }

    [GtkCallback]
    private void search_cancelled ()
    {
        if (!search_bar.search_mode_enabled)
            return;
        hide_search_view ();
    }

    private void hide_search_view ()
    {
        reload_search_action.set_enabled (false);
        if (saved_type == ViewType.FOLDER)
            request_folder (saved_view, saved_selection);
        else
            update_current_path (saved_type, strdup (saved_view));
        reload_search_next = true;
    }

    /*\
    * * Global callbacks
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
        bool focus_is_text_widget = focus != null && (((!) focus is Entry) || ((!) focus is TextView));
        if (!focus_is_text_widget)
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

                case "c":
                    if (search_bar.search_mode_enabled)
                        model.copy_action = true;
                    else if (focus_is_text_widget)
                        return false;

                    browser_view.discard_row_popover (); // TODO avoid duplicate get_selected_row () call

                    string? selected_row_text = browser_view.get_copy_text ();
                    if (selected_row_text == null && current_type == ViewType.OBJECT)
                        selected_row_text = model.get_key_copy_text (current_path, browser_view.last_context);
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row_text == null ? current_path : (!) selected_row_text);
                    return true;

                case "d":
                    if (bookmarks_button.sensitive == false)
                        return true;
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (current_path, true);
                    return true;
                case "D":
                    if (bookmarks_button.sensitive == false)
                        return true;
                    if (info_button.active)
                        info_button.active = false;
                    browser_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (current_path, false);
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

                case "i":
                    if (revealer.reveal_child)
                    {
                        revealer.toggle_modifications_list ();
                        return true;
                    }
                    return false;

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
                    if (revealer.dismiss_selected_modification ())
                    {
                        reload_view ();
                        return true;
                    }
                    browser_view.discard_row_popover ();
                    string selected_row = browser_view.get_selected_row_name ();
                    if (selected_row.has_suffix ("/"))
                        reset_path ((!) selected_row, true);
                    else
                        browser_view.set_selected_to_default ();
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
         && info_button.active == false
         && !revealer.get_modifications_list_state ())
            return browser_view.up_pressed ();
        if (name == "Down"
         && bookmarks_button.active == false
         && info_button.active == false
         && !revealer.get_modifications_list_state ())
            return browser_view.down_pressed ();

        if ((name == "Return" || name == "KP_Enter")
         && browser_view.current_view == ViewType.SEARCH
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
        if (search_bar.search_mode_enabled)
            return;

        browser_view.discard_row_popover ();
        if (current_path == "/")
            return;
        if (shift)
            request_folder ("/");
        else
            request_folder (SettingsModel.get_parent_path (current_path), current_path.dup ());
    }
    private void go_forward (bool shift)
    {
        if (search_bar.search_mode_enabled)
            return;

        string complete_path = pathbar.complete_path;

        browser_view.discard_row_popover ();
        if (current_path == complete_path)
            return;

        if (shift)
        {
            if (SettingsModel.is_key_path (complete_path))
                request_object (complete_path);
            else
                request_folder (complete_path);
            return;
        }

        int index_of_last_slash = complete_path.index_of ("/", ((!) current_path).length);
        if (index_of_last_slash != -1)
            request_folder (complete_path.slice (0, index_of_last_slash + 1));
        else if (SettingsModel.is_key_path (complete_path))
            request_object (complete_path);
        else
            request_folder (complete_path);
    }

    /*\
    * * Non-existant path notifications
    \*/

    private void show_notification (string notification)
    {
        notification_label.set_text (notification);
        notification_revealer.set_reveal_child (true);
    }

    private void cannot_find_key (string full_name)
    {
        show_notification (_("Cannot find key “%s”.").printf (full_name));
    }
    private void cannot_find_folder (string full_name)
    {
        show_notification (_("There’s nothing in requested folder “%s”.").printf (full_name));
    }
}
