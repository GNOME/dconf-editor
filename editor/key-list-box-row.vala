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

private const int MAX_ROW_WIDTH = LARGE_WINDOW_SIZE - 42;

private class ListBoxRowWrapper : ListBoxRow
{
    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class RegistryWarning : Grid
{
    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }
}

private class ListBoxRowHeader : Grid
{
    internal override void get_preferred_width (out int minimum_width, out int natural_width)
    {
        base.get_preferred_width (out minimum_width, out natural_width);
        natural_width = MAX_ROW_WIDTH;
    }

    internal ListBoxRowHeader (bool is_first_row, string? header_text)
    {
        if (header_text != null)
        {
            orientation = Orientation.VERTICAL;

            Label label = new Label ((!) header_text);
            label.visible = true;
            label.halign = Align.START;
            label.set_ellipsize (Pango.EllipsizeMode.END);
            StyleContext context = label.get_style_context ();
            context.add_class ("dim-label");
            context.add_class ("header-label");
            add (label);
        }

        halign = Align.CENTER;

        if (is_first_row)
            return;

        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.visible = true;
        separator.hexpand = true;
        add (separator);
    }
}

private abstract class ClickableListBoxRow : EventBox
{
    [CCode (notify = false)] public bool search_result_mode  { internal get; protected construct; default = false; }

    [CCode (notify = false)] public string full_name         { internal get; protected construct; }
    [CCode (notify = false)] public uint16 context_id        { internal get; protected construct; }

    /*\
    * * right click popover stuff
    \*/

    internal ContextPopover? nullable_popover = null;

    internal void destroy_popover ()
    {
        if (nullable_popover == null)       // check sometimes not useful
            return;
        ((!) nullable_popover).destroy ();
        nullable_popover = null;
    }

    internal void hide_right_click_popover ()
    {
        if (nullable_popover != null)
            ((!) nullable_popover).popdown ();
    }

