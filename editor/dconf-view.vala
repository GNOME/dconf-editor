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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-editor.ui")]
private class KeyEditor : Dialog
{
    [GtkChild] private Label schema_label;
    [GtkChild] private Label summary_label;
    [GtkChild] private Label description_label;
    [GtkChild] private Label type_label;
    [GtkChild] private Label default_label;

    [GtkChild] private Button button_apply;
    [GtkChild] private Switch custom_value_switch;
    [GtkChild] private Grid custom_value_grid;

    private Key key;
    private bool custom_value_is_valid = true;

    public KeyEditor (Key _key)
        requires (_key.has_schema)
    {
        Object (use_header_bar: Gtk.Settings.get_default ().gtk_dialogs_use_header ? 1 : 0);

        this.key = _key;

        // infos
        this.title = key.name;
        if (this.use_header_bar == 1)        // TODO else..?
            ((HeaderBar) this.get_header_bar ()).subtitle = key.parent.full_name;       // TODO get_header_bar() is [transfer none]

        string? gettext_domain = key.schema.gettext_domain;

        string summary = key.schema.summary ?? "";
        if (gettext_domain != null && summary != "")
            summary = dgettext (gettext_domain, summary);

        string description = key.schema.description ?? "";
        if (gettext_domain != null && description != "")
            description = dgettext (gettext_domain, description);

        schema_label.set_text (key.schema.schema.id);
        summary_label.set_text (summary.strip ());
        description_label.set_text (description.strip ());
        type_label.set_text (key_to_description ());
        default_label.set_text (key.schema.default_value.print (false));

        // widgets creation

        custom_value_switch.set_active (key.is_default);
        custom_value_switch.notify["active"].connect (() => { button_apply.set_sensitive (custom_value_switch.get_active () ? true : custom_value_is_valid); });

        custom_value_grid.add (create_child ());

        this.response.connect (response_cb);
    }

    private KeyEditorChild create_child ()
    {
        if (key.schema.choices != null)
            return new KeyEditorChildMulti (key);

        switch (key.type_string)
        {
            case "<enum>":
                return new KeyEditorChildMulti (key);
            case "b":
                return new KeyEditorChildBool (key.value.get_boolean ());
            case "s":
                return new KeyEditorChildString (key.value.get_string ());
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
            case "d":
                return new KeyEditorChildNumber (key);
            default:
                KeyEditorChildDefault key_editor_child_default = new KeyEditorChildDefault (key.type_string, key.value);
                key_editor_child_default.is_valid.connect ((is_valid) => { custom_value_is_valid = is_valid; button_apply.set_sensitive (is_valid); });
                return key_editor_child_default;
        }
    }

    private string key_to_description ()
    {
        switch (key.type_string)
        {
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":
                Variant min, max;
                if (key.schema.range != null)
                {
                    min = key.schema.range.min;
                    max = key.schema.range.max;
                }
                else
                {
                    string variant_type = key.value.get_type_string ();
                    min = Key.get_min (variant_type);
                    max = Key.get_max (variant_type);
                }
                return _("Integer [%s..%s]").printf (min.print (false), max.print (false));
            case "d":
                Variant min, max;
                if (key.schema.range != null)
                {
                    min = key.schema.range.min;
                    max = key.schema.range.max;
                }
                else
                {
                    string variant_type = key.value.get_type_string ();
                    min = Key.get_min (variant_type);
                    max = Key.get_max (variant_type);
                }
                return _("Double [%s..%s]").printf (min.print (false), max.print (false));
            case "b":
                return _("Boolean");
            case "s":
                return _("String");
            case "<enum>":
                return _("Enumeration");
            default:
                return key.schema.type;
        }
    }

    private void response_cb (Dialog dialog, int response_id)
    {
        if (response_id == ResponseType.APPLY)
        {
            if (!custom_value_switch.active)
            {
                Variant variant = ((KeyEditorChild) custom_value_grid.get_child_at (0, 0)).get_variant ();
                if (key.is_default || key.value != variant)
                    key.value = variant;
            }
            else if (!key.is_default)
                key.set_to_default ();
        }
        this.destroy ();
    }
}

public interface KeyEditorChild : Widget
{
    public abstract Variant get_variant ();
}

private class KeyEditorChildMulti : Grid, KeyEditorChild
{
    private ContextPopover popover;

    private Variant variant;

