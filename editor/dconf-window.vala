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

private class DConfWindow : BookmarksWindow, AdaptativeWidget
{
    private SettingsModel model;
    private ModificationsHandler modifications_handler;

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    private ulong use_shortpaths_changed_handler = 0;
    private ulong behaviour_changed_handler = 0;

    private ulong delayed_changes_changed_handler = 0;

    private DConfHeaderBar headerbar;
    private DConfView      main_view;

    internal DConfWindow (bool disable_warning, string? schema, string? path, string? key_name)
    {
        SettingsModel _model = new SettingsModel ();
        ModificationsHandler _modifications_handler = new ModificationsHandler (_model);
        DConfHeaderBar _headerbar = new DConfHeaderBar ();
        DConfView _main_view = new DConfView (_modifications_handler);

        Object (nta_headerbar               : (BaseHeaderBar) _headerbar,
                base_view                   : (BaseView) _main_view,
                window_title                : ConfigurationEditor.PROGRAM_NAME,
                specific_css_class_or_empty : "dconf-editor",
                help_string_or_empty        : "",
                schema_path                 : "/ca/desrt/dconf-editor/");

        model = _model;
        modifications_handler = _modifications_handler;
        headerbar = _headerbar;
        main_view = _main_view;

        create_modifications_revealer ();

        install_ui_action_entries ();
        install_kbd_action_entries ();

        use_shortpaths_changed_handler = settings.changed ["use-shortpaths"].connect_after (reload_view);
        settings.bind ("use-shortpaths", model, "use-shortpaths", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        revealer.modifications_handler = modifications_handler;
        delayed_changes_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                uint total_changes_count = modifications_handler.dconf_changes_count + modifications_handler.gsettings_changes_count;
                if (total_changes_count == 0)
                    headerbar.set_has_pending_changes (/* has pending changes */ false,
                                                       /* mode is not delayed */ !modifications_handler.get_current_delay_mode ());
                else
                {
                    if (modifications_handler.mode == ModificationsMode.TEMPORARY && total_changes_count != 1)
                        assert_not_reached ();
                    headerbar.set_has_pending_changes (/* has pending changes */ true,
                                                       /* mode is not delayed */ !modifications_handler.get_current_delay_mode ());
                }
            });

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
            headerbar.set_path (ModelUtils.is_folder_path (fallback_path) ? ViewType.FOLDER : ViewType.OBJECT, fallback_path);
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
        if (current_type == ViewType.SEARCH)
        {
            if (!internal_changes)  // TODO do not react to value changes
                reload_search_action.set_enabled (true);
        }
        else if (main_view.check_reload (current_type, current_path, !internal_changes))    // handle infobars in needed
            reload_view ();

