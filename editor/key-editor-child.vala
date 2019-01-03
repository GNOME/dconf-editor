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

private interface KeyEditorChild : Widget
{
    internal signal void value_has_changed (bool is_valid);

    internal abstract Variant get_variant ();
    internal signal void child_activated ();

    internal abstract void reload (Variant gvariant);

    /* Translators: tooltip text of the entry's icon when editing the value of a double or a 64-bit (signed or unsigned) key, if the key only allows a range of values and the written value is out of range */
    protected const string out_of_range_text = _("Given value is out of range.");

    /* Translators: tooltip text of the entry's icon (if using an entry) or text displayed under the text view (if using a text view) when editing the value of a key, if the written text cannot be parsed regarding to the key's value type */
    protected const string invalid_value_text = _("This value is invalid for the key type.");

    /*\
    * * for entries and textviews
    \*/

    protected static void set_lock_on (Object buffer, ulong deleted_text_handler, ulong inserted_text_handler)
        requires (deleted_text_handler != 0)
        requires (inserted_text_handler != 0)
    {
        SignalHandler.block (buffer, deleted_text_handler);
        SignalHandler.block (buffer, inserted_text_handler);
    }
    protected static void set_lock_off (Object buffer, ulong deleted_text_handler, ulong inserted_text_handler)
        requires (deleted_text_handler != 0)
        requires (inserted_text_handler != 0)
    {
        SignalHandler.unblock (buffer, deleted_text_handler);
        SignalHandler.unblock (buffer, inserted_text_handler);
    }
}

private class KeyEditorChildSingle : Label, KeyEditorChild
{
    private Variant variant;

    internal KeyEditorChildSingle (Variant key_value, string text)
    {
        variant = key_value;
        set_label (text);
        show ();
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant) {}
}

private class KeyEditorChildEnum : MenuButton, KeyEditorChild
{
    private Variant variant;
    private GLib.Action action;

    internal KeyEditorChildEnum (Variant initial_value, bool delay_mode, bool has_planned_change, Variant range_content)
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;
        this.use_popover = true;
        this.width_request = 100;

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (false, delay_mode, has_planned_change, "<enum>", range_content, initial_value);
        popover.set_relative_to (this);

