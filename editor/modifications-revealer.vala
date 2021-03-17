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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/modifications-revealer.ui")]
private class ModificationsRevealer : Revealer, AdaptativeWidget
{
    private ModificationsHandler _modifications_handler;
    [CCode (notify = false)] internal ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set
        {
            _modifications_handler = value;
            _modifications_handler.delayed_changes_changed.connect (update);
        }
    }

    StyleContext apply_button_context;
    private bool disable_action_bar = false;
    private bool short_size_button = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_action_bar = AdaptativeWidget.WindowSize.is_extra_thin (new_size)
                                || AdaptativeWidget.WindowSize.is_extra_flat (new_size);
        if (disable_action_bar != _disable_action_bar)
        {
            disable_action_bar = _disable_action_bar;
            update ();
        }

        bool _short_size_button = AdaptativeWidget.WindowSize.is_quite_thin (new_size);
        if (short_size_button != _short_size_button)
        {
            short_size_button = _short_size_button;
            if (_short_size_button)
            {
                apply_button_context.remove_class ("text-button");
                apply_button.icon = apply_button_icon;
                apply_button_context.add_class ("image-button");
            }
            else
            {
                apply_button_context.remove_class ("image-button");
                apply_button.icon = null;
                apply_button_context.add_class ("text-button");
            }
        }
    }

    [GtkChild] private unowned Label label;
    [GtkChild] private unowned ModelButton apply_button;
    [GtkChild] private unowned MenuButton delayed_list_button;
    [GtkChild] private unowned Popover delayed_settings_list_popover;
    [GtkChild] private unowned ModificationsList modifications_list;

    private ThemedIcon apply_button_icon = new ThemedIcon.from_names ({"object-select-symbolic"});

    construct
    {
        apply_button_context = apply_button.get_style_context ();
        apply_button.icon = null;
        apply_button.get_style_context ().add_class ("text-button");
    }

    /*\
    * * Resetting objects
    \*/

    internal void reset_objects (string base_path, Variant? objects, bool recursively)
    {
        _reset_objects (base_path, objects, recursively);
        warn_if_no_planned_changes ();
    }

    private void _reset_objects (string base_path, Variant? objects, bool recursively)
    {
        if (objects == null)
            return;
        SettingsModel model = modifications_handler.model;

        VariantIter iter = new VariantIter ((!) objects);
        uint16 context_id;
        string name;
        while (iter.next ("(qs)", out context_id, out name))
        {
            // directory
            if (ModelUtils.is_folder_context_id (context_id))
            {
                string full_name = ModelUtils.recreate_full_name (base_path, name, true);
                if (recursively)
                    _reset_objects (full_name, model.get_children (full_name), true);
            }
            // dconf key
            else if (ModelUtils.is_dconf_context_id (context_id))
            {
                string full_name = ModelUtils.recreate_full_name (base_path, name, false);
                if (!model.is_key_ghost (full_name))
                    modifications_handler.add_delayed_setting (full_name, null, ModelUtils.dconf_context_id);
            }
            // gsettings
            else
            {
                string full_name = ModelUtils.recreate_full_name (base_path, name, false);
                RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.IS_DEFAULT)));
                bool is_key_default;
                if (!properties.lookup (PropertyQuery.IS_DEFAULT,       "b",    out is_key_default))
                    assert_not_reached ();
                properties.clear ();

                if (!is_key_default)
                    modifications_handler.add_delayed_setting (full_name, null, context_id);
            }
        }
    }

    private void warn_if_no_planned_changes ()
    {
        if (modifications_handler.dconf_changes_count == 0 && modifications_handler.gsettings_changes_count == 0)
            /* Translators: displayed in the bottom bar in normal sized windows, when the user tries to reset keys from/for a folder that has nothing to reset */
            label.set_text (_("Nothing to reset."));
            // FIXME appears twice
    }

    /*\
    * * keyboard calls
    \*/

    internal bool next_match ()
    {
        return modifications_list.next_match ();
    }

    internal bool previous_match ()
    {
        return modifications_list.previous_match ();
    }

    internal bool handle_copy_text (out string copy_text)
    {
        if (delayed_list_button.active)
            return modifications_list.handle_copy_text (out copy_text);
        return BaseWindow.no_copy_text (out copy_text);
    }

    /*\
    * * Modifications list public functions
    \*/

    internal bool dismiss_selected_modification ()
    {
        if (!delayed_list_button.active)
            return false;

        string? selected_row_name = modifications_list.get_selected_row_name ();
        if (selected_row_name == null)
            return false;

        modifications_handler.dismiss_change ((!) selected_row_name);
        update ();
        return true;
    }

    internal void hide_modifications_list ()
    {
        delayed_settings_list_popover.popdown ();
    }

    internal void toggle_modifications_list ()
    {
        delayed_list_button.active = !delayed_settings_list_popover.visible;
    }

    internal bool get_modifications_list_state ()
    {
        return delayed_list_button.active;
    }

    /*\
    * * Modifications list population
    \*/

    private Widget delayed_setting_row_create (Object object)
    {
        SimpleSettingObject sso = (SimpleSettingObject) object;
        return create_delayed_setting_row (modifications_handler, sso.name, sso.full_name, sso.context_id);
    }

    internal static Widget create_delayed_setting_row (ModificationsHandler modifications_handler, string name, string full_name, uint16 context_id)
    {
        SettingsModel model = modifications_handler.model;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.HAS_SCHEMA & PropertyQuery.IS_DEFAULT & PropertyQuery.DEFAULT_VALUE & PropertyQuery.KEY_VALUE)));

        bool has_schema;
        if (!properties.lookup (PropertyQuery.HAS_SCHEMA,               "b",    out has_schema))
            assert_not_reached ();

        bool has_schema_and_is_default;
        if (!has_schema)
            has_schema_and_is_default = false;
        else if (!properties.lookup (PropertyQuery.IS_DEFAULT,          "b",    out has_schema_and_is_default))
            assert_not_reached ();

        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);
        string? cool_planned_value = null;
        if (planned_value != null)
            cool_planned_value = Key.cool_text_value_from_variant ((!) planned_value);

        string? cool_default_value = null;
        if (has_schema
         && !properties.lookup (PropertyQuery.DEFAULT_VALUE,            "s",    out cool_default_value))
            assert_not_reached ();

        Variant key_value;
        if (!properties.lookup (PropertyQuery.KEY_VALUE,                "v",    out key_value))
            assert_not_reached ();

        properties.clear ();

        DelayedSettingView view = new DelayedSettingView (name,
                                                          full_name,
                                                          context_id,
                                                          has_schema_and_is_default,    // at row creation, key is never ghost
                                                          key_value,
                                                          cool_planned_value,
                                                          cool_default_value);

        if (modifications_handler.get_current_delay_mode ())
        {
            Variant variant = new Variant ("(sq)", full_name, context_id);
            view.set_detailed_action_name ("browser.open-object(" + variant.print (true) + ")");
        }
        view.show ();
        return view;
    }

    /*\
    * * Updating values; TODO only works for watched keys...
    \*/

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        modifications_list.gkey_value_push (full_name, context_id, key_value, is_key_default);
    }

    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        modifications_list.dkey_value_push (full_name, key_value_or_null);
    }

    /*\
    * * Updating text
    \*/

    private void update ()
    {
        if (disable_action_bar)
        {
            set_reveal_child (false);
            return;
        }

        GLib.ListStore modifications_liststore = modifications_handler.get_delayed_settings ();
        modifications_list.bind_model (modifications_liststore, delayed_setting_row_create);

        if (modifications_liststore.get_n_items () == 0)
            delayed_settings_list_popover.popdown ();

        if (modifications_handler.mode == ModificationsMode.NONE)
        {
            set_reveal_child (false);
            apply_button.sensitive = false;
            label.set_text ("");
            return;
        }
        uint total_changes_count = modifications_handler.dconf_changes_count + modifications_handler.gsettings_changes_count;
        if (modifications_handler.mode == ModificationsMode.TEMPORARY)
        {
            if (total_changes_count == 0)
            {
                apply_button.sensitive = false;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key and enters in the entry or text view a value that cannot be parsed to the correct data type */
                label.set_text (_("The value is invalid."));
            }
            else if (total_changes_count != 1)
                assert_not_reached ();
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            {
                apply_button.sensitive = true;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key (with the "always confirm explicit" behaviour) */
                label.set_text (_("The change will be dismissed if you quit this view without applying."));
            }
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || modifications_handler.behaviour == Behaviour.SAFE)
            {
                apply_button.sensitive = true;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key (with default "always confirm implicit" behaviour notably) */
                label.set_text (_("The change will be applied on such request or if you quit this view."));
            }
            else
                assert_not_reached ();
            set_reveal_child (true);
        }
        else // if (mode == Mode.DELAYED)
        {
            if (total_changes_count == 0)
                /* Translators: displayed in the bottom bar in normal sized windows, when the user tries to reset keys from/for a folder that has nothing to reset */
                label.set_text (_("Nothing to reset."));
                // FIXME appears twice
            apply_button.sensitive = total_changes_count > 0;
            label.set_text (get_text (modifications_handler.dconf_changes_count, modifications_handler.gsettings_changes_count));
            set_reveal_child (true);
        }
    }

    private static string get_text (uint dconf, uint gsettings)     // TODO change text if current path is a key?
    {
        if (dconf == 0)
        {
            if (gsettings == 0)
            /* Translators: Text displayed in the bottom bar; displayed if there are no pending changes, to document what is the "delay mode". */
                return _("Changes will be delayed until you request it.");

            /* Translators: Text displayed in the bottom bar; "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One gsettings operation delayed.", "%u gsettings operations delayed.", gsettings).printf (gsettings);
        }
        if (gsettings == 0)
            /* Translators: Text displayed in the bottom bar; "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One dconf operation delayed.", "%u dconf operations delayed.", dconf).printf (dconf);

         /* Translators: Text displayed in the bottom bar. Hacky: I split a sentence like "One gsettings operation and 2 dconf operations delayed." in two parts, before the "and"; there is at least one gsettings operation and one dconf operation. So, you can either keep "%s%s" like that, and have the second part of the translation starting with a space (if that makes sense in your language), or you might use "%s %s" here. */
        return _("%s%s").printf (

         /* Translators: Text displayed in the bottom bar; beginning of a sentence like "One gsettings operation and 2 dconf operations delayed.", you could duplicate "delayed" if needed, as it refers to both the gsettings and dconf operations (at least one of each).
            Also, "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            ngettext ("One gsettings operation", "%u gsettings operations", gsettings).printf (gsettings),

         /* Translators: Text displayed in the bottom bar; second part (and end) of a sentence like "One gsettings operation and 2 dconf operations delayed.", so:
             * the space before the "and" is probably wanted, if you keeped the "%s%s" translation as-is, and
             * the "delayed" refers to both the gsettings and dconf operations (at least one of each).
            Also, "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            ngettext (" and one dconf operation delayed.", " and %u dconf operations delayed.", dconf).printf (dconf)
        );
    }
}
