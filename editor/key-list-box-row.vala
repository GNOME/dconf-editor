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
    * * right click popover stuff
    \*/

    private ContextPopover? nullable_popover = null;
    protected virtual bool generate_popover (ContextPopover popover) { return false; }      // no popover should be created

    protected void destroy_popover ()
    {
        if (nullable_popover != null)       // check sometimes not useful
            ((!) nullable_popover).destroy ();
    }

    public override bool button_press_event (Gdk.EventButton event)     // list_box_row selection is done elsewhere
    {
        if (event.button == Gdk.BUTTON_SECONDARY)
            show_right_click_popover ((int) (event.x - this.get_allocated_width () / 2.0));

        return false;
    }

    public void hide_right_click_popover ()
    {
        if (nullable_popover != null)
            ((!) nullable_popover).hide ();
    }

    public void show_right_click_popover (int event_x = 0)
    {
        if (nullable_popover == null)
        {
            nullable_popover = new ContextPopover ();
            if (!generate_popover ((!) nullable_popover))
            {
                ((!) nullable_popover).destroy ();  // TODO better, again
                return;
            }

            ((!) nullable_popover).destroy.connect (() => { nullable_popover = null; });

            ((!) nullable_popover).set_relative_to (this);
            ((!) nullable_popover).position = PositionType.BOTTOM;     // TODO better
        }
        else if ((!) nullable_popover.visible)
            warning ("show_right_click_popover() called but popover is visible");   // TODO is called on multi-right-click or long Menu key press

        Gdk.Rectangle rect;
        ((!) nullable_popover).get_pointing_to (out rect);
        rect.x = event_x;
        ((!) nullable_popover).set_pointing_to (rect);
        ((!) nullable_popover).show ();
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

    protected override bool generate_popover (ContextPopover popover)
    {
        popover.new_action ("open", () => { on_row_clicked (); });
        popover.new_copy_action (get_text ());

        return true;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private abstract class KeyListBoxRow : ClickableListBoxRow
{
    [GtkChild] protected Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;

    protected static string cool_text_value (Key key)   // TODO better
    {
        return Key.cool_text_value_from_variant (key.value, key.type_string);
    }
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    public DConfKey key { get; private set; }

    public KeyListBoxRowEditableNoSchema (DConfKey _key)
    {
        this.key = _key;

        Pango.AttrList attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));
        key_name_label.set_attributes (attr_list);
        key_value_label.set_attributes (attr_list);

        key_name_label.label = key.name;
        key_value_label.label = cool_text_value (key);
        key_info_label.set_markup ("<i>" + _("No Schema Found") + "</i>");

        key.value_changed.connect (() => {
                key_value_label.label = cool_text_value (key);
                destroy_popover ();
            });
    }

    protected override string get_text ()
    {
        return key.full_name + " " + key.value.print (false);
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        popover.new_action ("customize", () => { on_row_clicked (); });
        popover.new_copy_action (get_text ());

        if (key.type_string == "b" || key.type_string == "mb")
        {
            popover.new_section ();
            popover.create_buttons_list (key, false);

            popover.value_changed.connect ((gvariant) => {
                    destroy_popover ();
                    key.value = gvariant;
                });
        }
        return true;
    }
}

private class KeyListBoxRowEditable : KeyListBoxRow
{
    public GSettingsKey key { get; private set; }

    private Pango.AttrList attr_list = new Pango.AttrList ();

    public KeyListBoxRowEditable (GSettingsKey _key)
    {
        this.key = _key;

        key_value_label.set_attributes (attr_list);
        update ();      // sets key_name_label attributes and key_value_label label
        key_name_label.label = key.name;
        key_info_label.label = key.summary;

        key.value_changed.connect (() => {
                update ();
                destroy_popover ();
            });
    }

