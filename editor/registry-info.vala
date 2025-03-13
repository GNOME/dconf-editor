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
private class RegistryInfo : Grid, BrowsableView
{
    [GtkChild] private unowned Revealer conflicting_key_warning_revealer;
    [GtkChild] private unowned Revealer hard_conflicting_key_error_revealer;
    [GtkChild] private unowned Revealer no_schema_warning;
    [GtkChild] private unowned Revealer one_choice_warning_revealer;
    [GtkChild] private unowned Label one_choice_enum_warning;
    [GtkChild] private unowned Label one_choice_integer_warning;
    [GtkChild] private unowned Label one_choice_tuple_warning;
    [GtkChild] private unowned ListBox properties_list_box;
    [GtkChild] private unowned Button erase_button;

    private Label current_value_label;

    [CCode (notify = false)] internal ModificationsHandler modifications_handler { private get; set; }

    private uint current_key_info_hash = 0;

    /*\
    * * Cleaning
    \*/

    private ulong revealer_reload_1_handler = 0;
    private ulong revealer_reload_2_handler = 0;

    internal void clean ()
    {
        erase_button.set_action_target ("s", "");
        disconnect_handler (modifications_handler, ref revealer_reload_1_handler);
        disconnect_handler (modifications_handler, ref revealer_reload_2_handler);
        properties_list_box.@foreach ((widget) => widget.destroy ());
    }

    private static void disconnect_handler (Object object, ref ulong handler)
    {
        if (handler == 0)   // revealer_reload_1_handler depends of the key's type
            return;
        object.disconnect (handler);
        handler = 0;
    }

    /*\
    * * Populating
    \*/

    [CCode (notify = false)] internal string full_name   { internal get; private set; default = ""; }
    [CCode (notify = false)] internal uint16 context_id  { internal get; private set; default = ModelUtils.undefined_context_id; }

    /* Translators: field description when displaying folder properties; name of the folder */
    private const string          NAME_FIELD_DESCRIPTION = _("Name");

    /* Translators: field description when displaying key properties; the key can be defined by a schema or by the dconf engine */
    private const string    DEFINED_BY_FIELD_DESCRIPTION = _("Defined by");

    /* Translators: field description when displaying key properties; the schema id (if the key is defined by a schema) */
    private const string        SCHEMA_FIELD_DESCRIPTION = _("Schema");

    /* Translators: field description when displaying key properties; a summary describing the key use*/
    private const string       SUMMARY_FIELD_DESCRIPTION = _("Summary");

    /* Translators: field description when displaying key properties; a description describing deeply the key use*/
    private const string   DESCRIPTION_FIELD_DESCRIPTION = _("Description");

    /* Translators: field description when displaying key properties; the datatype of the key (integer, boolean, string, etc.) */
    private const string          TYPE_FIELD_DESCRIPTION = _("Type");
    private const string         _TYPE_FIELD_DESCRIPTION = "Type";

    /* Translators: field description when displaying key properties; specific name of the datatype of the key ("Signed 32-bit integer" for example) */
    private const string     TYPE_NAME_FIELD_DESCRIPTION = _("Type name");
    private const string    _TYPE_NAME_FIELD_DESCRIPTION = "Type name";

    /* Translators: field description when displaying key properties; technical code of the datatype of the key ("q" for uint16, "b" for boolean, etc.) */
    private const string     TYPE_CODE_FIELD_DESCRIPTION = _("Type code");

    /* Translators: field description when displaying key properties; if the numeral key has a minimum or a maximum set */
    private const string  FORCED_RANGE_FIELD_DESCRIPTION = _("Forced range");

    /* Translators: field description when displaying key properties; the minimum value a numeral key can take */
    private const string       MINIMUM_FIELD_DESCRIPTION = _("Minimum");

    /* Translators: field description when displaying key properties; the maximum value a numeral key can take */
    private const string       MAXIMUM_FIELD_DESCRIPTION = _("Maximum");

    /* Translators: field description when displaying key properties; the default value of the key (defined if it has a schema) */
    private const string       DEFAULT_FIELD_DESCRIPTION = _("Default");

