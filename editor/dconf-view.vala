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

public interface KeyEditorChild : Widget
{
    public signal void value_has_changed (bool enable_revealer, bool is_valid = false);

    public abstract Variant get_variant ();
    public signal void child_activated ();

    public abstract void reload (Variant gvariant);
}

private class KeyEditorChildEnum : MenuButton, KeyEditorChild
{
    private Variant variant;
    private GLib.Action action;

    public KeyEditorChildEnum (Key key)
        requires (key.type_string == "<enum>")
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;
        this.use_popover = true;
        this.width_request = 100;

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (key, false, false);
        popover.set_relative_to (this);

        popover.value_changed.connect ((gvariant) => {
                reload (gvariant);
                popover.closed ();

                value_has_changed (true, true);
            });
        reload (key.planned_change && (key.planned_value != null) ? key.planned_value : key.value);
        this.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant)
    {
        variant = gvariant;
        VariantType type = gvariant.get_type ();
        label = type == VariantType.STRING ? gvariant.get_string () : gvariant.print (false);
        action.change_state (new Variant.maybe (null, new Variant.maybe (type, gvariant)));
    }
}

private class KeyEditorChildFlags : Grid, KeyEditorChild
{
    private Variant variant;
    private Label label = new Label ("");

    public KeyEditorChildFlags (GSettingsKey key)
        requires (key.type_string == "<flags>")
    {
        this.visible = true;
        this.hexpand = true;

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
                reload (gvariant);
                value_has_changed (true, true);
            });
        reload (key.planned_change && (key.planned_value != null) ? key.planned_value : key.value);
        button.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant)
    {
        this.variant = gvariant;
        label.label = gvariant.print (false);
        value_has_changed (false);
    }
}

private class KeyEditorChildNullableBool : MenuButton, KeyEditorChild
{
    private Variant variant;
    private Variant? maybe_variant;
    private GLib.Action action;

    public KeyEditorChildNullableBool (Key key)
        requires (key.type_string == "mb")
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;
        this.use_popover = true;
        this.width_request = 100;

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (key, false, false);
        popover.set_relative_to (this);

        popover.value_changed.connect ((gvariant) => {
                reload (gvariant);
                popover.closed ();

                value_has_changed (true, true);
            });
        reload (key.planned_change && (key.planned_value != null) ? key.planned_value : key.value);
        this.set_popover ((Popover) popover);
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant)
    {
        variant = gvariant;
        maybe_variant = variant.get_maybe ();

        if (maybe_variant == null)
            label = Key.cool_boolean_text_value (null);
        else
            label = Key.cool_boolean_text_value (((!) maybe_variant).get_boolean ());

        action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType ("mb"), gvariant)));
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

        button_true.toggled.connect (() => { value_has_changed (true, true); });
    }

    public Variant get_variant ()
    {
        return new Variant.boolean (button_true.active);
    }

    public void reload (Variant gvariant)
    {
        button_true.active = gvariant.get_boolean ();
        value_has_changed (false);
    }
}

private class KeyEditorChildNumberDouble : SpinButton, KeyEditorChild
{
    private uint locked = 0;

    public KeyEditorChildNumberDouble (Key key)
        requires (key.type_string == "d")
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;

        double min, max;
        if (key.has_schema && ((GSettingsKey) key).range_type == "range")
        {
            min = (((GSettingsKey) key).range_content.get_child_value (0)).get_double ();
            max = (((GSettingsKey) key).range_content.get_child_value (1)).get_double ();
        }
        else
        {
            min = double.MIN;
            max = double.MAX;
        }

        Adjustment adjustment = new Adjustment (key.planned_change && (key.planned_value != null) ? key.planned_value.get_double () : key.value.get_double (), min, max, 0.01, 0.1, 0.0);
        this.configure (adjustment, 0.01, 2);

        this.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        this.snap_to_ticks = false;
        this.input_purpose = InputPurpose.NUMBER;
        this.width_chars = 30;

        this.buffer.deleted_text.connect (() => { if (locked > 0) locked -= 1; else value_has_changed (true, true); });     // TODO test value for
        this.buffer.inserted_text.connect (() => { if (locked > 0) locked -= 1; else value_has_changed (true, true); });    //   non-numeric chars
        this.activate.connect (() => { update (); child_activated (); });
    }

    public Variant get_variant ()
    {
        return new Variant.double (this.get_value ());
    }

    public void reload (Variant gvariant)
    {
        locked = 2;
        this.set_value (gvariant.get_double ());
        value_has_changed (false);  // set disable_revealer_for_value to false, might be useful for corner cases
    }
}