    protected override string get_text ()
    {
        return key.descriptor + " " + key.value.print (false);
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        popover.new_action ("customize", () => { on_row_clicked (); });
        popover.new_copy_action (get_text ());

        if (key.type_string == "b" || key.type_string == "<enum>" || key.type_string == "mb")
        {
            popover.new_section ();
            popover.create_buttons_list (key, true);

            popover.set_to_default.connect (() => {
                    destroy_popover ();
                    key.set_to_default ();
                });
            popover.value_changed.connect ((gvariant) => {
                    destroy_popover ();
                    key.value = gvariant;
                });
        }
        else if (key.type_string == "<flags>")
        {
            popover.new_section ();

            if (!key.is_default)
                popover.new_action ("default2", () => {
                        destroy_popover ();
                        key.set_to_default ();
                    });
            popover.set_group ("flags");    // ensures a flag called "customize" or "default2" won't cause problems

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

    // public signals
    public signal void set_to_default ();
    public signal void value_changed (Variant gvariant);

    public ContextPopover ()
    {
        new_section_real ();

        bind_model (menu, null);

        key_press_event.connect (on_key_press_event);
    }

    private bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        if (Gdk.keyval_name (event.keyval) != "Menu")
            return false;
        hide ();
        return true;
    }

    /*\
    * * Simple actions
    \*/

    public delegate void button_action ();
    public void new_action (string action_action, button_action action)
    {
        set_group ("options");
        string group_dot_action = "options." + action_action;

        SimpleAction simple_action = new SimpleAction (action_action, null);
        simple_action.activate.connect (() => { action (); });
        current_group.add_action (simple_action);

        if (action_action == "customize")
            /* Translators: "open key-editor dialog" action in the right-click menu on the list of keys */
            current_section.append (_("Customize…"), group_dot_action);
        else if (action_action == "default1")
            /* Translators: "reset key value" action in the right-click menu on the list of keys */
            current_section.append (_("Set to default"), group_dot_action);
        else if (action_action == "default2")
            new_multi_default_action (group_dot_action);
        else if (action_action == "open")
            /* Translators: "open folder" action in the right-click menu on a folder */
            current_section.append (_("Open"), group_dot_action);
        else assert_not_reached ();
    }

    public void new_copy_action (string text)
    {
        /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
        current_section.append (_("Copy"), "app.copy(\"" + text + "\")");   // TODO protection against some chars in text? 2/2
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
        }

        finalize_menu ();
    }

    /*\
    * * Choices
    \*/

    public void create_buttons_list (Key key, bool nullable)
    {
        set_group ("enum");
        const string ACTION_NAME = "choice";
        string group_dot_action = "enum.choice";

        VariantType original_type = key.value.get_type ();
        VariantType nullable_type = new VariantType.maybe (original_type);
        string nullable_type_string = nullable_type.dup_string ();
        Variant variant = new Variant.maybe (original_type, key.has_schema && ((GSettingsKey) key).is_default ? null : key.value);

        current_group.add_action (new SimpleAction.stateful (ACTION_NAME, nullable_type, variant));

        if (nullable)
            new_multi_default_action (group_dot_action + "(@" + nullable_type_string + " nothing)");

        switch (key.type_string)
        {
            case "b":
                current_section.append (Key.cool_boolean_text_value (true), group_dot_action + "(@mb true)");
                current_section.append (Key.cool_boolean_text_value (false), group_dot_action + "(@mb false)");
                break;
            case "<enum>":      // defined by the schema
                Variant range = ((GSettingsKey) key).range_content;
                uint size = (uint) range.n_children ();
                if (size == 0)      // TODO special case also 1?
                    assert_not_reached ();
                for (uint index = 0; index < size; index++)
                    current_section.append (range.get_child_value (index).print (false), group_dot_action + "(@ms '" + range.get_child_value (index).get_string () + "')");        // TODO use int settings.get_enum ()
                break;
            case "mb":
                current_section.append (Key.cool_boolean_text_value (null), group_dot_action + "(@mmb just nothing)");
                current_section.append (Key.cool_boolean_text_value (true), group_dot_action + "(@mmb true)");
                current_section.append (Key.cool_boolean_text_value (false), group_dot_action + "(@mmb false)");
                break;
        }

        ((GLib.ActionGroup) current_group).action_state_changed [ACTION_NAME].connect ((unknown_string, tmp_variant) => {
                Variant? new_variant = tmp_variant.get_maybe ();
                if (new_variant == null)
                    set_to_default ();
                else
                    value_changed ((!) new_variant);
            });

        finalize_menu ();
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
