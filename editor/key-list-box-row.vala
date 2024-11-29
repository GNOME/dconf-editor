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
    construct
    {
        margin_top = 6;
        margin_bottom = 6;
    }
}

private class RegistryWarning : Grid
{
    // internal override void get_preferred_width (out int minimum_width, out int natural_width)
    // {
    //     base.get_preferred_width (out minimum_width, out natural_width);
    //     natural_width = MAX_ROW_WIDTH;
    // }
}

private class ListBoxRowHeader : Box
{
    // internal override void get_preferred_width (out int minimum_width, out int natural_width)
    // {
    //     base.get_preferred_width (out minimum_width, out natural_width);
    //     natural_width = MAX_ROW_WIDTH;
    // }

    internal ListBoxRowHeader (bool is_first_row, string header_text)
    {
        orientation = Orientation.VERTICAL;
        halign = Align.START;
        add_css_class ("header-row");
        if (is_first_row)
            add_css_class ("first-row");

        Label label = new Label ((!) header_text);
        label.halign = Align.START;
        label.set_ellipsize (Pango.EllipsizeMode.END);
        label.add_css_class ("heading");
        append (label);

    }
}

private abstract class ClickableListBoxRow : Box
{
    [CCode (notify = false)] public bool search_result_mode  { internal get; protected construct; default = false; }

    [CCode (notify = false)] public string full_name         { internal get; protected construct; }
    [CCode (notify = false)] public uint16 context_id        { internal get; protected construct; }

    /*\
    * * right click popover stuff
    \*/

    internal Popover? nullable_popover = null;

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

    internal void show_right_click_popover (int event_x, int event_y)
    {
        if (nullable_popover == null)
            return;

        Gdk.Rectangle position = {x: event_x, y: event_y};
        ((!) nullable_popover).set_pointing_to (position);
        ((!) nullable_popover).popup ();
    }

    /* FIXME: Crudely copied from RegistryList. Needs a lot of work.
     */

    internal void generate_popover_if_needed (ModificationsHandler modifications_handler)
    {
        if (nullable_popover != null)
            return;

        // boolean test for rows without popovers, but that never happens in current design
        if (!generate_popover (modifications_handler))
        {
            // ((!) nullable_popover).destroy ();  // TODO better, again
            // nullable_popover = null;
            return;
        }

        ((!) nullable_popover).destroy.connect_after (() => { nullable_popover = null; });
        ((!) nullable_popover).has_arrow = false;
        append ((!) nullable_popover);
    }

    protected virtual bool generate_popover (ModificationsHandler modifications_handler)
    {
        return false;
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

    [GtkCallback]
    private void on_right_mouse_button_pressed (GestureClick gesture, int n_press, double x, double y)
    {
        show_right_click_popover ((int) x, (int) y);
    }

    protected override bool generate_popover (ModificationsHandler modifications_handler)
    {
        Variant variant = new Variant.string (full_name);

        ContextPopoverBuilder builder = new ContextPopoverBuilder ();

        if (search_result_mode)
        {
            builder.new_gaction ("open-parent", "browser.open-parent(" + variant.print (false) + ")");
            builder.new_section ();
        }

        builder.new_gaction ("open-folder", "browser.open-folder(" + variant.print (false) + ")");
        builder.new_gaction ("copy", "browser.copy-value(" + _get_folder_copy_text_variant ().print (false) + ")");
        builder.new_section ();
        builder.new_gaction ("recursivereset", "ui.reset-recursive(" + variant.print (false) + ")");

        nullable_popover = builder.build ();

        return true;
    }

    private inline Variant _get_folder_copy_text_variant ()
    {
        return new Variant.string (full_name);
    }

}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private class KeyListBoxRow : ClickableListBoxRow
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
    // internal void set_window_size (AdaptativeWidget.WindowSize new_size)
    // {
    //     bool _thin_window = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
    //     if (thin_window == _thin_window)
    //         return;
    //     thin_window = _thin_window;

    //     if (_thin_window)
    //     {
    //         if (boolean_switch != null)
    //             ((!) boolean_switch).hide ();
    //         key_value_label.hide ();
    //         key_type_label.show ();
    //     }
    //     else
    //     {
    //         key_type_label.hide ();
    //         if (_use_switch && !delay_mode)
    //             ((!) boolean_switch).show ();
    //         else
    //             key_value_label.show ();
    //     }
    // }

