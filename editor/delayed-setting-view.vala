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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/delayed-setting-view.ui")]
private class DelayedSettingView : Grid
{
    [GtkChild] private Label key_name_label;
    [GtkChild] private Label key_value_label;
    [GtkChild] private Label key_value_default;
    [GtkChild] private Label planned_value_label;
    [GtkChild] private Label planned_value_default;
    [GtkChild] private Button cancel_change_button;

    public string full_name     { internal get; internal construct; }
    public uint16 context_id    { internal get; internal construct; }

    internal DelayedSettingView (string name, string _full_name, uint16 _context_id, bool has_schema_and_is_default, Variant key_value, string? cool_planned_value, string? cool_default_value)
    {
        Object (full_name: _full_name, context_id: _context_id);
        Variant variant = new Variant.string (full_name);
        key_name_label.label = name;
        cancel_change_button.set_detailed_action_name ("ui.dismiss-change(" + variant.print (false) + ")");

        if (cool_default_value == null)
        {
            // at row creation, key is never ghost
            update_dconf_key_current_value (key_value);
            update_dconf_key_planned_value (cool_planned_value);
        }
        else
        {
            update_gsettings_key_current_value (key_value, has_schema_and_is_default);
            update_gsettings_key_planned_value (cool_planned_value, (!) cool_default_value);
        }
    }

    /*\
    * * "Updating" planned value
    \*/

    private void update_gsettings_key_planned_value (string? cool_planned_value, string cool_default_value)
    {
        if (cool_planned_value == null)
        {
            planned_value_label.label = cool_default_value;
            planned_value_default.label = _("Default value");
            planned_value_default.visible = true;
        }
        else
        {
            planned_value_label.label = (!) cool_planned_value;
            planned_value_default.visible = false;
        }
    }

    private void update_dconf_key_planned_value (string? cool_planned_value)
    {
        if (cool_planned_value == null)
        {
            planned_value_label.visible = false;
            planned_value_default.label = _("Key erased.");
            planned_value_default.visible = true;
        }
        else
        {
            planned_value_label.label = (!) cool_planned_value;
            planned_value_label.visible = true;
            planned_value_default.visible = false;
        }
    }

    /*\
    * * Updating current value
    \*/

    internal void update_gsettings_key_current_value (Variant key_value, bool is_default)
    {
        key_value_label.label = Key.cool_text_value_from_variant (key_value);
        if (is_default)
        {
            key_value_default.label = _("Default value");
            key_value_default.visible = true;
        }
        else
            key_value_default.visible = false;
    }

    internal void update_dconf_key_current_value (Variant? key_value_or_null)
    {
        if (key_value_or_null == null)
        {
            key_value_label.visible = false;
            key_value_default.label = _("Key erased");
            key_value_default.visible = true;
        }
        else
        {
            key_value_default.visible = false;
            key_value_label.label = Key.cool_text_value_from_variant ((!) key_value_or_null);
            key_value_label.visible = true;
        }
    }
}
