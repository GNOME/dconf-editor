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

public interface KeyEditorChild : Widget
{
    public signal void value_has_changed (bool is_valid = true);

    public abstract Variant get_variant ();
    public signal void child_activated ();

    public abstract void reload (Variant gvariant);
}

private class KeyEditorChildSingle : Label, KeyEditorChild
{
    private Variant variant;

    public KeyEditorChildSingle (Variant key_value, string text)
    {
        variant = key_value;
        set_label (text);
        show ();
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant) {}
}

private class KeyEditorChildEnum : MenuButton, KeyEditorChild
{
    private Variant variant;
    private GLib.Action action;

    public KeyEditorChildEnum (Variant initial_value, bool delay_mode, bool has_planned_change, Variant range_content)
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;
        this.use_popover = true;
        this.width_request = 100;

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (false, delay_mode, has_planned_change, "<enum>", initial_value, range_content);
        popover.set_relative_to (this);

        popover.value_changed.connect ((gvariant) => {
                if (gvariant == null)   // TODO better (1/3)
                    assert_not_reached ();
                reload ((!) gvariant);
                popover.closed ();

                value_has_changed ();
            });
        reload (initial_value);
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
    private string [] all_flags;
    private ContextPopover popover = new ContextPopover ();

    private Variant variant;
    private Label label = new Label ("");

    public KeyEditorChildFlags (Variant initial_value, string [] _all_flags, string [] active_flags)
    {
        all_flags = _all_flags;
        this.visible = true;
        this.hexpand = true;
        this.orientation = Orientation.HORIZONTAL;
        this.column_spacing = 8;

        MenuButton button = new MenuButton ();
        button.visible = true;
        button.use_popover = true;
        button.halign = Align.START;
        button.get_style_context ().add_class ("image-button");
        this.add (button);

        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.add (label);

        popover.create_flags_list (active_flags, all_flags);
        popover.set_relative_to (button);
        popover.value_changed.connect ((gvariant) => {
                if (gvariant == null)   // TODO better (2/3)
                    assert_not_reached ();
                reload ((!) gvariant);
                value_has_changed ();
            });
        reload (initial_value);
        button.set_popover ((Popover) popover);
    }

    public void update_flags (string [] active_flags)
    {
        foreach (string flag in all_flags)
            popover.update_flag_status (flag, flag in active_flags);
    }

    public Variant get_variant ()
    {
        return variant;
    }

    public void reload (Variant gvariant)
    {
        this.variant = gvariant;
        label.label = gvariant.print (false);
    }
}

private class KeyEditorChildNullableBool : MenuButton, KeyEditorChild
{
    private Variant variant;
    private Variant? maybe_variant;
    private GLib.Action action;

    public KeyEditorChildNullableBool (Variant initial_value, bool delay_mode, bool has_planned_change, Variant? range_content_or_null)
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;
        this.use_popover = true;
        this.width_request = 100;

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (false, delay_mode, has_planned_change, "mb", initial_value, range_content_or_null);
        popover.set_relative_to (this);

        popover.value_changed.connect ((gvariant) => {
                if (gvariant == null)   // TODO better (3/3)
                    assert_not_reached ();
                reload ((!) gvariant);
                popover.closed ();

                value_has_changed ();
            });
        reload (initial_value);
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

private class KeyEditorChildBool : Box, KeyEditorChild // might be managed by action, but can't find a way to ensure one-and-only-one button is active  // https://bugzilla.gnome.org/show_bug.cgi?id=769876
{
    private ToggleButton button_true;