    construct
    {
        if (has_schema)
            add_css_class ("gsettings-key");
        else
            add_css_class ("dconf-key");

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
            key_info_label.add_css_class ("italic-label");
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
        Button actionable = new Button ();
        actionable.visible = false;
        Variant variant = new Variant.string (full_name);
        actionable.set_detailed_action_name ("ui.dismiss-change(" + variant.print (false) + ")");
        // FIXME What even
        // key_name_and_value_grid.add (actionable);
        // actionable.clicked ();
        // key_name_and_value_grid.remove (actionable);
        // actionable.destroy ();
    }

    internal void on_delete_call ()
    {
        set_key_value (null);
    }

    internal void set_key_value (Variant? new_value)
    {
        Button actionable = new Button ();
        actionable.visible = false;
        Variant variant;
        if (new_value == null)
        {
            if (has_schema)
            {
                variant = new Variant ("(sq)", full_name, context_id);
                activate_action_variant ("view.set-to-default", variant);
            }
            else
            {
                variant = new Variant.string (full_name);
                activate_action_variant ("ui.erase", variant);
            }
        }
        else
        {
            variant = new Variant ("(sqv)", full_name, context_id, (!) new_value);
            activate_action_variant ("view.set-key-value", variant);
        }
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
            if (!key_value_label_has_italic_label_class) key_value_label.add_css_class ("italic-label");
        }
        else if (key_value_label_has_italic_label_class) key_value_label.remove_css_class ("italic-label");
        key_value_label_has_italic_label_class = key_value_italic;
        key_value_label.set_label (key_value_string);

        if (key_type_italic)
        {
            if (!key_type_label_has_italic_label_class) key_type_label.add_css_class ("italic-label");
        }
        else if (key_type_label_has_italic_label_class) key_type_label.remove_css_class ("italic-label");
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

    [GtkCallback]
    private void on_right_mouse_button_pressed (GestureClick gesture, int n_press, double x, double y)
    {
        show_right_click_popover ((int) x, (int) y);
    }

    protected override bool generate_popover (ModificationsHandler modifications_handler)
    {
        if (context_id != ModelUtils.dconf_context_id)
            return generate_gsettings_popover (modifications_handler, _get_key_copy_text_variant (modifications_handler));
        else if (modifications_handler.model.is_key_ghost (full_name))
            return generate_ghost_popover (_get_key_copy_text_variant (modifications_handler));
        else
            return generate_dconf_popover (modifications_handler, _get_key_copy_text_variant (modifications_handler));
    }

    private inline Variant _get_key_copy_text_variant (ModificationsHandler modifications_handler)
    {
        return new Variant.string (_get_key_copy_text (modifications_handler));
    }

    private inline string _get_key_copy_text (ModificationsHandler modifications_handler)
    {
        return modifications_handler.model.get_suggested_key_copy_text (full_name, context_id);
    }

