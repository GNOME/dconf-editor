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
internal enum RelocatableSchemasEnabledMappings
{
    USER,
    BUILT_IN,
    INTERNAL,
    STARTUP
}

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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
private class DConfWindow : ApplicationWindow
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

    internal bool mouse_extra_buttons   { private get; set; default = true; }
    internal int mouse_back_button      { private get; set; default = 8; }
    internal int mouse_forward_button   { private get; set; default = 9; }

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    [GtkChild] private MenuButton info_button;
    [GtkChild] private PathWidget path_widget;

    [GtkChild] private BrowserView browser_view;
    [GtkChild] private ModificationsRevealer revealer;

    [GtkChild] private Revealer notification_revealer;
    [GtkChild] private Label notification_label;

    private ulong use_shortpaths_changed_handler = 0;
    private ulong behaviour_changed_handler = 0;

    internal DConfWindow (bool disable_warning, string? schema, string? path, string? key_name, bool _night_time, bool _dark_theme, bool _automatic_night_mode)
    {
        init_night_mode (_night_time, _dark_theme, _automatic_night_mode);

        install_ui_action_entries ();
        install_kbd_action_entries ();

        use_shortpaths_changed_handler = settings.changed ["use-shortpaths"].connect_after (reload_view);
        settings.bind ("use-shortpaths", model, "use-shortpaths", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        modifications_handler = new ModificationsHandler (model);
        revealer.modifications_handler = modifications_handler;
        browser_view.modifications_handler = modifications_handler;

        behaviour_changed_handler = settings.changed ["behaviour"].connect_after (invalidate_popovers_with_ui_reload);
        settings.bind ("behaviour", modifications_handler, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        if (!disable_warning && settings.get_boolean ("show-warning"))
            show.connect (show_initial_warning);

        if (settings.get_boolean ("window-is-maximized"))
            maximize ();
        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));

        set_css_styles ();

        settings.bind ("mouse-use-extra-buttons", this, "mouse-extra-buttons", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-back-button", this, "mouse-back-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("mouse-forward-button", this, "mouse-forward-button", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        /* init current_path */
        bool restore_view = settings.get_boolean ("restore-view");
        string? settings_saved_view = null;
        if (restore_view)
        {
            settings_saved_view = settings.get_string ("saved-view");
            if (((!) settings_saved_view).contains ("//"))
                settings_saved_view = "/";

            string saved_path = settings.get_string ("saved-pathbar-path");
            string fallback_path = model.get_fallback_path (saved_path);
            /* path_widget.set_path (ModelUtils.is_folder_path (saved_path) ? ViewType.FOLDER : ViewType.OBJECT, saved_path);
            path_widget.update_ghosts (fallback_path);  // TODO allow a complete state restoration (including search and this) */
            path_widget.set_path (ModelUtils.is_folder_path (fallback_path) ? ViewType.FOLDER : ViewType.OBJECT, fallback_path);
        }

        SchemasUtility schemas_utility = new SchemasUtility ();
        bool strict = false;
        string? first_path = path;
        if (schema == null)
        {
            if (key_name != null)
                assert_not_reached ();

            if (first_path == null && restore_view)
                first_path = settings_saved_view;
        }
        else if (schemas_utility.is_relocatable_schema ((!) schema))
        {
            if (first_path == null)
            {
                warning (_("Schema is relocatable, a path is needed."));
                if (restore_view)
                    first_path = settings_saved_view;
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
                if (restore_view)
                    first_path = settings_saved_view;
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
            if (restore_view)
                first_path = settings_saved_view;
        }

        prepare_model ();

        if (first_path == null)
            first_path = "/";

        string startup_path = model.get_startup_path_fallback ((!) first_path);
        if (ModelUtils.is_folder_path (startup_path))
            request_folder (startup_path);
        else if (schema != null)
            request_object (startup_path, ModelUtils.undefined_context_id, true, (!) schema);
        else
            request_object (startup_path, ModelUtils.undefined_context_id, true);

        Timeout.add (300, () => { this.get_style_context ().remove_class ("startup"); return Source.REMOVE; });
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

        model.paths_changed.connect (on_paths_changed);
        model.gkey_value_push.connect (propagate_gkey_value_push);
        model.dkey_value_push.connect (propagate_dkey_value_push);
    }
    private void on_paths_changed (SettingsModelCore _model, GenericSet<string> unused, bool internal_changes)
    {
        if (current_type == ViewType.SEARCH)
        {
            if (!internal_changes)  // TODO do not react to value changes
                reload_search_action.set_enabled (true);
        }
        else if (browser_view.check_reload (current_type, current_path, !internal_changes))    // handle infobars in needed
            reload_view ();

        path_widget.update_ghosts (((SettingsModel) _model).get_fallback_path (path_widget.complete_path));
    }
    private void propagate_gkey_value_push (string full_name, uint16 context, Variant key_value, bool is_key_default)
    {
        browser_view.gkey_value_push (full_name, context, key_value, is_key_default);
        revealer.gkey_value_push     (full_name, context, key_value, is_key_default);
    }
    private void propagate_dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        browser_view.dkey_value_push (full_name, key_value_or_null);
        revealer.dkey_value_push     (full_name, key_value_or_null);
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
    * * Night mode
    \*/

    private bool night_time = false;    // no need to use NightTime here (that allows an "Unknown" value)
    private bool dark_theme = false;
    private bool automatic_night_mode = false;

    private void init_night_mode (bool _night_time, bool _dark_theme, bool _automatic_night_mode)
    {
        night_time = _night_time;
        dark_theme = _dark_theme;
        automatic_night_mode = _automatic_night_mode;
    }

    internal void night_time_changed (Object nlm, ParamSpec thing)
    {
        night_time = NightLightMonitor.NightTime.should_use_dark_theme (((NightLightMonitor) nlm).night_time);
        update_hamburger_menu ();
    }

    internal void dark_theme_changed (Object nlm, ParamSpec thing)
    {
        dark_theme = ((NightLightMonitor) nlm).dark_theme;
        update_hamburger_menu ();
    }

    internal void automatic_night_mode_changed (Object nlm, ParamSpec thing)
    {
        automatic_night_mode = ((NightLightMonitor) nlm).automatic_night_mode;
        // update menu not needed
    }

    private void append_or_not_night_mode_entry (ref GLib.Menu section)
    {
        if (!night_time)
            return;

        if (dark_theme)
            section.append (_("Pause night mode"), "app.set-use-night-mode(false)");
        else if (automatic_night_mode)
            section.append (_("Reuse night mode"), "app.set-use-night-mode(true)");
        else
            section.append (_("Use night mode"), "app.set-use-night-mode(true)");
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

    private bool extra_small_window = false;
    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        /* responsive design */

        StyleContext context = get_style_context ();
        if (allocation.width > MAX_ROW_WIDTH + 42)
        {
            if (extra_small_window)
            {
                extra_small_window = false;
                context.remove_class ("extra-small-window");
                browser_view.extra_small_window = false;
            }
            context.remove_class ("small-window");
            context.add_class ("large-window");
        }
        else if (allocation.width < 590)
        {
            context.remove_class ("large-window");
            context.add_class ("small-window");
            if (!extra_small_window)
            {
                extra_small_window = true;
                context.add_class ("extra-small-window");
                browser_view.extra_small_window = true;
            }
        }
        else if (allocation.width < 787)
        {
            context.remove_class ("large-window");
            if (extra_small_window)
            {
                extra_small_window = false;
                context.remove_class ("extra-small-window");
                browser_view.extra_small_window = false;
            }
            context.add_class ("small-window");
        }
        else
        {
            context.remove_class ("large-window");
            context.remove_class ("small-window");
            if (extra_small_window)
            {
                extra_small_window = false;
                context.remove_class ("extra-small-window");
                browser_view.extra_small_window = false;
            }
        }

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

    internal bool quit_if_no_pending_changes ()
    {
        if (modifications_handler.has_pending_changes ())
        {
            show_notification ("There are pending changes. Use <ctrl><shift>q to apply changes and quit.");
            return false;
        }
        destroy ();
        return true;
    }

    internal void apply_pending_changes_and_quit ()
    {
        modifications_handler.apply_delayed_settings ();
        destroy ();
    }

    [GtkCallback]
    private void on_destroy ()
    {
        ((ConfigurationEditor) get_application ()).clean_copy_notification ();

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (use_shortpaths_changed_handler);
        settings.disconnect (small_keys_list_rows_handler);
        settings.disconnect (small_bookmarks_rows_handler);

        settings.delay ();
        settings.set_string ("saved-view", saved_view);
        settings.set_string ("saved-pathbar-path", path_widget.complete_path);
        if (window_width <= 630)    settings.set_int ("window-width", 630);
        else                        settings.set_int ("window-width", window_width);
        if (window_height <= 420)   settings.set_int ("window-height", 420);
        else                        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();

        base.destroy ();
    }

    /*\
    * * Main UI action entries
    \*/

    private SimpleAction reload_search_action;
    private bool reload_search_next = true;

    private void install_ui_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (ui_action_entries, this);
        insert_action_group ("ui", action_group);

        reload_search_action = (SimpleAction) action_group.lookup_action ("reload-search");
        reload_search_action.set_enabled (false);
    }

    private const GLib.ActionEntry [] ui_action_entries =
    {
        { "empty", empty, "*" },

        { "notify-folder-emptied", notify_folder_emptied, "s" },
        { "notify-object-deleted", notify_object_deleted, "(sq)" },

        { "open-folder", open_folder, "s" },
        { "open-object", open_object, "(sq)" },
        { "open-config", open_config, "s" },
        { "open-search", open_search, "s" },
        { "open-parent", open_parent, "s" },

        { "reload-folder", reload_folder },
        { "reload-object", reload_object },
        { "reload-search", reload_search },

        { "toggle-search", toggle_search, "b" },
        { "update-bookmarks-icons", update_bookmarks_icons, "as" },

        { "reset-recursive", reset_recursively, "s" },
        { "reset-visible", reset_visible, "s" },

        { "enter-delay-mode", enter_delay_mode },
        { "apply-delayed-settings", apply_delayed_settings },
        { "dismiss-delayed-settings", dismiss_delayed_settings },

        { "dismiss-change", dismiss_change, "s" },  // here because needs to be accessed from DelayedSettingView rows
        { "erase", erase_dconf_key, "s" },          // here because needs a reload_view as we enter delay_mode

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
        uint16 unused;  // GAction parameter type switch is a little touchy, see pathbar.vala
        ((!) path_variant).@get ("(sq)", out full_name, out unused);

        show_notification (_("Key “%s” has been deleted.").printf (full_name));
    }

    private void open_folder (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        path_widget.close_popovers ();

        string full_name = ((!) path_variant).get_string ();

        request_folder (full_name, "");
    }

    private void open_object (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        path_widget.close_popovers ();
        revealer.hide_modifications_list ();

        string full_name;
        uint16 context_id;
        ((!) path_variant).@get ("(sq)", out full_name, out context_id);

        request_object (full_name, context_id);
    }

    private void open_config (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        path_widget.close_popovers ();

        string full_name = ((!) path_variant).get_string ();    // TODO use current_path instead?

        request_config (full_name);
    }

    private void open_search (SimpleAction action, Variant? search_variant)
        requires (search_variant != null)
    {
        path_widget.close_popovers ();

        string search = ((!) search_variant).get_string ();

        request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_ALL, search);
    }

    private void open_parent (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name = ((!) path_variant).get_string ();
        request_folder (ModelUtils.get_parent_path (full_name), full_name);
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

    private void toggle_search (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        bool search_request = ((!) path_variant).get_boolean ();
        if (search_request && !path_widget.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_ALL);
        else if (!search_request && path_widget.search_mode_enabled)
            stop_search ();
    }

    private void update_bookmarks_icons (SimpleAction action, Variant? bookmarks_variant)
        requires (bookmarks_variant != null)
    {
        string [] bookmarks = ((!) bookmarks_variant).get_strv ();

        if (bookmarks.length == 0)
            return;

        foreach (string bookmark in bookmarks)
        {
            if (bookmark.has_prefix ("?"))
                continue;
            if (is_path_invalid (bookmark))
                continue;
            if (ModelUtils.is_folder_path (bookmark))
                continue;   // TODO check folder existence

            uint16 context_id;
            string name;
            bool bookmark_exists = model.get_object (bookmark, out context_id, out name, false);
            if (!bookmark_exists)
                path_widget.update_bookmark_icon (bookmark, false);
            else if (context_id == ModelUtils.dconf_context_id)
                path_widget.update_bookmark_icon (bookmark, true, false);
            else
            {
                RegistryVariantDict bookmark_properties = new RegistryVariantDict.from_aqv (model.get_key_properties (bookmark, context_id, (uint16) PropertyQuery.IS_DEFAULT));
                bool is_default;
                if (!bookmark_properties.lookup (PropertyQuery.IS_DEFAULT, "b", out is_default))
                    assert_not_reached ();
                path_widget.update_bookmark_icon (bookmark, true, true, is_default);
            }
        }
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
        revealer.reset_objects (path, model.get_children (path), recursively);
    }

    private void enter_delay_mode (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.enter_delay_mode ();
        invalidate_popovers_with_ui_reload ();
    }

    private void apply_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.apply_delayed_settings ();
        invalidate_popovers_with_ui_reload ();
    }

    private void dismiss_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        modifications_handler.dismiss_delayed_settings ();
        invalidate_popovers_with_ui_reload ();
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
        invalidate_popovers_with_ui_reload ();
    }

    private void hide_notification (/* SimpleAction action, Variant? variant */)
    {
        notification_revealer.set_reveal_child (false);
    }

    /*\
    * * Keyboad action entries
    \*/

    private void install_kbd_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (kbd_action_entries, this);
        insert_action_group ("kbd", action_group);
    }

    private const GLib.ActionEntry [] kbd_action_entries =
    {
        // keyboard calls
        { "toggle-bookmark",    toggle_bookmark     },  // <P>b & <P>B
        { "copy-path",          copy_path           },  // <P>C
        { "bookmark",           bookmark            },  // <P>d
        { "unbookmark",         unbookmark          },  // <P>D
        { "toggle-search",      _toggle_search      },  // <P>f // TODO unduplicate names
        { "next-match",         next_match          },  // <P>g // usual shortcut for "next-match"     in a SearchEntry; see also "Down"
        { "previous-match",     previous_match      },  // <P>G // usual shortcut for "previous-match" in a SearchEntry; see also "Up"
        { "request-config",     _request_config     },  // <P>i // TODO fusion with ui.open-config?
        { "modifications",      modifications_list  },  // <A>i
        { "edit-path-end",      edit_path_end       },  // <P>l
        { "edit-path-last",     edit_path_last      },  // <P>L

        { "open-root",          open_root           },  // <S><A>Up
        { "open-parent",        open_current_parent },  //    <A>Up
        { "open-child",         open_child          },  //    <A>Down
        { "open-last-child",    open_last_child     },  // <S><A>Down

        { "toggle-boolean",     toggle_boolean      },  // <P>Return & <P>KP_Enter
        { "set-to-default",     set_to_default      }   // <P>Delete & <P>KP_Delete & decimalpoint & period & KP_Decimal
    };

    private void toggle_bookmark                        (/* SimpleAction action, Variant? variant */)
    {
        hide_hamburger_menu ();
        browser_view.discard_row_popover ();
        path_widget.click_bookmarks_button ();
    }

    private void copy_path                              (/* SimpleAction action, Variant? path_variant */)
    {
        browser_view.discard_row_popover ();

        if (path_widget.search_mode_enabled)
        {
            model.copy_action_called ();
            string selected_row_text = browser_view.get_copy_path_text () ?? saved_view;
            ((ConfigurationEditor) get_application ()).copy (selected_row_text);
        }
        else
        {
            if (browser_view.current_view == ViewType.OBJECT)
                model.copy_action_called ();
            ((ConfigurationEditor) get_application ()).copy (current_path);
        }
    }

    private void bookmark                               (/* SimpleAction action, Variant? variant */)
    {
        hide_hamburger_menu ();
        browser_view.discard_row_popover ();
        path_widget.bookmark_current_path ();
    }

    private void unbookmark                             (/* SimpleAction action, Variant? variant */)
    {
        hide_hamburger_menu ();
        browser_view.discard_row_popover ();
        path_widget.unbookmark_current_path ();
    }

    private void _toggle_search                         (/* SimpleAction action, Variant? variant */)
    {
        path_widget.close_popovers ();  // should never be needed if path_widget.search_mode_enabled
        hide_hamburger_menu ();         // should never be needed if path_widget.search_mode_enabled
        browser_view.discard_row_popover ();   // could be needed if path_widget.search_mode_enabled

        if (!path_widget.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.SEARCH);
        else if (!path_widget.entry_has_focus)
            path_widget.entry_grab_focus ();
        else if (path_widget.text.has_prefix ("/"))
            request_search (true, PathEntry.SearchMode.SEARCH);
        else
            stop_search ();
    }

    private void next_match                             (/* SimpleAction action, Variant? variant */)   // See also "Down"
    {
        if (path_widget.has_popover ()) // only for bookmarks popover, but let pathwidget handle that
            path_widget.down_pressed ();
        else if (info_button.active == false && !revealer.get_modifications_list_state ())
            browser_view.down_pressed ();               // FIXME returns bool
    }

    private void previous_match                         (/* SimpleAction action, Variant? variant */)   // See also "Up"
    {
        if (path_widget.has_popover ()) // only for bookmarks popover, but let pathwidget handle that
            path_widget.up_pressed ();
        else if (info_button.active == false && !revealer.get_modifications_list_state ())
            browser_view.up_pressed ();                 // FIXME returns bool
    }

    private void _request_config                        (/* SimpleAction action, Variant? variant */)  // TODO unduplicate method name
    {
        if (browser_view.current_view == ViewType.FOLDER)
            request_config (current_path);
    }

    private void modifications_list                     (/* SimpleAction action, Variant? variant */)
    {
        if (revealer.reveal_child)
            revealer.toggle_modifications_list ();
    }

    private void edit_path_end                          (/* SimpleAction action, Variant? variant */)
    {
        if (!path_widget.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.EDIT_PATH_MOVE_END);
    }

    private void edit_path_last                         (/* SimpleAction action, Variant? variant */)
    {
        if (!path_widget.search_mode_enabled)
            request_search (true, PathEntry.SearchMode.EDIT_PATH_SELECT_LAST_WORD);
    }

    private void open_root                              (/* SimpleAction action, Variant? variant */)
    {
        go_backward (true);
    }

    private void open_current_parent                    (/* SimpleAction action, Variant? variant */)
    {
        if (browser_view.current_view == ViewType.CONFIG)
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

    private void toggle_boolean                         (/* SimpleAction action, Variant? variant */)
    {
        if (info_button.active || path_widget.has_popover ())
            return;

        browser_view.discard_row_popover ();
        browser_view.toggle_boolean_key ();
    }

    private void set_to_default                         (/* SimpleAction action, Variant? variant */)
    {
        if (info_button.active || path_widget.has_popover ())
            return;

        if (revealer.dismiss_selected_modification ())
        {
            reload_view ();
            return;
        }
        browser_view.discard_row_popover ();
        string selected_row = browser_view.get_selected_row_name ();
        if (selected_row.has_suffix ("/"))
            reset_path ((!) selected_row, true);
        else
            browser_view.set_selected_to_default ();
    }

    private inline void hide_hamburger_menu ()
    {
        if (info_button.active)
            info_button.active = false;
    }

    /*\
    * * Path requests
    \*/

    public static bool is_path_invalid (string path)
    {
        return path.has_prefix ("/") && (path.contains ("//") || path.contains (" "));
    }

    private void request_config (string full_name)
    {
        browser_view.prepare_object_view (full_name, ModelUtils.folder_context_id,
                                          model.get_folder_properties (full_name),
                                          true);
        update_current_path (ViewType.CONFIG, strdup (full_name));

        stop_search ();
        // path_widget.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    private void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true)
    {
        string fallback_path = model.get_fallback_path (full_name);

        if (notify_missing && (fallback_path != full_name))
            cannot_find_folder (full_name); // do not place after, full_name is in some cases changed by set_directory()...

        browser_view.prepare_folder_view (create_key_model (fallback_path, model.get_children (fallback_path, true, true)), current_path.has_prefix (fallback_path));
        update_current_path (ViewType.FOLDER, fallback_path);

        if (selected_or_empty == "")
            browser_view.select_row (path_widget.get_selected_child (fallback_path));
        else
            browser_view.select_row (selected_or_empty);

        stop_search ();
        // path_widget.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }
    private static GLib.ListStore create_key_model (string base_path, Variant? children)
    {
        GLib.ListStore key_model = new GLib.ListStore (typeof (SimpleSettingObject));

        string name = ModelUtils.get_name (base_path);
        SimpleSettingObject sso = new SimpleSettingObject.from_full_name (ModelUtils.folder_context_id, name, base_path, false, true);
        key_model.append (sso);

        if (children != null)
        {
            VariantIter iter = new VariantIter ((!) children);
            uint16 context_id;
            while (iter.next ("(qs)", out context_id, out name))
            {
                if (ModelUtils.is_undefined_context_id (context_id))
                    assert_not_reached ();
                sso = new SimpleSettingObject.from_base_path (context_id, name, base_path);
                key_model.append (sso);
            }
        }
        return key_model;
    }

    private void request_object (string full_name, uint16 context_id = ModelUtils.undefined_context_id, bool notify_missing = true, string schema_id = "")
    {
        context_id = model.get_fallback_context (full_name, context_id, schema_id);

        if (ModelUtils.is_undefined_context_id (context_id))
        {
            if (notify_missing)
            {
                if (ModelUtils.is_key_path (full_name))
                    cannot_find_key (full_name);
                else
                    cannot_find_folder (full_name);
            }
            request_folder (ModelUtils.get_parent_path (full_name), full_name, false);
            path_widget.update_ghosts (model.get_fallback_path (path_widget.complete_path));
        }
        else
        {
            browser_view.prepare_object_view (full_name, context_id,
                                              model.get_key_properties (full_name, context_id, 0),
                                              current_path == ModelUtils.get_parent_path (full_name));
            update_current_path (ViewType.OBJECT, strdup (full_name));
        }

        stop_search ();
        // path_widget.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    private void request_search (bool reload, PathEntry.SearchMode mode = PathEntry.SearchMode.UNCLEAR, string? search = null)
    {
        string selected_row = browser_view.get_selected_row_name ();
        if (reload)
        {
            reload_search_action.set_enabled (false);
            browser_view.set_search_parameters (saved_view, path_widget.get_bookmarks ());
            reload_search_next = false;
        }
        if (mode != PathEntry.SearchMode.UNCLEAR)
            path_widget.prepare_search (mode, search);
        string search_text = search == null ? path_widget.text : (!) search;
        update_current_path (ViewType.SEARCH, search_text);
        if (mode != PathEntry.SearchMode.UNCLEAR)
            browser_view.select_row (selected_row);
        if (!path_widget.entry_has_focus)
            path_widget.entry_grab_focus_without_selecting ();
    }

    private void reload_view ()
    {
        if (browser_view.current_view == ViewType.FOLDER)
            request_folder (current_path, browser_view.get_selected_row_name ());
        else if (browser_view.current_view == ViewType.OBJECT)
            request_object (current_path, ModelUtils.undefined_context_id, false);
        else if (browser_view.current_view == ViewType.SEARCH)
            request_search (true);
    }

    /*\
    * * Path changing
    \*/

    private void update_current_path (ViewType type, string path)
    {
        if (type == ViewType.OBJECT || type == ViewType.FOLDER)
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
        path_widget.set_path (type, path);
        invalidate_popovers_without_reload ();
    }

    private void update_hamburger_menu ()
    {
        GLib.Menu section;

        GLib.Menu menu = new GLib.Menu ();

        if (current_type == ViewType.OBJECT && !ModelUtils.is_folder_path (current_path))   // TODO a better way to copy various representations of a key name/value/path
        {
            Variant variant = new Variant.string (model.get_suggested_key_copy_text (current_path, browser_view.last_context_id));
            menu.append (_("Copy descriptor"), "app.copy(" + variant.print (false) + ")");
        }
        else if (current_type != ViewType.SEARCH)
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

        section = new GLib.Menu ();
        append_or_not_night_mode_entry (ref section);
        section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
        section.append (_("About Dconf Editor"), "app.about");   // TODO move as "win."
        section.freeze ();
        menu.append_section (null, section);

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
    }

    private void invalidate_popovers_with_ui_reload ()
    {
        browser_view.hide_or_show_toggles (!modifications_handler.get_current_delay_mode ());
        invalidate_popovers_without_reload ();
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

    private void stop_search ()
    {
        if (path_widget.search_mode_enabled)
            search_stopped_cb ();
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
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        Widget? focus = get_focus ();
        bool focus_is_text_widget = focus != null && (((!) focus is Entry) || ((!) focus is TextView));

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            switch (name)
            {
                case "c":
                    if (focus_is_text_widget)
                        return false;

                    model.copy_action_called ();

                    browser_view.discard_row_popover (); // TODO avoid duplicate get_selected_row () call

                    string? selected_row_text = browser_view.get_copy_text ();
                    if (selected_row_text == null && current_type == ViewType.OBJECT)
                        selected_row_text = model.get_suggested_key_copy_text (current_path, browser_view.last_context_id);
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row_text == null ? current_path : (!) selected_row_text);
                    return true;

                case "v":   // https://bugzilla.gnome.org/show_bug.cgi?id=762257 is WONTFIX // TODO <Shift><Primary>v something?
                    if (focus_is_text_widget)
                        return false;

                    Gdk.Display? display = Gdk.Display.get_default ();
                    if (display == null)    // ?
                        return false;

                    string? clipboard_content = Clipboard.get_default ((!) display).wait_for_text ();
                    if (clipboard_content != null)
                        request_search (true, PathEntry.SearchMode.EDIT_PATH_MOVE_END, clipboard_content);
                    else
                        request_search (true, PathEntry.SearchMode.SEARCH);
                    return true;

                case "F1":  // TODO dance done to avoid <Primary>F1 to show help overlay
                    browser_view.discard_row_popover ();
                    if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                        return false;   // help overlay
                    ((ConfigurationEditor) get_application ()).about_cb ();
                    return true;

                default:
                    break;
            }
        }

        /* don't use "else if", or some widgets will not be hidden on <ctrl>F10 or such things */
        if (name == "F10")
        {
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
            {
                if (!focus_is_text_widget) // && browser_view.current_view != ViewType.SEARCH
                {
                    path_widget.toggle_pathbar_menu ();
                    return true;
                }
                return false;
            }

            browser_view.discard_row_popover ();
            path_widget.close_popovers ();
            return false;
        }

        if (name == "Up"
         && (event.state & Gdk.ModifierType.MOD1_MASK) == 0
         // see also <ctrl>G
         && !path_widget.has_popover ()
         && info_button.active == false
         && !revealer.get_modifications_list_state ())
            return browser_view.up_pressed ();
        if (name == "Down"
         && (event.state & Gdk.ModifierType.MOD1_MASK) == 0
         // see also <ctrl>g
         && !path_widget.has_popover ()
         && info_button.active == false
         && !revealer.get_modifications_list_state ())
            return browser_view.down_pressed ();

        if (name == "Return" || name == "KP_Enter")
        {
            if (browser_view.current_view == ViewType.SEARCH
             && path_widget.entry_has_focus
             && browser_view.return_pressed ())
                return true;
            return false;
        }

        if (name == "Escape")
        {
            if (path_widget.search_mode_enabled)
            {
                stop_search ();
                return true;
            }
            if (current_type == ViewType.CONFIG)
            {
                request_folder (current_path);
                return true;
            }
            return false;
        }

        if (name == "Menu")
        {
            if (browser_view.toggle_row_popover ())
            {
                path_widget.close_popovers ();
                hide_hamburger_menu ();
            }
            else if (info_button.sensitive == false)
                return true;
            else if (info_button.active == false)
            {
                path_widget.close_popovers ();
                browser_view.discard_row_popover ();
                info_button.active = true;
            }
            else
                info_button.active = false;
            return true;
        }

        if (info_button.active || path_widget.has_popover ())
            return false;

        if (!path_widget.search_mode_enabled &&
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

        if ((!focus_is_text_widget)
         && (event.is_modifier == 0)
         && (event.length != 0)
//       && (name != "F10")     // else <Shift>F10 toggles the search_entry popup; see if a976aa9740 fixes that in Gtk+ 4
         && (path_widget.handle_event (event)))
            return true;

        return false;
    }

    private void go_backward (bool shift)
    {
        if (path_widget.search_mode_enabled)
            return;

        browser_view.discard_row_popover ();
        if (current_path == "/")
            return;
        if (shift)
            request_folder ("/");
        else
            request_folder (ModelUtils.get_parent_path (current_path), current_path.dup ());
    }

    private void go_forward (bool shift)
    {
        if (path_widget.search_mode_enabled)
            return;

        string complete_path = path_widget.complete_path;

        browser_view.discard_row_popover ();
        if (current_path == complete_path)  // TODO something?
            return;

        if (shift)
        {
            string fallback_path = model.get_fallback_path (complete_path);
            if (ModelUtils.is_key_path (fallback_path))
                request_object (fallback_path);
            else if (fallback_path != current_path)
                request_folder (fallback_path);
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