    public KeyEditorChildBool (bool initial_value)
    {
        this.visible = true;
        this.hexpand = true;
        this.orientation = Orientation.HORIZONTAL;
        this.halign = Align.START;
        this.homogeneous = true;
        this.width_request = 100;
        this.get_style_context ().add_class ("linked");

        ToggleButton button_false = new ToggleButton ();
        button_false.visible = true;
        button_false.label = Key.cool_boolean_text_value (false);
        this.add (button_false);

        button_true = new ToggleButton ();
        button_true.visible = true;
        button_true.label = Key.cool_boolean_text_value (true);
        this.add (button_true);

        button_true.active = initial_value;
        button_true.bind_property ("active", button_false, "active", BindingFlags.INVERT_BOOLEAN|BindingFlags.SYNC_CREATE|BindingFlags.BIDIRECTIONAL);

        button_true.toggled.connect (() => value_has_changed ());
    }

    public Variant get_variant ()
    {
        return new Variant.boolean (button_true.active);
    }

    public void reload (Variant gvariant)
    {
        button_true.active = gvariant.get_boolean ();
    }
}

private class KeyEditorChildNumberDouble : Entry, KeyEditorChild
{
    private Variant variant;

    private ulong deleted_text_handler = 0;
    private ulong inserted_text_handler = 0;

    construct
    {
        get_style_context ().add_class ("key-editor-child-entry");
    }

    public KeyEditorChildNumberDouble (Variant initial_value)
    {
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;
        this.set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("Failed to parse as double."));

        this.text = initial_value.print (false);

        EntryBuffer ref_buffer = buffer;    // an EntryBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.deleted_text.connect (() => value_has_changed (test_value ()));
        inserted_text_handler = ref_buffer.inserted_text.connect (() => value_has_changed (test_value ()));
        ulong entry_activate_handler = activate.connect (() => { if (test_value ()) child_activated (); });

        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
                disconnect (entry_activate_handler);
            });
    }

    private bool test_value ()
    {
        string tmp_text = this.text; // don't put in the try{} for correct C code
        try
        {
            Variant? tmp_variant = Variant.parse (VariantType.DOUBLE, tmp_text);
            variant = (!) tmp_variant;

            StyleContext context = get_style_context ();
            if (context.has_class ("error"))
                context.remove_class ("error");
            set_icon_from_icon_name (EntryIconPosition.SECONDARY, null);

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

    private void set_lock (bool state)
        requires (deleted_text_handler != 0 && inserted_text_handler != 0)
    {
        if (state)
        {
            SignalHandler.block (buffer, deleted_text_handler);
            SignalHandler.block (buffer, inserted_text_handler);
        }
        else
        {
            SignalHandler.unblock (buffer, deleted_text_handler);
            SignalHandler.unblock (buffer, inserted_text_handler);
        }
    }

    public void reload (Variant gvariant)
    {
        set_lock (true);
        this.text = gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        set_lock (false);
    }
}

private class KeyEditorChildNumberInt : SpinButton, KeyEditorChild
{
    private string key_type;

    private ulong deleted_text_handler = 0;
    private ulong inserted_text_handler = 0;

    public KeyEditorChildNumberInt (Variant initial_value, string type_string, Variant? range_content_or_null)
        requires (type_string == "y" || type_string == "n" || type_string == "q" || type_string == "i" || type_string == "u" || type_string == "h")     // TODO type_string == "x" || type_string == "t" ||
    {
        this.key_type = type_string;

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;

        double min, max;
        if (range_content_or_null != null)
        {
            min = get_variant_as_double (((!) range_content_or_null).get_child_value (0));
            max = get_variant_as_double (((!) range_content_or_null).get_child_value (1));
        }
        else
            get_min_and_max_double (out min, out max, type_string);

        Adjustment adjustment = new Adjustment (get_variant_as_double (initial_value), min, max, 1.0, 5.0, 0.0);
        this.configure (adjustment, 1.0, 0);

        this.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        this.snap_to_ticks = true;
        this.numeric = true;
        this.input_purpose = InputPurpose.NUMBER;   // TODO could be DIGITS for UnsignedInt
        this.width_chars = 30;

        EntryBuffer ref_buffer = buffer;    // an EntryBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.deleted_text.connect (() => value_has_changed ());
        inserted_text_handler = ref_buffer.inserted_text.connect (() => value_has_changed ());
        ulong entry_activate_handler = activate.connect (() => { update (); child_activated (); });

        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
                disconnect (entry_activate_handler);
            });
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

    public Variant get_variant ()   // TODO test_value against range
    {
        switch (key_type)
        {
            case "y": return new Variant.byte   ((uchar)  get_int64_from_entry ()); // TODO uchar or uint8?
            case "n": return new Variant.int16  ((int16)  get_int64_from_entry ());
            case "q": return new Variant.uint16 ((uint16) get_int64_from_entry ());
            case "i": return new Variant.int32  ((int32)  get_int64_from_entry ());
            case "u": return new Variant.uint32 ((uint32) get_int64_from_entry ()); // TODO also use get_value_as_int?
            case "h": return new Variant.handle ((int32)  get_int64_from_entry ());
            default: assert_not_reached ();
        }
    }
    private int64 get_int64_from_entry ()
    {
        return int64.parse (this.get_text ());
    }

    private void set_lock (bool state)
        requires (deleted_text_handler != 0 && inserted_text_handler != 0)
    {
        if (state)
        {
            SignalHandler.block (buffer, deleted_text_handler);
            SignalHandler.block (buffer, inserted_text_handler);
        }
        else
        {
            SignalHandler.unblock (buffer, deleted_text_handler);
            SignalHandler.unblock (buffer, inserted_text_handler);
        }
    }

    public void reload (Variant gvariant)       // TODO "key_editor_child_number_int_real_reload: assertion 'gvariant != NULL' failed" two times when ghosting a key
    {
        set_lock (true);
        this.set_value (get_variant_as_double (gvariant));
        set_lock (false);
    }
}