        string complete_path;
        headerbar.get_complete_path (out complete_path);
        headerbar.update_ghosts (((SettingsModel) _model).get_fallback_path (complete_path));
    }
    private void propagate_gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        main_view.gkey_value_push (full_name, context_id, key_value, is_key_default);
        revealer.gkey_value_push  (full_name, context_id, key_value, is_key_default);
    }
    private void propagate_dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        main_view.dkey_value_push (full_name, key_value_or_null);
        revealer.dkey_value_push  (full_name, key_value_or_null);
    }

    /*\
    * * ModificationsRevealer
    \*/

    private ModificationsRevealer revealer;

    private void create_modifications_revealer ()
    {
        revealer = new ModificationsRevealer ();
        revealer.visible = true;
        add_to_main_grid (revealer);
        add_adaptative_child (revealer);
    }

    /*\
    * * initial warning
    \*/

    private void show_initial_warning ()
    {
        /* Translators: initial "use at your own risk" dialog, the welcoming text */
        Gtk.MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.INFO, ButtonsType.NONE, _("Thanks for using Dconf Editor for editing your settings!"));

        /* Translators: initial "use at your own risk" dialog, the warning text */
        dialog.format_secondary_text (_("Don’t forget that some options may break applications, so be careful."));

        /* Translators: initial "use at your own risk" dialog, the button label */
        dialog.add_buttons (_("I’ll be careful."), ResponseType.ACCEPT);

        Box box = (Box) dialog.get_message_area ();
        /* Translators: initial "use at your own risk" dialog, the checkbox label */
        CheckButton checkbutton = new CheckButton.with_label (_("Show this dialog next time."));
        checkbutton.visible = true;
        checkbutton.active = true;
        checkbutton.margin_top = 5;
        box.add (checkbutton);  // TODO don't show box if the user explicitly said she wanted to see the dialog next time?

        ulong dialog_response_handler = dialog.response.connect (() => { if (!checkbutton.active) settings.set_boolean ("show-warning", false); });
        dialog.run ();
        dialog.disconnect (dialog_response_handler);
        dialog.destroy ();
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

    protected override void before_destroy ()
    {
        base.before_destroy ();

        ((ConfigurationEditor) get_application ()).clean_copy_notification ();

        modifications_handler.disconnect (delayed_changes_changed_handler);

        settings.disconnect (settings_user_paths_changed_handler);
        settings.disconnect (settings_enabled_mappings_changed_handler);

        model.disconnect (paths_changed_handler);
        model.disconnect (gkey_value_push_handler);
        model.disconnect (dkey_value_push_handler);

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (use_shortpaths_changed_handler);

        settings.delay ();
        settings.set_string ("saved-view", saved_view);
        string complete_path;
        headerbar.get_complete_path (out complete_path);
        settings.set_string ("saved-pathbar-path", complete_path);
        settings.apply ();
    }

    /*\
    * * Main UI action entries
    \*/

    private void install_ui_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (ui_action_entries, this);
        insert_action_group ("ui", action_group);
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

        { "show-in-window-modifications",   show_modifications_view },

        { "notify-folder-emptied", notify_folder_emptied, "s" },
        { "notify-object-deleted", notify_object_deleted, "(sq)" }
    };

    private void reset_recursively (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        reset_path (((!) path_variant).get_string (), true);
    }

    private void reset_current_recursively (/* SimpleAction action, Variant? path_variant */)
    {
        reset_path (current_path, true);
    }

    private void reset_current_non_recursively (/* SimpleAction action, Variant? path_variant */)
    {
        reset_path (current_path, false);
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
        if (main_view.in_window_modifications)
            show_default_view ();
        modifications_handler.apply_delayed_settings ();
        invalidate_popovers_with_ui_reload ();
    }

    private void dismiss_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        if (main_view.in_window_modifications)
            show_default_view ();
        modifications_handler.dismiss_delayed_settings ();
        invalidate_popovers_with_ui_reload ();
    }

    private void dismiss_change (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
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
        bool delay_mode = modifications_handler.get_current_delay_mode ();
        main_view.hide_or_show_toggles (!delay_mode);
        main_view.invalidate_popovers ();
        headerbar.delay_mode = delay_mode;
    }

    /*\
    * * showing or hiding panels
    \*/

    protected override void show_default_view ()
    {
        if (main_view.in_window_modifications)
        {
            headerbar.show_default_view ();
            main_view.show_default_view ();

            if (current_type == ViewType.CONFIG)
                request_folder (current_path);
        }
        else
            base.show_default_view ();
    }

    private void show_modifications_view (/* SimpleAction action, Variant? path_variant */)
    {
        close_in_window_panels ();

        headerbar.show_modifications_view ();
        main_view.show_modifications_view ();
    }

    /*\
    * * bookmarks interaction
    \*/

    protected override BookmarkIcon get_bookmark_icon (ref string bookmark)
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
    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);

        bool _disable_action_bar = AdaptativeWidget.WindowSize.is_extra_thin (new_size)
                                || AdaptativeWidget.WindowSize.is_extra_flat (new_size);
        if (disable_action_bar != _disable_action_bar)
        {
            disable_action_bar = _disable_action_bar;
            if (main_view.in_window_modifications)
                show_default_view ();
        }
    }

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
        { "modifications",      modifications_list  },  // <A>i

        { "toggle-boolean",     toggle_boolean      },  // <P>Return & <P>KP_Enter
        { "set-to-default",     set_to_default      }   // <P>Delete & <P>KP_Delete & decimalpoint & period & KP_Decimal
    };

    private void modifications_list                     (/* SimpleAction action, Variant? variant */)
    {
        if (!modifications_handler.get_current_delay_mode ())
            return;

        // use popover
        if (!disable_action_bar)
            revealer.toggle_modifications_list ();
        // use in-window
        else if (main_view.in_window_modifications)
            show_default_view ();
        else
            show_modifications_view ();
    }

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

        if (revealer.dismiss_selected_modification ())
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
    * * keyboard actions overrides
    \*/

    protected override void toggle_bookmark_called ()   // TODO better
    {
        if (main_view.in_window_modifications)
            show_default_view ();
    }

    protected override bool escape_pressed ()
    {
        if (main_view.in_window_modifications)
        {
            show_default_view ();
            return true;
        }
        return base.escape_pressed ();
    }

    /*\
    * * keyboard calls helpers
    \*/

    protected override bool intercept_next_match (out bool interception_result)
    {
        if (revealer.get_modifications_list_state ())   // for modifications popover
        {
            interception_result = revealer.next_match ();
            return true;
        }
        return base.intercept_next_match (out interception_result);
    }

    protected override bool intercept_previous_match (out bool interception_result)
    {
        if (revealer.get_modifications_list_state ())   // for modifications popover
        {
            interception_result = revealer.previous_match ();
            return true;
        }
        return base.intercept_previous_match (out interception_result);
    }

    /*\
    * * Path requests
    \*/

    protected override void reconfigure_search (bool local_search)
    {
        main_view.set_search_parameters (local_search, saved_view, ((DConfHeaderBar) headerbar).get_bookmarks ());
    }

    protected override void close_in_window_panels ()
    {
        hide_notification ();
        headerbar.close_popovers ();
        revealer.hide_modifications_list ();
        if (main_view.in_window_bookmarks || main_view.in_window_modifications || in_window_about)
            show_default_view ();
    }

    protected override void request_config (string full_name)
    {
        main_view.prepare_object_view (full_name, ModelUtils.folder_context_id,
                                       model.get_folder_properties (full_name),
                                       true);
        update_current_path (ViewType.CONFIG, strdup (full_name));

        stop_search ();
        // headerbar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    protected override void request_folder (string full_name, string selected_or_empty = "", bool notify_missing = true)
    {
        string fallback_path = model.get_fallback_path (full_name);

        if (notify_missing && (fallback_path != full_name))
            cannot_find_folder (full_name); // do not place after, full_name is in some cases changed by set_directory()...

        main_view.prepare_folder_view (create_key_model (fallback_path, model.get_children (fallback_path, true, true)), current_path.has_prefix (fallback_path));
        update_current_path (ViewType.FOLDER, fallback_path);

        if (selected_or_empty == "")
            main_view.select_row (headerbar.get_selected_child (fallback_path));
        else
            main_view.select_row (selected_or_empty);

        stop_search ();
        // headerbar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }
    private static GLib.ListStore create_key_model (string base_path, Variant? children)
    {
        GLib.ListStore key_model = new GLib.ListStore (typeof (SimpleSettingObject));

        string name = ModelUtils.get_name (base_path);
        SimpleSettingObject sso = new SimpleSettingObject.from_full_name (/* context id */ ModelUtils.folder_context_id,
                                                                          /* name       */ name,
                                                                          /* base path  */ base_path,
                                                                          /* is search  */ true,
                                                                          /* is pinned  */ true);
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

    protected override void request_object (string full_name, uint16 context_id = ModelUtils.undefined_context_id, bool notify_missing = true, string schema_id = "")
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
            string complete_path;
            headerbar.get_complete_path (out complete_path);
            headerbar.update_ghosts (model.get_fallback_path (complete_path));
        }
        else
        {
            main_view.prepare_object_view (full_name, context_id,
                                           model.get_key_properties (full_name, context_id, 0),
                                           current_path == ModelUtils.get_parent_path (full_name));
            update_current_path (ViewType.OBJECT, strdup (full_name));
        }

        stop_search ();
        // headerbar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
    }

    /*\
    * * navigation helpers
    \*/

    protected override bool handle_copy_text (out string copy_text)
    {
        model.copy_action_called ();

        if (headerbar.handle_copy_text (out copy_text))     // for bookmarks popovers
            return true;
        if (revealer.handle_copy_text (out copy_text))      // for delayed settings popovers
            return true;
        if (main_view.handle_copy_text (out copy_text))  // for in-window panels and for content
            return true;
        if (current_type == ViewType.OBJECT)
            copy_text = model.get_suggested_key_copy_text (current_path, main_view.last_context_id);
        if (BaseWindow.is_empty_text (copy_text))
            copy_text = current_path;
        return true;
    }

    protected override bool get_alt_copy_text (out string copy_text)
    {
        model.copy_action_called ();

        if (headerbar.search_mode_enabled)
        {
            if (!main_view.handle_alt_copy_text (out copy_text))
                copy_text = saved_view;
        }
        else
            copy_text = current_path;
        return true;
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
}