    /* Translators: field description when displaying key properties; the current value of the key */
    private const string CURRENT_VALUE_FIELD_DESCRIPTION = _("Current value");

    /* Translators: field description when displaying key properties; the field content is a switch widget that allows using or not the default value of the key, as provided by its schema */
    private const string   USE_DEFAULT_FIELD_DESCRIPTION = _("Use default value");

    /* Translators: field description when displaying key properties; the field content is a widget that allows setting the value of the key (depending of its type, an entry, a switch, etc.) */
    private const string  CUSTOM_VALUE_FIELD_DESCRIPTION = _("Custom value");

    internal void populate_properties_list_box (string _full_name, uint16 _context_id, Variant current_key_info)
    {
        full_name = _full_name;
        context_id = _context_id;

        clean ();   // for when switching between two keys, for example with a search (maybe also bookmarks)

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (current_key_info);

        properties_list_box.@foreach ((widget) => widget.destroy ());

        if (context_id == ModelUtils.folder_context_id)
        {
            string folder_name;
            if (!properties.lookup (PropertyQuery.KEY_NAME,             "s",    out folder_name))
                assert_not_reached ();
            add_row_from_label (NAME_FIELD_DESCRIPTION,                             folder_name);

            conflicting_key_warning_revealer.set_reveal_child (false);
            hard_conflicting_key_error_revealer.set_reveal_child (false);
            no_schema_warning.set_reveal_child (false);
            one_choice_warning_revealer.set_reveal_child (false);

            return;
        }

        if (!properties.lookup (PropertyQuery.HASH,                     "u",    out current_key_info_hash))
            assert_not_reached ();

        bool has_schema;
        if (!properties.lookup (PropertyQuery.HAS_SCHEMA,               "b",    out has_schema))
            assert_not_reached ();

        KeyConflict key_conflict = KeyConflict.NONE;
        if (has_schema)
        {
            uint8 _key_conflict;
            if (!properties.lookup (PropertyQuery.KEY_CONFLICT,         "y",    out _key_conflict))
                assert_not_reached ();
            key_conflict = (KeyConflict) _key_conflict;

            if (key_conflict == KeyConflict.HARD)
            {
                conflicting_key_warning_revealer.set_reveal_child (false);
                hard_conflicting_key_error_revealer.set_reveal_child (true);
            }
            else if (key_conflict == KeyConflict.SOFT)
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

        // TODO g_variant_dict_lookup_value() return value is not annotated as nullable
        string type_code;
        if (!properties.lookup (PropertyQuery.TYPE_CODE,                "s",    out type_code))
            assert_not_reached ();

        bool tmp_bool;
        string tmp_string;

        if (!properties.lookup (PropertyQuery.FIXED_SCHEMA,             "b",    out tmp_bool))
            tmp_bool = false;
        add_row_from_label (DEFINED_BY_FIELD_DESCRIPTION,                           get_defined_by (has_schema, tmp_bool));

        if (properties.lookup (PropertyQuery.SCHEMA_ID,                 "s",    out tmp_string))
            add_row_from_label (SCHEMA_FIELD_DESCRIPTION,                           tmp_string);

        add_separator ();
        if (properties.lookup (PropertyQuery.SUMMARY,                   "s",    out tmp_string))
        {
            tmp_bool = tmp_string == "";
            add_row_from_label (SUMMARY_FIELD_DESCRIPTION,

            /* Translators: field content when displaying key properties; if the key does not have a summary describing its use */
                                tmp_bool ?                                          _("No summary provided")
                                         :                                          tmp_string,
                                tmp_bool);
        }
        if (properties.lookup (PropertyQuery.DESCRIPTION,               "s",    out tmp_string))
        {
            tmp_bool = tmp_string == "";
            add_row_from_label (DESCRIPTION_FIELD_DESCRIPTION,

            /* Translators: field content when displaying key properties; if the key does not have a description describing deeply its use */
                                tmp_bool ?                                          _("No description provided")
                                         :                                          tmp_string,
                                tmp_bool);
        }

        tmp_string = ModelUtils.key_to_long_description (type_code);
        if (type_code == tmp_string                     // no type name found; could use "type code", but then why saying "code"?
         || type_code == "<enum>"                       // not really a datatype name; and the type code
         || type_code == "<flags>")                     //   is weird, so do not show it        // TODO show it anyway for learning 1/2
            add_row_from_label (TYPE_FIELD_DESCRIPTION,                             tmp_string);
        else
        {
            string type_name_field_description;
            if (TYPE_NAME_FIELD_DESCRIPTION != _TYPE_NAME_FIELD_DESCRIPTION)
                type_name_field_description = TYPE_NAME_FIELD_DESCRIPTION;
            else if (TYPE_FIELD_DESCRIPTION != _TYPE_FIELD_DESCRIPTION)
                type_name_field_description = TYPE_FIELD_DESCRIPTION;   // FIXME this fallback do not work if the translation is "Type"...
            else
                type_name_field_description = _TYPE_NAME_FIELD_DESCRIPTION;

            add_row_from_label (type_name_field_description,                        tmp_string);
            if (type_code != "b" && type_code != "s")   // quite obvious and omnipresent types  // TODO show it anyway for learning 2/2
                add_row_from_label (TYPE_CODE_FIELD_DESCRIPTION,                    type_code);
        }

        bool range_type_is_range = false;
        uint8 range_type;
        if (properties.lookup (PropertyQuery.RANGE_TYPE,                "y",    out range_type)) // has_schema
        {
            if (type_code == "d" || type_code == "y"    // double and unsigned 8 bits; not the handle type
             || type_code == "i" || type_code == "u"    // signed and unsigned 32 bits
             || type_code == "n" || type_code == "q"    // signed and unsigned 16 bits
             || type_code == "x" || type_code == "t")   // signed and unsigned 64 bits
            {
                range_type_is_range = ((RangeType) range_type) == RangeType.RANGE;
                add_row_from_label (FORCED_RANGE_FIELD_DESCRIPTION,
                /* Translators: field content when displaying key properties; "Yes" if the key has a range set, "No" if not */
                                                                                    range_type_is_range ? _("Yes")

                /* Translators: field content when displaying key properties; "Yes" if the key has a range set, "No" if not */
                                                                                                        : _("No"));
            }
        }

        bool minimum_is_maximum = false;
        string tmp = "";
        tmp_string = "";
        if (properties.lookup (PropertyQuery.MINIMUM,                   "s",    out tmp_string))
            add_row_from_label (MINIMUM_FIELD_DESCRIPTION,                          tmp_string);
        if (properties.lookup (PropertyQuery.MAXIMUM,                   "s",    out tmp       ))
            add_row_from_label (MAXIMUM_FIELD_DESCRIPTION,                          tmp       );
        if (tmp != "" && tmp == tmp_string)
            minimum_is_maximum = true;

        bool has_schema_and_is_default;
        if (!has_schema)
            has_schema_and_is_default = false;
        else if (!properties.lookup (PropertyQuery.IS_DEFAULT,          "b",    out has_schema_and_is_default))
            assert_not_reached ();

        if (properties.lookup (PropertyQuery.DEFAULT_VALUE,             "s",    out tmp_string))
            add_row_from_label (DEFAULT_FIELD_DESCRIPTION,                          tmp_string);
        else if (has_schema)
            assert_not_reached ();

        if ( /* has_schema && */ key_conflict == KeyConflict.HARD)
        {
            /* Translators: field content when displaying key properties; displayed instead of the value, in case of conflicting keys */
            current_value_label = new Label (_("There are conflicting definitions of this key, getting value would be either problematic or meaningless."));
            current_value_label.get_style_context ().add_class ("italic-label");
        }
        else if (has_schema_and_is_default)
            current_value_label = new Label (get_current_value_text (null));
        else
        {
            Variant key_value;
            if (!properties.lookup (PropertyQuery.KEY_VALUE,            "v",    out key_value))
                assert_not_reached ();
            current_value_label = new Label (get_current_value_text (key_value));
        }
        current_value_label.halign = Align.START;
        current_value_label.valign = Align.START;
        current_value_label.xalign = 0;
        current_value_label.yalign = 0;
        current_value_label.wrap = true;
        current_value_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        current_value_label.hexpand = true;
        current_value_label.show ();
        add_row_from_widget (CURRENT_VALUE_FIELD_DESCRIPTION, current_value_label);

        add_separator ();

        KeyEditorChild key_editor_child;
        Variant initial_value = modifications_handler.get_key_custom_value (full_name, context_id);
        switch (type_code)
        {
            case "b":       // boolean
                key_editor_child = (KeyEditorChild) new KeyEditorChildBool (initial_value.get_boolean ());                          break;

            case "i":       // int32
            case "u":       // uint32
            case "n":       // int16
            case "q":       // uint16
            case "y":       // byte (uint8)
                if (minimum_is_maximum)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.print (false));
                else
                {
                    Variant? range = null;
                    if (has_schema && range_type_is_range && !properties.lookup (PropertyQuery.RANGE_CONTENT, "v", out range))
                        assert_not_reached ();
                    key_editor_child = (KeyEditorChild) new KeyEditorChildNumberInt (initial_value, type_code, range);
                }                                                                                                                   break;

            case "d":       // double
                if (minimum_is_maximum)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.print (false));
                else
                {
                    Variant? range = null;
                    if (has_schema && range_type_is_range && !properties.lookup (PropertyQuery.RANGE_CONTENT, "v", out range))
                        assert_not_reached ();
                    key_editor_child = (KeyEditorChild) new KeyEditorChildNumberDouble (initial_value, range);
                }                                                                                                                   break;
            case "t":       // uint64
                if (minimum_is_maximum)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.print (false));
                else
                {
                    Variant? range = null;
                    if (has_schema && range_type_is_range && !properties.lookup (PropertyQuery.RANGE_CONTENT, "v", out range))
                        assert_not_reached ();
                    key_editor_child = (KeyEditorChild) new KeyEditorChildNumberUint64 (initial_value, range);
                }                                                                                                                   break;
            case "x":       // int64
                if (minimum_is_maximum)
                    key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (initial_value, initial_value.print (false));
                else
                {
                    Variant? range = null;
                    if (has_schema && range_type_is_range && !properties.lookup (PropertyQuery.RANGE_CONTENT, "v", out range))
                        assert_not_reached ();
                    key_editor_child = (KeyEditorChild) new KeyEditorChildNumberInt64 (initial_value, range);
                }                                                                                                                   break;

