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
class ModificationsRevealer : Revealer
{
    private ModificationsHandler _modifications_handler;
    public ModificationsHandler modifications_handler
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
    }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        StyleContext context = apply_button.get_style_context ();
        if (allocation.width < 900)
        {
            context.remove_class ("text-button");
            apply_button.icon = apply_button_icon;
            context.add_class ("image-button");
        }
        else
        {
            context.remove_class ("image-button");
            apply_button.icon = null;
            context.add_class ("text-button");
        }
    }

    /*\
    * * Reseting objects
    \*/

    public void reset_objects (GLib.ListStore? objects, bool recursively)
    {
        _reset_objects (objects, recursively);
        warn_if_no_planned_changes ();
    }

    private void _reset_objects (GLib.ListStore? objects, bool recursively)
    {
        SettingsModel model = modifications_handler.model;
        if (objects == null)
            return;

        for (uint position = 0;; position++)
        {
            Object? object = ((!) objects).get_object (position);
            if (object == null)
                return;

            SettingObject setting_object = (SettingObject) ((!) object);
            if (setting_object is Directory)
            {
                if (recursively)
                {
                    GLib.ListStore? children = model.get_children (setting_object.full_name);
                    if (children != null)
                        _reset_objects ((!) children, true);
                }
                continue;
            }
            if (setting_object is DConfKey)
            {
                if (!model.is_key_ghost ((DConfKey) setting_object))
                    modifications_handler.add_delayed_setting (setting_object.full_name, null);
            }
            else if (!model.is_key_default ((GSettingsKey) setting_object))
                modifications_handler.add_delayed_setting (setting_object.full_name, null);
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

    public bool dismiss_selected_modification ()
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

    public void hide_modifications_list ()
    {
        delayed_settings_list_popover.popdown ();
    }

    public void toggle_modifications_list ()
    {
        delayed_list_button.active = !delayed_settings_list_popover.visible;
    }

    public bool get_modifications_list_state ()
    {
        return delayed_list_button.active;
    }

    /*\
    * * Modifications list population
    \*/

    private Widget delayed_setting_row_create (Object key)
    {
        string full_name = ((Key) key).full_name;
        bool has_schema = key is GSettingsKey;
        bool is_default_or_ghost = has_schema ? modifications_handler.model.is_key_default ((GSettingsKey) key)
                                              : modifications_handler.model.is_key_ghost ((DConfKey) key);
        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);
        string? cool_planned_value = null;
        if (planned_value != null)
            cool_planned_value = Key.cool_text_value_from_variant ((!) planned_value, ((Key) key).type_string);
        string? cool_default_value = null;
        if (has_schema)
            cool_default_value = Key.cool_text_value_from_variant (((GSettingsKey) key).default_value, ((Key) key).type_string);
        string cool_key_value = Key.cool_text_value_from_variant (modifications_handler.model.get_key_value ((Key) key),
                                                                                                             ((Key) key).type_string);
        DelayedSettingView view = new DelayedSettingView (full_name,
                                                          is_default_or_ghost,
                                                          cool_key_value,
                                                          cool_planned_value,
                                                          cool_default_value);

        ListBoxRow wrapper = new ListBoxRow ();
        wrapper.add (view);
        if (modifications_handler.get_current_delay_mode ())
        {
            Variant variant = new Variant ("(ss)", full_name, has_schema ? ((GSettingsKey) key).schema_id : ".dconf");
            wrapper.set_detailed_action_name ("ui.open-object(" + variant.print (false) + ")");
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

            if (SettingsModel.get_parent_path (row_key_name) != SettingsModel.get_parent_path (before_key_name))
                add_location_header = true;
        }

        if (add_location_header)
        {
            Grid location_header = new Grid ();
            location_header.show ();
            location_header.orientation = Orientation.VERTICAL;

            Label location_header_label = new Label (SettingsModel.get_parent_path (row_key_name));
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
    * * Update
    \*/

    private void update ()
    {
        GLib.ListStore modifications_list = modifications_handler.get_delayed_settings ();
        delayed_settings_listbox.bind_model (modifications_handler.get_delayed_settings (), delayed_setting_row_create);
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
