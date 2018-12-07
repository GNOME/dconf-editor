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

private class DConfWindow : BrowserWindow
{
    private SettingsModel model = new SettingsModel ();
    private ModificationsHandler modifications_handler;

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    private ulong use_shortpaths_changed_handler = 0;
    private ulong behaviour_changed_handler = 0;

    private ulong headerbar_update_bookmarks_icons_handler = 0;
    private ulong browserview_update_bookmarks_icons_handler = 0;

    private ulong delayed_changes_changed_handler = 0;
    private ulong bookmarks_selection_changed_handler = 0;

    private DConfHeaderBar headerbar;

    private StyleContext context;
    construct
    {
        title = _("dconf Editor");
        context = get_style_context ();
        context.add_class ("dconf-editor");

        create_modifications_revealer ();

        install_ui_action_entries ();
        install_kbd_action_entries ();
        install_bmk_action_entries ();

        bookmarks_selection_changed_handler = browser_view.bookmarks_selection_changed.connect (on_bookmarks_selection_changed);
    }

    internal DConfWindow (bool disable_warning, string? schema, string? path, string? key_name, bool night_time, bool dark_theme, bool automatic_night_mode)
    {
        DConfHeaderBar _headerbar = new DConfHeaderBar ();
        Object (initial_night_time: night_time, initial_dark_theme: dark_theme, initial_automatic_night_mode: automatic_night_mode, adaptative_headerbar: (AdaptativeHeaderBar) _headerbar);
        headerbar = _headerbar;

        headerbar_update_bookmarks_icons_handler = headerbar.update_bookmarks_icons.connect (update_bookmarks_icons_from_variant);
        browserview_update_bookmarks_icons_handler = browser_view.update_bookmarks_icons.connect (update_bookmarks_icons_from_variant);

        use_shortpaths_changed_handler = settings.changed ["use-shortpaths"].connect_after (reload_view);
        settings.bind ("use-shortpaths", model, "use-shortpaths", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        modifications_handler = new ModificationsHandler (model);
        revealer.modifications_handler = modifications_handler;
        browser_view.modifications_handler = modifications_handler;
        delayed_changes_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                if (!AdaptativeWidget.WindowSize.is_extra_thin (window_size)
                 && !AdaptativeWidget.WindowSize.is_extra_flat (window_size))
                    return;

                uint total_changes_count = modifications_handler.dconf_changes_count + modifications_handler.gsettings_changes_count;
                if (total_changes_count == 0)
                    headerbar.set_apply_modifications_button_sensitive (false);
                else
                {
                    if (modifications_handler.mode == ModificationsMode.TEMPORARY && total_changes_count != 1)
                        assert_not_reached ();
                    headerbar.set_apply_modifications_button_sensitive (true);
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

            string saved_path = settings.get_string ("saved-pathbar-path");
            string fallback_path = model.get_fallback_path (saved_path);
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
        else if (browser_view.check_reload (current_type, current_path, !internal_changes))    // handle infobars in needed
            reload_view ();

        headerbar.update_ghosts (((SettingsModel) _model).get_fallback_path (headerbar.get_complete_path ()));
    }
    private void propagate_gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        browser_view.gkey_value_push (full_name, context_id, key_value, is_key_default);
        revealer.gkey_value_push     (full_name, context_id, key_value, is_key_default);
    }
    private void propagate_dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        browser_view.dkey_value_push (full_name, key_value_or_null);
        revealer.dkey_value_push     (full_name, key_value_or_null);
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

    /*\
    * * quitting
    \*/

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

    protected override void before_destroy ()
    {
        ((ConfigurationEditor) get_application ()).clean_copy_notification ();

        browser_view.disconnect (bookmarks_selection_changed_handler);
        modifications_handler.disconnect (delayed_changes_changed_handler);

        headerbar.disconnect (headerbar_update_bookmarks_icons_handler);
        browser_view.disconnect (browserview_update_bookmarks_icons_handler);

        settings.disconnect (settings_user_paths_changed_handler);
        settings.disconnect (settings_enabled_mappings_changed_handler);

        model.disconnect (paths_changed_handler);
        model.disconnect (gkey_value_push_handler);
        model.disconnect (dkey_value_push_handler);

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (use_shortpaths_changed_handler);

        settings.delay ();
        settings.set_string ("saved-view", saved_view);
        settings.set_string ("saved-pathbar-path", headerbar.get_complete_path ());
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
        { "reset-recursive", reset_recursively, "s" },
        { "reset-visible", reset_visible, "s" },

        { "enter-delay-mode", enter_delay_mode },
        { "apply-delayed-settings", apply_delayed_settings },
        { "dismiss-delayed-settings", dismiss_delayed_settings },

        { "dismiss-change", dismiss_change, "s" },  // here because needs to be accessed from DelayedSettingView rows
        { "erase", erase_dconf_key, "s" },          // here because needs a reload_view as we enter delay_mode

        { "show-in-window-bookmarks",       show_in_window_bookmarks },
        { "hide-in-window-bookmarks",       hide_in_window_bookmarks },

        { "show-in-window-modifications",   show_in_window_modifications },
        { "hide-in-window-modifications",   hide_in_window_modifications },

        { "update-bookmarks-icons", update_bookmarks_icons, "as" },

        { "notify-folder-emptied", notify_folder_emptied, "s" },
        { "notify-object-deleted", notify_object_deleted, "(sq)" }
    };

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
        if (browser_view.in_window_modifications)
            hide_in_window_modifications ();
        modifications_handler.apply_delayed_settings ();
        invalidate_popovers_with_ui_reload ();
    }

