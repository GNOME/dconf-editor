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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private class KeyListBoxRow : EventBox
{
    protected Window window { get; set; }
    protected Notification notification = new Notification (_("Copied to clipboard"));
    protected bool notification_active = false;
    protected uint notification_number;

    [GtkChild] protected Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;

    public signal void show_dialog ();

    protected ContextPopover? nullable_popover;
    protected virtual bool generate_popover (ContextPopover popover) { return false; }      // no popover should be created

    public override bool button_press_event (Gdk.EventButton event)     // list_box_row selection is done elsewhere
    {
        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            nullable_popover = new ContextPopover ();
            if (!generate_popover ((!) nullable_popover))
                return false;

            ((!) nullable_popover).set_relative_to (this);
            ((!) nullable_popover).position = PositionType.BOTTOM;     // TODO better

            Gdk.Rectangle rect;
            ((!) nullable_popover).get_pointing_to (out rect);
            rect.x = (int) (event.x - this.get_allocated_width () / 2.0);
            ((!) nullable_popover).set_pointing_to (rect);
            ((!) nullable_popover).show ();
        }

        return false;
    }

    protected void copy_text (string text)
    {
        // clipboard
        Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null)
            return;

        Clipboard clipboard = Clipboard.get_default ((!) display);
        clipboard.set_text (text, text.length);

        // notification
        GLib.Application application = window.get_application ();   // TODO better; but "of course", after the window is added to the application...
        if (notification_active == true)
        {
            Source.remove (notification_number);
            notification_active = false;
        }

        notification_number = Timeout.add_seconds (30, () => {
                if (notification_active == false)
                    return Source.CONTINUE;
                application.withdraw_notification ("copy");
                notification_active = false;
                return Source.REMOVE;
            });
        notification_active = true;

        notification.set_body (text);
        application.withdraw_notification ("copy");     // TODO report bug: Shell cancels previous notification of the same name, instead of replacing it
        application.send_notification ("copy", notification);
    }

    protected static string cool_text_value (Key key)   // TODO better
    {
        return Key.cool_text_value_from_variant (key.value, key.type_string);
    }
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    public DConfKey key { get; private set; }

    public KeyListBoxRowEditableNoSchema (Window _window, DConfKey _key)
    {
        this.window = _window;
        this.key = _key;

        Pango.AttrList attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
        key_name_label.set_attributes (attr_list);
        key_value_label.set_attributes (attr_list);

        key_name_label.label = key.name;
        key_value_label.label = cool_text_value (key);
        key_info_label.set_markup ("<i>" + _("No Schema Found") + "</i>");

        key.value_changed.connect (() => { key_value_label.label = cool_text_value (key); if (nullable_popover != null) nullable_popover.destroy (); });
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        popover.new_action ("customize", () => { show_dialog (); });
        popover.new_action ("copy", () => { copy_text (key.full_name + " " + key.value.print (false)); });

        if (key.type_string == "b" || key.type_string == "mb")
        {
            popover.new_section ();
            popover.create_buttons_list (key, false);

            popover.value_changed.connect ((gvariant) => { nullable_popover.destroy (); key.value = gvariant; });
        }
        return true;
    }
}

private class KeyListBoxRowEditable : KeyListBoxRow
{
    public GSettingsKey key { get; private set; }

    private Pango.AttrList attr_list = new Pango.AttrList ();

    public KeyListBoxRowEditable (Window _window, GSettingsKey _key)
    {
        this.window = _window;
        this.key = _key;

        key_value_label.set_attributes (attr_list);
        update ();      // sets key_name_label attributes and key_value_label label
        key_name_label.label = key.name;
        key_info_label.label = key.summary;

        key.value_changed.connect (() => { update (); if (nullable_popover != null) nullable_popover.destroy (); });
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        popover.new_action ("customize", () => { show_dialog (); });
        popover.new_action ("copy", () => { copy_text (key.schema_id + " " + key.name + " " + key.value.print (false)); });

        if (key.type_string == "b" || key.type_string == "<enum>" || key.type_string == "mb")
        {
            popover.new_section ();
            popover.create_buttons_list (key, true);

            popover.set_to_default.connect (() => { nullable_popover.destroy (); key.set_to_default (); });
            popover.value_changed.connect ((gvariant) => { nullable_popover.destroy (); key.value = gvariant; });
        }
        else if (key.type_string == "<flags>")
        {
            popover.new_section ();
            if (!key.is_default)
            {
                popover.new_action ("default2", () => { nullable_popover.destroy (); key.set_to_default (); });
                popover.new_section (false);    // ensures a flag called "default2" won't cause problems
            }
            popover.create_flags_list ((GSettingsKey) key);

            popover.value_changed.connect ((gvariant) => { key.value = gvariant; });
        }
        else if (!key.is_default)
        {
            popover.new_section ();
            popover.new_action ("default1", () => { key.set_to_default (); });
        }
        return true;
    }

    private void update ()
    {
        attr_list.change (Pango.attr_weight_new (key.is_default ? Pango.Weight.NORMAL : Pango.Weight.BOLD));
        key_name_label.set_attributes (attr_list);
        // TODO key_info_label.set_attributes (attr_list); ?

        key_value_label.label = cool_text_value (key);
    }
}

