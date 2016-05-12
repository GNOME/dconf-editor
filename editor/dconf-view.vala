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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/property-row.ui")]
private class PropertyRow : ListBoxRow
{
    bool locked = false;

    [GtkChild] private Grid grid;
    [GtkChild] private Label name_label;

    public string label { get; construct; }

    construct
    {
        name_label.set_text (label);
    }

    public void set_text (string text)
        requires (locked == false)  /* TODO some properties can be edited after construction */
    {
        Label value_label = new Label (text);
        value_label.valign = Align.START;
        value_label.xalign = 0;
        value_label.yalign = 0;
        value_label.wrap = true;
        value_label.selectable = true;
        value_label.max_width_chars = 42;
        value_label.width_chars = 42;
        value_label.show ();
        grid.attach (value_label, 1, 0, 1, 1);

        locked = true;
    }

    public void set_widget (Widget widget, Widget? warning)
        requires (locked == false)
    {
        grid.attach (widget, 1, 0, 1, 1);
        widget.valign = Align.CENTER;

        if (warning != null)
        {
            grid.row_spacing = 4;
            grid.attach ((!) warning, 0, 1, 2, 1);
            warning.hexpand = true;
            warning.halign = Align.CENTER;
        }

        locked = true;
    }

    public Switch set_switch ()
        requires (locked == false)
    {
        Switch custom_value_switch = new Switch ();
        custom_value_switch.width_request = 100; /* same request than for button_cancel/button_apply on scale 1; TODO better */
        custom_value_switch.halign = Align.END;
        custom_value_switch.hexpand = true;
        custom_value_switch.valign = Align.CENTER;
        custom_value_switch.show ();
        grid.attach (custom_value_switch, 1, 0, 1, 1);

        locked = true;

        return custom_value_switch;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-editor.ui")]
private abstract class KeyEditorDialog : Dialog
{
    [GtkChild] protected Button button_apply;
    [GtkChild] protected InfoBar no_schema_warning;
    [GtkChild] private PropertyRow schema_row;
    [GtkChild] private PropertyRow summary_row;
    [GtkChild] private PropertyRow description_row;
    [GtkChild] private PropertyRow type_row;
    [GtkChild] private PropertyRow minimum_row;
    [GtkChild] private PropertyRow maximum_row;
    [GtkChild] private PropertyRow default_row;
    [GtkChild] protected PropertyRow custom_value_row;
    [GtkChild] protected PropertyRow value_row;

    protected bool custom_value_is_valid { get; set; default = true; }
    protected KeyEditorChild key_editor_child;

    public KeyEditorDialog ()
    {
        Object (use_header_bar: Gtk.Settings.get_default ().gtk_dialogs_use_header ? 1 : 0);
        this.response.connect ((dialog, response_id) => { if (response_id == ResponseType.APPLY) response_apply_cb (); else this.destroy (); });
    }

    private void response_apply_cb () { on_response_apply (); this.destroy (); }

    protected abstract void on_response_apply ();

    protected void setup_rows (bool has_schema, Variant dict)
    {
        if (has_schema)
        {
            no_schema_warning.destroy ();
        }
        else
        {
            custom_value_row.destroy ();
            no_schema_warning.show ();
        }

        // TODO use VariantDict
        string tmp_string;
        if (dict.lookup ("schema-id",     "s", out tmp_string))      schema_row.set_text (tmp_string);
        else schema_row.destroy ();
        if (dict.lookup ("summary",       "s", out tmp_string))     summary_row.set_text (tmp_string);
        else summary_row.destroy ();
        if (dict.lookup ("description",   "s", out tmp_string)) description_row.set_text (tmp_string);
        else description_row.destroy ();
        if (dict.lookup ("type-name",     "s", out tmp_string))        type_row.set_text (tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string))     minimum_row.set_text (tmp_string);
        else minimum_row.destroy ();
        if (dict.lookup ("maximum",       "s", out tmp_string))     maximum_row.set_text (tmp_string);
        else maximum_row.destroy ();
        if (dict.lookup ("default-value", "s", out tmp_string))     default_row.set_text (tmp_string);
        else default_row.destroy ();
    }

    protected Widget create_child (Key key)
    {
        switch (key.type_string)
        {
            case "<enum>":
                KeyEditorChildEnum _key_editor_child = new KeyEditorChildEnum (key);
                key_editor_child = (KeyEditorChild) _key_editor_child;
                return (Widget) _key_editor_child;
            case "<flags>":
                KeyEditorChildFlags _key_editor_child = new KeyEditorChildFlags ((GSettingsKey) key);
                key_editor_child = (KeyEditorChild) _key_editor_child;
                return (Widget) _key_editor_child;
            case "b":
                KeyEditorChildBool _key_editor_child = new KeyEditorChildBool (key.value.get_boolean ());
                key_editor_child = (KeyEditorChild) _key_editor_child;
                return (Widget) _key_editor_child;
            case "s":
                KeyEditorChildString _key_editor_child = new KeyEditorChildString (key.value.get_string ());
                key_editor_child = (KeyEditorChild) _key_editor_child;
                key_editor_child.child_activated.connect (response_apply_cb);
                return (Widget) _key_editor_child;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
            case "d":
            case "h":
                KeyEditorChildNumber _key_editor_child = new KeyEditorChildNumber (key);
                key_editor_child = (KeyEditorChild) _key_editor_child;
                key_editor_child.child_activated.connect (response_apply_cb);
                return (Widget) _key_editor_child;
            case "mb":
                KeyEditorChildNullableBool _key_editor_child = new KeyEditorChildNullableBool (key);
                key_editor_child = (KeyEditorChild) _key_editor_child;
                return (Widget) _key_editor_child;
            default:
                KeyEditorChildDefault _key_editor_child = new KeyEditorChildDefault (key.type_string, key.value);
                _key_editor_child.is_valid.connect ((is_valid) => { custom_value_is_valid = is_valid; });
                key_editor_child = (KeyEditorChild) _key_editor_child;
                key_editor_child.child_activated.connect (response_apply_cb);
                return (Widget) _key_editor_child;
        }
    }

    protected Widget? add_warning (Key key)
    {
        if (key.type_string != "<flags>" && (("s" in key.type_string && key.type_string != "s") || "g" in key.type_string) || "o" in key.type_string)
        {
            if ("m" in key.type_string)
                /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
                return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value. Strings, signatures and object paths should be surrounded by quotation marks."));
            else
                return warning_label (_("Strings, signatures and object paths should be surrounded by quotation marks."));
        }
        else if ("m" in key.type_string && key.type_string != "m" && key.type_string != "mb" && key.type_string != "<enum>")
            /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
            return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value."));
        return null;
    }
    private Widget warning_label (string text)
    {
        Label label = new Label ("<i>" + text + "</i>");
        label.visible = true;
        label.use_markup = true;
        label.max_width_chars = 59;
        label.wrap = true;
        label.halign = Align.START;
        return (Widget) label;
    }
}

private class KeyEditorNoSchema : KeyEditorDialog       // TODO add type information, or integrate type information in KeyEditorChilds; doesn't have a "Custom value" text
{
    private DConfKey key;

