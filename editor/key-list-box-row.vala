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

private abstract class ClickableListBoxRow : EventBox
{
    public signal void on_row_clicked ();

    public abstract string get_text ();

    /*\
    * * Dismiss popover on window resize
    \*/

    private int width;

    construct
    {
        size_allocate.connect (on_size_allocate);
    }

    private void on_size_allocate (Allocation allocation)
    {
        if (allocation.width == width)
            return;
        hide_right_click_popover ();
        width = allocation.width;
    }

    /*\
    * * right click popover stuff
    \*/

    private ContextPopover? nullable_popover = null;
    protected virtual bool generate_popover (ContextPopover popover, bool delayed_apply_menu) { return false; }      // no popover should be created

    public void destroy_popover ()
    {
        if (nullable_popover != null)       // check sometimes not useful
            ((!) nullable_popover).destroy ();
    }

    public void hide_right_click_popover ()
    {
        if (nullable_popover != null)
            ((!) nullable_popover).popdown ();
    }

    public void show_right_click_popover (bool delayed_apply_menu, int event_x = (int) (get_allocated_width () / 2.0))
    {
        if (nullable_popover == null)
        {
            nullable_popover = new ContextPopover ();
            if (!generate_popover ((!) nullable_popover, delayed_apply_menu))
            {
                ((!) nullable_popover).destroy ();  // TODO better, again
                nullable_popover = null;
                return;
            }

            ((!) nullable_popover).destroy.connect (() => nullable_popover = null);

            ((!) nullable_popover).set_relative_to (this);
            ((!) nullable_popover).position = PositionType.BOTTOM;     // TODO better
        }
        else if (((!) nullable_popover).visible)
            warning ("show_right_click_popover() called but popover is visible");   // TODO is called on multi-right-click or long Menu key press

        Gdk.Rectangle rect = { x:event_x, y:get_allocated_height (), width:0, height:0 };
        ((!) nullable_popover).set_pointing_to (rect);
        ((!) nullable_popover).popup ();
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/folder-list-box-row.ui")]
private class FolderListBoxRow : ClickableListBoxRow
{
    [GtkChild] private Label folder_name_label;
    private string full_name;

    public FolderListBoxRow (string label, string path)
    {
        folder_name_label.set_text (label);
        full_name = path;
    }

    public override string get_text ()
    {
        return full_name;
    }

    protected override bool generate_popover (ContextPopover popover, bool unused)  // TODO better
    {
        popover.new_action ("open", () => on_row_clicked ());
        popover.new_copy_action (get_text ());

        return true;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private abstract class KeyListBoxRow : ClickableListBoxRow
{
    [GtkChild] private Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;

    protected StyleContext name_context;
    protected StyleContext value_context;

    public signal void set_key_value (Variant? new_value);
    public signal void change_dismissed ();

    protected static string cool_text_value (Key key)   // TODO better
    {
        return Key.cool_text_value_from_variant (key.value, key.type_string);
    }

    construct
    {
        name_context = key_name_label.get_style_context ();
        value_context = key_value_label.get_style_context ();

        update ();
        key_name_label.set_label (abstract_key.name);

        ulong key_value_changed_handler = abstract_key.value_changed.connect (() => {
                update ();
                destroy_popover ();
            });
        destroy.connect (() => abstract_key.disconnect (key_value_changed_handler));
    }
    private abstract Key abstract_key { get; }
    protected abstract void update ();
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    public DConfKey key { get; construct; }
    private override Key abstract_key { get { return (Key) key; }}

    public KeyListBoxRowEditableNoSchema (DConfKey _key)
    {
        Object (key: _key);

        key_info_label.get_style_context ().add_class ("italic-label");
        key_info_label.set_label (_("No Schema Found"));
    }

    protected override void update ()
    {
        if (key.is_ghost)
        {
            if (!value_context.has_class ("italic-label")) value_context.add_class ("italic-label");
            if (value_context.has_class ("bold-label")) value_context.remove_class ("bold-label");
            key_value_label.set_label (_("Key erased."));

            if (name_context.has_class ("bold-label")) name_context.remove_class ("bold-label");
        }
        else
        {
            if (value_context.has_class ("italic-label")) value_context.remove_class ("italic-label");
            if (!value_context.has_class ("bold-label")) value_context.add_class ("bold-label");
            key_value_label.set_label (cool_text_value (key));

            if (!name_context.has_class ("bold-label")) name_context.add_class ("bold-label");
        }
    }

    protected override string get_text ()
    {
        return key.is_ghost ? _("%s (key erased)").printf (key.full_name) : key.descriptor + " " + key.value.print (false);
    }

    protected override bool generate_popover (ContextPopover popover, bool delayed_apply_menu)
    {
        if (key.is_ghost)
        {
            popover.new_copy_action (get_text ());
            return true;
        }

        popover.new_action ("customize", () => on_row_clicked ());
        popover.new_copy_action (get_text ());

        if (key.type_string == "b" || key.type_string == "mb")
        {
            popover.new_section ();
            GLib.Action action = popover.create_buttons_list (key, true, delayed_apply_menu);

            popover.change_dismissed.connect (() => {
                    destroy_popover ();
                    change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    hide_right_click_popover ();
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (key.type_string), gvariant)));
                    set_key_value (gvariant);
                });

            if (!delayed_apply_menu)
            {
                popover.new_section ();
                popover.new_action ("erase", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
            }
        }
        else
        {
            if (key.planned_change)
            {
                popover.new_section ();
                popover.new_action (key.planned_value == null ? "unerase" : "dismiss", () => {
                        destroy_popover ();
                        change_dismissed ();
                    });
            }

            if (!key.planned_change || key.planned_value != null)
            {
                popover.new_section ();
                popover.new_action ("erase", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
            }
        }
        return true;
    }
}

private class KeyListBoxRowEditable : KeyListBoxRow
{
    public GSettingsKey key { get; construct; }
    private override Key abstract_key { get { return (Key) key; }}

    public KeyListBoxRowEditable (GSettingsKey _key)
    {
        Object (key: _key);

        key_info_label.set_label (key.summary);
    }

    protected override void update ()
    {
        if (key.is_default)
        {
            if (name_context.has_class ("bold-label")) name_context.remove_class ("bold-label");
            if (value_context.has_class ("bold-label")) value_context.remove_class ("bold-label");
        }
        else
        {
            if (!name_context.has_class ("bold-label")) name_context.add_class ("bold-label");
            if (!value_context.has_class ("bold-label")) value_context.add_class ("bold-label");
        }
        key_value_label.set_label (cool_text_value (key));
    }

    protected override string get_text ()
    {
        return key.descriptor + " " + key.value.print (false);
    }

    protected override bool generate_popover (ContextPopover popover, bool delayed_apply_menu)
    {
        popover.new_action ("customize", () => on_row_clicked ());
        popover.new_copy_action (get_text ());

        if (key.type_string == "b" || key.type_string == "<enum>" || key.type_string == "mb")
        {
            string real_type_string = key.value.get_type_string ();

            popover.new_section ();
            GLib.Action action = popover.create_buttons_list (key, true, delayed_apply_menu);

            popover.change_dismissed.connect (() => {
                    destroy_popover ();
                    change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    hide_right_click_popover ();
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (real_type_string), gvariant)));
                    set_key_value (gvariant);
                });
        }
        else if (!delayed_apply_menu && !key.planned_change && key.type_string == "<flags>")
        {
            popover.new_section ();

            if (!key.is_default)
                popover.new_action ("default2", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
            popover.set_group ("flags");    // ensures a flag called "customize" or "default2" won't cause problems

            popover.create_flags_list ((GSettingsKey) key);

            popover.value_changed.connect ((gvariant) => set_key_value (gvariant));
        }
        else if (key.planned_change)
        {
            popover.new_section ();
            popover.new_action ("dismiss", () => {
                    destroy_popover ();
                    change_dismissed ();
                });
            if (key.planned_value != null)
                popover.new_action ("default1", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
        }
        else if (!key.is_default)
        {
            popover.new_section ();
            popover.new_action ("default1", () => {
                    destroy_popover ();
                    set_key_value (null);
                });
        }
        return true;
    }
}

private class ContextPopover : Popover
{
    private GLib.Menu menu = new GLib.Menu ();
    private GLib.Menu current_section;

    private ActionMap current_group;

    // public signals
    public signal void value_changed (Variant? gvariant);
    public signal void change_dismissed ();

    public ContextPopover ()
    {
        new_section_real ();

        bind_model (menu, null);

        key_press_event.connect (on_key_press_event);   // TODO should be only for RegistryView popovers, not for RegistryInfo ones (nullable booleans & enums)
    }

    private bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        if (Gdk.keyval_name (event.keyval) != "Menu")
            return false;
        popdown ();
        return true;
    }

    /*\
    * * Simple actions
    \*/

    public delegate void button_action ();
    public void new_action (string action_action, button_action action)
    {
        set_group ("options");
        string group_dot_action = @"options.$action_action";

        SimpleAction simple_action = new SimpleAction (action_action, null);
        simple_action.activate.connect (() => action ());
        current_group.add_action (simple_action);

        switch (action_action)
        {
            case "customize":
                /* Translators: "open key-editor dialog" action in the right-click menu on the list of keys */
                current_section.append (_("Customize…"), group_dot_action);     return;
            case "default1":
                /* Translators: "reset key value" action in the right-click menu on the list of keys */
                current_section.append (_("Set to default"), group_dot_action); return;
            case "default2":
                new_multi_default_action (group_dot_action);                    return;
            case "dismiss":
                /* Translators: "dismiss change" action in the right-click menu on a key with pending changes */
                current_section.append (_("Dismiss change"), group_dot_action); return;
            case "open":
                /* Translators: "open folder" action in the right-click menu on a folder */
                current_section.append (_("Open"), group_dot_action);           return;
            case "erase":
                /* Translators: "erase key" action in the right-click menu on a key without schema */
                current_section.append (_("Erase key"), group_dot_action);      return;
            case "unerase":
                /* Translators: "dismiss change" action in the right-click menu on a key without schema planned to be erased */
                current_section.append (_("Do not erase"), group_dot_action);   return;
            default:
                assert_not_reached ();
        }
    }

    public void new_copy_action (string text)
    {
        /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
        current_section.append (_("Copy"), "app.copy(\"" + text.escape ("") + "\")");
    }

    public void set_group (string group_name)
    {
        GLib.ActionGroup? group = get_action_group (group_name);
        if (group == null)
        {
            current_group = new SimpleActionGroup ();
            insert_action_group (group_name, (SimpleActionGroup) current_group);
        }
        else
            current_group = (ActionMap) ((!) group);
    }

    public void new_section ()
    {
        current_section.freeze ();
        new_section_real ();
    }
    private void new_section_real ()
    {
        current_section = new GLib.Menu ();
        menu.append_section (null, current_section);
    }

    /*\
    * * Flags
    \*/

    public void create_flags_list (GSettingsKey key)
    {
        set_group ("flags");
        string group_dot = "flags.";

        GLib.Settings settings = new GLib.Settings (key.schema_id);
        string [] active_flags = settings.get_strv (key.name);
        string [] all_flags = key.range_content.get_strv ();
        SimpleAction [] flags_actions = new SimpleAction [0];
        foreach (string flag in all_flags)
        {
            SimpleAction simple_action = new SimpleAction.stateful (flag, null, new Variant.boolean (flag in active_flags));
            current_group.add_action (simple_action);

            current_section.append (flag, group_dot + flag);

            flags_actions += simple_action;

            simple_action.change_state.connect ((gaction, gvariant) => {
                    gaction.set_state ((!) gvariant);

                    string [] new_flags = new string [0];
                    foreach (SimpleAction action in flags_actions)
                        if (((!) action.state).get_boolean ())
                            new_flags += action.name;
                    Variant variant = new Variant.strv (new_flags);
                    value_changed (variant);
                });

            key.notify ["planned-value"].connect (() => {
                    active_flags = key.planned_value != null ? ((!) key.planned_value).get_strv () : key.value.get_strv ();
                    bool active = flag in active_flags;
                    if (active != simple_action.get_state ())
                        simple_action.set_state (new Variant.boolean (active));
                });
        }

        finalize_menu ();
    }

    /*\
    * * Choices
    \*/

    public GLib.Action create_buttons_list (Key key, bool has_default_value, bool delayed_apply_menu)
    {
        set_group ("enum");
        const string ACTION_NAME = "choice";
        string group_dot_action = "enum.choice";

        VariantType original_type = key.value.get_type ();
        VariantType nullable_type = new VariantType.maybe (original_type);
        VariantType nullable_nullable_type = new VariantType.maybe (nullable_type);
        string type_string = original_type.dup_string ();

        Variant? value_variant;
        if (!has_default_value) // TODO report bug: if using ?: inside ?:, there's a "g_variant_ref: assertion 'value->ref_count > 0' failed"
            value_variant = key.planned_change && (key.planned_value != null) ? key.planned_value : key.value;
        else if (key.planned_change)
            value_variant = key.planned_value;
        else if (key is GSettingsKey && ((GSettingsKey) key).is_default)
            value_variant = null;
        else
            value_variant = key.value;
        Variant variant = new Variant.maybe (original_type, value_variant);
        Variant nullable_variant;
        if (delayed_apply_menu && !key.planned_change)
            nullable_variant = new Variant.maybe (nullable_type, null);
        else
            nullable_variant = new Variant.maybe (nullable_type, variant);

        GLib.Action action = (GLib.Action) new SimpleAction.stateful (ACTION_NAME, nullable_nullable_type, nullable_variant);
        current_group.add_action (action);

        if (has_default_value)
        {
            bool complete_menu = delayed_apply_menu || key.planned_change;

            if (complete_menu)
                /* Translators: "no change" option in the right-click menu on a key when on delayed mode */
                current_section.append (_("No change"), @"$group_dot_action(@mm$type_string nothing)");

            if (key is GSettingsKey)
                new_multi_default_action (@"$group_dot_action(@mm$type_string just nothing)");
            else if (complete_menu)
                /* Translators: "erase key" option in the right-click menu on a key without schema when on delayed mode */
                current_section.append (_("Erase key"), @"$group_dot_action(@mm$type_string just nothing)");
        }

        switch (key.type_string)
        {
            case "b":
                current_section.append (Key.cool_boolean_text_value (true), @"$group_dot_action(@mmb true)");
                current_section.append (Key.cool_boolean_text_value (false), @"$group_dot_action(@mmb false)");
                break;
            case "<enum>":      // defined by the schema
                Variant range = ((GSettingsKey) key).range_content;
                uint size = (uint) range.n_children ();
                if (size == 0 || (size == 1 && !has_default_value))
                    assert_not_reached ();
                for (uint index = 0; index < size; index++)
                    current_section.append (range.get_child_value (index).print (false), @"$group_dot_action(@mms '" + range.get_child_value (index).get_string () + "')");        // TODO use int settings.get_enum ()
                break;
            case "mb":
                current_section.append (Key.cool_boolean_text_value (null), @"$group_dot_action(@mmmb just just nothing)");
                current_section.append (Key.cool_boolean_text_value (true), @"$group_dot_action(@mmmb true)");
                current_section.append (Key.cool_boolean_text_value (false), @"$group_dot_action(@mmmb false)");
                break;
        }

        ((GLib.ActionGroup) current_group).action_state_changed [ACTION_NAME].connect ((unknown_string, tmp_variant) => {
                Variant? change_variant = tmp_variant.get_maybe ();
                if (change_variant != null)
                    value_changed (((!) change_variant).get_maybe ());
                else
                    change_dismissed ();
            });

        finalize_menu ();

        return action;
    }

    /*\
    * * Multi utilities
    \*/

    private void new_multi_default_action (string action)
    {
        /* Translators: "reset key value" option of a multi-choice list (checks or radios) in the right-click menu on the list of keys */
        current_section.append (_("Default value"), action);
    }

    private void finalize_menu ()
        requires (menu.is_mutable ())  // should just "return;" then if function is made public
    {
        current_section.freeze ();
        menu.freeze ();
    }
}
