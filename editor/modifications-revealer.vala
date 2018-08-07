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
private class ModificationsRevealer : Revealer
{
    private ModificationsHandler _modifications_handler;
    internal ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set
        {
            _modifications_handler = value;
            _modifications_handler.delayed_changes_changed.connect (update);
        }
    }

    [GtkChild] private Label label;
    [GtkChild] private ModelButton apply_button;
    [GtkChild] private MenuButton delayed_list_button;
    [GtkChild] private Popover delayed_settings_list_popover;
    [GtkChild] private ListBox delayed_settings_listbox;

    private ThemedIcon apply_button_icon = new ThemedIcon.from_names ({"object-select-symbolic"});

    construct
    {
        delayed_settings_listbox.set_header_func (delayed_setting_row_update_header);

        apply_button.icon = null;
        apply_button.get_style_context ().add_class ("text-button");
    }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)   // TODO remaining warnings printed on redim when allocation width passes 900
    {
        StyleContext context = apply_button.get_style_context ();
        if (allocation.width < 900)
        {
            if (apply_button.icon == null)
            {
                context.remove_class ("text-button");
                apply_button.icon = apply_button_icon;
                context.add_class ("image-button");
            }
        }
        else
        {
            if (apply_button.icon != null)
            {
                context.remove_class ("image-button");
                apply_button.icon = null;
                context.add_class ("text-button");
            }
        }
    }

    /*\
    * * Reseting objects
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
            label.set_text (_("Nothing to reset."));
    }

    /*\
    * * Modifications list public functions
    \*/

    internal bool dismiss_selected_modification ()
    {
        if (!delayed_list_button.active)
            return false;

        ListBoxRow? selected_row = delayed_settings_listbox.get_selected_row ();
        if (selected_row == null)
            return false;

        modifications_handler.dismiss_change (((DelayedSettingView) (!) ((!) selected_row).get_child ()).full_name);
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
        string full_name = ((SimpleSettingObject) object).full_name;
        uint16 context_id = ((SimpleSettingObject) object).context_id;

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

        DelayedSettingView view = new DelayedSettingView (((SimpleSettingObject) object).name,
                                                          full_name,
                                                          context_id,
                                                          has_schema_and_is_default,    // at row creation, key is never ghost
                                                          key_value,
                                                          cool_planned_value,
                                                          cool_default_value);

        ListBoxRow wrapper = new ListBoxRow ();
        wrapper.add (view);
        if (modifications_handler.get_current_delay_mode ())
        {
            Variant variant = new Variant ("(sq)", full_name, context_id);
            wrapper.set_detailed_action_name ("ui.open-object(" + variant.print (true) + ")");
        }
        return wrapper;
    }

    private void delayed_setting_row_update_header (ListBoxRow row, ListBoxRow? before)
    {
        string row_key_name = ((DelayedSettingView) row.get_child ()).full_name;
        bool add_location_header = false;
        if (before == null)
            add_location_header = true;
        else
        {
            string before_key_name = ((DelayedSettingView) ((!) before).get_child ()).full_name;

            if (ModelUtils.get_parent_path (row_key_name) != ModelUtils.get_parent_path (before_key_name))
                add_location_header = true;
        }

        if (add_location_header)
        {
            Grid location_header = new Grid ();
            location_header.show ();
            location_header.orientation = Orientation.VERTICAL;

            Label location_header_label = new Label (ModelUtils.get_parent_path (row_key_name));
            location_header_label.show ();
            location_header_label.hexpand = true;
            location_header_label.halign = Align.START;

            StyleContext context = location_header_label.get_style_context ();
            context.add_class ("dim-label");
            context.add_class ("bold-label");
            context.add_class ("list-row-header");

            location_header.add (location_header_label);

            Separator separator_header = new Separator (Orientation.HORIZONTAL);
            separator_header.show ();
            location_header.add (separator_header);

            row.set_header (location_header);
        }
        else
        {
            Separator separator_header = new Separator (Orientation.HORIZONTAL);
            separator_header.show ();
            row.set_header (separator_header);
        }
    }

    /*\
    * * Updating values; TODO only works for watched keys...
    \*/

    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        delayed_settings_listbox.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name && row.context_id == context_id)
                    row.update_gsettings_key_current_value (key_value, is_key_default);
            });
    }

    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        delayed_settings_listbox.foreach ((widget) => {
                DelayedSettingView row = (DelayedSettingView) ((Bin) widget).get_child ();
                if (row.full_name == full_name)
                    row.update_dconf_key_current_value (key_value_or_null);
            });
    }

    /*\
    * * Updating text
    \*/

    private void update ()
    {
        GLib.ListStore modifications_list = modifications_handler.get_delayed_settings ();
        delayed_settings_listbox.bind_model (modifications_list, delayed_setting_row_create);
        if (modifications_list.get_n_items () == 0)
            delayed_settings_list_popover.popdown ();
        else
            delayed_settings_listbox.select_row ((!) delayed_settings_listbox.get_row_at_index (0));

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
                label.set_text (_("The value is invalid."));
            }
            else if (total_changes_count != 1)
                assert_not_reached ();
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            {
                apply_button.sensitive = true;
                label.set_text (_("The change will be dismissed if you quit this view without applying."));
            }
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || modifications_handler.behaviour == Behaviour.SAFE)
            {
                apply_button.sensitive = true;
                label.set_text (_("The change will be applied on such request or if you quit this view."));
            }
            else
                assert_not_reached ();
            set_reveal_child (true);
        }
        else // if (mode == Mode.DELAYED)
        {
            if (total_changes_count == 0)
                label.set_text (_("Nothing to reset."));
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
                return _("Changes will be delayed until you request it.");
            /* Translators: "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One gsettings operation delayed.", "%u gsettings operations delayed.", gsettings).printf (gsettings);
        }
        if (gsettings == 0)
            /* Translators: "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One dconf operation delayed.", "%u dconf operations delayed.", dconf).printf (dconf);
            /* Translators: Beginning of a sentence like "One gsettings operation and 2 dconf operations delayed.", you could duplicate "delayed" if needed, as it refers to both the gsettings and dconf operations (at least one of each).
                            Also, "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
        return _("%s%s").printf (ngettext ("One gsettings operation", "%u gsettings operations", gsettings).printf (gsettings),
            /* Translators: Second part (and end) of a sentence like "One gsettings operation and 2 dconf operations delayed.", so:
                             * the space before the "and" is probably wanted, and
                             * the "delayed" refers to both the gsettings and dconf operations (at least one of each).
                            Also, "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
                                 ngettext (" and one dconf operation delayed.", " and %u dconf operations delayed.", dconf).printf (dconf));
    }
}