        popover.value_changed.connect (on_popover_value_changed);
        reload (initial_value);
        this.set_popover ((Popover) popover);
    }
    private void on_popover_value_changed (ContextPopover _popover, Variant? gvariant)
        requires (gvariant != null)
    {
        reload ((!) gvariant);
        _popover.closed ();

        value_has_changed (true);
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
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

    internal KeyEditorChildFlags (Variant initial_value, string [] _all_flags)
    {
        all_flags = _all_flags;
        this.visible = true;
        this.hexpand = true;
        this.orientation = Orientation.HORIZONTAL;
        this.column_spacing = 8;

        MenuButton button = new MenuButton ();  // TODO change icon when popover will go up
        button.visible = true;
        button.use_popover = true;
        button.halign = Align.START;
        button.get_style_context ().add_class ("image-button");
        this.add (button);

        label.visible = true;
        label.halign = Align.START;
        label.hexpand = true;
        this.add (label);

        popover.create_flags_list (initial_value.get_strv (), all_flags);
        popover.set_relative_to (button);
        popover.value_changed.connect (on_popover_value_changed);
        reload (initial_value);
        button.set_popover ((Popover) popover);
    }
    private void on_popover_value_changed (Popover _popover, Variant? gvariant)
        requires (gvariant != null)
    {
        reload ((!) gvariant);
        value_has_changed (true);
    }

    internal void update_flags (string [] active_flags)
    {
        foreach (string flag in all_flags)
            popover.update_flag_status (flag, flag in active_flags);
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
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

    internal KeyEditorChildNullableBool (Variant initial_value, bool delay_mode, bool has_planned_change, bool has_schema)
    {
        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;
        this.use_popover = true;
        this.width_request = 100;

        Variant? meaningless_variant_or_null = null;  // only used for adding or not "set to default"
        if (has_schema)
            meaningless_variant_or_null = new Variant.boolean (true);

        ContextPopover popover = new ContextPopover ();
        action = popover.create_buttons_list (false, delay_mode, has_planned_change, "mb", meaningless_variant_or_null, initial_value);
        popover.set_relative_to (this);

        popover.value_changed.connect (on_popover_value_changed);
        reload (initial_value);
        this.set_popover ((Popover) popover);
    }
    private void on_popover_value_changed (Popover _popover, Variant? gvariant)
        requires (gvariant != null)
    {
        reload ((!) gvariant);
        _popover.closed ();

        value_has_changed (true);
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
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

    internal KeyEditorChildBool (bool initial_value)
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

        button_true.toggled.connect (() => value_has_changed (true));
    }

    internal Variant get_variant ()
    {
        return new Variant.boolean (button_true.active);
    }

    internal void reload (Variant gvariant)
    {
        button_true.active = gvariant.get_boolean ();
    }
}

private abstract class KeyEditorChildNumberCustom : Entry, KeyEditorChild
{
    protected Variant variant;

    protected ulong deleted_text_handler = 0;
    protected ulong inserted_text_handler = 0;

    construct
    {
        get_style_context ().add_class ("key-editor-child-entry");
    }

    protected void connect_entry ()
    {
        EntryBuffer ref_buffer = buffer;    // an EntryBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.deleted_text.connect (() => value_has_changed (test_value ()));
        inserted_text_handler = ref_buffer.inserted_text.connect (() => value_has_changed (test_value ()));
        ulong entry_activated_handler = activate.connect (() => { if (test_value ()) child_activated (); });
        ulong entry_sensitive_handler = notify ["sensitive"].connect (set_error_class);

        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
                disconnect (entry_activated_handler);
                disconnect (entry_sensitive_handler);
            });
    }

    private bool value_has_error = false;
    private void set_error_class ()
    {
        StyleContext context = get_style_context ();
        if (value_has_error)
        {
            if (is_sensitive ())
            {
                if (!context.has_class ("error"))
                    context.add_class ("error");
            }
            else if (context.has_class ("error"))
                context.remove_class ("error");
        }
        else if (is_sensitive () && context.has_class ("error"))
            context.remove_class ("error");
    }

    protected void show_error (bool show)
    {
        value_has_error = show;
        if (show)
            secondary_icon_name = "dialog-error-symbolic";
        else
            set_icon_from_icon_name (EntryIconPosition.SECONDARY, null);
        set_error_class ();
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
    {
        KeyEditorChild.set_lock_on (buffer, deleted_text_handler, inserted_text_handler);
        this.text = gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        KeyEditorChild.set_lock_off (buffer, deleted_text_handler, inserted_text_handler);
    }

    protected abstract bool test_value ();
}

private class KeyEditorChildNumberDouble : KeyEditorChildNumberCustom
{
    private double min;
    private double max;

    internal KeyEditorChildNumberDouble (Variant initial_value, Variant? range_content_or_null)
    {
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;

        this.text = initial_value.print (false);

        if (range_content_or_null != null)
        {
            min = ((!) range_content_or_null).get_child_value (0).get_double ();
            max = ((!) range_content_or_null).get_child_value (1).get_double ();
        }
        else
        {
            min = -double.MAX; // https://gitlab.gnome.org/GNOME/vala/issues/680
            max = double.MAX;
        }

        connect_entry ();
    }

    private void switch_icon_tooltip_text (bool range_error)
    {
        if (range_error)
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, out_of_range_text);
        else
            /* Translators: tooltip text of the entry's icon when editing the value of a double key, if the written value cannot be parsed */
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("Failed to parse as double."));
    }

    protected override bool test_value ()
    {
        Variant? tmp_variant;
        string tmp_text = this.text; // don't put in the try{} for correct C code
        try
        {
            tmp_variant = Variant.parse (VariantType.DOUBLE, tmp_text);
        }
        catch (VariantParseError e)
        {
            switch_icon_tooltip_text (false);
            show_error (true);
            return false;
        }

        double variant_value = ((!) tmp_variant).get_double ();
        if ((variant_value < min) || (variant_value > max))
        {
            switch_icon_tooltip_text (true);
            show_error (true);
            return false;
        }
        else
        {
            variant = (!) tmp_variant;
            show_error (false);
            return true;
        }
    }
}