    public KeyEditorNoSchema (DConfKey _key)
    {
        key = _key;

        this.title = key.name;
        if (this.use_header_bar == 1)        // TODO else..?
            ((HeaderBar) this.get_header_bar ()).subtitle = ((!) key.parent).full_name;   // TODO get_header_bar() is [transfer none]

        value_row.set_widget (create_child ((Key) _key), add_warning ((Key) _key));

        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);
        setup_rows (has_schema, dict_container [0]);

        notify ["custom-value-is-valid"].connect (() => { button_apply.set_sensitive (custom_value_is_valid); });
    }

    protected override void on_response_apply ()
    {
        Variant variant = key_editor_child.get_variant ();
        if (key.value != variant)
            key.value = variant;
    }
}

private class KeyEditor : KeyEditorDialog
{
    private Switch custom_value_switch;

    protected GSettingsKey key;

    public KeyEditor (GSettingsKey _key)
    {
        key = _key;

        this.title = key.name;
        if (this.use_header_bar == 1)        // TODO else..?
            ((HeaderBar) this.get_header_bar ()).subtitle = ((!) key.parent).full_name;   // TODO get_header_bar() is [transfer none]

        // infos

        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);
        setup_rows (has_schema, dict_container [0]);

        // actions

        Widget _key_editor_child = create_child ((Key) key);
        value_row.set_widget (_key_editor_child, add_warning ((Key) _key));

        custom_value_switch = custom_value_row.set_switch ();
        custom_value_switch.bind_property ("active", _key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

        // switch

        custom_value_switch.set_active (key.is_default);
        custom_value_switch.notify ["active"].connect (() => { button_apply.set_sensitive (custom_value_switch.get_active () ? true : custom_value_is_valid); });
        notify ["custom-value-is-valid"].connect (() => { button_apply.set_sensitive (custom_value_is_valid); });
    }

