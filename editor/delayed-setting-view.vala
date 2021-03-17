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
private class DelayedSettingView : OverlayedListRow
{
    [GtkChild] private unowned Label key_name_label;
    [GtkChild] private unowned Label key_value_label;
    [GtkChild] private unowned Label key_value_default;
    [GtkChild] private unowned Label planned_value_label;
    [GtkChild] private unowned Label planned_value_default;
    [GtkChild] private unowned Button cancel_change_button;

    [CCode (notify = false)] public string full_name     { internal get; internal construct; }
    [CCode (notify = false)] public uint16 context_id    { internal get; internal construct; }

    internal DelayedSettingView (string name, string _full_name, uint16 _context_id, bool has_schema_and_is_default, Variant key_value, string? cool_planned_value, string? cool_default_value)
    {
        Object (full_name: _full_name, context_id: _context_id);
        Variant variant = new Variant.string (full_name);
        key_name_label.label = name;
        cancel_change_button.set_detailed_action_name ("ui.dismiss-change(" + variant.print (false) + ")");

        if (cool_default_value == null)
        {
            // at row creation, key is never ghost
            _update_dconf_key_current_value (key_value,
                                             key_value_label,
                                             key_value_default);

            _update_dconf_key_planned_value (cool_planned_value,
                                             planned_value_label,
                                             planned_value_default);
        }
        else
        {
            _update_gsettings_key_current_value (key_value,
                                                 has_schema_and_is_default,
                                                 key_value_label,
                                                 key_value_default);

            _update_gsettings_key_planned_value (cool_planned_value,
                                                 (!) cool_default_value,
                                                 planned_value_label,
                                                 planned_value_default);
        }
    }

    internal override bool handle_copy_text (out string copy_text)
    {
        copy_text = full_name;
        return true;
    }

    /*\
    * * "updating" planned value
    \*/

    private static inline void _update_gsettings_key_planned_value (string? cool_planned_value,
                                                                    string  cool_default_value,
                                                                    Label   planned_value_label,
                                                                    Label   planned_value_default)
    {
        bool is_default = cool_planned_value == null;
        planned_value_label.label = is_default ? cool_default_value : (!) cool_planned_value;
        update_value_default_label (is_default, planned_value_default);
    }

    private static inline void _update_dconf_key_planned_value (string? cool_planned_value,
                                                                Label   planned_value_label,
                                                                Label   planned_value_default)
    {
        if (cool_planned_value == null)
            update_labels_dconf_key_erased (planned_value_label, planned_value_default);
        else
            update_labels_dconf_key_values ((!) cool_planned_value,
                                            planned_value_label, planned_value_default);
    }

    /*\
    * * updating current value
    \*/

    internal void update_gsettings_key_current_value (Variant key_value, bool is_default)
    {
        _update_gsettings_key_current_value (key_value, is_default, key_value_label, key_value_default);
    }
    private static void _update_gsettings_key_current_value (Variant key_value,
                                                             bool    is_default,
                                                             Label   key_value_label,
                                                             Label   key_value_default)
    {
        key_value_label.label = Key.cool_text_value_from_variant (key_value);
        update_value_default_label (is_default, key_value_default);
    }

    internal void update_dconf_key_current_value (Variant? key_value_or_null)
    {
        _update_dconf_key_current_value (key_value_or_null, key_value_label, key_value_default);
    }
    private static void _update_dconf_key_current_value (Variant? key_value_or_null,
                                                         Label    key_value_label,
                                                         Label    key_value_default)
    {
        if (key_value_or_null == null)
            update_labels_dconf_key_erased (key_value_label, key_value_default);
        else
            update_labels_dconf_key_values (Key.cool_text_value_from_variant ((!) key_value_or_null),
                                            key_value_label, key_value_default);
    }

    /*\
    * * common utilities
    \*/

    private static void update_labels_dconf_key_erased (Label value_label, Label value_default)
    {
        value_label.visible = false;
        /* Translators: displayed in the list of pending changes (could be an in-window panel, or in the popover of the bottom bar); for dconf keys */
        value_default.label = _("Key erased");
        value_default.visible = true;
    }

    private static void update_labels_dconf_key_values (string key_value, Label value_label, Label value_default)
    {
        value_default.visible = false;
        value_label.label = key_value;  // TODO move Key.cool_text_value_from_variant here?
        value_label.visible = true;
    }

    private static void update_value_default_label (bool is_default, Label value_default)
    {
        if (is_default)
            /* Translators: displayed in the list of pending changes (could be an in-window panel, or in the popover of the bottom bar); for gsettings keys */
            value_default.label = _("Default value");
        value_default.visible = is_default;
    }
}