    private void dismiss_delayed_settings (/* SimpleAction action, Variant? path_variant */)
    {
        if (browser_view.in_window_modifications)
            hide_in_window_modifications ();
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

    private void invalidate_popovers_with_ui_reload ()
    {
        bool delay_mode = modifications_handler.get_current_delay_mode ();
        browser_view.hide_or_show_toggles (!delay_mode);
        browser_view.invalidate_popovers ();
        headerbar.delay_mode = delay_mode;
    }

    /*\
    * * showing or hiding panels
    \*/

    private void show_in_window_bookmarks (/* SimpleAction action, Variant? path_variant */)
    {
        if (browser_view.in_window_modifications == true)
            hide_in_window_modifications ();
        else if (in_window_about)
            hide_in_window_about ();

        headerbar.show_in_window_bookmarks ();
        string [] bookmarks = headerbar.get_bookmarks ();
        browser_view.show_in_window_bookmarks (bookmarks);
        update_bookmarks_icons_from_array (bookmarks);
    }

    private void hide_in_window_bookmarks (/* SimpleAction action, Variant? path_variant */)
        requires (browser_view.in_window_bookmarks == true)
    {
        if (browser_view.in_window_bookmarks_edit_mode)
            leave_edit_mode ();     // TODO place after
        headerbar.hide_in_window_bookmarks ();
        browser_view.hide_in_window_bookmarks ();
    }

    private void show_in_window_modifications (/* SimpleAction action, Variant? path_variant */)
    {
        if (browser_view.in_window_bookmarks == true)
            hide_in_window_bookmarks ();
        else if (in_window_about)
            hide_in_window_about ();

        headerbar.show_in_window_modifications ();
        browser_view.show_in_window_modifications ();
    }

    private void hide_in_window_modifications (/* SimpleAction action, Variant? path_variant */)
        requires (browser_view.in_window_modifications == true)
    {
        headerbar.hide_in_window_modifications ();
        browser_view.hide_in_window_modifications ();
    }

    /*\
    * * updating bookmarks icons
    \*/

    private void update_bookmarks_icons (SimpleAction action, Variant? bookmarks_variant)
        requires (bookmarks_variant != null)
    {
        update_bookmarks_icons_from_variant ((!) bookmarks_variant);
    }

    private void update_bookmarks_icons_from_variant (Variant variant)
    {
        update_bookmarks_icons_from_array (variant.get_strv ());
    }

    private void update_bookmarks_icons_from_array (string [] bookmarks)
    {
        if (bookmarks.length == 0)
            return;

        foreach (string bookmark in bookmarks)
        {
            if (bookmark.has_prefix ("?"))  // TODO broken search
            {
                update_bookmark_icon (bookmark, BookmarkIcon.SEARCH);
                continue;
            }
            if (is_path_invalid (bookmark)) // TODO broken folder and broken object
                continue;

            uint16 context_id;
            string name;
            bool bookmark_exists = model.get_object (bookmark, out context_id, out name, false);    // TODO get_folder

            if (context_id == ModelUtils.folder_context_id)
            {
                if (bookmark_exists)
                    update_bookmark_icon (bookmark, BookmarkIcon.VALID_FOLDER);
                else
                    update_bookmark_icon (bookmark, BookmarkIcon.EMPTY_FOLDER);
                continue;
            }

            if (!bookmark_exists)
                update_bookmark_icon (bookmark, BookmarkIcon.EMPTY_OBJECT);
            else if (context_id == ModelUtils.dconf_context_id)
                update_bookmark_icon (bookmark, BookmarkIcon.DCONF_OBJECT);
            else
            {
                RegistryVariantDict bookmark_properties = new RegistryVariantDict.from_aqv (model.get_key_properties (bookmark, context_id, (uint16) PropertyQuery.IS_DEFAULT));
                bool is_default;
                if (!bookmark_properties.lookup (PropertyQuery.IS_DEFAULT, "b", out is_default))
                    assert_not_reached ();
                if (is_default)
                    update_bookmark_icon (bookmark, BookmarkIcon.KEY_DEFAULTS);
                else
                    update_bookmark_icon (bookmark, BookmarkIcon.EDITED_VALUE);
            }
        }
    }

    private void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        if (AdaptativeWidget.WindowSize.is_extra_thin (window_size)
         || AdaptativeWidget.WindowSize.is_extra_flat (window_size))
            browser_view.update_bookmark_icon (bookmark, icon);
        else
            headerbar.update_bookmark_icon (bookmark, icon);
    }