            case "mb":      // nullable boolean
                key_editor_child = create_child_mb (initial_value, full_name, has_schema, modifications_handler);                   break;
            case "<enum>":  // enumeration, so has_schema == true
                Variant range_content;
                if (!properties.lookup (PropertyQuery.RANGE_CONTENT,    "v",    out range_content))
                    assert_not_reached ();
                key_editor_child = create_child_enum (range_content, initial_value, full_name, modifications_handler);              break;
            case "<flags>": // flags, so has_schema == true
                Variant range_content;
                if (!properties.lookup (PropertyQuery.RANGE_CONTENT,    "v",    out range_content))
                    assert_not_reached ();
                key_editor_child = create_child_flags (full_name, context_id, range_content, initial_value, modifications_handler); break;

            case "h":       // handle type, no range allowed
                key_editor_child = (KeyEditorChild) new KeyEditorChildNumberInt (initial_value, type_code, /* range */ null);       break;

            case "()":      // empty tuple
                key_editor_child = (KeyEditorChild) new KeyEditorChildSingle (new Variant ("()", "()"), "()");                      break;

            default:        // others
                if ("a" in type_code)   // if there is an array, the variant string might be quite long, so use a textview
                    key_editor_child = (KeyEditorChild) new KeyEditorChildArray (type_code, initial_value);
                else                    // else, use a single-line entry
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

