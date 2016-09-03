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
    [GtkChild] private Revealer one_choice_enum_warning;
    [GtkChild] private ListBox properties_list_box;
    [GtkChild] private Button erase_button;

    public ModificationsRevealer revealer { get; set; }

    /*\
    * * Cleaning
    \*/

    private ulong erase_button_handler = 0;
    private ulong revealer_reload_1_handler = 0;
    private ulong revealer_reload_2_handler = 0;

    public void clean ()
    {
        disconnect_handler (erase_button, ref erase_button_handler);
        disconnect_handler (revealer, ref revealer_reload_1_handler);
        disconnect_handler (revealer, ref revealer_reload_2_handler);
        properties_list_box.@foreach ((widget) => widget.destroy ());
    }

    private void disconnect_handler (Widget widget, ref ulong handler)
    {
        if (handler == 0)   // erase_button_handler & revealer_reload_1_handler depend of the key's type
            return;
        widget.disconnect (handler);
        handler = 0;
    }

    /*\
    * * Populating
    \*/

    public void populate_properties_list_box (Key key)
    {
        if (key is DConfKey && ((DConfKey) key).is_ghost)   // TODO place in "requires"
            assert_not_reached ();
        clean ();   // for when switching between two keys, for example with a search (maybe also bookmarks)

        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);

        no_schema_warning.set_reveal_child (!has_schema);

        properties_list_box.@foreach ((widget) => widget.destroy ());

        Variant dict = dict_container [0];

        // TODO use VariantDict
        string key_name, parent_path, tmp_string;

        if (!dict.lookup ("key-name",     "s", out key_name))    assert_not_reached ();
        if (!dict.lookup ("parent-path",  "s", out parent_path)) assert_not_reached ();

        if (dict.lookup ("schema-id",     "s", out tmp_string))  add_row_from_label (_("Schema"),      tmp_string);
        if (dict.lookup ("summary",       "s", out tmp_string))  add_row_from_label (_("Summary"),     tmp_string);
        if (dict.lookup ("description",   "s", out tmp_string))  add_row_from_label (_("Description"), tmp_string);
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (dict.lookup ("type-name",     "s", out tmp_string))  add_row_from_label (_("Type"),        tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string))  add_row_from_label (_("Minimum"),     tmp_string);
        if (dict.lookup ("maximum",       "s", out tmp_string))  add_row_from_label (_("Maximum"),     tmp_string);
        if (dict.lookup ("default-value", "s", out tmp_string))  add_row_from_label (_("Default"),     tmp_string);

        if (!dict.lookup ("type-code",    "s", out tmp_string))  assert_not_reached ();

        Label label = new Label (get_current_value_text (has_schema && ((GSettingsKey) key).is_default, key));
        ulong key_value_changed_handler = key.value_changed.connect (() => {
                if (!has_schema && ((DConfKey) key).is_ghost)
                    ((RegistryView) DConfWindow._get_parent (DConfWindow._get_parent (this))).request_path (parent_path);
                else
                    label.set_text (get_current_value_text (has_schema && ((GSettingsKey) key).is_default, key));
            });
        label.halign = Align.START;
        label.valign = Align.START;
        label.xalign = 0;
        label.yalign = 0;
        label.wrap = true;
        label.max_width_chars = 42;
        label.width_chars = 42;
        label.hexpand = true;
        label.show ();
        add_row_from_widget (_("Current value"), label, null);

        add_separator ();

        KeyEditorChild key_editor_child = create_child (key);
        one_choice_enum_warning.set_reveal_child (key_editor_child is KeyEditorChildEnumSingle);

        ulong value_has_changed_handler = key_editor_child.value_has_changed.connect ((is_valid) => {
                if (revealer.should_delay_apply (tmp_string))
                {
                    if (is_valid)
                        revealer.add_delayed_setting (key, key_editor_child.get_variant ());
                    else
                        revealer.dismiss_change (key);
                }
                else
                    key.value = key_editor_child.get_variant ();
            });

        if (has_schema)
        {
            Switch custom_value_switch = new Switch ();
            custom_value_switch.set_can_focus (false);
            custom_value_switch.halign = Align.START;
            custom_value_switch.hexpand = true;
            custom_value_switch.show ();
            add_switch_row (_("Use default value"), custom_value_switch);

            custom_value_switch.bind_property ("active", key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            GSettingsKey gkey = (GSettingsKey) key;
            custom_value_switch.set_active (key.planned_change ? key.planned_value == null : gkey.is_default);
            ulong switch_active_handler = custom_value_switch.notify ["active"].connect (() => {
                    if (revealer.should_delay_apply (tmp_string))
                    {
                        if (custom_value_switch.get_active ())
                            revealer.add_delayed_setting (key, null);
                        else
                        {
                            Variant tmp_variant = key.planned_change && (key.planned_value != null) ? (!) key.planned_value : key.value;
                            revealer.add_delayed_setting (key, tmp_variant);
                            key_editor_child.reload (tmp_variant);
                        }
                    }
                    else
                    {
                        if (custom_value_switch.get_active ())
                        {
                            ((GSettingsKey) key).set_to_default ();
                            SignalHandler.block (key_editor_child, value_has_changed_handler);
                            key_editor_child.reload (key.value);
                            if (tmp_string == "<flags>")
                                key.planned_value = key.value;
                            SignalHandler.unblock (key_editor_child, value_has_changed_handler);
                        }
                        else
                            key.value = key.value;  // TODO that hurts...
                    }
                });
            revealer_reload_1_handler = revealer.reload.connect (() => {
                    SignalHandler.block (custom_value_switch, switch_active_handler);
                    custom_value_switch.set_active (gkey.is_default);
                    SignalHandler.unblock (custom_value_switch, switch_active_handler);
                });
            custom_value_switch.destroy.connect (() => custom_value_switch.disconnect (switch_active_handler));
        }
        else
        {
            erase_button_handler = erase_button.clicked.connect (() => {
                    revealer.enter_delay_mode ();
                    revealer.add_delayed_setting (key, null);
                });
        }

        ulong child_activated_handler = key_editor_child.child_activated.connect (() => revealer.apply_delayed_settings ());  // TODO "only" used for string-based and spin widgets
        revealer_reload_2_handler = revealer.reload.connect (() => {
                if (key is DConfKey && ((DConfKey) key).is_ghost)
                    return;
                SignalHandler.block (key_editor_child, value_has_changed_handler);
                key_editor_child.reload (key.value);
                if (tmp_string == "<flags>")
                    key.planned_value = key.value;
                SignalHandler.unblock (key_editor_child, value_has_changed_handler);
            });
        add_row_from_widget (_("Custom value"), key_editor_child, tmp_string);

        key_editor_child.destroy.connect (() => {
                key.disconnect (key_value_changed_handler);
                key_editor_child.disconnect (value_has_changed_handler);
                key_editor_child.disconnect (child_activated_handler);
            });
    }

    private static KeyEditorChild create_child (Key key)
    {
        switch (key.type_string)
        {
            case "<enum>":
                switch (((GSettingsKey) key).range_content.n_children ())
                {
                    case 0:  assert_not_reached ();
                    case 1:  return (KeyEditorChild) new KeyEditorChildEnumSingle (key.value);
                    default: return (KeyEditorChild) new KeyEditorChildEnum (key);
                }
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
                return (KeyEditorChild) new KeyEditorChildDefault (key.type_string, key.planned_change && (key.planned_value != null) ? (!) key.planned_value : key.value);
        }
    }

    private static string get_current_value_text (bool is_default, Key key)
    {
        if (is_default)
            return _("Default value");
        else
            return Key.cool_text_value_from_variant (key.value, key.type_string);
    }

    public string? get_copy_text ()
    {
        Widget? focused_row = properties_list_box.get_focus_child ();
        if (focused_row == null)
            return null;
        else if ((!) focused_row is PropertyRow)
            return ((PropertyRow) (!) focused_row).get_copy_text ();
        else    // separator
            return null;
    }

    /*\
    * * Rows creation
    \*/

    private void add_row_from_label (string property_name, string property_value)
    {
        properties_list_box.add (new PropertyRow.from_label (property_name, property_value));
    }

    private void add_switch_row (string property_name, Switch custom_value_switch)
    {
        PropertyRow row = new PropertyRow.from_widgets (property_name, custom_value_switch, null);
        ulong default_value_row_activate_handler = row.activate.connect (() => custom_value_switch.set_active (!custom_value_switch.get_active ()));
        row.destroy.connect (() => row.disconnect (default_value_row_activate_handler));
        properties_list_box.add (row);
    }

    private void add_row_from_widget (string property_name, Widget widget, string? type)
    {
        properties_list_box.add (new PropertyRow.from_widgets (property_name, widget, type != null ? add_warning ((!) type) : null));
    }

    private void add_separator ()
    {
        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.halign = Align.CENTER;
        separator.width_request = 620;
        separator.margin_bottom = 5;
        separator.margin_top = 5;
        separator.show ();

        ListBoxRow row = new ListBoxRow ();
        row.add (separator);
        row.set_sensitive (false);
/* TODO could be selected by down arrow        row.focus.connect ((direction) => { row.move_focus (direction); return false; }); */
        row.show ();
        properties_list_box.add (row);
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
        label.max_width_chars = 59;
        label.wrap = true;
        StyleContext context = label.get_style_context ();
        context.add_class ("italic-label");
        context.add_class ("greyed-label");
        return (Widget) label;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/property-row.ui")]
private class PropertyRow : ListBoxRow
{
    [GtkChild] private Grid grid;
    [GtkChild] private Label name_label;

    private Widget? value_widget = null;

    public PropertyRow.from_label (string property_name, string property_value)
    {
        name_label.set_text (property_name);

        Label value_label = new Label (property_value);
        value_widget = value_label;
        value_label.valign = Align.START;
        value_label.xalign = 0;
        value_label.yalign = 0;
        value_label.wrap = true;
        value_label.max_width_chars = 42;
        value_label.width_chars = 42;
        value_label.show ();
        grid.attach (value_label, 1, 0, 1, 1);
    }

    public PropertyRow.from_widgets (string property_name, Widget widget, Widget? warning)
    {
        name_label.set_text (property_name);

        if (widget is Label)    // TODO handle other rows
            value_widget = widget;

        grid.attach (widget, 1, 0, 1, 1);
        widget.valign = Align.CENTER;

        if (warning != null)
        {
            ((!) warning).hexpand = true;
            ((!) warning).halign = Align.CENTER;
            ((!) warning).show ();
            grid.row_spacing = 4;
            grid.attach ((!) warning, 0, 1, 2, 1);
        }
    }

    public string? get_copy_text ()
    {
        if (value_widget != null)
            return ((Label) (!) value_widget).get_label ();
        else
            return null;
    }
}