    protected override void on_response_apply ()
    {
        if (!custom_value_switch.active)
        {
            Variant variant = key_editor_child.get_variant ();
            if (key.value != variant)
                key.value = variant;
        }
        else if (!key.is_default)
            key.set_to_default ();
    }
}

public interface KeyEditorChild : Widget
{
    public abstract Variant get_variant ();
    public signal void child_activated ();
}

private class KeyEditorChildEnum : MenuButton, KeyEditorChild
{
    private Variant variant;

    public KeyEditorChildEnum (Key key)
    {
        this.variant = key.value;

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;
        this.use_popover = true;
        this.width_request = 100;
        this.label = variant.get_type () == VariantType.STRING ? variant.get_string () : variant.print (false);

        ContextPopover popover = new ContextPopover ();
        popover.create_buttons_list (key, false);
        popover.set_relative_to (this);
        popover.value_changed.connect ((gvariant) => {
                variant = gvariant;
                this.label = gvariant.get_type () == VariantType.STRING ? gvariant.get_string () : gvariant.print (false);
                popover.closed ();
            });
        this.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }
}

private class KeyEditorChildFlags : Grid, KeyEditorChild
{
    private Variant variant;

    public KeyEditorChildFlags (GSettingsKey key)
    {
        this.variant = key.value;

        this.visible = true;
        this.hexpand = true;

        Label label = new Label (variant.print (false));
        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.attach (label, 0, 0, 1, 1);

        MenuButton button = new MenuButton ();
        button.visible = true;
        button.use_popover = true;
        button.halign = Align.END;
        ((StyleContext) button.get_style_context ()).add_class ("image-button");
        this.attach (button, 1, 0, 1, 1);

        ContextPopover popover = new ContextPopover ();
        popover.create_flags_list (key);
        popover.set_relative_to (button);
        popover.value_changed.connect ((gvariant) => {
                variant = gvariant;
                label.label = gvariant.print (false);
            });
        button.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }
}

private class KeyEditorChildNullableBool : MenuButton, KeyEditorChild
{
    private Variant variant;

    public KeyEditorChildNullableBool (Key key)
    {
        this.variant = key.value;
        Variant? maybe_variant = variant.get_maybe ();

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;
        this.use_popover = true;
        this.width_request = 100;
        if (maybe_variant == null)
            this.label = Key.cool_boolean_text_value (null);
        else
            this.label = Key.cool_boolean_text_value (((!) maybe_variant).get_boolean ());

        ContextPopover popover = new ContextPopover ();
        popover.create_buttons_list (key, false);
        popover.set_relative_to (this);
        popover.value_changed.connect ((gvariant) => {
                variant = gvariant;
                maybe_variant = gvariant.get_maybe ();
                if (maybe_variant == null)
                    this.label = Key.cool_boolean_text_value (null);
                else
                    this.label = Key.cool_boolean_text_value (((!) maybe_variant).get_boolean ());
                popover.closed ();
            });
        this.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }
}

private class KeyEditorChildBool : Grid, KeyEditorChild // might be managed by action, but can't find a way to ensure one-and-only-one button is active
{
    private ToggleButton button_true;

    public KeyEditorChildBool (bool initial_value)
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;
        this.column_homogeneous = true;
        this.width_request = 100;
        ((StyleContext) this.get_style_context ()).add_class ("linked");

        ToggleButton button_false = new ToggleButton ();
        button_false.visible = true;
        button_false.label = Key.cool_boolean_text_value (false);
        this.attach (button_false, 0, 0, 1, 1);

        button_true = new ToggleButton ();
        button_true.visible = true;
        button_true.label = Key.cool_boolean_text_value (true);
        this.attach (button_true, 1, 0, 1, 1);

        button_true.active = initial_value;
        button_true.bind_property ("active", button_false, "active", BindingFlags.INVERT_BOOLEAN|BindingFlags.SYNC_CREATE|BindingFlags.BIDIRECTIONAL);
    }

    public Variant get_variant ()
    {
        return new Variant.boolean (button_true.active);
    }
}

private class KeyEditorChildNumber : SpinButton, KeyEditorChild
{
    private string key_type;

