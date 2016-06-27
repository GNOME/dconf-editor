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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-info.ui")]
class RegistryInfo : Grid
{
    [GtkChild] private Revealer no_schema_warning;
    [GtkChild] private ListBox properties_list_box;

    public bool populate_properties_list_box (ModificationsRevealer revealer, Key key)
    {
        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);
        
        if (!has_schema)
        {
            if (((DConfKey) key).is_ghost)
                return false;
            no_schema_warning.set_reveal_child (true);
        }
        else
            no_schema_warning.set_reveal_child (false);

        properties_list_box.@foreach ((widget) => { widget.destroy (); });

        Variant dict = dict_container [0];

        // TODO use VariantDict
        string key_name, tmp_string;

        if (!dict.lookup ("key-name",     "s", out key_name))   assert_not_reached ();
        if (!dict.lookup ("parent-path",  "s", out tmp_string)) assert_not_reached ();

        if (dict.lookup ("schema-id",     "s", out tmp_string)) add_row_from_label (_("Schema"),      tmp_string);
        if (dict.lookup ("summary",       "s", out tmp_string)) add_row_from_label (_("Summary"),     tmp_string);
        if (dict.lookup ("description",   "s", out tmp_string)) add_row_from_label (_("Description"), tmp_string);
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (dict.lookup ("type-name",     "s", out tmp_string)) add_row_from_label (_("Type"),        tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string)) add_row_from_label (_("Minimum"),     tmp_string);
        if (dict.lookup ("maximum",       "s", out tmp_string)) add_row_from_label (_("Maximum"),     tmp_string);
        if (dict.lookup ("default-value", "s", out tmp_string)) add_row_from_label (_("Default"),     tmp_string);

        if (!dict.lookup ("type-code",    "s", out tmp_string)) assert_not_reached ();

        bool disable_revealer_for_value = false;
        KeyEditorChild key_editor_child = create_child (key);
        if (has_schema)
        {
            Switch custom_value_switch = new Switch ();
            custom_value_switch.halign = Align.END;
            custom_value_switch.hexpand = true;
            custom_value_switch.show ();
            add_row_from_widget (_("Use default value"), custom_value_switch, null);

            custom_value_switch.bind_property ("active", key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            bool disable_revealer_for_switch = false;
            GSettingsKey gkey = (GSettingsKey) key;
            revealer.reload.connect (() => {
                    disable_revealer_for_switch = true;
                    custom_value_switch.set_active (gkey.is_default);
                    disable_revealer_for_switch = false;    // TODO bad but needed
                });
            custom_value_switch.set_active (key.planned_change ? key.planned_value == null : gkey.is_default);
            custom_value_switch.notify ["active"].connect (() => {
                    if (disable_revealer_for_switch)
                        disable_revealer_for_switch = false;
                    else if (custom_value_switch.get_active ())
                        revealer.add_delayed_setting (key, null);
                    else
                    {
                        Variant tmp_variant = key.planned_change && (key.planned_value != null) ? key.planned_value : key.value;
                        revealer.add_delayed_setting (key, tmp_variant);
                        key_editor_child.reload (tmp_variant);
                    }
                });
        }
        key_editor_child.value_has_changed.connect ((enable_revealer, is_valid) => {
                if (disable_revealer_for_value)
                    disable_revealer_for_value = false;
                else if (enable_revealer && is_valid)
                    revealer.add_delayed_setting (key, key_editor_child.get_variant ());
                else if (enable_revealer && !is_valid)
                    revealer.dismiss_change (key);
            });
        key_editor_child.child_activated.connect (() => { revealer.apply_delayed_settings (); });  // TODO "only" used for string-based and spin widgets
        revealer.reload.connect (() => {
                disable_revealer_for_value = true;
                key_editor_child.reload (key.value);
                if (tmp_string == "<flags>")
                    key.planned_value = key.value;
            });
        add_row_from_widget (_("Custom value"), key_editor_child, tmp_string);

        return true;
    }

    private static KeyEditorChild create_child (Key key)
    {
        switch (key.type_string)
        {
            case "<enum>":
                return (KeyEditorChild) new KeyEditorChildEnum (key);
            case "<flags>":
                return (KeyEditorChild) new KeyEditorChildFlags ((GSettingsKey) key);
            case "b":
                return (KeyEditorChild) new KeyEditorChildBool (key.planned_change && (key.planned_value != null) ? ((!) key.planned_value).get_boolean () : key.value.get_boolean ());
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "h":   // TODO "x" and "t" are not working in spinbuttons (double-based)
                return (KeyEditorChild) new KeyEditorChildNumberInt (key);
            case "d":
                return (KeyEditorChild) new KeyEditorChildNumberDouble (key);
            case "mb":
                return (KeyEditorChild) new KeyEditorChildNullableBool (key);
            default:
                return (KeyEditorChild) new KeyEditorChildDefault (key.type_string, key.planned_change && (key.planned_value != null) ? key.planned_value : key.value);
        }
    }

    /*\
    * * Rows creation
    \*/

    private void add_row_from_label (string property_name, string property_value)
    {
        properties_list_box.add (new PropertyRow.from_label (property_name, property_value));
    }

    private void add_row_from_widget (string property_name, Widget widget, string? type)
    {
        properties_list_box.add (new PropertyRow.from_widgets (property_name, widget, type != null ? add_warning ((!) type) : null));
    }

    private static Widget? add_warning (string type)
    {
        if (type != "<flags>" && ((type != "s" && "s" in type) || (type != "g" && "g" in type)) || (type != "o" && "o" in type))
        {
            if ("m" in type)
                /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
                return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value. Strings, signatures and object paths should be surrounded by quotation marks."));
            else
                return warning_label (_("Strings, signatures and object paths should be surrounded by quotation marks."));
        }
        else if (type != "m" && type != "mb" && type != "<enum>" && "m" in type)
            /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
            return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value."));
        return null;
    }
    private static Widget warning_label (string text)
    {
        Label label = new Label (text);
        label.visible = true;
        label.max_width_chars = 59;
        label.wrap = true;
        label.halign = Align.START;
        label.get_style_context ().add_class ("italic-label");
        return (Widget) label;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/property-row.ui")]
private class PropertyRow : ListBoxRow
{
    [GtkChild] private Grid grid;
    [GtkChild] private Label name_label;

    public PropertyRow.from_label (string property_name, string property_value)
    {
        name_label.set_text (property_name);

        Label value_label = new Label (property_value);
        value_label.valign = Align.START;
        value_label.xalign = 0;
        value_label.yalign = 0;
        value_label.wrap = true;
        value_label.selectable = true;
        value_label.max_width_chars = 42;
        value_label.width_chars = 42;
        value_label.show ();
        grid.attach (value_label, 1, 0, 1, 1);
    }

    public PropertyRow.from_widgets (string property_name, Widget widget, Widget? warning)
    {
        name_label.set_text (property_name);

        grid.attach (widget, 1, 0, 1, 1);
        widget.valign = Align.CENTER;

        if (warning != null)
        {
            grid.row_spacing = 4;
            grid.attach ((!) warning, 0, 1, 2, 1);
            warning.hexpand = true;
            warning.halign = Align.CENTER;
        }
    }
}