private class ContextPopover : Popover
{
    private GLib.Menu menu = new GLib.Menu ();
    private GLib.Menu current_section;

    private ActionMap current_group;
    private string current_group_prefix = "";

    // public signals
    public signal void set_to_default ();
    public signal void value_changed (Variant gvariant);

    public ContextPopover ()
    {
        new_section ();

        bind_model (menu, null);    // TODO menu.freeze() [and sections?], somewhere
    }

    /*\
    * * Simple actions
    \*/

    public delegate void button_action ();
    public void new_action (string action_action, button_action action)
    {
        string text;
        switch (action_action)        // TODO enum
        {
            /* Translators: "open key-editor dialog" action in the right-click menu on the list of keys */
            case "customize":   text = _("Customize…");     break;
            /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
            case "copy":        text = _("Copy");           break;
            /* Translators: "reset key value" action in the right-click menu on the list of keys */
            case "default1":    text = _("Set to default"); break;
            /* Translators: "reset key value" option of a multi-choice list in the right-click menu on the list of keys */
            case "default2":    text = _("Default value");  break;      // TODO string duplication
            default: assert_not_reached ();
        }

        SimpleAction simple_action = new SimpleAction (action_action, null);
        simple_action.activate.connect (() => { action (); });
        current_group.add_action (simple_action);

        current_section.append (text, current_group_prefix + "." + action_action);
    }

    public void new_section (bool draw_line = true)
    {
        current_group_prefix += "a";
        current_group = new SimpleActionGroup ();
        insert_action_group (current_group_prefix, (SimpleActionGroup) current_group);

        if (!draw_line)
            return;

        current_section = new GLib.Menu ();
        menu.append_section (null, current_section);
    }

    /*\
    * * Flags
    \*/

    public void create_flags_list (GSettingsKey key)
    {
        GLib.Settings settings = new GLib.Settings (key.schema_id);
        string [] active_flags = settings.get_strv (key.name);
        string [] all_flags = key.range_content.get_strv ();
        SimpleAction [] flags_actions = new SimpleAction [0];
        foreach (string flag in all_flags)
        {
            SimpleAction simple_action = new SimpleAction.stateful (flag, null, new Variant.boolean (flag in active_flags));
            current_group.add_action (simple_action);

            current_section.append (flag, current_group_prefix + "." + flag);

            flags_actions += simple_action;

            simple_action.change_state.connect ((gaction, gvariant) => {
                    gaction.set_state (gvariant);

                    string [] new_flags = new string [0];
                    foreach (SimpleAction action in flags_actions)
                        if (action.state.get_boolean ())
                            new_flags += action.name;
                    Variant variant = new Variant.strv (new_flags);
                    value_changed (variant);
                });
        }
    }

    /*\
    * * Choices
    \*/

    public void create_buttons_list (Key key, bool nullable)
    {
        const string ACTION_NAME = "reservedactionprefix";

        VariantType original_type = key.value.get_type ();
        VariantType nullable_type = new VariantType.maybe (original_type);
        string nullable_type_string = nullable_type.dup_string ();
        Variant variant = new Variant.maybe (original_type, key.has_schema && ((GSettingsKey) key).is_default ? null : key.value);

        current_group.add_action (new SimpleAction.stateful (ACTION_NAME, nullable_type, variant));

        if (nullable)
            current_section.append (_("Default value"), current_group_prefix + "." + ACTION_NAME + "(@" + nullable_type_string + " nothing)");   // TODO string duplication

        switch (key.type_string)
        {
            case "b":
                current_section.append (Key.cool_boolean_text_value (true), current_group_prefix + "." + ACTION_NAME + "(@mb true)");
                current_section.append (Key.cool_boolean_text_value (false), current_group_prefix + "." + ACTION_NAME + "(@mb false)");
                break;
            case "<enum>":      // defined by the schema
                Variant range = ((GSettingsKey) key).range_content;
                uint size = (uint) range.n_children ();
                if (size == 0)      // TODO special case also 1?
                    assert_not_reached ();
                for (uint index = 0; index < size; index++)
                    current_section.append (range.get_child_value (index).print (false), current_group_prefix + "." + ACTION_NAME + "(@ms '" + range.get_child_value (index).get_string () + "')");        // TODO use int settings.get_enum ()
                break;
            case "mb":
                current_section.append (Key.cool_boolean_text_value (null), current_group_prefix + "." + ACTION_NAME + "(@mmb just nothing)");
                current_section.append (Key.cool_boolean_text_value (true), current_group_prefix + "." + ACTION_NAME + "(@mmb true)");
                current_section.append (Key.cool_boolean_text_value (false), current_group_prefix + "." + ACTION_NAME + "(@mmb false)");
                break;
        }

        ((GLib.ActionGroup) current_group).action_state_changed [ACTION_NAME].connect ((unknown_string, tmp_variant) => {
                Variant? new_variant = tmp_variant.get_maybe ();
                if (new_variant == null)
                    set_to_default ();
                else
                    value_changed ((!) new_variant);
            });
    }
}