        properties.clear ();

        if ( /* has_schema && */ key_conflict == KeyConflict.HARD)
            return;

        ulong value_has_changed_handler = key_editor_child.value_has_changed.connect ((_key_editor_child, is_valid) => on_value_has_changed (modifications_handler, _key_editor_child, full_name, context_id, has_schema, type_code, is_valid));

        if (has_schema)
        {
            Switch custom_value_switch = new Switch ();
            custom_value_switch.set_can_focus (false);
            custom_value_switch.halign = Align.START;
            custom_value_switch.hexpand = true;
            custom_value_switch.show ();
            add_switch_row (USE_DEFAULT_FIELD_DESCRIPTION, custom_value_switch);

            custom_value_switch.bind_property ("active", key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            bool planned_change = modifications_handler.key_has_planned_change (full_name);
            Variant? planned_value = modifications_handler.get_key_planned_value (full_name);
            bool key_value_is_default = planned_change ? planned_value == null : has_schema_and_is_default;
            custom_value_switch.set_active (key_value_is_default);

            ulong switch_active_handler = custom_value_switch.notify ["active"].connect (() => on_custom_value_switch_toggled (modifications_handler, custom_value_switch, key_editor_child, value_has_changed_handler, full_name, context_id, type_code)); // TODO get custom_value_switch from the params
            revealer_reload_1_handler = modifications_handler.leave_delay_mode.connect ((_modifications_handler) => on_revealer_reload_1 (_modifications_handler, custom_value_switch, switch_active_handler, full_name, context_id));
            custom_value_switch.destroy.connect (() => custom_value_switch.disconnect (switch_active_handler));
        }
        else
            erase_button.set_action_target ("s", full_name);

        ulong child_activated_handler = key_editor_child.child_activated.connect (() => modifications_handler.apply_delayed_settings ());  // TODO "only" used for string-based and spin widgets
        revealer_reload_2_handler = modifications_handler.leave_delay_mode.connect ((_modifications_handler) => on_revealer_reload_2 (_modifications_handler, key_editor_child, value_has_changed_handler, full_name, context_id, has_schema));
        add_row_from_widget (CUSTOM_VALUE_FIELD_DESCRIPTION, key_editor_child, type_code, minimum_is_maximum);

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

    private static KeyEditorChild create_child_flags (string full_name, uint16 context_id, Variant range_content, Variant initial_value, ModificationsHandler modifications_handler)
    {
        KeyEditorChildFlags key_editor_child_flags = new KeyEditorChildFlags (initial_value, range_content.get_strv ());

        ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                string [] active_flags = modifications_handler.get_key_custom_value (full_name, context_id).get_strv ();
                key_editor_child_flags.update_flags (active_flags);
            });
        key_editor_child_flags.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));
        return (KeyEditorChild) key_editor_child_flags;
    }

    private static string get_current_value_text (Variant? key_value)
    {
        if (key_value == null)
            /* Translators: field content when displaying key properties; the field description is "Current value", and as the default value of the key is written near, there's just this text displayed if the key uses its default value */
            return _("Default value");
        return Key.cool_text_value_from_variant ((!) key_value);
    }

    internal bool handle_copy_text (out string copy_text) // can compile with "private", but is public 2/2
    {
        if (BaseWindow.copy_clipboard_text (out copy_text))
            return true;

        Widget? focused_row = properties_list_box.get_focus_child ();
        if (focused_row == null)
            return BaseWindow.no_copy_text (out copy_text);
        else if ((!) focused_row is PropertyRow)
            return ((PropertyRow) (!) focused_row).handle_copy_text (out copy_text);
        else    // separator
            return BaseWindow.no_copy_text (out copy_text);
    }

    private static void on_value_has_changed (ModificationsHandler _modifications_handler, KeyEditorChild key_editor_child, string full_name, uint16 context_id, bool has_schema, string type_code, bool is_valid)
    {
        if (_modifications_handler.should_delay_apply (type_code))
        {
            if (is_valid)
                _modifications_handler.add_delayed_setting (full_name, key_editor_child.get_variant (), context_id);
            else
                _modifications_handler.dismiss_change (full_name);
        }
        else if (has_schema)
            _modifications_handler.model.set_gsettings_key_value (full_name, context_id, key_editor_child.get_variant ());
        else
            _modifications_handler.model.set_dconf_key_value (full_name, key_editor_child.get_variant ());
    }

    private static void on_custom_value_switch_toggled (ModificationsHandler _modifications_handler, Switch custom_value_switch, KeyEditorChild key_editor_child, ulong value_has_changed_handler, string full_name, uint16 context_id, string type_code)
    {
        if (_modifications_handler.should_delay_apply (type_code))
        {
            if (custom_value_switch.get_active ())
                _modifications_handler.add_delayed_setting (full_name, null, context_id);
            else
            {
                Variant tmp_variant = _modifications_handler.get_key_custom_value (full_name, context_id);
                _modifications_handler.add_delayed_setting (full_name, tmp_variant, context_id);
                key_editor_child.reload (tmp_variant);
            }
        }
        else
        {
            SettingsModel model = _modifications_handler.model;
            RegistryVariantDict local_properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) PropertyQuery.KEY_VALUE));
            Variant key_value;
            if (!local_properties.lookup (PropertyQuery.KEY_VALUE, "v", out key_value))
                assert_not_reached ();
            local_properties.clear ();
            if (custom_value_switch.get_active ())
            {
                model.set_key_to_default (full_name, context_id);
                SignalHandler.block (key_editor_child, value_has_changed_handler);
                key_editor_child.reload (key_value);
                //if (type_code == "<flags>")                      let's try to live without this...
                //    key.planned_value = key.value;
                SignalHandler.unblock (key_editor_child, value_has_changed_handler);
            }
            else
                model.set_gsettings_key_value (full_name, context_id, key_value); // TODO sets key value with key value... that hurts
        }
    }

    private static void on_revealer_reload_1 (ModificationsHandler _modifications_handler, Switch custom_value_switch, ulong switch_active_handler, string full_name, uint16 context_id)
    {
        SignalHandler.block (custom_value_switch, switch_active_handler);

        RegistryVariantDict local_properties = new RegistryVariantDict.from_aqv (_modifications_handler.model.get_key_properties (full_name, context_id, (uint16) PropertyQuery.IS_DEFAULT));
        bool is_key_default;
        if (!local_properties.lookup (PropertyQuery.IS_DEFAULT, "b", out is_key_default))
            assert_not_reached ();
        local_properties.clear ();
        custom_value_switch.set_active (is_key_default);
        SignalHandler.unblock (custom_value_switch, switch_active_handler);
    }

    private static void on_revealer_reload_2 (ModificationsHandler _modifications_handler, KeyEditorChild key_editor_child, ulong value_has_changed_handler, string full_name, uint16 context_id, bool has_schema)
    {
        if (!has_schema && _modifications_handler.model.is_key_ghost (full_name))
            return;
        SignalHandler.block (key_editor_child, value_has_changed_handler);

        RegistryVariantDict local_properties = new RegistryVariantDict.from_aqv (_modifications_handler.model.get_key_properties (full_name, context_id, (uint16) PropertyQuery.KEY_VALUE));
        Variant key_value;
        if (!local_properties.lookup (PropertyQuery.KEY_VALUE, "v", out key_value))
            assert_not_reached ();
        local_properties.clear ();
        key_editor_child.reload (key_value);
        //if (type_code == "<flags>")                      let's try to live without this...
        //    key.planned_value = key.value;
        SignalHandler.unblock (key_editor_child, value_has_changed_handler);
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

    private void add_row_from_widget (string property_name, Widget widget, string? type = null, bool minimum_is_maximum = false)
    {
        PropertyRow row = new PropertyRow.from_widgets (property_name, widget, type != null ? add_warning ((!) type, minimum_is_maximum) : null);
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

    private static Widget? add_warning (string type, bool minimum_is_maximum)
    {
        if (type == "d")    // TODO if type contains "d"; on Intl.get_language_names ()[0] != "C"?
        {
            if (minimum_is_maximum)
                return null;
            /* Translators: annotation under the entry that allows customizing a key, when displaying key properties; for keys of type "double" */
            return warning_label (_("Use a dot as decimal mark and no thousands separator. You can use the X.Ye+Z notation."));
        }

        if ("v" in type)
        {
            string docs_url = "https://docs.gtk.org/glib/gvariant-text-format.html";
            /* Translators: annotation under the entry that allows customizing a key, when displaying key properties; for keys of type "variant" (or of a type composed with a variant) */
            return warning_label (_("Variants content should be surrounded by XML brackets (‘<’ and ‘>’). See %s for complete documentation.").printf (docs_url));
        }

        /* the "<flags>" special type is not concerned but has an 's' and a 'g' in it; "s", "g" and "o" types have a specific UI */
        if (type != "<flags>" && ((type != "s" && "s" in type) || (type != "g" && "g" in type)) || (type != "o" && "o" in type))
        {
            if ("m" in type)
                /* Translators: annotation under the entry that allows customizing a key, when displaying key properties; for keys of a type composed with a "maybe type" and with a string type (or similar); neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
                return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value. Strings, signatures and object paths should be surrounded by quotation marks."));
            else
                /* Translators: annotation under the entry that allows customizing a key, when displaying key properties; for keys of a type composed with a string type (or similar) */
                return warning_label (_("Strings, signatures and object paths should be surrounded by quotation marks."));
        }
        /* the "mb" type has a specific UI; the "<enum>" special type is not concerned but has an 'm' in it */
        else if (type != "mb" && type != "<enum>" && "m" in type)
            /* Translators: annotation under the entry that allows customizing a key, when displaying key properties; for keys of a type composed with a "maybe type"; neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
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

    internal bool check_reload (uint properties_hash)
    {
        if (current_key_info_hash == 0) // should not happen?
            return true;
        return current_key_info_hash == properties_hash; // TODO compare key value with editor value?
    }

    /*\
    * * Updating value
    \*/

    internal void gkey_value_push (Variant key_value, bool is_key_default)    // TODO check if there isn't a problem on conflicting keys
    {
        if (is_key_default)
            current_value_label.set_text (get_current_value_text (null));
        else
            current_value_label.set_text (get_current_value_text (key_value));
    }

    internal void dkey_value_push (Variant? key_value_or_null)
    {
        if (key_value_or_null == null)
        {
            current_value_label.get_style_context ().add_class ("italic-label");
            /* Translators: field content when displaying key properties; the field description is "Current value", this text displayed if the key, not defined by a schema, has been erased (and so has no value anymore) */
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
    [GtkChild] private unowned Overlay overlay;
    [GtkChild] private unowned Label name_label;

    private Widget? value_widget = null;

    internal PropertyRow.from_label (string property_name, string property_value, bool use_italic)
    {
        name_label.set_text (property_name);

        Label value_label = new Label (property_value);
        value_widget = value_label;
        value_label.hexpand = true;
        value_label.halign = Align.FILL;
        value_label.valign = Align.START;
        value_label.xalign = 0;
        value_label.yalign = 0;
        value_label.wrap = true;
        value_label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        value_label.selectable = true;
        value_label.can_focus = false;

        StyleContext context = value_label.get_style_context ();
        if (use_italic)
            context.add_class ("italic-label");
        context.add_class ("property-value");

        value_label.show ();
        overlay.add (value_label);
    }

    internal PropertyRow.from_widgets (string property_name, Widget widget, Widget? warning)
    {
        name_label.set_text (property_name);

        if (widget is Label)    // TODO handle other rows
            value_widget = widget;

        Grid grid = new Grid ();
        grid.orientation = Orientation.VERTICAL;
        grid.add (widget);

        StyleContext context = grid.get_style_context ();
        context.add_class ("property-value");

        if (warning != null)
        {
            ((!) warning).hexpand = true;
            ((!) warning).halign = Align.CENTER;
            ((!) warning).get_style_context ().add_class ("property-warning");
            ((!) warning).show ();
            grid.add ((!) warning);
        }

        grid.show ();
        overlay.add (grid);
        grid.valign = Align.CENTER;
    }

    internal bool handle_copy_text (out string copy_text)
    {
        if (value_widget != null)
        {
            copy_text = ((Label) (!) value_widget).get_label ();
            return true;
        }
        else
            return BaseWindow.no_copy_text (out copy_text);
    }
}