private class KeyEditorChildArray : Grid, KeyEditorChild
{
    private TextView text_view;
    private Revealer error_revealer;
    private string key_type;
    private Variant variant;

    private ulong deleted_text_handler = 0;
    private ulong inserted_text_handler = 0;

    construct
    {
        get_style_context ().add_class ("key-editor-child-array");
    }

    public KeyEditorChildArray (string type_string, Variant initial_value)
    {
        this.visible = true;
        this.hexpand = true;
        this.vexpand = false;
        orientation = Orientation.VERTICAL;
        get_style_context ().add_class ("frame");

        this.key_type = type_string;
        this.variant = initial_value;

        ScrolledWindow scrolled_window = new ScrolledWindow (null, null);
        scrolled_window.visible = true;

        text_view = new TextView ();
        text_view.visible = true;
        text_view.expand = true;
        text_view.wrap_mode = WrapMode.WORD;
        text_view.monospace = true;
        text_view.key_press_event.connect ((event) => {
                string keyval_name = (!) (Gdk.keyval_name (event.keyval) ?? "");
                if ((keyval_name == "Return" || keyval_name == "KP_Enter")
                && ((event.state & Gdk.ModifierType.MODIFIER_MASK) == 0)
                && (test_value ()))
                {
                    child_activated ();
                    return true;
                }
                return base.key_press_event (event);
            });
        // https://bugzilla.gnome.org/show_bug.cgi?id=789676
        text_view.button_press_event.connect_after (() => Gdk.EVENT_STOP);
        text_view.button_release_event.connect_after (() => Gdk.EVENT_STOP);

        scrolled_window.add (text_view);
        add (scrolled_window);

        error_revealer = new Revealer ();
        error_revealer.visible = true;
        error_revealer.transition_type = RevealerTransitionType.SLIDE_UP;
        error_revealer.reveal_child = false;
        add (error_revealer);

        ActionBar error_bar = new ActionBar ();
        error_bar.visible = true;
        error_revealer.add (error_bar);

        Image error_icon = new Image.from_icon_name ("dialog-error-symbolic", IconSize.BUTTON);
        error_icon.visible = true;
        error_bar.pack_start (error_icon);

        Label error_label = new Label (_("This value is invalid for the key type."));
        error_label.visible = true;
        error_bar.pack_start (error_label);

        text_view.buffer.text = initial_value.print (false);

        TextBuffer ref_buffer = text_view.buffer;    // an TextBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.delete_range.connect_after (() => value_has_changed (test_value ()));
        inserted_text_handler = ref_buffer.insert_text.connect_after (() => value_has_changed (test_value ()));
        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
            });
    }

    private bool test_value ()
    {
        string tmp_text = text_view.buffer.text; // don't put in the try{} for correct C code
        try
        {
            Variant? tmp_variant = Variant.parse (new VariantType (key_type), tmp_text);
            variant = (!) tmp_variant;

            StyleContext context = get_style_context ();
            if (context.has_class ("error"))
                context.remove_class ("error");
            error_revealer.reveal_child = false;

            return true;
        }
        catch (VariantParseError e)
        {
            StyleContext context = get_style_context ();
            if (!context.has_class ("error"))
                context.add_class ("error");
            error_revealer.reveal_child = true;

            return false;
        }
    }

    public Variant get_variant ()
    {
        return variant;
    }

    private void set_lock (bool state)
        requires (deleted_text_handler != 0 && inserted_text_handler != 0)
    {
        if (state)
        {
            SignalHandler.block (text_view.buffer, deleted_text_handler);
            SignalHandler.block (text_view.buffer, inserted_text_handler);
        }
        else
        {
            SignalHandler.unblock (text_view.buffer, deleted_text_handler);
            SignalHandler.unblock (text_view.buffer, inserted_text_handler);
        }
    }

    public void reload (Variant gvariant)
    {
        set_lock (true);
        text_view.buffer.text = gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        set_lock (false);
    }
}