private class KeyEditorChildNumberInt64 : KeyEditorChildNumberCustom
{
    private int64 min;
    private int64 max;

    internal KeyEditorChildNumberInt64 (Variant initial_value, Variant? range_content_or_null)
    {
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;

        this.text = initial_value.print (false);

        if (range_content_or_null != null)
        {
            min = ((!) range_content_or_null).get_child_value (0).get_int64 ();
            max = ((!) range_content_or_null).get_child_value (1).get_int64 ();
        }
        else
        {
            min = int64.MIN;
            max = int64.MAX;
        }

        connect_entry ();
    }

    private void switch_icon_tooltip_text (bool range_error)
    {
        if (range_error)
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, out_of_range_text);
        else
            /* Translators: tooltip text of the entry's icon when editing the value of a signed 64-bit key, if the written value cannot be parsed */
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("Failed to parse as 64-bit integer."));
    }

    protected override bool test_value ()
    {
        Variant? tmp_variant;
        string tmp_text = this.text; // don't put in the try{} for correct C code
        try
        {
            tmp_variant = Variant.parse (VariantType.INT64, tmp_text);
        }
        catch (VariantParseError e)
        {
            switch_icon_tooltip_text (false);
            show_error (true);
            return false;
        }

        int64 variant_value = ((!) tmp_variant).get_int64 ();
        if ((variant_value < min) || (variant_value > max))
        {
            switch_icon_tooltip_text (true);
            show_error (true);
            return false;
        }
        else
        {
            variant = (!) tmp_variant;
            show_error (false);
            return true;
        }
    }
}

private class KeyEditorChildNumberUint64 : KeyEditorChildNumberCustom
{
    private uint64 min;
    private uint64 max;

    internal KeyEditorChildNumberUint64 (Variant initial_value, Variant? range_content_or_null)
    {
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;

        this.text = initial_value.print (false);

        if (range_content_or_null != null)
        {
            min = ((!) range_content_or_null).get_child_value (0).get_uint64 ();
            max = ((!) range_content_or_null).get_child_value (1).get_uint64 ();
        }
        else
        {
            min = uint64.MIN;
            max = uint64.MAX;
        }

        connect_entry ();
    }

    private void switch_icon_tooltip_text (bool range_error)
    {
        if (range_error)
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, out_of_range_text);
        else
            /* Translators: tooltip text of the entry's icon when editing the value of an unsigned 64-bit key, if the written value cannot be parsed */
            set_icon_tooltip_text (EntryIconPosition.SECONDARY, _("Failed to parse as unsigned 64-bit integer."));
    }

    protected override bool test_value ()
    {
        Variant? tmp_variant;
        string tmp_text = this.text; // don't put in the try{} for correct C code
        try
        {
            tmp_variant = Variant.parse (VariantType.UINT64, tmp_text);
        }
        catch (VariantParseError e)
        {
            switch_icon_tooltip_text (false);
            show_error (true);
            return false;
        }

        uint64 variant_value = ((!) tmp_variant).get_uint64 ();
        if ((variant_value < min) || (variant_value > max))
        {
            switch_icon_tooltip_text (true);
            show_error (true);
            return false;
        }
        else
        {
            variant = (!) tmp_variant;
            show_error (false);
            return true;
        }
    }
}

private class KeyEditorChildNumberInt : SpinButton, KeyEditorChild
{
    private Variant variant;

    private string key_type;

    private int64 min_int64;
    private int64 max_int64;

    private ulong deleted_text_handler = 0;
    private ulong inserted_text_handler = 0;