    public KeyEditorChildMulti (Key key)
    {
        this.variant = key.value;

        this.visible = true;
        this.hexpand = true;

        Label label = new Label (_("Custom Value"));
        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.attach (label, 0, 0, 1, 1);

        MenuButton button = new MenuButton ();
        button.visible = true;
        button.use_popover = true;
        button.halign = Align.END;
        button.width_request = 100;
        button.label = variant.get_type () == VariantType.STRING ? variant.get_string () : variant.print (false);
        this.attach (button, 1, 0, 1, 1);

        popover = new ContextPopover ();
        popover.create_buttons_list (key, false);
        popover.set_relative_to (button);
        popover.value_changed.connect ((bytes) => {
                variant = new Variant.from_bytes (key.value.get_type (), bytes, true);
                button.label = variant.get_type () == VariantType.STRING ? variant.get_string () : variant.print (false);
                popover.closed ();
            });
        button.set_popover ((Popover) popover);
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

        Label label = new Label (_("Custom Value"));
        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.attach (label, 0, 0, 1, 1);

        Grid grid = new Grid ();
        grid.visible = true;
        grid.halign = Align.END;
        grid.column_homogeneous = true;
        grid.width_request = 100;
        ((StyleContext) grid.get_style_context ()).add_class ("linked");
        this.attach (grid, 1, 0, 1, 1);

        ToggleButton button_false = new ToggleButton ();
        button_false.visible = true;
        button_false.label = _("False");
        grid.attach (button_false, 0, 0, 1, 1);

        button_true = new ToggleButton ();
        button_true.visible = true;
        button_true.label = _("True");
        grid.attach (button_true, 1, 0, 1, 1);

        button_true.active = initial_value;
        button_true.bind_property ("active", button_false, "active", BindingFlags.INVERT_BOOLEAN|BindingFlags.SYNC_CREATE|BindingFlags.BIDIRECTIONAL);
    }

    public Variant get_variant ()
    {
        return new Variant.boolean (button_true.active);
    }
}

private class KeyEditorChildNumber : Grid, KeyEditorChild
{
    private SpinButton spin;
    private string key_type;

    public KeyEditorChildNumber (Key key)
    {
        this.key_type = key.type_string;

        this.visible = true;
        this.hexpand = true;

        Label label = new Label (_("Custom Value"));
        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.attach (label, 0, 0, 1, 1);

        bool has_range = /* key.has_schema && */ key.schema.range != null;
        double min = get_variant_as_double ((has_range && key.schema.range.min != null) ? key.schema.range.min : Key.get_min (key.value.get_type_string ()));
        double max = get_variant_as_double ((has_range && key.schema.range.max != null) ? key.schema.range.max : Key.get_max (key.value.get_type_string ()));

        if (key.type_string == "d")
        {
            Adjustment adjustment = new Adjustment (key.value.get_double (), min, max, 0.01, 0.1, 0.0);
            spin = new SpinButton (adjustment, 0.01, 2);
        }
        else
        {
            Adjustment adjustment = new Adjustment (get_variant_as_double (key.value), min, max, 1.0, 5.0, 0.0);
            spin = new SpinButton (adjustment, 1.0, 0);
        }

        spin.visible = true;
        spin.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        spin.snap_to_ticks = true;
        spin.input_purpose = InputPurpose.NUMBER;   // TODO spin.input_purpose = InputPurpose.DIGITS & spin.numeric = true; (no “e”) if not double?
        spin.width_chars = 30;
        this.attach (spin, 1, 0, 1, 1);
    }

    private static double get_variant_as_double (Variant variant)
        requires (variant != null)      // TODO is that realllly useful? it shouldn't...
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
            default:                    assert_not_reached ();
        }
    }

    public Variant get_variant ()
    {
        switch (key_type)
        {
            case "y": return new Variant.byte   ((uchar) spin.get_value ());
            case "n": return new Variant.int16  ((int16) spin.get_value ());
            case "q": return new Variant.uint16 ((uint16) spin.get_value ());
            case "i": return new Variant.int32  ((int) spin.get_value ());
            case "u": return new Variant.uint32 ((int) spin.get_value ());
            case "x": return new Variant.int64  ((int) spin.get_value ());
            case "t": return new Variant.uint64 ((int) spin.get_value ());
            case "d": return new Variant.double (spin.get_value ());
            default : assert_not_reached ();
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

        this.buffer.deleted_text.connect (test_value);
        this.buffer.inserted_text.connect (test_value);
        test_value ();
    }

    private void test_value ()
    {
        try
        {
            Variant? tmp_variant = Variant.parse (new VariantType (variant_type), this.text);
            variant = tmp_variant;
            is_valid (true);
        }
        catch (VariantParseError e)
        {
            is_valid (false);
        }
    }

    public Variant get_variant ()
    {
        return variant;
    }
}