    internal bool right_click_popover_visible ()
    {
        return (nullable_popover != null) && ((!) nullable_popover).visible;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/return-list-box-row.ui")]
private class ReturnListBoxRow : ClickableListBoxRow
{
    [GtkChild] private unowned Label folder_name_label;

    internal ReturnListBoxRow (string _full_name, uint16 _context_id)
    {
        Object (full_name: _full_name, context_id: _context_id, search_result_mode: true);
        /* Translators: first item of the keys list displayed during a search, the %s is a folder path usually */
        folder_name_label.set_text (_("Go to “%s”").printf (_full_name));
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/folder-list-box-row.ui")]
private class FolderListBoxRow : ClickableListBoxRow
{
    [GtkChild] private unowned Label folder_name_label;

    [CCode (notify = false)] public bool path_search { internal get; internal construct; }

    internal FolderListBoxRow (string label, string path, bool path_search, bool search_result_mode)
    {
        Object (full_name: path, context_id: ModelUtils.folder_context_id, path_search: path_search, search_result_mode: search_result_mode);
        folder_name_label.set_text (search_result_mode ? path : label);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/filter-list-box-row.ui")]
private class FilterListBoxRow : ClickableListBoxRow
{
    public bool is_local_search { internal get; protected construct; }

    [GtkChild] private unowned Label folder_name_label;

    internal FilterListBoxRow (string name, string path)
    {
        Object (is_local_search: name != "" && path != "/", full_name: path, context_id: ModelUtils.folder_context_id, search_result_mode: true);

        if (is_local_search)
            /* Translators: first item of the keys list displayed during browsing, the %s is the current folder name */
            folder_name_label.set_text (_("Search in “%s” folder").printf (name));

        else if (path == "/")
            /* Translators: first item of the keys list displayed during browsing at root path */
            folder_name_label.set_text (_("Open path entry"));

        else
            /* Translators: last item of the keys list displayed during a local search */
            folder_name_label.set_text (_("Search everywhere"));
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/search-list-box-row.ui")]
private class SearchListBoxRow : ClickableListBoxRow
{
    [GtkChild] private unowned Label search_label;

    internal SearchListBoxRow (string search)
    {
        Object (full_name: search, context_id: ModelUtils.undefined_context_id);
        search_label.set_text (search);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private class KeyListBoxRow : ClickableListBoxRow, AdaptativeWidget
{
    [GtkChild] private unowned Grid key_name_and_value_grid;
    [GtkChild] private unowned Label key_name_label;
    [GtkChild] private unowned Label key_type_label;
    [GtkChild] private unowned Label key_value_label;
    [GtkChild] private unowned Label key_info_label;
    private Switch? boolean_switch = null;

    [CCode (notify = false)] public string key_name    { internal get; internal construct; }
    [CCode (notify = false)] public string type_string { internal get; internal construct; }
    [CCode (notify = false)] public bool has_schema    { internal get; internal construct; }

    private bool _delay_mode = false;
    [CCode (notify = false)] internal bool delay_mode
    {
        private get
        {
            return _delay_mode;
        }
        set
        {
            _delay_mode = value;
            if (boolean_switch != null)
                hide_or_show_switch ();
        }
    }

    [CCode (notify = false)] internal bool small_keys_list_rows
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

    private bool thin_window = false;
    internal void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _thin_window = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (thin_window == _thin_window)
            return;
        thin_window = _thin_window;

        if (_thin_window)
        {
            if (boolean_switch != null)
                ((!) boolean_switch).hide ();
            key_value_label.hide ();
            key_type_label.show ();
        }
        else
        {
            key_type_label.hide ();
            if (_use_switch && !delay_mode)
                ((!) boolean_switch).show ();
            else
                key_value_label.show ();
        }
    }

    construct
    {
        if (has_schema)
            get_style_context ().add_class ("gsettings-key");
        else
            get_style_context ().add_class ("dconf-key");

        if (type_string == "b")
        {
            boolean_switch = new Switch ();
            ((!) boolean_switch).can_focus = false;
            ((!) boolean_switch).halign = Align.END;
            ((!) boolean_switch).valign = Align.CENTER;
            if (has_schema)
                ((!) boolean_switch).set_detailed_action_name ("browser.empty(('',uint16 0,true,true))");
            else
                ((!) boolean_switch).set_detailed_action_name ("browser.empty(('',true))");

            _use_switch = true;
            hide_or_show_switch ();

            key_name_and_value_grid.attach ((!) boolean_switch, 1, 0, 1, 2);
        }

        key_name_label.set_label (search_result_mode ? full_name : key_name);
    }

    internal KeyListBoxRow (bool _has_schema,
                            string _type_string,
                            uint16 _context_id,
                            string summary,
                            bool italic_summary,
                            bool _delay_mode,
                            string _key_name,
                            string _full_name,
                            bool _search_result_mode)
    {
        Object (has_schema: _has_schema,
                type_string: _type_string,
                context_id: _context_id,
                delay_mode: _delay_mode,
                key_name: _key_name,
                full_name: _full_name,
                search_result_mode: _search_result_mode);

        if (italic_summary)
            key_info_label.get_style_context ().add_class ("italic-label");
        key_info_label.set_label (summary);
    }

    internal void toggle_boolean_key ()
    {
        if (type_string != "b")
            return;
        if (boolean_switch == null)
            return;
        bool state = ((!) boolean_switch).get_active ();
        ((!) boolean_switch).set_active (!state);
    }

    internal void change_dismissed ()
    {
        ModelButton actionable = new ModelButton ();
        actionable.visible = false;
        Variant variant = new Variant.string (full_name);
        actionable.set_detailed_action_name ("ui.dismiss-change(" + variant.print (false) + ")");
        Container child = (Container) get_child ();
        child.add (actionable);
        actionable.clicked ();
        child.remove (actionable);
        actionable.destroy ();
    }

    internal void on_delete_call ()
    {
        set_key_value (null);
    }

    internal void set_key_value (Variant? new_value)
    {
        ModelButton actionable = new ModelButton ();
        actionable.visible = false;
        Variant variant;
        if (new_value == null)
        {
            if (has_schema)
            {
                variant = new Variant ("(sq)", full_name, context_id);
                actionable.set_detailed_action_name ("view.set-to-default(" + variant.print (true) + ")");
            }
            else
            {
                variant = new Variant.string (full_name);
                actionable.set_detailed_action_name ("ui.erase(" + variant.print (false) + ")");
            }
        }
        else
        {
            variant = new Variant ("(sqv)", full_name, context_id, (!) new_value);
            actionable.set_detailed_action_name ("view.set-key-value(" + variant.print (true) + ")");
        }
        Container child = (Container) get_child ();
        child.add (actionable);
        actionable.clicked ();
        child.remove (actionable);
        actionable.destroy ();
    }

    /*\
    * * Updating
    \*/

    private bool key_value_label_has_italic_label_class = false;
    private bool key_type_label_has_italic_label_class = false;
    internal void update_label (string key_value_string, bool key_value_italic, string key_type_string, bool key_type_italic)
    {
        if (key_value_italic)
        {
            if (!key_value_label_has_italic_label_class) key_value_label.get_style_context ().add_class ("italic-label");
        }
        else if (key_value_label_has_italic_label_class) key_value_label.get_style_context ().remove_class ("italic-label");
        key_value_label_has_italic_label_class = key_value_italic;
        key_value_label.set_label (key_value_string);

        if (key_type_italic)
        {
            if (!key_type_label_has_italic_label_class) key_type_label.get_style_context ().add_class ("italic-label");
        }
        else if (key_type_label_has_italic_label_class) key_type_label.get_style_context ().remove_class ("italic-label");
        key_type_label_has_italic_label_class = key_type_italic;
        key_type_label.set_label (key_type_string);
    }

    private bool _use_switch = false;
    internal void use_switch (bool show)
        requires (boolean_switch != null)
    {
        if (_use_switch != show)
        {
            _use_switch = show;
            hide_or_show_switch ();
        }
    }
    private void hide_or_show_switch ()
        requires (boolean_switch != null)
    {
        if (thin_window)
        {
            key_value_label.hide ();
            ((!) boolean_switch).hide ();
            key_type_label.show ();
        }
        else if (_use_switch && !delay_mode)
        {
            key_value_label.hide ();
            key_type_label.hide ();
            ((!) boolean_switch).show ();
        }
        else
        {
            ((!) boolean_switch).hide ();
            key_type_label.hide ();
            key_value_label.show ();
        }
    }

    internal void update_switch (bool key_value_boolean, string detailed_action_name)
        requires (boolean_switch != null)
    {
        ((!) boolean_switch).set_action_name ("browser.empty");
        ((!) boolean_switch).set_active (key_value_boolean);
        ((!) boolean_switch).set_detailed_action_name (detailed_action_name);
    }
}

private class ContextPopover : Popover
{
    private GLib.Menu menu = new GLib.Menu ();
    private GLib.Menu current_section;

    private ActionMap current_group = new SimpleActionGroup ();

    // public signals
    internal signal void value_changed (Variant? gvariant);
    internal signal void change_dismissed ();

    internal ContextPopover ()
    {
        new_section_real ();

        insert_action_group ("popmenu", (SimpleActionGroup) current_group);

        bind_model (menu, null);
    }

    /*\
    * * Simple actions
    \*/

    internal void new_gaction (string action_name, string action_action)
    {
        string action_text;
        switch (action_name)
        {
            /* Translators: "copy to clipboard" action in the right-click menu on the list of keys */
            case "copy":            action_text = _("Copy");                break;

            /* Translators: "open key-editor page" action in the right-click menu on the list of keys */
            case "customize":       action_text = _("Customize…");          break;

            /* Translators: "reset key value" action in the right-click menu on the list of keys */
            case "default1":        action_text = _("Set to default");      break;

            case "default2": new_multi_default_action (action_action);      return;

            /* Translators: "open key-editor page" action in the right-click menu on the list of keys, when key is hard-conflicting */
            case "detail":          action_text = _("Show details…");       break;

            /* Translators: "dismiss change" action in the right-click menu on a key with pending changes */
            case "dismiss":         action_text = _("Dismiss change");      break;

            /* Translators: "erase key" action in the right-click menu on a key without schema */
            case "erase":           action_text = _("Erase key");           break;

            /* Translators: "go to" action in the right-click menu on a "go back" line during search */
            case "go-back":         action_text = _("Go to this path");     break;

            /* Translators: "open folder" action in the right-click menu on a folder */
            case "open-folder":     action_text = _("Open");                break;

            /* Translators: "open" action in the right-click menu on a "show folder info" row */
            case "open-config":     action_text = _("Show properties");     break;

            /* Translators: "open search" action in the right-click menu on a search */
            case "open-search":     action_text = _("Search");              break;

            /* Translators: "open parent folder" action in the right-click menu on a folder in a search result */
            case "open-parent":     action_text = _("Open parent folder");  break;

            /* Translators: "reset recursively" action in the right-click menu on a folder */
            case "recursivereset":  action_text = _("Reset recursively");   break;

            /* Translators: "dismiss change" action in the right-click menu on a key without schema planned to be erased */
            case "unerase":         action_text = _("Do not erase");        break;

            default: assert_not_reached ();
        }
        current_section.append (action_text, action_action);
    }

    internal void new_section ()
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

    internal void create_flags_list (string [] active_flags, string [] all_flags)
    {
        foreach (string flag in all_flags)
            create_flag (flag, flag in active_flags, all_flags);

        finalize_menu ();
    }
    private void create_flag (string flag, bool active, string [] all_flags)
    {
        SimpleAction simple_action = new SimpleAction.stateful (flag, null, new Variant.boolean (active));
        current_group.add_action (simple_action);

        current_section.append (flag, @"popmenu.$flag");

        simple_action.change_state.connect ((gaction, gvariant) => {
                gaction.set_state ((!) gvariant);

                string [] new_flags = new string [0];
                foreach (string iter in all_flags)
                {
                    SimpleAction action = (SimpleAction) current_group.lookup_action (iter);
                    if (((!) action.state).get_boolean ())
                        new_flags += action.name;
                }
                Variant variant = new Variant.strv (new_flags);
                value_changed (variant);
            });
    }

    internal void update_flag_status (string flag, bool active)
    {
        SimpleAction simple_action = (SimpleAction) current_group.lookup_action (flag);
        if (active != simple_action.get_state ())
            simple_action.set_state (new Variant.boolean (active));
    }

    /*\
    * * Choices
    \*/

    internal GLib.Action create_buttons_list (bool display_default_value, bool delayed_apply_menu, bool planned_change, string settings_type, Variant? range_content_or_null, Variant? value_variant)
    {
        // TODO report bug: if using ?: inside ?:, there's a "g_variant_ref: assertion 'value->ref_count > 0' failed"
        const string ACTION_NAME = "choice";
        string group_dot_action = "popmenu.choice";

        string type_string = settings_type == "<enum>" ? "s" : settings_type;
        VariantType original_type = new VariantType (type_string);
        VariantType nullable_type = new VariantType.maybe (original_type);
        VariantType nullable_nullable_type = new VariantType.maybe (nullable_type);

        Variant variant = new Variant.maybe (original_type, value_variant);
        Variant nullable_variant;
        if (delayed_apply_menu && !planned_change)
            nullable_variant = new Variant.maybe (nullable_type, null);
        else
            nullable_variant = new Variant.maybe (nullable_type, variant);

        GLib.Action action = (GLib.Action) new SimpleAction.stateful (ACTION_NAME, nullable_nullable_type, nullable_variant);
        current_group.add_action (action);

        if (display_default_value)
        {
            bool complete_menu = delayed_apply_menu || planned_change;

            if (complete_menu)
                /* Translators: "no change" option in the right-click menu on a key when on delayed mode */
                current_section.append (_("No change"), @"$group_dot_action(@mm$type_string nothing)");

            if (range_content_or_null != null)
                new_multi_default_action (@"$group_dot_action(@mm$type_string just nothing)");
            else if (complete_menu)
                /* Translators: "erase key" option in the right-click menu on a key without schema when on delayed mode */
                current_section.append (_("Erase key"), @"$group_dot_action(@mm$type_string just nothing)");
        }

        switch (settings_type)
        {
            case "b":
                current_section.append (Key.cool_boolean_text_value (true), @"$group_dot_action(@mmb true)");
                current_section.append (Key.cool_boolean_text_value (false), @"$group_dot_action(@mmb false)");
                break;
            case "<enum>":      // defined by the schema
                Variant range = (!) range_content_or_null;
                uint size = (uint) range.n_children ();
                if (size == 0 || (size == 1 && !display_default_value))
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
                Variant range = (!) range_content_or_null;
                for (uint64 number =  Key.get_variant_as_uint64 (range.get_child_value (0));
                            number <= Key.get_variant_as_uint64 (range.get_child_value (1));
                            number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
                break;
            case "n":
            case "i":
            case "h":
            case "x":
                Variant range = (!) range_content_or_null;
                for (int64 number =  Key.get_variant_as_int64 (range.get_child_value (0));
                           number <= Key.get_variant_as_int64 (range.get_child_value (1));
                           number++)
                    current_section.append (number.to_string (), @"$group_dot_action(@mm$type_string $number)");
                break;
            case "()":
                current_section.append ("()", @"$group_dot_action(@mm() ())");
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