    /*\
    * * adaptative stuff
    \*/

    private bool disable_popovers = false;
    private bool disable_action_bar = false;
    protected override void chain_set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (browser_view.in_window_bookmarks)
                hide_in_window_bookmarks ();
        }

        bool _disable_action_bar = _disable_popovers
                                || AdaptativeWidget.WindowSize.is_extra_flat (new_size);
        if (disable_action_bar != _disable_action_bar)
        {
            disable_action_bar = _disable_action_bar;
            if (browser_view.in_window_modifications)
                hide_in_window_modifications ();
        }
    }

    /*\
    * * bookmarks action entries
    \*/

    bool actions_init_done = false;
    private SimpleAction move_top_action;
    private SimpleAction move_up_action;
    private SimpleAction move_down_action;
    private SimpleAction move_bottom_action;
    private SimpleAction trash_bookmark_action;
    private SimpleAction edit_mode_state_action;

    private void update_actions ()
        requires (actions_init_done)
    {
        Bookmarks._update_actions (browser_view.get_bookmarks_selection_state (), ref move_top_action, ref move_up_action, ref move_down_action, ref move_bottom_action, ref trash_bookmark_action);
    }

    private void install_bmk_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (bmk_action_entries, this);
        insert_action_group ("bmk", action_group);

        move_top_action         = (SimpleAction) action_group.lookup_action ("move-top");
        move_up_action          = (SimpleAction) action_group.lookup_action ("move-up");
        move_down_action        = (SimpleAction) action_group.lookup_action ("move-down");
        move_bottom_action      = (SimpleAction) action_group.lookup_action ("move-bottom");
        trash_bookmark_action   = (SimpleAction) action_group.lookup_action ("trash-bookmark");
        edit_mode_state_action  = (SimpleAction) action_group.lookup_action ("set-edit-mode");
        actions_init_done = true;
    }

    private const GLib.ActionEntry [] bmk_action_entries =
    {
        { "set-edit-mode", set_edit_mode, "b", "false" },

        { "trash-bookmark", trash_bookmark },

        { "move-top",    move_top    },
        { "move-up",     move_up     },
        { "move-down",   move_down   },
        { "move-bottom", move_bottom }
    };

    private void set_edit_mode (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        bool new_state = ((!) variant).get_boolean ();
        action.set_state (new_state);

        if (new_state)
            enter_edit_mode ();
        else
            leave_edit_mode ();
    }

    private void enter_edit_mode ()
    {
        // edit_mode_state_action.change_state (true);

        update_actions ();

        headerbar.edit_in_window_bookmarks ();
        browser_view.enter_bookmarks_edit_mode ();
    }

    private void leave_edit_mode ()
    {
        edit_mode_state_action.set_state (false);

        bool give_focus_to_info_button = browser_view.leave_bookmarks_edit_mode ();
        headerbar.show_in_window_bookmarks ();

/*        if (give_focus_to_info_button)
            info_button.grab_focus (); */
    }

    private void trash_bookmark (/* SimpleAction action, Variant? variant */)
    {
        browser_view.trash_bookmark ();
//        update_bookmarks_icons_from_array (new_bookmarks);
    }

    private void move_top       (/* SimpleAction action, Variant? variant */)
    {
        browser_view.move_top ();
    }

    private void move_up        (/* SimpleAction action, Variant? variant */)
    {
        browser_view.move_up ();
    }

    private void move_down      (/* SimpleAction action, Variant? variant */)
    {
        browser_view.move_down ();
    }

    private void move_bottom    (/* SimpleAction action, Variant? variant */)
    {
        browser_view.move_bottom ();
    }

    private void on_bookmarks_selection_changed ()
    {
        update_actions ();
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
        { "toggle-bookmark",    toggle_bookmark     },  // <P>b & <P>B
        { "bookmark",           bookmark            },  // <P>d
        { "unbookmark",         unbookmark          },  // <P>D
        { "modifications",      modifications_list  },  // <A>i

        { "escape",             escape_pressed      },  // Escape

        { "toggle-boolean",     toggle_boolean      },  // <P>Return & <P>KP_Enter
        { "set-to-default",     set_to_default      }   // <P>Delete & <P>KP_Delete & decimalpoint & period & KP_Decimal
    };

    private void toggle_bookmark                        (/* SimpleAction action, Variant? variant */)
    {
        browser_view.discard_row_popover ();
        if (!AdaptativeWidget.WindowSize.is_phone_size (window_size)
         && !AdaptativeWidget.WindowSize.is_extra_thin (window_size))
        {
            if (browser_view.in_window_modifications)
                hide_in_window_modifications ();
            headerbar.click_bookmarks_button ();
        }
        else if (browser_view.in_window_bookmarks)
            hide_in_window_bookmarks ();
        else
            show_in_window_bookmarks ();
    }

    private void bookmark                               (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        browser_view.discard_row_popover ();
        headerbar.bookmark_current_path ();
    }

    private void unbookmark                             (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        browser_view.discard_row_popover ();
        headerbar.unbookmark_current_path ();
    }

    private void modifications_list                     (/* SimpleAction action, Variant? variant */)
    {
        if (!modifications_handler.get_current_delay_mode ())
            return;

        if (!AdaptativeWidget.WindowSize.is_extra_thin (window_size)
         && !AdaptativeWidget.WindowSize.is_extra_flat (window_size))
            revealer.toggle_modifications_list ();
        else if (browser_view.in_window_modifications)
            hide_in_window_modifications ();
        else
            show_in_window_modifications ();
    }

    private void escape_pressed                         (/* SimpleAction action, Variant? variant */)
    {
        if (browser_view.in_window_bookmarks)
        {
            if (browser_view.in_window_bookmarks_edit_mode)
                leave_edit_mode ();
            else
                hide_in_window_bookmarks ();
        }
        else if (browser_view.in_window_modifications)
            hide_in_window_modifications ();
        else if (in_window_about)
            hide_in_window_about ();
        else if (headerbar.search_mode_enabled)
            stop_search ();
        else if (current_type == ViewType.CONFIG)
            request_folder (current_path);
    }

    private void toggle_boolean                         (/* SimpleAction action, Variant? variant */)
    {
        if (row_action_blocked ())
            return;

        browser_view.discard_row_popover ();
        browser_view.toggle_boolean_key ();
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
        browser_view.discard_row_popover ();
        string selected_row = browser_view.get_selected_row_name ();
        if (selected_row.has_suffix ("/"))
            reset_path ((!) selected_row, true);
        else
            browser_view.set_selected_to_default ();
    }

    /*\
    * * keyboard calls helpers
    \*/

    protected override bool intercept_next_match (out bool interception_result)
    {
        if (headerbar.has_popover ())                   // for bookmarks popover
        {
            interception_result = headerbar.next_match ();
            return true;
        }
        if (revealer.get_modifications_list_state ())   // for modifications popover
        {
            interception_result = revealer.next_match ();
            return true;
        }
        interception_result = false; // garbage
        return false;
    }

    protected override bool intercept_previous_match (out bool interception_result)
    {
        if (headerbar.has_popover ())                   // for bookmarks popover
        {
            interception_result = headerbar.previous_match ();
            return true;
        }
        if (revealer.get_modifications_list_state ())   // for modifications popover
        {
            interception_result = revealer.previous_match ();
            return true;
        }
        interception_result = false; // garbage
        return false;
    }

    /*\
    * * Path requests
    \*/

    protected override void close_in_window_panels ()
    {
        hide_notification ();
        headerbar.close_popovers ();
        revealer.hide_modifications_list ();
        if (browser_view.in_window_bookmarks)
            hide_in_window_bookmarks ();
        else if (browser_view.in_window_modifications)
            hide_in_window_modifications ();
        else if (in_window_about)
            hide_in_window_about ();
    }

    public static bool is_path_invalid (string path)
    {
        return path.has_prefix ("/") && (path.contains ("//") || path.contains (" "));
    }

    protected override void request_config (string full_name)
    {
        browser_view.prepare_object_view (full_name, ModelUtils.folder_context_id,
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

        browser_view.prepare_folder_view (create_key_model (fallback_path, model.get_children (fallback_path, true, true)), current_path.has_prefix (fallback_path));
        update_current_path (ViewType.FOLDER, fallback_path);

        if (selected_or_empty == "")
            browser_view.select_row (headerbar.get_selected_child (fallback_path));
        else
            browser_view.select_row (selected_or_empty);

        stop_search ();
        // headerbar.search_mode_enabled = false; // do last to avoid flickering RegistryView before PropertiesView when selecting a search result
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
            headerbar.update_ghosts (model.get_fallback_path (headerbar.get_complete_path ()));
        }
        else
        {
            browser_view.prepare_object_view (full_name, context_id,
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

    protected override string get_copy_text ()
    {
        model.copy_action_called ();

        string? selected_row_text = browser_view.get_copy_text ();
        if (selected_row_text == null && current_type == ViewType.OBJECT)
            selected_row_text = model.get_suggested_key_copy_text (current_path, browser_view.last_context_id);
        return selected_row_text == null ? current_path : (!) selected_row_text;
    }

    protected override string get_copy_path_text ()
    {
        if (headerbar.search_mode_enabled)
        {
            model.copy_action_called ();
            return browser_view.get_copy_path_text () ?? saved_view;
        }

        if (browser_view.current_view == ViewType.OBJECT)
            model.copy_action_called ();

        return current_path;
    }

    /*\
    * * Non-existant path notifications // TODO unduplicate
    \*/

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

    private void cannot_find_key (string full_name)
    {
        show_notification (_("Cannot find key “%s”.").printf (full_name));
    }

    private void cannot_find_folder (string full_name)
    {
        show_notification (_("There’s nothing in requested folder “%s”.").printf (full_name));
    }
}

namespace AboutDialogInfos
{
    // strings
    internal const string program_name = _("dconf Editor");
    internal const string version = Config.VERSION;
    internal const string comments = _("A graphical viewer and editor of applications’ internal settings.");
    internal const string copyright = _("Copyright \xc2\xa9 2010-2014 – Canonical Ltd\nCopyright \xc2\xa9 2015-2018 – Arnaud Bonatti\nCopyright \xc2\xa9 2017-2018 – Davi da Silva Böger");
    /* Translators: This string should be replaced by a text crediting yourselves and your translation team, or should be left empty. Do not translate literally! */
    internal const string translator_credits = _("translator-credits");

    // various
    internal const string logo_icon_name = "ca.desrt.dconf-editor";
    internal const string website = "https://wiki.gnome.org/Apps/DconfEditor";
    internal const string website_label = _("Page on GNOME wiki");
    internal const string [] authors = { "Robert Ancell", "Arnaud Bonatti" };
    internal const License license_type = License.GPL_3_0; /* means "version 3.0 or later" */
}
