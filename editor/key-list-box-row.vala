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

const int MAX_ROW_WIDTH = 1000;

private class ListBoxRowWrapper : ListBoxRow
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class RegistryWarning : Grid
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class ListBoxRowHeader : Grid
{
    public override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }

    public ListBoxRowHeader (bool is_first_row, string? header_text = null)
    {
        if (header_text == null)
        {
            if (is_first_row)
                return;
        }
        else
        {
            orientation = Orientation.VERTICAL;

            Label label = new Label ((!) header_text);
            label.visible = true;
            label.halign = Align.START;
            StyleContext context = label.get_style_context ();
            context.add_class ("dim-label");
            context.add_class ("header-label");
            add (label);
        }

        halign = Align.CENTER;

        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.visible = true;
        separator.hexpand = true;
        add (separator);
    }
}

private abstract class ClickableListBoxRow : EventBox
{
    public signal void on_popover_disappear ();
    public ulong on_popover_disappear_handler = 0;  // used by registry-search

    public abstract string get_text ();

    public bool search_result_mode { protected get; construct; default = false; }

    public ModificationsHandler modifications_handler { protected get; construct; }

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
    protected virtual bool generate_popover (ContextPopover popover) { return false; }      // no popover should be created

    public void destroy_popover ()
    {
        if (nullable_popover != null)       // check sometimes not useful
            ((!) nullable_popover).destroy ();
    }

    protected void hide_right_click_popover ()
    {
        if (nullable_popover != null)
            ((!) nullable_popover).popdown ();
    }

    public bool right_click_popover_visible ()
    {
        return (nullable_popover != null) && (((!) nullable_popover).visible);
    }

