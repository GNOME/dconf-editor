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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/modifications-view.ui")]
private class ModificationsView : Box
{
    [GtkChild] private unowned ModificationsList modifications_list;

    internal ModificationsHandler modifications_handler { get; set; }

    construct
    {
        notify["modifications-handler"].connect (() => {
            modifications_handler.delayed_changes_changed.connect (update);
        });
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
        // if (modifications_handler.dconf_changes_count == 0 && modifications_handler.gsettings_changes_count == 0)
            /* Translators: displayed in the bottom bar in normal sized windows, when the user tries to reset keys from/for a folder that has nothing to reset */
            // FIXME: USE A TOAST FOR THIS
            // label = _("Nothing to reset.");
            // FIXME appears twice
    }

    /*\
    * * keyboard calls
    \*/

    internal bool handle_copy_text (out string copy_text)
    {
        // if (delayed_list_button.active)
        //     return modifications_list.handle_copy_text (out copy_text);
        return BaseWindow.no_copy_text (out copy_text);
    }

    /*\
    * * Modifications list public functions
    \*/

    internal bool dismiss_selected_modification ()
    {
        // if (!delayed_list_button.active)
        //     return false;

        string? selected_row_name = modifications_list.get_selected_row_name ();
        if (selected_row_name == null)
            return false;

        modifications_handler.dismiss_change ((!) selected_row_name);
        update ();
        return true;
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
        GLib.ListStore modifications_liststore = modifications_handler.get_delayed_settings ();
        modifications_list.bind_model (modifications_liststore, delayed_setting_row_create);
    }
}