    internal KeyEditorChildNumberInt (Variant initial_value, string type_string, Variant? range_content_or_null)
        requires (type_string == "y" || type_string == "n" || type_string == "q" || type_string == "i" || type_string == "u" || type_string == "h")     // "x" and "t" are managed elsewhere
    {
        this.variant = initial_value;
        this.key_type = type_string;

        this.visible = true;
        this.hexpand = true;
        this.halign = Align.START;

        double min_double, max_double;
        if (range_content_or_null != null)
        {
            if (type_string == "h")
                assert_not_reached ();

            Variant min_variant = ((!) range_content_or_null).get_child_value (0);
            Variant max_variant = ((!) range_content_or_null).get_child_value (1);
            min_double = get_variant_as_double (min_variant);
            max_double = get_variant_as_double (max_variant);
            min_int64  = get_variant_as_int64  (min_variant);
            max_int64  = get_variant_as_int64  (max_variant);
        }
        else
        {
            get_min_and_max_double (out min_double, out max_double, type_string);
            get_min_and_max_int64  (out min_int64,  out max_int64,  type_string);
        }

        Adjustment adjustment = new Adjustment (get_variant_as_double (initial_value), min_double, max_double, 1.0, 5.0, 0.0);
        this.configure (adjustment, 1.0, 0);

        this.update_policy = SpinButtonUpdatePolicy.IF_VALID;
        this.snap_to_ticks = true;
        this.numeric = true;
        this.input_purpose = InputPurpose.NUMBER;   // TODO could be DIGITS for UnsignedInt
        this.max_width_chars = 30;

        EntryBuffer ref_buffer = buffer;    // an EntryBuffer doesn't emit a "destroy" signal
        deleted_text_handler = ref_buffer.deleted_text.connect (() => value_has_changed (test_value ()));
        inserted_text_handler = ref_buffer.inserted_text.connect (() => value_has_changed (test_value ()));
        ulong entry_activated_handler = activate.connect (() => { if (test_value ()) child_activated (); update (); });
        ulong entry_sensitive_handler = notify ["sensitive"].connect (set_error_class);

        destroy.connect (() => {
                ref_buffer.disconnect (deleted_text_handler);
                ref_buffer.disconnect (inserted_text_handler);
                disconnect (entry_activated_handler);
                disconnect (entry_sensitive_handler);
            });
    }

    private static void get_min_and_max_double (out double min, out double max, string variant_type)
    {
        switch (variant_type)
        {
            case "i": min = (double)  int32.MIN;    max = (double)  int32.MAX;  break;
            case "u": min = (double) uint32.MIN;    max = (double) uint32.MAX;  break;
            case "n": min = (double)  int16.MIN;    max = (double)  int16.MAX;  break;
            case "q": min = (double) uint16.MIN;    max = (double) uint16.MAX;  break;
            case "y": min = (double) uint8.MIN;     max = (double) uint8.MAX;   break;
            case "h": min = (double)  int32.MIN;    max = (double)  int32.MAX;  break;
            default: assert_not_reached ();
        }
    }
    private static void get_min_and_max_int64 (out int64 min, out int64 max, string variant_type)
    {
        switch (variant_type)
        {
            case "i": min = (int64)  int32.MIN;     max = (int64)  int32.MAX;   break;
            case "u": min = (int64) uint32.MIN;     max = (int64) uint32.MAX;   break;
            case "n": min = (int64)  int16.MIN;     max = (int64)  int16.MAX;   break;
            case "q": min = (int64) uint16.MIN;     max = (int64) uint16.MAX;   break;
            case "y": min = (int64) uint8.MIN;      max = (int64) uint8.MAX;    break;
            case "h": min = (int64)  int32.MIN;     max = (int64)  int32.MAX;   break;
            default: assert_not_reached ();
        }
    }