    public void show_right_click_popover (int event_x = (int) (get_allocated_width () / 2.0))
    {
        if (nullable_popover == null)
        {
            nullable_popover = new ContextPopover ();
            if (!generate_popover ((!) nullable_popover))
            {
                ((!) nullable_popover).destroy ();  // TODO better, again
                nullable_popover = null;
                return;
            }

            ((!) nullable_popover).closed.connect (() => on_popover_disappear ());
            ((!) nullable_popover).destroy.connect (() => {
                    on_popover_disappear ();
                    nullable_popover = null;
                });

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
    public string full_name;
    private string parent_path;

    public FolderListBoxRow (string label, string path, string _parent_path, bool search_result_mode = false)
    {
        Object (search_result_mode: search_result_mode);
        folder_name_label.set_text (search_result_mode ? path : label);
        full_name = path;
        parent_path = _parent_path;
    }

    public override string get_text ()
    {
        return full_name;
    }

    protected override bool generate_popover (ContextPopover popover)  // TODO better
    {
        Variant variant;

        if (search_result_mode)
        {
            variant = new Variant ("(ss)", parent_path, full_name);
            popover.new_gaction ("open_parent", "ui.open-path-with-selection(" + variant.print (false) + ")");
            popover.new_section ();
        }

        variant = new Variant.string (full_name);
        popover.new_gaction ("open", "ui.open-path(" + variant.print (false) + ")");
        popover.new_copy_action (get_text ());

        popover.new_section ();
        popover.new_gaction ("recursivereset", "ui.reset-recursive(" + variant.print (false) + ")");

        return true;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private abstract class KeyListBoxRow : ClickableListBoxRow
{
    public signal void on_delete_call ();

    [GtkChild] private Grid key_name_and_value_grid;
    [GtkChild] private Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;
    protected Switch? boolean_switch = null;

    public bool small_keys_list_rows
    {
        set
        {
            if (value)
            {
                key_value_label.set_lines (2);
                key_info_label.set_lines (1);
            }
            else
            {
                key_value_label.set_lines (3);
                key_info_label.set_lines (2);
            }
        }
    }

    public signal void set_key_value (Variant? new_value);
    public signal void change_dismissed ();

    construct
    {
        if (abstract_key.type_string == "b" && !modifications_handler.get_current_delay_mode ())
        {
            boolean_switch = new Switch ();
            ((!) boolean_switch).can_focus = false;
            ((!) boolean_switch).valign = Align.CENTER;
            ((!) boolean_switch).show ();
            key_value_label.hide ();
            key_name_and_value_grid.attach ((!) boolean_switch, 1, 0, 1, 2);
        }

        update ();
        key_name_label.set_label (search_result_mode ? abstract_key.full_name : abstract_key.name);

        ulong key_value_changed_handler = abstract_key.value_changed.connect (() => {
                update ();
                destroy_popover ();
            });
        destroy.connect (() => {
                abstract_key.disconnect (key_value_changed_handler);
            });
    }
    private abstract Key abstract_key { get; }
    protected abstract void update ();

    public void toggle_boolean_key ()
    {
        if (boolean_switch == null)
            return;
        ((!) boolean_switch).set_active (!((!) boolean_switch).get_active ());
    }

    public void set_delayed_icon ()
    {
        SettingsModel model = modifications_handler.model;
        Key key = abstract_key;
        StyleContext context = get_style_context ();
        if (modifications_handler.key_has_planned_change (key))
        {
            context.add_class ("delayed");
            if (key is DConfKey)
            {
                if (modifications_handler.get_key_planned_value (key) == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
        {
            context.remove_class ("delayed");
            if (key is DConfKey && model.is_key_ghost ((DConfKey) key))
                context.add_class ("erase");
            else
                context.remove_class ("erase");
        }
    }
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    public DConfKey key { get; construct; }
    private override Key abstract_key { get { return (Key) key; }}

    construct
    {
        SettingsModel model = modifications_handler.model;
        get_style_context ().add_class ("dconf-key");

        if (boolean_switch != null)
            ((!) boolean_switch).notify ["active"].connect (
                        () => model.set_key_value (key, new Variant.boolean (((!) boolean_switch).get_active ())));

        key_info_label.get_style_context ().add_class ("italic-label");
        key_info_label.set_label (_("No Schema Found"));
    }

    public KeyListBoxRowEditableNoSchema (DConfKey _key, ModificationsHandler modifications_handler, bool search_result_mode = false)
    {
        Object (key: _key, modifications_handler: modifications_handler, search_result_mode : search_result_mode);
    }

    protected override void update ()
    {
        SettingsModel model = modifications_handler.model;
        if (model.is_key_ghost (key))
        {
            if (boolean_switch != null)
            {
                ((!) boolean_switch).hide ();
                key_value_label.show ();
            }
            key_value_label.set_label (_("Key erased."));
        }
        else
        {
            Variant key_value = model.get_key_value (key);
            if (boolean_switch != null)
            {
                key_value_label.hide ();
                ((!) boolean_switch).show ();
                ((!) boolean_switch).set_active (key_value.get_boolean ());
            }
            key_value_label.set_label (Key.cool_text_value_from_variant (key_value, key.type_string));
        }
    }

    protected override string get_text ()
    {
        SettingsModel model = modifications_handler.model;
        return model.get_key_copy_text (key);
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        SettingsModel model = modifications_handler.model;
        Variant variant;

        if (model.is_key_ghost (key))
        {
            popover.new_copy_action (get_text ());
            return true;
        }

        if (search_result_mode)
        {
            variant = new Variant ("(ss)", key.parent_path, key.full_name);
            popover.new_gaction ("open_parent", "ui.open-path-with-selection(" + variant.print (false) + ")");
            popover.new_section ();
        }

        variant = new Variant.string (key.full_name);
        popover.new_gaction ("customize", "ui.open-path(" + variant.print (false) + ")");
        popover.new_copy_action (get_text ());


        if (key.type_string == "b" || key.type_string == "mb")
        {
            popover.new_section ();
            GLib.Action action = popover.create_buttons_list (key, true, modifications_handler);

            popover.change_dismissed.connect (() => {
                    destroy_popover ();
                    change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    hide_right_click_popover ();
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (key.type_string), gvariant)));
                    set_key_value (gvariant);
                });

            bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
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
            bool planned_change = modifications_handler.key_has_planned_change (key);
            Variant? planned_value = modifications_handler.get_key_planned_value (key);
            if (planned_change)
            {
                popover.new_section ();
                popover.new_action (planned_value == null ? "unerase" : "dismiss", () => {
                        destroy_popover ();
                        change_dismissed ();
                    });
            }

            if (!planned_change || planned_value != null) // not &&
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
    private ulong boolean_switch_toggled_handler = 0;

    construct
    {
        SettingsModel model = modifications_handler.model;
        get_style_context ().add_class ("gsettings-key");

        if (boolean_switch != null)
            boolean_switch_toggled_handler = ((!) boolean_switch).notify ["active"].connect (() => {
                    bool boolean = ((!) boolean_switch).get_active ();
                    if (boolean == key.default_value.get_boolean ())
                        model.set_key_to_default (key);
                    else
                        model.set_key_value (key, new Variant.boolean (boolean));
                });

        if (key.summary != "")
            key_info_label.set_label (key.summary);
        else
        {
            key_info_label.get_style_context ().add_class ("italic-label");
            key_info_label.set_label (_("No summary provided"));
        }
    }

    public KeyListBoxRowEditable (GSettingsKey _key, ModificationsHandler modifications_handler, bool search_result_mode = false)
    {
        Object (key: _key, modifications_handler: modifications_handler, search_result_mode : search_result_mode);
    }

    protected override void update ()
    {
        SettingsModel model = modifications_handler.model;
        if (boolean_switch != null)
        {
            bool boolean = model.get_key_value (key).get_boolean ();
            if (((!) boolean_switch).get_active () != boolean)
            {
                if (boolean_switch_toggled_handler > 0)
                {
                    SignalHandler.block ((!) boolean_switch, boolean_switch_toggled_handler);
                    ((!) boolean_switch).set_active (boolean);
                    SignalHandler.unblock ((!) boolean_switch, boolean_switch_toggled_handler);
                }
                else // first init
                    ((!) boolean_switch).set_active (boolean);
            }
        }

        StyleContext css_context = get_style_context ();
        if (model.is_key_default (key))
            css_context.remove_class ("edited");
        else
            css_context.add_class ("edited");
        key_value_label.set_label (Key.cool_text_value_from_variant (model.get_key_value (key), key.type_string));
    }

    protected override string get_text ()
    {
        SettingsModel model = modifications_handler.model;
        return model.get_key_copy_text (key);
    }

    protected override bool generate_popover (ContextPopover popover)
    {
        SettingsModel model = modifications_handler.model;
        Variant variant;

        if (search_result_mode)
        {
            variant = new Variant ("(ss)", key.parent_path, key.full_name);
            popover.new_gaction ("open_parent", "ui.open-path-with-selection(" + variant.print (false) + ")");
            popover.new_section ();
        }

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (key);
        Variant? planned_value = modifications_handler.get_key_planned_value (key);

        variant = new Variant.string (key.full_name);
        popover.new_gaction ("customize", "ui.open-path(" + variant.print (false) + ")");
        popover.new_copy_action (get_text ());

        if (key.type_string == "b" || key.type_string == "<enum>" || key.type_string == "mb"
            || (
                (key.type_string == "y" || key.type_string == "q" || key.type_string == "u" || key.type_string == "t")
                && (((GSettingsKey) key).range_type == "range")
                && (Key.get_variant_as_uint64 (((GSettingsKey) key).range_content.get_child_value (1)) - Key.get_variant_as_uint64 (((GSettingsKey) key).range_content.get_child_value (0)) < 13)
               )
            || (
                (key.type_string == "n" || key.type_string == "i" || key.type_string == "h" || key.type_string == "x")
                && (((GSettingsKey) key).range_type == "range")
                && (Key.get_variant_as_int64 (((GSettingsKey) key).range_content.get_child_value (1)) - Key.get_variant_as_int64 (((GSettingsKey) key).range_content.get_child_value (0)) < 13)
               ))
        {
            popover.new_section ();
            GLib.Action action = popover.create_buttons_list (key, true, modifications_handler);

            popover.change_dismissed.connect (() => {
                    destroy_popover ();
                    change_dismissed ();
                });
            popover.value_changed.connect ((gvariant) => {
                    hide_right_click_popover ();
                    Variant key_value = model.get_key_value (key);
                    action.change_state (new Variant.maybe (null, new Variant.maybe (new VariantType (key_value.get_type_string ()), gvariant)));
                    set_key_value (gvariant);
                });
        }
        else if (!delayed_apply_menu && !planned_change && key.type_string == "<flags>")
        {
            popover.new_section ();

            if (!model.is_key_default (key))
                popover.new_action ("default2", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
            popover.set_group ("flags");    // ensures a flag called "customize" or "default2" won't cause problems

            popover.create_flags_list ((GSettingsKey) key, modifications_handler);

            popover.value_changed.connect ((gvariant) => set_key_value (gvariant));
        }
        else if (planned_change)
        {
            popover.new_section ();
            popover.new_action ("dismiss", () => {
                    destroy_popover ();
                    change_dismissed ();
                });
            if (planned_value != null)
                popover.new_action ("default1", () => {
                        destroy_popover ();
                        set_key_value (null);
                    });
        }
        else if (!model.is_key_default (key))
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
            case "default1":
                /* Translators: "reset key value" action in the right-click menu on the list of keys */
                current_section.append (_("Set to default"), group_dot_action);     return;
            case "default2":
                new_multi_default_action (group_dot_action);                        return;
            case "dismiss":
                /* Translators: "dismiss change" action in the right-click menu on a key with pending changes */
                current_section.append (_("Dismiss change"), group_dot_action);     return;
            case "erase":
                /* Translators: "erase key" action in the right-click menu on a key without schema */
                current_section.append (_("Erase key"), group_dot_action);          return;
            case "unerase":
                /* Translators: "dismiss change" action in the right-click menu on a key without schema planned to be erased */
                current_section.append (_("Do not erase"), group_dot_action);       return;
            default:
                assert_not_reached ();
        }
    }

    public void new_gaction (string action_name, string action_action)
    {
        string action_text;
        switch (action_name)
        {
            /* Translators: "open key-editor page" action in the right-click menu on the list of keys */
            case "customize":       action_text = _("Customize…");          break;

            /* Translators: "open folder" action in the right-click menu on a folder */
            case "open":            action_text = _("Open");                break;

            /* Translators: "open parent folder" action in the right-click menu on a folder in a search result */
            case "open_parent":     action_text = _("Open parent folder");  break;

            /* Translators: "reset recursively" action in the right-click menu on a folder */
            case "recursivereset":  action_text = _("Reset recursively");   break;

            default: assert_not_reached ();
        }
        current_section.append (action_text, action_action);
    }

    public void new_copy_action (string text)
    {
        /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
        current_section.append (_("Copy"), "app.copy(\"" + text.escape (null).escape (null) + "\")");
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

    public void create_flags_list (GSettingsKey key, ModificationsHandler modifications_handler)
    {
        set_group ("flags");
        string group_dot = "flags.";

        GLib.Settings settings = key.settings;
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

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => {
                    active_flags = modifications_handler.get_key_custom_value (key).get_strv ();
                    bool active = flag in active_flags;
                    if (active != simple_action.get_state ())
                        simple_action.set_state (new Variant.boolean (active));
                });

            destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));
        }

        finalize_menu ();
    }

    /*\
    * * Choices
    \*/

    public GLib.Action create_buttons_list (Key key, bool has_default_value, ModificationsHandler modifications_handler)
    {
        SettingsModel model = modifications_handler.model;
        set_group ("enum");
        const string ACTION_NAME = "choice";
        string group_dot_action = "enum.choice";

        Variant key_value = model.get_key_value (key);
        VariantType original_type = key_value.get_type ();
        VariantType nullable_type = new VariantType.maybe (original_type);
        VariantType nullable_nullable_type = new VariantType.maybe (nullable_type);
        string type_string = original_type.dup_string ();

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (key);
        Variant? planned_value = modifications_handler.get_key_planned_value (key);

        Variant? value_variant;
        if (!has_default_value) // TODO report bug: if using ?: inside ?:, there's a "g_variant_ref: assertion 'value->ref_count > 0' failed"
            value_variant = modifications_handler.get_key_custom_value (key);
        else if (planned_change)
            value_variant = planned_value;
        else if (key is GSettingsKey && model.is_key_default ((GSettingsKey) key))
            value_variant = null;
        else
            value_variant = key_value;
        Variant variant = new Variant.maybe (original_type, value_variant);
        Variant nullable_variant;
        if (delayed_apply_menu && !planned_change)
            nullable_variant = new Variant.maybe (nullable_type, null);
        else
            nullable_variant = new Variant.maybe (nullable_type, variant);

        GLib.Action action = (GLib.Action) new SimpleAction.stateful (ACTION_NAME, nullable_nullable_type, nullable_variant);
        current_group.add_action (action);

        if (has_default_value)
        {
            bool complete_menu = delayed_apply_menu || planned_change;

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
            case "y":
            case "q":
            case "u":
            case "t":
                Variant range = ((GSettingsKey) key).range_content;
                for (uint64 number =  Key.get_variant_as_uint64 (range.get_child_value (0));
                            number <= Key.get_variant_as_uint64 (range.get_child_value (1));
                            number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
                break;
            case "n":
            case "i":
            case "h":
            case "x":
                Variant range = ((GSettingsKey) key).range_content;
                for (int64 number =  Key.get_variant_as_int64 (range.get_child_value (0));
                           number <= Key.get_variant_as_int64 (range.get_child_value (1));
                           number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
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