    private bool generate_gsettings_popover (ModificationsHandler modifications_handler, Variant copy_text_variant)
    {
        ContextPopoverBuilder builder = new ContextPopoverBuilder ();

        SettingsModel model = modifications_handler.model;

        RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, context_id, (uint16) (PropertyQuery.TYPE_CODE & PropertyQuery.RANGE_TYPE & PropertyQuery.RANGE_CONTENT & PropertyQuery.IS_DEFAULT & PropertyQuery.KEY_CONFLICT & PropertyQuery.KEY_VALUE)));

        string type_string;
        uint8 _range_type, _key_conflict;
        Variant range_content;
        bool is_key_default;
        if (!properties.lookup (PropertyQuery.TYPE_CODE,            "s",    out type_string))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.RANGE_TYPE,           "y",    out _range_type))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.RANGE_CONTENT,        "v",    out range_content))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.IS_DEFAULT,           "b",    out is_key_default))
            assert_not_reached ();
        if (!properties.lookup (PropertyQuery.KEY_CONFLICT,         "y",    out _key_conflict))
            assert_not_reached ();
        RangeType range_type = (RangeType) _range_type;
        KeyConflict key_conflict = (KeyConflict) _key_conflict;

        Variant variant_s = new Variant.string (full_name);
        Variant variant_sq = new Variant ("(sq)", full_name, context_id);

        if (search_result_mode)
        {
            builder.new_gaction ("open-parent", "browser.open-parent(" + variant_s.print (false) + ")");
            builder.new_section ();
        }

        if (key_conflict == KeyConflict.HARD)
        {
            builder.new_gaction ("detail", "browser.open-object(" + variant_sq.print (true) + ")");
            builder.new_gaction ("copy", "browser.copy-value(" + copy_text_variant.print (false) + ")");
            properties.clear ();
            return true; // anything else is value-related, so we are done
        }

        bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
        bool planned_change = modifications_handler.key_has_planned_change (full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);

        builder.new_gaction ("customize", "browser.open-object(" + variant_sq.print (true) + ")");
        builder.new_gaction ("copy", "browser.copy-value(" + copy_text_variant.print (false) + ")");

        if (type_string == "b" || type_string == "<enum>" || type_string == "mb"
            || (
                (type_string == "y" || type_string == "q" || type_string == "u" || type_string == "t")
                && (range_type == RangeType.RANGE)
                && (Key.get_variant_as_uint64 (range_content.get_child_value (1)) - Key.get_variant_as_uint64 (range_content.get_child_value (0)) < 13)
               )
            || (
                (type_string == "n" || type_string == "i" || type_string == "x")    // the handle type cannot have range
                && (range_type == RangeType.RANGE)
                && (Key.get_variant_as_int64 (range_content.get_child_value (1)) - Key.get_variant_as_int64 (range_content.get_child_value (0)) < 13)
               )
            || type_string == "()")
        {
            GLib.Action? action = null;

            builder.new_section ();
            if (planned_change)
                builder.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content,
                                                      modifications_handler.get_key_planned_value (full_name), out action);
            else if (is_key_default)
                builder.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content,
                                                      null, out action);
            else
            {
                Variant key_value;
                if (!properties.lookup (PropertyQuery.KEY_VALUE,    "v",    out key_value))
                    assert_not_reached ();
                builder.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, range_content, key_value, out action);
            }

            builder.on_change_dismissed (() => on_popover_change_dismissed ());
            builder.on_value_changed (on_popover_value_change);
        }
        else if (!delayed_apply_menu && !planned_change && type_string == "<flags>")
        {
            builder.new_section ();

            if (!is_key_default)
                builder.new_gaction ("default2", "view.set-to-default(" + variant_sq.print (true) + ")");

            string [] all_flags = range_content.get_strv ();
            builder.create_flags_list (modifications_handler.get_key_custom_value (full_name, context_id).get_strv (), all_flags);
            // FIXME Unbreak this :/
            ActionMap action_map;
            builder.peek_action_map (out action_map);
            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (
                () => {
                    string [] active_flags = modifications_handler.get_key_custom_value (full_name, context_id).get_strv ();
                    foreach (string flag in all_flags)
                        ContextPopoverBuilder.update_flag_status (action_map, flag, flag in active_flags);
                }
            );
            // FIXME We really need this but also I don't care yet because this whole thing needs to be replaced
            // popover.destroy.connect (() => modifications_handler.disconnect (delayed_modifications_changed_handler));

            builder.on_value_changed (set_key_value);
        }
        else if (planned_change)
        {
            builder.new_section ();
            builder.new_gaction ("dismiss", "ui.dismiss-change(" + variant_s.print (false) + ")");

            if (planned_value != null)
                builder.new_gaction ("default1", "view.set-to-default(" + variant_sq.print (true) + ")");
        }
        else if (!is_key_default)
        {
            builder.new_section ();
            builder.new_gaction ("default1", "view.set-to-default(" + variant_sq.print (true) + ")");
        }
        properties.clear ();

        nullable_popover = builder.build ();

        return true;
    }

    private bool generate_ghost_popover (Variant copy_text_variant)
    {
        nullable_popover = new ContextPopoverBuilder ()
            .new_gaction ("copy", "browser.copy-value(" + copy_text_variant.print (false) + ")")
            .build ();
        return true;
    }

    private bool generate_dconf_popover (ModificationsHandler modifications_handler, Variant copy_text_variant)
    {
        ContextPopoverBuilder builder = new ContextPopoverBuilder ();

        SettingsModel model = modifications_handler.model;
        Variant variant_s = new Variant.string (full_name);
        Variant variant_sq = new Variant ("(sq)", full_name, ModelUtils.dconf_context_id);

        if (search_result_mode)
        {
            builder.new_gaction ("open-parent", "browser.open-parent(" + variant_s.print (false) + ")");
            builder.new_section ();
        }

        builder.new_gaction ("customize", "browser.open-object(" + variant_sq.print (true) + ")");
        builder.new_gaction ("copy", "browser.copy-value(" + copy_text_variant.print (false) + ")");

        bool planned_change = modifications_handler.key_has_planned_change (full_name);
        Variant? planned_value = modifications_handler.get_key_planned_value (full_name);

        GLib.Action? action = null;

        if (type_string == "b" || type_string == "mb" || type_string == "()")
        {
            builder.new_section ();
            bool delayed_apply_menu = modifications_handler.get_current_delay_mode ();
            RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (full_name, ModelUtils.dconf_context_id, (uint16) PropertyQuery.KEY_VALUE));
            Variant key_value;
            if (!properties.lookup (PropertyQuery.KEY_VALUE,        "v",    out key_value))
                assert_not_reached ();
            properties.clear ();
            builder.create_buttons_list (true, delayed_apply_menu, planned_change, type_string, null,
                                                              planned_change ? planned_value : key_value);

            builder.on_change_dismissed (() => on_popover_change_dismissed ());
            builder.on_value_changed (on_popover_value_change);

            if (!delayed_apply_menu)
            {
                builder.new_section ();
                builder.new_gaction ("erase", "ui.erase(" + variant_s.print (false) + ")");
            }
        }
        else
        {
            if (planned_change)
            {
                builder.new_section ();
                builder.new_gaction (planned_value == null ? "unerase" : "dismiss", "ui.dismiss-change(" + variant_s.print (false) + ")");
            }

            if (!planned_change || planned_value != null) // not &&
            {
                builder.new_section ();
                builder.new_gaction ("erase", "ui.erase(" + variant_s.print (false) + ")");
            }
        }

        nullable_popover = builder.build ();

        return true;
    }

    private void on_popover_change_dismissed ()
    {
        destroy_popover ();
        change_dismissed ();
    }

    private void on_popover_value_change (Variant? gvariant)
    {
        set_key_value (gvariant);
    }
}

