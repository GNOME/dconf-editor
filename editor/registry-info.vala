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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-info.ui")]
class RegistryInfo : Grid, BrowsableView
{
    [GtkChild] private Revealer conflicting_key_warning_revealer;
    [GtkChild] private Revealer hard_conflicting_key_error_revealer;
    [GtkChild] private Revealer no_schema_warning;
    [GtkChild] private Revealer one_choice_warning_revealer;
    [GtkChild] private Label one_choice_enum_warning;
    [GtkChild] private Label one_choice_integer_warning;
    [GtkChild] private ListBox properties_list_box;
    [GtkChild] private Button erase_button;

    public ModificationsHandler modifications_handler { private get; set; }

    private Variant? current_key_info = null;
    public string full_name { get; private set; default = ""; }

    /*\
    * * Cleaning
    \*/

    private ulong erase_button_handler = 0;
    private ulong revealer_reload_1_handler = 0;
    private ulong revealer_reload_2_handler = 0;

    public void clean ()
    {
        disconnect_handler (erase_button, ref erase_button_handler);
        disconnect_handler (modifications_handler, ref revealer_reload_1_handler);
        disconnect_handler (modifications_handler, ref revealer_reload_2_handler);
        properties_list_box.@foreach ((widget) => widget.destroy ());
    }

    private static void disconnect_handler (Object object, ref ulong handler)
    {
        if (handler == 0)   // erase_button_handler & revealer_reload_1_handler depend of the key's type
            return;
        object.disconnect (handler);
        handler = 0;
    }

    /*\
    * * Populating
    \*/

    public void populate_properties_list_box (Key key)
    {
        SettingsModel model = modifications_handler.model;
        if (key is DConfKey && model.is_key_ghost ((DConfKey) key))   // TODO place in "requires"
            assert_not_reached ();
        clean ();   // for when switching between two keys, for example with a search (maybe also bookmarks)

        bool has_schema;
        unowned Variant [] dict_container;
        current_key_info = key.properties;
        full_name = key.full_name;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);

        if (key is GSettingsKey)
        {
            if (((GSettingsKey) key).error_hard_conflicting_key)
            {
                conflicting_key_warning_revealer.set_reveal_child (false);
                hard_conflicting_key_error_revealer.set_reveal_child (true);
            }
            else if (((GSettingsKey) key).warning_conflicting_key)
            {
                conflicting_key_warning_revealer.set_reveal_child (true);
                hard_conflicting_key_error_revealer.set_reveal_child (false);
            }
            else
            {
                conflicting_key_warning_revealer.set_reveal_child (false);
                hard_conflicting_key_error_revealer.set_reveal_child (false);
            }
        }
        else
        {
            conflicting_key_warning_revealer.set_reveal_child (false);
            hard_conflicting_key_error_revealer.set_reveal_child (false);
        }
        no_schema_warning.set_reveal_child (!has_schema);

        properties_list_box.@foreach ((widget) => widget.destroy ());

        Variant dict = dict_container [0];

        // TODO use VariantDict
        string key_name, parent_path, tmp_string;
        bool test;

        if (!dict.lookup ("key-name",     "s", out key_name))    assert_not_reached ();
        if (!dict.lookup ("parent-path",  "s", out parent_path)) assert_not_reached ();

