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
    [GtkChild] private Label one_choice_tuple_warning;
    [GtkChild] private ListBox properties_list_box;
    [GtkChild] private Button erase_button;

    private Label current_value_label;

    public ModificationsHandler modifications_handler { private get; set; }

    private Variant? current_key_info = null;
    public string full_name { get; private set; default = ""; }
    public string context { get; private set; default = ""; }

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

    public void populate_properties_list_box (string _full_name, string _context, Variant _current_key_info)
    {
        full_name = _full_name;
        context = _context;
        current_key_info = _current_key_info;

        bool has_schema = context != ".dconf";
        SettingsModel model = modifications_handler.model;

        if (!has_schema && model.is_key_ghost (full_name))   // TODO place in "requires"
            assert_not_reached ();
        clean ();   // for when switching between two keys, for example with a search (maybe also bookmarks)

        VariantDict properties = new VariantDict (_current_key_info);

        bool error_hard_conflicting_key = false;
        if (has_schema)
        {
            if (!properties.lookup ("hard-conflict", "b", out error_hard_conflicting_key))
                assert_not_reached ();

            if (error_hard_conflicting_key)
            {
                conflicting_key_warning_revealer.set_reveal_child (false);
                hard_conflicting_key_error_revealer.set_reveal_child (true);
            }
            else
            {
                bool warning_conflicting_key;
                if (!properties.lookup ("soft-conflict", "b", out warning_conflicting_key))
                    assert_not_reached ();
                if (warning_conflicting_key)
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
        }
        else
        {
            conflicting_key_warning_revealer.set_reveal_child (false);
            hard_conflicting_key_error_revealer.set_reveal_child (false);
        }
        no_schema_warning.set_reveal_child (!has_schema);

        properties_list_box.@foreach ((widget) => widget.destroy ());

        // TODO g_variant_dict_lookup_value() return value is not annotated as nullable
        string type_code;
        if (!properties.lookup ("type-code",        "s",    out type_code))
            assert_not_reached ();

        bool test;
        string tmp_string;

        if (properties.lookup ("defined-by",        "s",    out tmp_string))
            add_row_from_label (_("Defined by"),                tmp_string);
        else assert_not_reached ();

        if (properties.lookup ("schema-id",         "s",    out tmp_string))
            add_row_from_label (_("Schema"),                    tmp_string);

        add_separator ();
        if (properties.lookup ("summary",           "s",    out tmp_string))
        {
            test = tmp_string == "";
            add_row_from_label (_("Summary"),
                                test ?                          _("No summary provided")
                                     :                          tmp_string,
                                test);
        }
        if (properties.lookup ("description",       "s",    out tmp_string))
        {
            test = tmp_string == "";
            add_row_from_label (_("Description"),
                                test ?                          _("No description provided")
                                     :                          tmp_string,
                                test);
        }
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (properties.lookup ("type-name",         "s",    out tmp_string))
            add_row_from_label (_("Type"),                      tmp_string);
        else assert_not_reached ();

        bool range_type_is_range = false;
        if (properties.lookup ("range-type",        "s",    out tmp_string)) // has_schema
        {
            if (type_code == "d" || type_code == "y"    // double and unsigned 8 bits; not the handle type
             || type_code == "i" || type_code == "u"    // signed and unsigned 32 bits
             || type_code == "n" || type_code == "q"    // signed and unsigned 16 bits
             || type_code == "x" || type_code == "t")   // signed and unsigned 64 bits
            {
                range_type_is_range = tmp_string == "range";
                add_row_from_label (_("Forced range"),          Key.cool_boolean_text_value (range_type_is_range));
            }
        }

        bool minimum_is_maximum = false;
        string tmp = "";
        tmp_string = "";
        if (properties.lookup ("minimum",           "s",    out tmp_string))
            add_row_from_label (_("Minimum"),                   tmp_string);
        if (properties.lookup ("maximum",           "s",    out tmp       ))
            add_row_from_label (_("Maximum"),                   tmp       );
        if (tmp != "" && tmp == tmp_string)
            minimum_is_maximum = true;

        bool has_schema_and_is_default;
        if (!has_schema)
            has_schema_and_is_default = false;
        else if (!properties.lookup ("is-default",  "b",    out has_schema_and_is_default))
            assert_not_reached ();

        if (properties.lookup ("default-value",     "s",    out tmp_string))
            add_row_from_label (_("Default"),                   tmp_string);

        if ( /* has_schema && */ error_hard_conflicting_key)
        {
            current_value_label = new Label (_("There are conflicting definitions of this key, getting value would be either problematic or meaningless."));
            current_value_label.get_style_context ().add_class ("italic-label");
        }
        else if (has_schema_and_is_default)
            current_value_label = new Label (get_current_value_text (null));
        else
        {
            Variant key_value;
            if (!properties.lookup ("key-value",    "v",    out key_value))
                assert_not_reached ();
            current_value_label = new Label (get_current_value_text (key_value));
        }
        current_value_label.halign = Align.START;
        current_value_label.valign = Align.START;
        current_value_label.xalign = 0;
        current_value_label.yalign = 0;
        current_value_label.wrap = true;
        current_value_label.hexpand = true;
        current_value_label.show ();
        add_row_from_widget (_("Current value"), current_value_label, null);

        add_separator ();

        KeyEditorChild key_editor_child;
        Variant initial_value = modifications_handler.get_key_custom_value (full_name, context);
        switch (type_code)
        {
            case "b":
                key_editor_child = (KeyEditorChild) new KeyEditorChildBool (initial_value.get_boolean ());                      break;
            case "i":   // int32
            case "u":   // uint32
            case "n":   // int16
            case "q":   // uint16
            case "y":   // uint8
            case "h":   // handle type
            // TODO "x" and "t" are not working in spinbuttons (double-based)
                if (minimum_is_maximum)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.print (false));
                else
                {
                    Variant? range = null;
                    if (has_schema && range_type_is_range && !properties.lookup ("range-content", "v", out range))  // type_string != "h"
                        assert_not_reached ();
                    key_editor_child = (KeyEditorChild) new KeyEditorChildNumberInt (initial_value, type_code, range);
                }                                                                                                                   break;
            case "d":
                key_editor_child = (KeyEditorChild) new KeyEditorChildNumberDouble (initial_value);                                 break;
            case "mb":
                key_editor_child = create_child_mb (initial_value, full_name, has_schema, modifications_handler);                   break;
            case "<enum>":  // has_schema
                Variant range_content;
                if (!properties.lookup ("range-content", "v", out range_content))
                    assert_not_reached ();
                key_editor_child = create_child_enum (range_content, initial_value, full_name, modifications_handler);              break;
            case "<flags>": // has_schema
                Variant range_content;
                if (!properties.lookup ("range-content", "v", out range_content))
                    assert_not_reached ();
                key_editor_child = create_child_flags (full_name, context, range_content, initial_value, modifications_handler);    break;
            case "()":
                key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (new Variant ("()", "()"), "()");                      break;
            default:
                if ("a" in type_code)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildArray (type_code, initial_value);
                else
                    key_editor_child = (KeyEditorChild) new KeyEditorChildDefault (type_code, initial_value);                       break;
        }

        bool is_key_editor_child_single = key_editor_child is KeyEditorChildSingle;
        if (is_key_editor_child_single)
        {
            one_choice_enum_warning.visible = type_code == "<enum>";
            one_choice_tuple_warning.visible = type_code == "()";
            one_choice_integer_warning.visible = (type_code != "<enum>") && (type_code != "()");
        }
        one_choice_warning_revealer.set_reveal_child (is_key_editor_child_single);

        if (has_schema && error_hard_conflicting_key)
            return;

        ulong value_has_changed_handler = key_editor_child.value_has_changed.connect ((is_valid) => {
                if (modifications_handler.should_delay_apply (type_code))
                {
                    if (is_valid)
                        modifications_handler.add_delayed_setting (full_name, key_editor_child.get_variant (), context);
                    else
                        modifications_handler.dismiss_change (full_name);
                }
                else if (has_schema)
                    model.set_gsettings_key_value (full_name, context, key_editor_child.get_variant ());
                else
                    model.set_dconf_key_value (full_name, key_editor_child.get_variant ());
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

            bool planned_change = modifications_handler.key_has_planned_change (full_name);
            Variant? planned_value = modifications_handler.get_key_planned_value (full_name);
            bool key_value_is_default = planned_change ? planned_value == null : has_schema_and_is_default;
            custom_value_switch.set_active (key_value_is_default);

            ulong switch_active_handler = custom_value_switch.notify ["active"].connect (() => {
                    if (modifications_handler.should_delay_apply (type_code))
                    {
                        if (custom_value_switch.get_active ())
                            modifications_handler.add_delayed_setting (full_name, null, context);
                        else
                        {
                            Variant tmp_variant = modifications_handler.get_key_custom_value (full_name, context);
                            modifications_handler.add_delayed_setting (full_name, tmp_variant, context);
                            key_editor_child.reload (tmp_variant);
                        }
                    }
                    else
                    {
                        VariantDict local_properties = new VariantDict (model.get_key_properties (full_name, context, {"key-value"}));
                        Variant key_value;
                        if (!local_properties.lookup ("key-value", "v", out key_value))
                            assert_not_reached ();
                        if (custom_value_switch.get_active ())
                        {
                            model.set_key_to_default (full_name, context);
                            SignalHandler.block (key_editor_child, value_has_changed_handler);
                            key_editor_child.reload (key_value);
                            //if (type_code == "<flags>")                      let's try to live without this...
                            //    key.planned_value = key.value;
                            SignalHandler.unblock (key_editor_child, value_has_changed_handler);
                        }
                        else
                            model.set_gsettings_key_value (full_name, context, key_value); // TODO sets key value with key value... that hurts
                    }
                });
            revealer_reload_1_handler = modifications_handler.leave_delay_mode.connect (() => {
                    SignalHandler.block (custom_value_switch, switch_active_handler);

                    VariantDict local_properties = new VariantDict (model.get_key_properties (full_name, context, {"is-default"}));
                    bool is_key_default;
                    if (!local_properties.lookup ("is-default", "b", out is_key_default))
                        assert_not_reached ();
                    custom_value_switch.set_active (is_key_default);
                    SignalHandler.unblock (custom_value_switch, switch_active_handler);
                });
            custom_value_switch.destroy.connect (() => custom_value_switch.disconnect (switch_active_handler));
        }
        else
        {
            erase_button_handler = erase_button.clicked.connect (() => {
                    modifications_handler.enter_delay_mode ();
                    modifications_handler.add_delayed_setting (full_name, null, ".dconf");
                });
        }

        ulong child_activated_handler = key_editor_child.child_activated.connect (() => modifications_handler.apply_delayed_settings ());  // TODO "only" used for string-based and spin widgets
        revealer_reload_2_handler = modifications_handler.leave_delay_mode.connect (() => {
                if (!has_schema && model.is_key_ghost (full_name))
                    return;
                SignalHandler.block (key_editor_child, value_has_changed_handler);

                VariantDict local_properties = new VariantDict (model.get_key_properties (full_name, context, {"key-value"}));
                Variant key_value;
                if (!local_properties.lookup ("key-value", "v", out key_value))
                    assert_not_reached ();
                key_editor_child.reload (key_value);
                //if (type_code == "<flags>")                      let's try to live without this...
                //    key.planned_value = key.value;
                SignalHandler.unblock (key_editor_child, value_has_changed_handler);
            });
        add_row_from_widget (_("Custom value"), key_editor_child, type_code);

        key_editor_child.destroy.connect (() => {
                key_editor_child.disconnect (value_has_changed_handler);
                key_editor_child.disconnect (child_activated_handler);
            });
    }

    private static KeyEditorChild create_child_mb (Variant initial_value, string full_name, bool has_schema, ModificationsHandler modifications_handler)
    {
        bool delay_mode = modifications_handler.get_current_delay_mode ();
        bool has_planned_change = modifications_handler.key_has_planned_change (full_name);
        return (KeyEditorChild) new KeyEditorChildNullableBool (initial_value, delay_mode, has_planned_change, has_schema);
    }

    private static KeyEditorChild create_child_enum (Variant range_content, Variant initial_value, string full_name, ModificationsHandler modifications_handler)
    {
        switch (range_content.n_children ())
        {
            case 0: assert_not_reached ();
            case 1:
                return (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.get_string ());
            default:
                bool delay_mode = modifications_handler.get_current_delay_mode ();
                bool has_planned_change = modifications_handler.key_has_planned_change (full_name);
                return (KeyEditorChild) new KeyEditorChildEnum (initial_value, delay_mode, has_planned_change, range_content);
        }
    }

    private static KeyEditorChild create_child_flags (string full_name, string context, Variant range_content, Variant initial_value, ModificationsHandler modifications_handler)
    {
        KeyEditorChildFlags key_editor_child_flags = new KeyEditorChildFlags (initial_value, range_content.get_strv ());

        ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                string [] active_flags = modifications_handler.get_key_custom_value (full_name, context).get_strv ();
                key_editor_child_flags.update_flags (active_flags);
            });
        key_editor_child_flags.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));
        return (KeyEditorChild) key_editor_child_flags;
    }

    private static string get_current_value_text (Variant? key_value)
    {
        if (key_value == null)
            return _("Default value");
        return Key.cool_text_value_from_variant ((!) key_value);
    }

    public string? get_copy_text () // can compile with "private", but is public 2/2
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

        if ("v" in type)
            return warning_label (_("Variants content should be surrounded by XML brackets (‘<’ and ‘>’). See https://developer.gnome.org/glib/stable/gvariant-text.html for complete documentation."));

        /* the "<flags>" special type is not concerned but has an 's' and a 'g' in it; "s", "g" and "o" types have a specific UI */
        if (type != "<flags>" && ((type != "s" && "s" in type) || (type != "g" && "g" in type)) || (type != "o" && "o" in type))
        {
            if ("m" in type)
                /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
                return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value. Strings, signatures and object paths should be surrounded by quotation marks."));
            else
                return warning_label (_("Strings, signatures and object paths should be surrounded by quotation marks."));
        }
        /* the "mb" type has a specific UI; the "<enum>" special type is not concerned but has an 'm' in it */
        else if (type != "mb" && type != "<enum>" && "m" in type)
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

    /*\
    * * Updating value
    \*/

    public void gkey_value_push (Variant key_value, bool is_key_default)    // TODO check if there isn't a problem on conflicting keys
    {
        if (is_key_default)
            current_value_label.set_text (get_current_value_text (null));
        else
            current_value_label.set_text (get_current_value_text (key_value));
    }

    public void dkey_value_push (Variant? key_value_or_null)
    {
        if (key_value_or_null == null)
        {
            current_value_label.get_style_context ().add_class ("italic-label");
            current_value_label.set_text (_("Key erased."));
        }
        else
        {
            current_value_label.get_style_context ().remove_class ("italic-label");
            current_value_label.set_text (get_current_value_text (key_value_or_null));
        }
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
