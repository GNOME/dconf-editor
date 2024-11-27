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


[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-window.ui")]
private class DConfWindow : Adw.ApplicationWindow
{
    private SettingsModel model;
    internal ModificationsHandler modifications_handler { get; set; }

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    private ulong use_shortpaths_changed_handler = 0;
    private ulong behaviour_changed_handler = 0;

    private ulong delayed_changes_changed_handler = 0;

    [GtkChild] private unowned Adw.ToastOverlay toast_overlay;
    [GtkChild] private unowned Adw.ToolbarView toolbar_view;
    [GtkChild] private unowned Adw.HeaderBar headerbar;
    [GtkChild] private unowned Gtk.Stack toolbar_switcher;
    [GtkChild] private unowned Pathbar pathbar;
    [GtkChild] private unowned Gtk.Entry location_entry;
    [GtkChild] private unowned Gtk.SearchEntry search_entry;
    [GtkChild] private unowned Gtk.Box content_box;
    [GtkChild] private unowned ModificationsView modifications_view;
    private DConfView main_view;

    private Adw.Toast? current_toast;

    internal string saved_view { get; set; default = "/"; }
    internal string current_path { get; set; default = "/"; }
    internal bool delay_mode { get; set; default = false; }
    internal bool show_search { get; set; default = false; }
    internal bool show_location { get; set; default = false; }
    internal bool show_modifications_bar { get; set; default = false; }
    internal bool show_modifications_sheet { get; set; default = false; }

    internal string toolbar_mode {
        get {
            if (show_search)
                return "search";
            else if (show_location)
                return "location";
            else
                return "pathbar";
        }
    }

    internal DConfWindow (bool disable_warning, string? schema, string? path, string? key_name)
    {
        notify["show-search"].connect (
            () => {
                // Only reset search_entry text when it is hidden. The widget
                // may already have text captured from elsewhere.
                if (! show_search)
                    search_entry.set_text ("");
                search_entry.grab_focus ();
                notify_property ("toolbar-mode");
            }
        );

        notify["show-location"].connect (
            () => {
                location_entry.set_text (current_path);
                location_entry.grab_focus ();
                notify_property ("toolbar-mode");
            }
        );

        notify["show-modifications-bar"].connect (
            () => {
                if (!show_modifications_bar)
                    show_modifications_sheet = false;
            }
        );

        notify["current-path"].connect (
            () => {
                search_entry.set_placeholder_text (_("Search in %s").printf (current_path));
            }
        );

        bind_property ("current-path", pathbar, "path", BindingFlags.SYNC_CREATE);

        search_entry.set_key_capture_widget (toolbar_view);

        model = new SettingsModel ();
        modifications_handler = new ModificationsHandler (model);

        main_view = new DConfView (modifications_handler);
        bind_property ("current-path", main_view, "path", BindingFlags.SYNC_CREATE);
        content_box.append (main_view);

        main_view.notify["current_view"].connect (
            () => {
                bool is_listing_view = (
                    main_view.current_view == ViewType.FOLDER
                    || main_view.current_view == ViewType.OBJECT
                );
                action_set_enabled ("ui.reset-recursive", is_listing_view);
                action_set_enabled ("ui.reset-current-recursively", is_listing_view);
                action_set_enabled ("ui.reset-current-non-recursively", is_listing_view);
            }
        );

        install_ui_action_entries ();
        install_browser_action_entries ();
        install_kbd_action_entries ();

        use_shortpaths_changed_handler = settings.changed ["use-shortpaths"].connect_after (reload_view);
        settings.bind ("use-shortpaths", model, "use-shortpaths", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        modifications_handler.notify["mode"].connect (on_modifications_handler_notify_mode);
        // TODO: Do we need to keep track of the handler ID?
        delayed_changes_changed_handler = modifications_handler.delayed_changes_changed.connect (on_modifications_handler_delayed_changes_changed);
        modifications_handler.delayed_changes_applied.connect (on_modifications_handler_delayed_changes_applied);

        behaviour_changed_handler = settings.changed ["behaviour"].connect_after (invalidate_popovers_with_ui_reload);
        settings.bind ("behaviour", modifications_handler, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        if (!disable_warning && settings.get_boolean ("show-warning"))
            show.connect (show_initial_warning);

        /* init current_path */
        bool restore_view = settings.get_boolean ("restore-view");
        string? settings_saved_view = null;
        if (restore_view)
        {
            settings_saved_view = settings.get_string ("saved-view");
            if (((!) settings_saved_view).contains ("//"))
                settings_saved_view = "/";

            /* string saved_path = settings.get_string ("saved-pathbar-path"); */
            string fallback_path = model.get_fallback_path (settings.get_string ("saved-pathbar-path"));
            /* headerbar.set_path (ModelUtils.is_folder_path (saved_path) ? ViewType.FOLDER : ViewType.OBJECT, saved_path);
            headerbar.update_ghosts (fallback_path);  // TODO allow a complete state restoration (including search and this) */
            // headerbar.set_path (ModelUtils.is_folder_path (fallback_path) ? ViewType.FOLDER : ViewType.OBJECT, fallback_path);
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
                /* Translators: command-line startup warning, try 'dconf-editor ca.desrt.dconf-editor.Demo.Relocatable' */
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
                    /* Translators: command-line startup warning */
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
                /* Translators: command-line startup warning, try 'dconf-editor ca.desrt.dconf-editor.Settings:/org/gnome/dconf-editor/' */
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
                /* Translators: command-line startup warning, try 'dconf-editor org.example.nothing'; the %s is the schema id */
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
    }

    [GtkCallback]
    private void on_location_entry_activate () {
        // TODO: Validate text! Show an error if it's wrong!
        current_path = location_entry.get_text ();
        // FIXME: We shouldn't need to do this
        request_folder (current_path);
        show_location = false;
    }

    [GtkCallback]
    private void on_location_entry_focus_leave () {
        /* Hide the location entry if it loses focus, but not if the window itself
         * loses focus, borrowing a behaviour from Nautilus
         */
        var focus_widget = root.get_focus ();
        if (focus_widget != null && ((!) focus_widget).is_ancestor (location_entry))
            return;
        show_location = false;
    }

    [GtkCallback]
    private void on_search_entry_changed () {
        request_search (search_entry.text);
    }

    private void request_search (string search_text)
    {
        if (!show_search && search_text != "")
            show_search = true;

        if (search_text == "")
        {
            request_path (current_path);
            return;
        }

        // FIXME: I don't know what search used to do with bookmarks but this
        //        was involved.
        // var bookmarks = ((DConfHeaderBar) headerbar).get_bookmarks ()
        // TODO: Do we need global search? (Set first parameter to false);
        main_view.set_search_parameters (true, current_path, {});
        main_view.set_dconf_path (ViewType.SEARCH, search_text);
    }

    ulong paths_changed_handler = 0;
    ulong gkey_value_push_handler = 0;
    ulong dkey_value_push_handler = 0;
    ulong settings_user_paths_changed_handler = 0;
    ulong settings_enabled_mappings_changed_handler = 0;
    private void prepare_model ()
    {
        settings_user_paths_changed_handler = settings.changed ["relocatable-schemas-user-paths"].connect (() => {
                RelocatableSchemasEnabledMappings enabled_mappings_flags = (RelocatableSchemasEnabledMappings) settings.get_flags ("relocatable-schemas-enabled-mappings");
                if (!(RelocatableSchemasEnabledMappings.USER in enabled_mappings_flags))
                    return;

                model.refresh_relocatable_schema_paths (true,
                                                        RelocatableSchemasEnabledMappings.BUILT_IN in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.INTERNAL in enabled_mappings_flags,
                                                        RelocatableSchemasEnabledMappings.STARTUP  in enabled_mappings_flags,
                                                        settings.get_value ("relocatable-schemas-user-paths"));
            });
        settings_enabled_mappings_changed_handler = settings.changed ["relocatable-schemas-enabled-mappings"].connect (() => {
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

        paths_changed_handler = model.paths_changed.connect (on_paths_changed);
        gkey_value_push_handler = model.gkey_value_push.connect (propagate_gkey_value_push);
        dkey_value_push_handler = model.dkey_value_push.connect (propagate_dkey_value_push);
    }

    private void on_paths_changed (SettingsModelCore _model, GenericSet<string> unused, bool internal_changes)
    {
        if (!main_view.check_reload (main_view.current_view, current_path, !internal_changes))
            return;

        reload_view ();
    }
    private void propagate_gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        main_view.gkey_value_push (full_name, context_id, key_value, is_key_default);
        modifications_view.gkey_value_push  (full_name, context_id, key_value, is_key_default);
    }
    private void propagate_dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        main_view.dkey_value_push (full_name, key_value_or_null);
        modifications_view.dkey_value_push  (full_name, key_value_or_null);
    }

    /*\
    * * initial warning
    \*/

    private void show_initial_warning ()
    {
        // FIXME: This should be in the UI file?!

        Adw.AlertDialog dialog = new Adw.AlertDialog (
            /* Translators: initial "use at your own risk" dialog, the welcoming text */
            _("Thanks for using Dconf Editor for editing your settings!"),
            /* Translators: initial "use at your own risk" dialog, the warning text */
              _("Don’t forget that some options may break applications, so be careful.")
        );

        /* Translators: initial "use at your own risk" dialog, the button label */
        dialog.add_response ("close", _("I’ll be careful."));

        dialog.set_close_response ("close");

        /* Translators: initial "use at your own risk" dialog, the checkbox label */
        CheckButton checkbutton = new CheckButton.with_label (_("Show this dialog next time."));
        settings.bind ("show-warning", checkbutton, "active", SettingsBindFlags.DEFAULT);
        dialog.set_extra_child (checkbutton);

        dialog.present (this);
    }

    /*\
    * * quitting
    \*/

    internal bool quit_if_no_pending_changes ()
    {
        if (modifications_handler.has_pending_changes ())
        {
            /* Translators: notification text, after a user Ctrl+Q keyboard action; same way to spell the shortcut as in the Settings application */
            show_notification (_("There are pending changes. Use Shift+Ctrl+Q to apply changes and quit, or Alt+F4 to dismiss changes and quit."));
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

    // protected override void before_destroy ()
    // {
    //     base.before_destroy ();

    //     ((ConfigurationEditor) get_application ()).clean_copy_notification ();

    //     modifications_handler.disconnect (delayed_changes_changed_handler);

    //     settings.disconnect (settings_user_paths_changed_handler);
    //     settings.disconnect (settings_enabled_mappings_changed_handler);

    //     model.disconnect (paths_changed_handler);
    //     model.disconnect (gkey_value_push_handler);
    //     model.disconnect (dkey_value_push_handler);

    //     settings.disconnect (behaviour_changed_handler);
    //     settings.disconnect (use_shortpaths_changed_handler);

    //     settings.delay ();
    //     settings.set_string ("saved-view", saved_view);
    //     string complete_path;
    //     headerbar.get_complete_path (out complete_path);
    //     settings.set_string ("saved-pathbar-path", complete_path);
    //     settings.apply ();
    // }

    /*\
    * * Main UI action entries
    \*/

    private void install_ui_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (ui_action_entries, this);
        insert_action_group ("ui", action_group);

        var show_modifications_action = new SimpleAction ("show-modifications", null);
        bind_property ("show-modifications-bar", show_modifications_action, "enabled", BindingFlags.SYNC_CREATE);
        show_modifications_action.activate.connect (
            () => {
                show_modifications_sheet = true;
            }
        );
        action_group.add_action (show_modifications_action);

        var hide_modifications_action = new SimpleAction ("hide-modifications", null);
        hide_modifications_action.activate.connect (
            () => {
                show_modifications_sheet = false;
            }
        );
        action_group.add_action (hide_modifications_action);
    }

    private const GLib.ActionEntry [] ui_action_entries =
    {
        { "reset-recursive",                reset_recursively, "s" },
        { "reset-current-recursively",      reset_current_recursively },
        { "reset-current-non-recursively",  reset_current_non_recursively },

        { "enter-delay-mode",           enter_delay_mode },
        { "apply-delayed-settings",     apply_delayed_settings },
        { "dismiss-delayed-settings",   dismiss_delayed_settings },

        { "dismiss-change", dismiss_change, "s" },  // here because needs to be accessed from DelayedSettingView rows
        { "erase", erase_dconf_key, "s" },          // here because needs a reload_view as we enter delay_mode

        { "notify-folder-emptied", notify_folder_emptied, "s" },
        { "notify-object-deleted", notify_object_deleted, "(sq)" }
    };

    // FIXME: We can either trim these action entries, or move them to mixins
    //        instead of the current weird class hierarchy.
    private void install_browser_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();

        action_group.add_action_entries (browser_action_entries, this);

        action_group.add_action (new PropertyAction ("toggle-search", this, "show-search"));

        var hide_search_action = new SimpleAction ("hide-search", null);
        hide_search_action.activate.connect (
            () => {
                show_search = false;
            }
        );
        action_group.add_action (hide_search_action);

        action_group.add_action (new PropertyAction ("edit-location", this, "show-location"));

        var hide_location_action = new SimpleAction ("hide-location", null);
        hide_location_action.activate.connect (
            () => {
                show_location = false;
            }
        );
        action_group.add_action (hide_location_action);

        insert_action_group ("browser", action_group);

        // var toolbar_mode_action = (SimpleAction) action_group.lookup_action ("toolbar-mode");
        // bind_property ("toolbar-mode", toolbar_mode_action, "state");

        // disabled_state_action = (SimpleAction) action_group.lookup_action ("disabled-state-s");
        // disabled_state_action.set_enabled (false);
        // disabled_state_action = (SimpleAction) action_group.lookup_action ("disabled-state-sq");
        // disabled_state_action.set_enabled (false);

        // open_path_action = (SimpleAction) action_group.lookup_action ("open-path");

        // reload_search_action = (SimpleAction) action_group.lookup_action ("reload-search");
        // reload_search_action.set_enabled (false);
    }

    private const GLib.ActionEntry [] browser_action_entries =
    {
        { "open-folder", on_open_folder_activate, "s" },
        { "reload-view", on_reload_view_activate },
        { "copy-location", on_copy_location_activate },
        { "open-object", on_open_object_activate, "(sq)" },
        // { "toggle-search", null, null, "false" }, // on_toggle_search_activate

        // { "empty",              empty, "*" },
        // { "empty-null",         empty },
        // { "disabled-state-s",   empty, "s", "''" },
        // { "disabled-state-sq",  empty, "(sq)", "('',uint16 65535)" },
        // { "edit-location",      edit_location },

        // { "open-folder",        open_folder, "s" },
        // { "open-object",        open_object, "(sq)" },
        // { "open-config",        open_config, "s" },
        // { "open-config-local",  open_config_local },
        // { "open-search",        open_search, "s" },
        // { "open-search-local",  open_search_local },
        // { "open-search-global", open_search_global },
        // { "open-search-root",   open_search_root },
        // { "next-search",        next_search, "s" },
        // { "open-parent",        open_parent, "s" },

        // { "open-path",          open_path, "(sq)", "('/',uint16 " + ModelUtils.folder_context_id_string + ")" },

        // { "reload-folder",      reload_folder },
        // { "reload-object",      reload_object },
        // { "reload-search",      reload_search },

        // { "hide-search",        hide_search },
        // { "show-search",        show_search },
        // { "toggle-search",      toggle_search, "b", "false" },
        // { "search-changed",     search_changed, "ms" }
    };

    private void reset_recursively (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        reset_from_path_and_notify (((!) path_variant).get_string (), true);
    }

    private void reset_current_recursively (/* SimpleAction action, Variant? path_variant */)
    {
        reset_from_path_and_notify (current_path, true);
    }

    private void reset_current_non_recursively (/* SimpleAction action, Variant? path_variant */)
    {
        reset_from_path_and_notify (current_path, false);
    }

    private void reset_from_path_and_notify (string path, bool recursive)
    {
        if (reset_path (path, recursive) == 0)
        {
            /* Translators: displayed as a toast, when the user tries to reset keys from/for a folder that has nothing to reset */
            show_notification (_("Nothing to reset."));
            // modifications_handler.dismiss_delayed_settings ();
        }
    }

    private uint reset_path (string path, bool recursive)
    {
        uint16 context_id;
        string name;

        if (!model.get_object (path, out context_id, out name, false))
            return 0;

        if (ModelUtils.is_folder_context_id (context_id))
        {
            return reset_objects_in_path (path, model.get_children (path), recursive);
        }
        else if (ModelUtils.is_dconf_context_id (context_id))
        {
            if (model.is_key_ghost (path))
                return 0;

            if (!modifications_handler.get_current_delay_mode ())
                modifications_handler.enter_delay_mode ();
            modifications_handler.add_delayed_setting (path, null, ModelUtils.dconf_context_id);
            return 1;
        }
        else // is gsettings key
        {
            RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (path, context_id, (uint16) (PropertyQuery.IS_DEFAULT)));
            bool is_key_default;
            if (!properties.lookup (PropertyQuery.IS_DEFAULT, "b", out is_key_default))
                assert_not_reached ();
            properties.clear ();

            if (is_key_default)
                return 0;

            if (!modifications_handler.get_current_delay_mode ())
                modifications_handler.enter_delay_mode ();
            modifications_handler.add_delayed_setting (path, null, context_id);
            return 1;
        }
    }

    private uint reset_objects_in_path (string base_path, Variant? objects, bool recursive)
    {
        if (objects == null)
            return 0;

        uint result = 0;

        VariantIter iter = new VariantIter ((!) objects);
        uint16 context_id;
        string name;
        while (iter.next ("(qs)", out context_id, out name))
        {
            string item_path = ModelUtils.recreate_full_name (base_path, name, ModelUtils.is_folder_context_id (context_id));
            bool skip_item = ModelUtils.is_folder_context_id (context_id) && !recursive;
            if (!skip_item)
                result += reset_path (item_path, recursive);
        }

        return result;
    }

    private void on_open_folder_activate (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        current_path = ((!) path_variant).get_string ();
        show_search = false;
        show_modifications_sheet = false;

        // FIXME I don't know why this is.
        request_folder (current_path);
    }


    private void on_open_object_activate (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        uint16 context_id;
        ((!) path_variant).@get ("(sq)", out full_name, out context_id);

        show_search = false;
        show_modifications_sheet = false;
        request_object (full_name, context_id);
    }

    private void on_reload_view_activate ()
    {
        reload_view ();
    }

    private void on_copy_location_activate ()
    {
        Gdk.Clipboard clipboard = get_clipboard ();
        clipboard.set_value (current_path);
    }

    private void on_modifications_handler_notify_mode ()
    {
        reload_view ();
    }

    private void on_modifications_handler_delayed_changes_changed ()
    {
        action_set_enabled ("ui.apply-delayed-settings", modifications_handler.has_pending_changes ());
        action_set_enabled ("ui.enter-delay-mode", modifications_handler.mode != ModificationsMode.DELAYED);

        if (modifications_handler.mode == ModificationsMode.TEMPORARY && ! modifications_handler.has_pending_changes ())
            show_modifications_bar = false;
        else
            show_modifications_bar = modifications_handler.mode != ModificationsMode.NONE;
    }

    private void on_modifications_handler_delayed_changes_applied (uint count)
    {
        show_notification (
            ngettext ("One change was applied.", "%u changes were applied.", count).printf (count)
        );
    }

    private void show_modifications (/* SimpleAction action, Variant? variant */)
    {
        show_modifications_sheet = true;
    }

    private void hide_modifications (/* SimpleAction action, Variant? variant */)
    {
        show_modifications_sheet = false;
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
        // FIXME: This doesn't actually dismiss the change in main_view, but it used to :(
        // FIXME: It's almost definitely because of the ModificationsHandler we passed to main_view
        modifications_handler.dismiss_change (((!) path_variant).get_string ());
        main_view.invalidate_popovers ();
        reload_view ();
    }

    private void erase_dconf_key (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        modifications_handler.erase_dconf_key (((!) path_variant).get_string ());
        invalidate_popovers_with_ui_reload ();
    }

    private void invalidate_popovers_with_ui_reload ()
    {
        delay_mode = modifications_handler.get_current_delay_mode ();
        main_view.hide_or_show_toggles (!delay_mode);
        main_view.invalidate_popovers ();
    }

    /*\
    * * bookmarks interaction
    \*/

    protected BookmarkIcon get_bookmark_icon (ref string bookmark)
    {
        uint16 context_id;
        string name;
        bool bookmark_exists = model.get_object (bookmark, out context_id, out name, false);    // TODO get_folder

        if (context_id == ModelUtils.folder_context_id)
        {
            if (bookmark_exists)
                return BookmarkIcon.VALID_FOLDER;
            else
                return BookmarkIcon.EMPTY_FOLDER;
        }

        if (!bookmark_exists)
            return BookmarkIcon.EMPTY_OBJECT;

        if (context_id == ModelUtils.dconf_context_id)
            return BookmarkIcon.DCONF_OBJECT;

        RegistryVariantDict bookmark_properties = new RegistryVariantDict.from_aqv (model.get_key_properties (bookmark, context_id, (uint16) PropertyQuery.IS_DEFAULT));
        bool is_default;
        if (!bookmark_properties.lookup (PropertyQuery.IS_DEFAULT, "b", out is_default))
            assert_not_reached ();

        if (is_default)
            return BookmarkIcon.KEY_DEFAULTS;
        else
            return BookmarkIcon.EDITED_VALUE;
    }

    /*\
    * * adaptative stuff
    \*/

    private bool disable_action_bar = false;

    /*\
    * * Keyboard action entries
    \*/

    private void install_kbd_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (kbd_action_entries, this);
        insert_action_group ("kbd", action_group);
    }

    private const GLib.ActionEntry [] kbd_action_entries =
    {
        { "toggle-boolean",     toggle_boolean      },  // <P>Return & <P>KP_Enter
        { "set-to-default",     set_to_default      }   // <P>Delete & <P>KP_Delete & decimalpoint & period & KP_Decimal
    };

    private void toggle_boolean                         (/* SimpleAction action, Variant? variant */)
    {
        if (row_action_blocked ())
            return;
        if (modifications_handler.get_current_delay_mode ())    // TODO better
            return;

        main_view.close_popovers ();
        main_view.toggle_boolean_key ();
    }

    private void set_to_default                         (/* SimpleAction action, Variant? variant */)
    {
        if (row_action_blocked ())
            return;

        if (modifications_view.dismiss_selected_modification ())
        {
            reload_view ();
            return;
        }
        main_view.close_popovers ();
        string selected_row = main_view.get_selected_row_name ();
        if (selected_row.has_suffix ("/"))
            reset_path ((!) selected_row, true);
        else
            main_view.set_selected_to_default ();
    }

    /*\
    * * Path requests
    \*/

    private void request_path (string path)
    {
        if (path.has_suffix ("/"))
            request_folder (path);
        else
            request_object (path);
    }

    protected void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true)
    {
        string fallback_path = model.get_fallback_path (full_name);
        bool is_ancestor = current_path.has_prefix (fallback_path);

        if (notify_missing && (fallback_path != full_name))
            cannot_find_folder (full_name); // do not place after, full_name is in some cases changed by set_directory()...

        current_path = fallback_path;
        main_view.prepare_folder_view (create_key_model (current_path, model.get_children (current_path, true, true)), is_ancestor);
        main_view.set_dconf_path (ViewType.FOLDER, current_path);

        if (selected_or_empty != "")
            main_view.select_row (selected_or_empty);
    }

    private static GLib.ListStore create_key_model (string base_path, Variant? children)
    {
        GLib.ListStore key_model = new GLib.ListStore (typeof (SimpleSettingObject));

        string name = ModelUtils.get_name (base_path);

        if (children != null)
        {
            VariantIter iter = new VariantIter ((!) children);
            uint16 context_id;
            while (iter.next ("(qs)", out context_id, out name))
            {
                if (ModelUtils.is_undefined_context_id (context_id))
                    assert_not_reached ();
                SimpleSettingObject sso = new SimpleSettingObject.from_base_path (context_id, name, base_path);
                key_model.append (sso);
            }
        }
        return key_model;
    }

    protected void request_object (string full_name, uint16 context_id = ModelUtils.undefined_context_id, bool notify_missing = true, string schema_id = "")
    {
        context_id = model.get_fallback_context (full_name, context_id, schema_id);

        if (ModelUtils.is_undefined_context_id (context_id))
        {
            // FIXME Use AdwToast, and also maybe flatten out all these functions
            if (notify_missing)
            {
                if (ModelUtils.is_key_path (full_name))
                    cannot_find_key (full_name);
                else
                    cannot_find_folder (full_name);
            }
            request_folder (ModelUtils.get_parent_path (full_name), full_name, false);
            // string complete_path;
            // headerbar.get_complete_path (out complete_path);
            // headerbar.update_ghosts (model.get_fallback_path (complete_path));
        }
        else
        {
            current_path = strdup (full_name);
            main_view.prepare_object_view (full_name, context_id,
                                           model.get_key_properties (full_name, context_id, 0),
                                           current_path == ModelUtils.get_parent_path (full_name));
            main_view.set_dconf_path (ViewType.OBJECT, current_path);
            // update_current_path (ViewType.OBJECT, strdup (full_name));
        }

        // stop_search ();
        // headerbar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    /*\
    * * Non-existent path notifications // TODO unduplicate
    \*/

    private void notify_folder_emptied (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name = ((!) path_variant).get_string ();

        /* Translators: notification text, when the requested folder has been removed; the %s is the folder path */
        show_notification (_("Folder “%s” is now empty.").printf (full_name));
    }

    private void notify_object_deleted (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        uint16 unused;  // GAction parameter type switch is a little touchy, see pathbar.vala
        string full_name;
        ((!) path_variant).@get ("(sq)", out full_name, out unused);

        /* Translators: notification text, when the requested key has been removed; the %s is the key path */
        show_notification (_("Key “%s” has been deleted.").printf (full_name));
    }

    private void cannot_find_key (string full_name)
    {
        /* Translators: notification text at startup, use 'dconf-editor /org/example/test'; the %s is the key path */
        show_notification (_("Cannot find key “%s”.").printf (full_name));
    }

    private void cannot_find_folder (string full_name)
    {
        /* Translators: notification text at startup, use 'dconf-editor /org/example/empty/'; the %s is the folder path */
        show_notification (_("There’s nothing in requested folder “%s”.").printf (full_name));
    }

    protected bool row_action_blocked ()
    {
        // if (headerbar.has_popover ())
        //     return true;
        if (main_view.is_in_in_window_mode ())
            return true;
        return false;
    }

    protected void reload_view ()
    {
        if (main_view.current_view == ViewType.FOLDER)
            request_folder (current_path, main_view.get_selected_row_name ());
        else if (main_view.current_view == ViewType.OBJECT)
            request_object (current_path, ModelUtils.undefined_context_id, false);
        else
            request_search (search_entry.text);
    }

    protected void show_notification (string notification)
    {
        // We sometimes show toasts based on user input, so it is better if we
        // only have one. Hide the old toast instead of forming a queue.
        if (current_toast != null)
            ((!) current_toast).dismiss ();

        Adw.Toast toast = new Adw.Toast (notification);
        toast_overlay.add_toast (toast);
        current_toast = toast;
    }
}