        if (dict.lookup ("defined-by",    "s", out tmp_string))  add_row_from_label (_("Defined by"),  tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("schema-id",     "s", out tmp_string))  add_row_from_label (_("Schema"),      tmp_string);
        add_separator ();
        if (dict.lookup ("summary",       "s", out tmp_string))
        {
            test = tmp_string == "";
            add_row_from_label (_("Summary"),                    test ? _("No summary provided")     : tmp_string, test);
        }
        if (dict.lookup ("description",   "s", out tmp_string))
        {
            test = tmp_string == "";
            add_row_from_label (_("Description"),                test ? _("No description provided") : tmp_string, test);
        }
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (dict.lookup ("type-name",     "s", out tmp_string))  add_row_from_label (_("Type"),        tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string))  add_row_from_label (_("Minimum"),     tmp_string);
        if (dict.lookup ("maximum",       "s", out tmp_string))  add_row_from_label (_("Maximum"),     tmp_string);
        if (dict.lookup ("default-value", "s", out tmp_string))  add_row_from_label (_("Default"),     tmp_string);

        if (!dict.lookup ("type-code",    "s", out tmp_string))  assert_not_reached ();

        ulong key_value_changed_handler = 0;
        Label label;
        if (key is GSettingsKey && ((GSettingsKey) key).error_hard_conflicting_key)
        {
            label = new Label (_("There are conflicting definitions of this key, getting value would be either problematic or meaningless."));
            label.get_style_context ().add_class ("italic-label");
        }
        else
        {
            label = new Label (get_current_value_text (has_schema && model.is_key_default ((GSettingsKey) key), key, modifications_handler.model));
            key_value_changed_handler = key.value_changed.connect (() => {
                    if (!has_schema && model.is_key_ghost ((DConfKey) key))
                        label.set_text (_("Key erased."));
                    else
                        label.set_text (get_current_value_text (has_schema && model.is_key_default ((GSettingsKey) key), key, modifications_handler.model));
                });
        }
        label.halign = Align.START;
        label.valign = Align.START;
        label.xalign = 0;
        label.yalign = 0;
        label.wrap = true;
        label.hexpand = true;
        label.show ();
        add_row_from_widget (_("Current value"), label, null);

        add_separator ();

        KeyEditorChild key_editor_child = create_child (key, has_schema, modifications_handler);
        bool is_key_editor_child_single = key_editor_child is KeyEditorChildSingle;
        if (is_key_editor_child_single)
        {
            bool is_enum = tmp_string == "<enum>";
            one_choice_integer_warning.visible = !is_enum;
            one_choice_enum_warning.visible = is_enum;
        }
        one_choice_warning_revealer.set_reveal_child (is_key_editor_child_single);

        if (key is GSettingsKey && ((GSettingsKey) key).error_hard_conflicting_key)
            return;

        ulong value_has_changed_handler = key_editor_child.value_has_changed.connect ((is_valid) => {
                if (modifications_handler.should_delay_apply (tmp_string))
                {
                    if (is_valid)
                        modifications_handler.add_delayed_setting (key.full_name, key_editor_child.get_variant ());
                    else
                        modifications_handler.dismiss_change (key.full_name);
                }
                else
                    model.set_key_value (key, key_editor_child.get_variant ());
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
            custom_value_switch.set_active (modifications_handler.key_value_is_default (gkey));
            ulong switch_active_handler = custom_value_switch.notify ["active"].connect (() => {
                    if (modifications_handler.should_delay_apply (tmp_string))
                    {
                        if (custom_value_switch.get_active ())
                            modifications_handler.add_delayed_setting (key.full_name, null);
                        else
                        {
                            Variant tmp_variant = modifications_handler.get_key_custom_value (key);
                            modifications_handler.add_delayed_setting (key.full_name, tmp_variant);
                            key_editor_child.reload (tmp_variant);
                        }
                    }
                    else
                    {
                        if (custom_value_switch.get_active ())
                        {
                            model.set_key_to_default (((GSettingsKey) key).full_name, ((GSettingsKey) key).schema_id);
                            SignalHandler.block (key_editor_child, value_has_changed_handler);
                            key_editor_child.reload (model.get_key_value (key));
                            //if (tmp_string == "<flags>")                      let's try to live without this...
                            //    key.planned_value = key.value;
                            SignalHandler.unblock (key_editor_child, value_has_changed_handler);
                        }
                        else
                            model.set_key_value (key, model.get_key_value (key));  // TODO that hurts...
                    }
                });
            revealer_reload_1_handler = modifications_handler.leave_delay_mode.connect (() => {
                    SignalHandler.block (custom_value_switch, switch_active_handler);
                    custom_value_switch.set_active (model.is_key_default (gkey));
                    SignalHandler.unblock (custom_value_switch, switch_active_handler);
                });
            custom_value_switch.destroy.connect (() => custom_value_switch.disconnect (switch_active_handler));
        }
        else
        {
            erase_button_handler = erase_button.clicked.connect (() => {
                    modifications_handler.enter_delay_mode ();
                    modifications_handler.add_delayed_setting (key.full_name, null);
                });
        }

        ulong child_activated_handler = key_editor_child.child_activated.connect (() => modifications_handler.apply_delayed_settings ());  // TODO "only" used for string-based and spin widgets
        revealer_reload_2_handler = modifications_handler.leave_delay_mode.connect (() => {
                if (key is DConfKey && model.is_key_ghost ((DConfKey) key))
                    return;
                SignalHandler.block (key_editor_child, value_has_changed_handler);
                key_editor_child.reload (model.get_key_value (key));
                //if (tmp_string == "<flags>")                      let's try to live without this...
                //    key.planned_value = key.value;
                SignalHandler.unblock (key_editor_child, value_has_changed_handler);
            });
        add_row_from_widget (_("Custom value"), key_editor_child, tmp_string);

        key_editor_child.destroy.connect (() => {
                if (key_value_changed_handler == 0)
                    assert_not_reached ();
                key.disconnect (key_value_changed_handler);
                key_editor_child.disconnect (value_has_changed_handler);
                key_editor_child.disconnect (child_activated_handler);
            });
    }

    private static KeyEditorChild create_child (Key key, bool has_schema, ModificationsHandler modifications_handler)
    {
        SettingsModel model = modifications_handler.model;
        Variant initial_value = modifications_handler.get_key_custom_value (key);
        switch (key.type_string)
        {
            case "<enum>":
                switch (((GSettingsKey) key).range_content.n_children ())
                {
                    case 0: assert_not_reached ();
                    case 1:
                        return (KeyEditorChild) new KeyEditorChildSingle (model.get_key_value (key), model.get_key_value (key).get_string ());
                    default:
                        bool delay_mode = modifications_handler.get_current_delay_mode ();
                        bool has_planned_change = modifications_handler.key_has_planned_change (key.full_name);
                        Variant range_content = ((GSettingsKey) key).range_content;
                        return (KeyEditorChild) new KeyEditorChildEnum (initial_value, delay_mode, has_planned_change, range_content);
                }

            case "<flags>":
                string [] all_flags = ((GSettingsKey) key).range_content.get_strv ();
                string [] active_flags = ((GSettingsKey) key).settings.get_strv (key.name);
                KeyEditorChildFlags key_editor_child_flags = new KeyEditorChildFlags (initial_value, all_flags, active_flags);

                ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                        active_flags = modifications_handler.get_key_custom_value (key).get_strv ();
                        key_editor_child_flags.update_flags (active_flags);
                    });
                key_editor_child_flags.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));
                return (KeyEditorChild) key_editor_child_flags;

            case "b":
                return (KeyEditorChild) new KeyEditorChildBool (initial_value.get_boolean ());

            case "n":
            case "i":
            case "h":
            // TODO "x" is not working in spinbuttons (double-based)
                Variant? range = null;
                if (has_schema && (((GSettingsKey) key).range_type == "range"))
                {
                    range = ((GSettingsKey) key).range_content;
                    if (Key.get_variant_as_int64 (((!) range).get_child_value (0)) == Key.get_variant_as_int64 (((!) range).get_child_value (1)))
                        return (KeyEditorChild) new KeyEditorChildSingle (model.get_key_value (key), model.get_key_value (key).print (false));
                }
                return (KeyEditorChild) new KeyEditorChildNumberInt (initial_value, key.type_string, range);

            case "y":
            case "q":
            case "u":
            // TODO "t" is not working in spinbuttons (double-based)
                Variant? range = null;
                if (has_schema && (((GSettingsKey) key).range_type == "range"))
                {
                    range = ((GSettingsKey) key).range_content;
                    if (Key.get_variant_as_uint64 (((!) range).get_child_value (0)) == Key.get_variant_as_uint64 (((!) range).get_child_value (1)))
                        return (KeyEditorChild) new KeyEditorChildSingle (model.get_key_value (key), model.get_key_value (key).print (false));
                }
                return (KeyEditorChild) new KeyEditorChildNumberInt (initial_value, key.type_string, range);

            case "d":
                return (KeyEditorChild) new KeyEditorChildNumberDouble (initial_value);

            case "mb":
                bool delay_mode = modifications_handler.get_current_delay_mode ();
                bool has_planned_change = modifications_handler.key_has_planned_change (key.full_name);
                Variant? range_content_or_null = null;
                if (key is GSettingsKey)
                    range_content_or_null = ((GSettingsKey) key).range_content;
                return (KeyEditorChild) new KeyEditorChildNullableBool (initial_value, delay_mode, has_planned_change, range_content_or_null);

            default:
                if ("a" in key.type_string)
                    return (KeyEditorChild) new KeyEditorChildArray (key.type_string, initial_value);
                else
                    return (KeyEditorChild) new KeyEditorChildDefault (key.type_string, initial_value);
        }
    }

    private static string get_current_value_text (bool is_default, Key key, SettingsModel model)
    {
        if (is_default)
            return _("Default value");
        else
            return Key.cool_text_value_from_variant (model.get_key_value (key), key.type_string);
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

    private void add_row_from_label (string property_name, string property_value, bool use_italic = false)
    {
        properties_list_box.add (new PropertyRow.from_label (property_name, property_value, use_italic));
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
        PropertyRow row = new PropertyRow.from_widgets (property_name, widget, type != null ? add_warning ((!) type) : null);
        widget.bind_property ("sensitive", row, "sensitive", BindingFlags.SYNC_CREATE);
        properties_list_box.add (row);
    }

    private void add_separator ()
    {
        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.halign = Align.FILL;
        separator.margin_bottom = 5;
        separator.margin_top = 5;
        separator.show ();

        ListBoxRowWrapper row = new ListBoxRowWrapper ();
        row.halign = Align.CENTER;
        row.add (separator);
        row.set_sensitive (false);
/* TODO could be selected by down arrow        row.focus.connect ((direction) => { row.move_focus (direction); return false; }); */
        row.show ();
        properties_list_box.add (row);
    }

    private static Widget? add_warning (string type)
    {
        if (type == "d")    // TODO if type contains "d"; on Intl.get_language_names ()[0] != "C"?
            return warning_label (_("Use a dot as decimal mark and no thousands separator. You can use the X.Ye+Z notation."));

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
        label.wrap = true;
        StyleContext context = label.get_style_context ();
        context.add_class ("italic-label");
        context.add_class ("greyed-label");
        context.add_class ("warning-label");
        return (Widget) label;
    }

    public bool check_reload (Variant properties)
    {
        if (current_key_info == null) // should not happen?
            return true;
        return !((!) current_key_info).equal (properties); // TODO compare key value with editor value?
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/property-row.ui")]
private class PropertyRow : ListBoxRowWrapper
{
    [GtkChild] private Grid grid;
    [GtkChild] private Label name_label;

    private Widget? value_widget = null;

    public PropertyRow.from_label (string property_name, string property_value, bool use_italic)
    {
        name_label.set_text (property_name);

        Label value_label = new Label (property_value);
        value_widget = value_label;
        value_label.valign = Align.START;
        value_label.xalign = 0;
        value_label.yalign = 0;
        value_label.wrap = true;
        if (use_italic)
            value_label.get_style_context ().add_class ("italic-label");
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