    public KeyEditorChildNumber (Key key)
    {
        this.key_type = key.type_string;

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;

        double min, max;
        if (key.has_schema && ((GSettingsKey) key).range_type == "range")    // TODO test more; and what happen if only min/max is in range?
        {
            min = get_variant_as_double (((GSettingsKey) key).range_content.get_child_value (0));
            max = get_variant_as_double (((GSettingsKey) key).range_content.get_child_value (1));
        }
        else
            get_min_and_max_double (out min, out max, key.type_string);

        if (key.type_string == "d")
        {
            Adjustment adjustment = new Adjustment (key.value.get_double (), min, max, 0.01, 0.1, 0.0);
            this.configure (adjustment, 0.01, 2);
        }
        else
        {
            Adjustment adjustment = new Adjustment (get_variant_as_double (key.value), min, max, 1.0, 5.0, 0.0);
            this.configure (adjustment, 1.0, 0);
        }

        this.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        this.snap_to_ticks = true;
        this.input_purpose = InputPurpose.NUMBER;   // TODO spin.input_purpose = InputPurpose.DIGITS & spin.numeric = true; (no “e”) if not double?
        this.width_chars = 30;
        this.activate.connect (() => { child_activated (); });
    }

    private static void get_min_and_max_double (out double min, out double max, string variant_type)
    {
        switch (variant_type)
        {
            case "y": min = (double) uint8.MIN;     max = (double) uint8.MAX;   break;
            case "n": min = (double) int16.MIN;     max = (double) int16.MAX;   break;
            case "q": min = (double) uint16.MIN;    max = (double) uint16.MAX;  break;
            case "i": min = (double) int32.MIN;     max = (double) int32.MAX;   break;
            case "u": min = (double) uint32.MIN;    max = (double) uint32.MAX;  break;
            case "x": min = (double) int64.MIN;     max = (double) int64.MAX;   break;
            case "t": min = (double) uint64.MIN;    max = (double) uint64.MAX;  break;
            case "d": min = (double) double.MIN;    max = (double) double.MAX;  break;
            case "h": min = (double) int32.MIN;     max = (double) int32.MAX;   break;
            default: assert_not_reached ();
        }
    }

    private static double get_variant_as_double (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.BYTE:    return (double) variant.get_byte ();
            case Variant.Class.INT16:   return (double) variant.get_int16 ();
            case Variant.Class.UINT16:  return (double) variant.get_uint16 ();
            case Variant.Class.INT32:   return (double) variant.get_int32 ();
            case Variant.Class.UINT32:  return (double) variant.get_uint32 ();
            case Variant.Class.INT64:   return (double) variant.get_int64 ();
            case Variant.Class.UINT64:  return (double) variant.get_uint64 ();
            case Variant.Class.DOUBLE:  return variant.get_double ();
            case Variant.Class.HANDLE:  return (double) variant.get_handle ();
            default: assert_not_reached ();
        }
    }

    public Variant get_variant ()
    {
        switch (key_type)
        {
            case "y": return new Variant.byte   ((uchar) this.get_value ());        // TODO uchar or uint8?
            case "n": return new Variant.int16  ((int16) this.get_value ());
            case "q": return new Variant.uint16 ((uint16) this.get_value ());
            case "i": return new Variant.int32  ((int) this.get_value ());
            case "u": return new Variant.uint32 ((int) this.get_value ());
            case "x": return new Variant.int64  ((int) this.get_value ());
            case "t": return new Variant.uint64 ((int) this.get_value ());
            case "d": return new Variant.double (this.get_value ());
            case "h": return new Variant.handle ((int) this.get_value ());
            default: assert_not_reached ();
        }
    }
}

private class KeyEditorChildString : Entry, KeyEditorChild
{
    public KeyEditorChildString (string _text)
    {
        this.visible = true;
        this.hexpand = true;
        this.text = _text;

        this.activate.connect (() => { child_activated (); });
    }

    public Variant get_variant ()
    {
        return new Variant.string (this.text);
    }
}

private class KeyEditorChildDefault : Entry, KeyEditorChild
{
    public signal void is_valid (bool is_valid);

    private string variant_type;
    private Variant variant;

    public KeyEditorChildDefault (string type, Variant initial_value)
    {
        this.variant_type = type;
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.text = initial_value.print (false);

        this.buffer.deleted_text.connect (emit_is_valid);
        this.buffer.inserted_text.connect (emit_is_valid);
        emit_is_valid ();

        this.activate.connect (() => { if (test_value ()) child_activated (); });
    }

    private void emit_is_valid () { is_valid (test_value ()); }
    private bool test_value ()
    {
        try
        {
            Variant? tmp_variant = Variant.parse (new VariantType (variant_type), this.text);
            variant = (!) tmp_variant;
            return true;
        }
        catch (VariantParseError e)
        {
            return false;
        }
    }

    public Variant get_variant ()
    {
        return variant;
    }
}