private class KeyEditorChildNumberInt : SpinButton, KeyEditorChild
{
    private string key_type;
    private uint locked = 0;

    public KeyEditorChildNumberInt (Key key)
        requires (key.type_string == "y" || key.type_string == "n" || key.type_string == "q" || key.type_string == "i" || key.type_string == "u" || key.type_string == "h")     // TODO key.type_string == "x" || key.type_string == "t" ||
    {
        this.key_type = key.type_string;

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.END;

        double min, max;
        if (key.has_schema && ((GSettingsKey) key).range_type == "range")
        {
            min = get_variant_as_double (((GSettingsKey) key).range_content.get_child_value (0));
            max = get_variant_as_double (((GSettingsKey) key).range_content.get_child_value (1));
        }
        else
            get_min_and_max_double (out min, out max, key.type_string);

        Adjustment adjustment = new Adjustment (get_variant_as_double (key.planned_change && (key.planned_value != null) ? key.planned_value : key.value), min, max, 1.0, 5.0, 0.0);
        this.configure (adjustment, 1.0, 0);

        this.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        this.snap_to_ticks = true;
        this.numeric = true;
        this.input_purpose = InputPurpose.NUMBER;   // TODO could be DIGITS for UnsignedInt
        this.width_chars = 30;

        this.buffer.deleted_text.connect (() => { if (locked > 0) locked -= 1; else value_has_changed (true, true); });     // TODO test value for
        this.buffer.inserted_text.connect (() => { if (locked > 0) locked -= 1; else value_has_changed (true, true); });    //   non-numeric chars
        this.activate.connect (() => { update (); child_activated (); });
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
            case Variant.Class.HANDLE:  return (double) variant.get_handle ();
            default: assert_not_reached ();
        }
    }

    public Variant get_variant ()
    {
        switch (key_type)
        {
            case "y": return new Variant.byte   ((uchar) this.get_value_as_int ());     // TODO uchar or uint8?
            case "n": return new Variant.int16  ((int16) this.get_value_as_int ());
            case "q": return new Variant.uint16 ((uint16) this.get_value_as_int ());
            case "i": return new Variant.int32  (this.get_value_as_int ());
            case "u": return new Variant.uint32 ((uint32) this.get_value ());           // TODO also use get_value_as_int?
            case "h": return new Variant.handle (this.get_value_as_int ());
            default: assert_not_reached ();
        }
    }

    public void reload (Variant gvariant)
    {
        locked = 2;
        this.set_value (get_variant_as_double (gvariant));
        value_has_changed (false);  // set disable_revealer_for_value to false, might be useful for corner cases
    }
}

private class KeyEditorChildDefault : Entry, KeyEditorChild
{
    private string variant_type;
    private Variant variant;
    private bool is_string;
    private bool locked = false;

    public KeyEditorChildDefault (string type, Variant initial_value)
    {
        this.variant_type = type;
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;
        this.set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("This value is invalid for the key type."));    // TODO report bug, not displayed, neither like that nor by setting secondary_icon_tooltip_text

        this.is_string = type == "s" || type == "o" || type == "g";
        this.text = is_string ? initial_value.get_string () : initial_value.print (false);

        this.buffer.deleted_text.connect (() => { if (!locked) value_has_changed (true, test_value ()); });
        this.buffer.inserted_text.connect (() => { if (!locked) value_has_changed (true, test_value ()); });
        this.activate.connect (() => { if (test_value ()) child_activated (); });
        value_has_changed (true, test_value ());
    }

    private bool test_value ()
    {
        if (variant_type == "s")
        {
            variant = new Variant.string (this.text);
            return true;
        }
        try
        {
            string tmp_text = is_string ? @"'$text'" : this.text;
            Variant? tmp_variant = Variant.parse (new VariantType (variant_type), tmp_text);
            variant = (!) tmp_variant;

            StyleContext context = get_style_context ();
            if (context.has_class ("error"))
                context.remove_class ("error");
            secondary_icon_name = null;

            return true;
        }
        catch (VariantParseError e)
        {
            StyleContext context = get_style_context ();
            if (!context.has_class ("error"))
                context.add_class ("error");
            secondary_icon_name = "dialog-error-symbolic";

            return false;
        }
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant)
    {
        locked = true;
        this.text = is_string ? gvariant.get_string () : gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        locked = false;
    }
}