private class ContextPopoverBuilder : Object
{
    private GLib.Menu menu = new GLib.Menu ();
    private GLib.Menu current_section;

    private ActionMap current_group = new SimpleActionGroup ();

    internal delegate void ValueChangedCallback (Variant? gvariant);
    internal delegate void ChangeDismissedCallback ();

    private ValueChangedCallback value_changed;
    private ChangeDismissedCallback change_dismissed;

    // public signals
    // internal signal void value_changed (Variant? gvariant);
    // internal signal void change_dismissed ();

    internal ContextPopoverBuilder ()
    {
        new_section_real ();
    }

    internal Popover build ()
    {
        Gtk.PopoverMenu popover = new Gtk.PopoverMenu.from_model (menu);
        popover.insert_action_group ("popmenu", (SimpleActionGroup) current_group);
        return popover;
    }

    internal ContextPopoverBuilder peek_action_map (out ActionMap out_action_map)
    {
        out_action_map = current_group;
        return this;
    }

    internal ContextPopoverBuilder on_value_changed (ValueChangedCallback callback)
    {
        value_changed = callback;
        return this;
    }

    internal ContextPopoverBuilder on_change_dismissed (ChangeDismissedCallback callback)
    {
        change_dismissed = callback;
        return this;
    }

    /*\
    * * Simple actions
    \*/

    internal ContextPopoverBuilder new_gaction (string action_name, string action_action)
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

            case "default2": new_multi_default_action (action_action);      return this;

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
        return this;
    }

    internal ContextPopoverBuilder new_section ()
    {
        current_section.freeze ();
        new_section_real ();
        return this;
    }

    private void new_section_real ()
    {
        current_section = new GLib.Menu ();
        menu.append_section (null, current_section);
    }

    /*\
    * * Flags
    \*/

    internal ContextPopoverBuilder create_flags_list (string [] active_flags, string [] all_flags)
    {
        foreach (string flag in all_flags)
            create_flag (flag, flag in active_flags, all_flags);

        finalize_menu ();

        return this;
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

    internal static void update_flag_status (ActionMap action_map, string flag, bool active)
    {
        SimpleAction simple_action = (SimpleAction) action_map.lookup_action (flag);
        if (active != simple_action.get_state ())
            simple_action.set_state (new Variant.boolean (active));
    }

    /*\
    * * Choices
    \*/

    internal ContextPopoverBuilder create_buttons_list (bool display_default_value, bool delayed_apply_menu, bool planned_change, string settings_type, Variant? range_content_or_null, Variant? value_variant, out GLib.Action out_action = null)
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

        GLib.SimpleAction choice_action = new SimpleAction.stateful (ACTION_NAME, nullable_nullable_type, nullable_variant);
        current_group.add_action (choice_action);

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

        choice_action.notify["state"].connect (
            () => {
                if (choice_action.state != null)
                    value_changed (((!) choice_action.state).get_maybe ());
                else
                    change_dismissed ();
            }
        );

        out_action = (GLib.Action) choice_action;

        finalize_menu ();

        return this;
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