private class KeyEditorChildDefault : Entry, KeyEditorChild
{
    private string key_type;
    private Variant variant;
    private bool is_string;

    private ulong deleted_text_handler = 0;
    private ulong inserted_text_handler = 0;

    construct
    {
        get_style_context ().add_class ("key-editor-child-entry");
    }

    public KeyEditorChildDefault (string type_string, Variant initial_value)
    {
        this.key_type = type_string;
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;
        this.set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("This value is invalid for the key type."));

        this.is_string = type_string == "s" || type_string == "o" || type_string == "g";
        this.text = is_string ? initial_value.get_string () : initial_value.print (false);

        EntryBuffer ref_buffer = buffer;    // an EntryBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.deleted_text.connect (() => value_has_changed (test_value ()));
        inserted_text_handler = ref_buffer.inserted_text.connect (() => value_has_changed (test_value ()));
        ulong entry_activate_handler = activate.connect (() => { if (test_value ()) child_activated (); });

        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
                disconnect (entry_activate_handler);
            });
    }

    private bool test_value ()
    {
        if (key_type == "s")
        {
            variant = new Variant.string (this.text);
            return true;
        }

        string tmp_text = is_string ? @"'$text'" : this.text; // don't put in the try{} for correct C code
        try
        {
            Variant? tmp_variant = Variant.parse (new VariantType (key_type), tmp_text);
            variant = (!) tmp_variant;

            StyleContext context = get_style_context ();
            if (context.has_class ("error"))
                context.remove_class ("error");
            set_icon_from_icon_name (EntryIconPosition.SECONDARY, null);

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

    private void set_lock (bool state)
        requires (deleted_text_handler != 0 && inserted_text_handler != 0)
    {
        if (state)
        {
            SignalHandler.block (buffer, deleted_text_handler);
            SignalHandler.block (buffer, inserted_text_handler);
        }
        else
        {
            SignalHandler.unblock (buffer, deleted_text_handler);
            SignalHandler.unblock (buffer, inserted_text_handler);
        }
    }

    public void reload (Variant gvariant)
    {
        set_lock (true);
        this.text = is_string ? gvariant.get_string () : gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        set_lock (false);
    }
}