    private static double get_variant_as_double (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.INT32:   return (double) variant.get_int32 ();
            case Variant.Class.UINT32:  return (double) variant.get_uint32 ();
            case Variant.Class.INT16:   return (double) variant.get_int16 ();
            case Variant.Class.UINT16:  return (double) variant.get_uint16 ();
            case Variant.Class.BYTE:    return (double) variant.get_byte ();
            case Variant.Class.HANDLE:  return (double) variant.get_handle ();
            default: assert_not_reached ();
        }
    }
    private static int64 get_variant_as_int64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.INT32:   return (int64) variant.get_int32 ();
            case Variant.Class.UINT32:  return (int64) variant.get_uint32 ();
            case Variant.Class.INT16:   return (int64) variant.get_int16 ();
            case Variant.Class.UINT16:  return (int64) variant.get_uint16 ();
            case Variant.Class.BYTE:    return (int64) variant.get_byte ();
            case Variant.Class.HANDLE:  return (int64) variant.get_handle ();
            default: assert_not_reached ();
        }
    }

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)       // TODO "key_editor_child_number_int_real_reload: assertion 'gvariant != NULL' failed" two times when ghosting a key
    {
        KeyEditorChild.set_lock_on (buffer, deleted_text_handler, inserted_text_handler);
        this.set_value (get_variant_as_double (gvariant));
        KeyEditorChild.set_lock_off (buffer, deleted_text_handler, inserted_text_handler);
    }

    private bool value_has_error = false;
    private void set_error_class ()
    {
        StyleContext context = get_style_context ();
        if (is_sensitive ())
        {
            if (value_has_error)
            {
                if (!context.has_class ("error"))
                    context.add_class ("error");
            }
            else if (context.has_class ("error"))
                context.remove_class ("error");
        }
        else if (context.has_class ("error"))
            context.remove_class ("error");
    }

    private bool test_value ()
    {
        Variant? tmp_variant;
        string tmp_text = this.text; // don't put in the try{} for correct C code
        try
        {
            tmp_variant = Variant.parse (VariantType.INT64, tmp_text);
        }
        catch (VariantParseError e)
        {
            value_has_error = true;
            set_error_class ();
            return false;
        }

        int64 variant_value = ((!) tmp_variant).get_int64 ();
        if ((variant_value < min_int64) || (variant_value > max_int64))
        {
            value_has_error = true;
            set_error_class ();

            return false;
        }
        else
        {
            value_has_error = false;
            set_error_class ();

            variant = get_variant_from_int64 (variant_value, key_type);
            return true;
        }
    }
    private static Variant get_variant_from_int64 (int64 int64_value, string key_type)
    {
        switch (key_type)
        {
            case "i": return new Variant.int32  ( (int32) int64_value);
            case "u": return new Variant.uint32 ((uint32) int64_value);
            case "n": return new Variant.int16  ( (int16) int64_value);
            case "q": return new Variant.uint16 ((uint16) int64_value);
            case "y": return new Variant.byte   ((uint8)  int64_value);
            case "h": return new Variant.handle ( (int32) int64_value);
            default: assert_not_reached ();
        }
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

    internal KeyEditorChildArray (string type_string, Variant initial_value)
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
        text_view.key_press_event.connect (on_key_press_event);
        // https://bugzilla.gnome.org/show_bug.cgi?id=789676
        text_view.button_press_event.connect_after (event_stop);
        text_view.button_release_event.connect_after (event_stop);

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

        Label error_label = new Label (invalid_value_text);
        error_label.visible = true;
        error_label.wrap = true;
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
    private bool on_key_press_event (Gdk.EventKey event)
    {
        string keyval_name = (!) (Gdk.keyval_name (event.keyval) ?? "");
        if ((keyval_name == "Return" || keyval_name == "KP_Enter")
        && ((event.state & Gdk.ModifierType.MODIFIER_MASK) == 0)
        && (test_value ()))
        {
            child_activated ();
            return Gdk.EVENT_STOP;
        }
        return base.key_press_event (event);
    }
    private static bool event_stop ()
    {
        return Gdk.EVENT_STOP;
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

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
    {
        KeyEditorChild.set_lock_on (text_view.buffer, deleted_text_handler, inserted_text_handler);
        text_view.buffer.text = gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        KeyEditorChild.set_lock_off (text_view.buffer, deleted_text_handler, inserted_text_handler);
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

    internal KeyEditorChildDefault (string type_string, Variant initial_value)
    {
        this.key_type = type_string;
        this.variant = initial_value;

        this.visible = true;
        this.hexpand = true;
        this.secondary_icon_activatable = false;
        this.set_icon_tooltip_text (EntryIconPosition.SECONDARY, invalid_value_text);

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

    internal Variant get_variant ()
    {
        return variant;
    }

    internal void reload (Variant gvariant)
    {
        KeyEditorChild.set_lock_on (buffer, deleted_text_handler, inserted_text_handler);
        this.text = is_string ? gvariant.get_string () : gvariant.print (false);
        if (!test_value ())
            assert_not_reached ();
        KeyEditorChild.set_lock_off (buffer, deleted_text_handler, inserted_text_handler);
    }
}
