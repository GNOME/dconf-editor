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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-view.ui")]
private abstract class RegistryList : Grid, BrowsableView
{
    [GtkChild] protected ListBox key_list_box;
    [GtkChild] protected RegistryPlaceholder placeholder;
    [GtkChild] private ScrolledWindow scrolled;

    protected GLib.ListStore list_model = new GLib.ListStore (typeof (SettingObject));

    protected GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    public ModificationsHandler modifications_handler { protected get; set; }

    protected bool _small_keys_list_rows;
    public bool small_keys_list_rows
    {
        set
        {
            _small_keys_list_rows = value;
            key_list_box.foreach ((row) => {
                    Widget? row_child = ((ListBoxRow) row).get_child ();
                    if (row_child != null && (!) row_child is KeyListBoxRow)
                        ((KeyListBoxRow) (!) row_child).small_keys_list_rows = value;
                });
        }
    }

    protected void scroll_to_row (ListBoxRow row, bool grab_focus)
    {
        key_list_box.select_row (row);
        if (grab_focus)
            row.grab_focus ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }

    public void invalidate_popovers ()
    {
        uint position = 0;
        ClickableListBoxRow? row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (0);
        while (row != null)
        {
            ((!) row).destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
    }

    public void hide_or_show_toggles (bool show)
    {
        key_list_box.@foreach ((row_wrapper) => {
                ClickableListBoxRow? row = (ClickableListBoxRow) ((ListBoxRowWrapper) row_wrapper).get_child ();
                if (row == null)
                    assert_not_reached ();
                if ((!) row is KeyListBoxRow && ((KeyListBoxRow) (!) row).type_string == "b")
                    ((KeyListBoxRow) row).hide_or_show_toggles (show);
            });
    }

    public string get_selected_row_name ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            return ((SettingObject) list_model.get_object (position)).full_name;
        }
        else
            return "";
    }

    public abstract void select_first_row ();

    public void select_row_named (string selected, string context, bool grab_focus)
    {
        check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (selected, context));
        if (row != null)
            scroll_to_row ((!) row, grab_focus);
    }
    private int get_row_position (string selected, string context)
    {
        uint position = 0;
        uint fallback = 0;
        while (position < list_model.get_n_items ())
        {
            SettingObject object = (SettingObject) list_model.get_object (position);
            if (object.full_name == selected)
            {
                if (!SettingsModel.is_key_path (object.full_name)
                 || context == ".dconf" && object is DConfKey // theorical?
                 || object is GSettingsKey && ((GSettingsKey) object).schema_id == context)
                    return (int) position;
                fallback = position;
            }
            position++;
        }
        return (int) fallback; // selected row may have been removed or context could be ""
    }

    public abstract bool up_or_down_pressed (bool is_down);

    protected void set_delayed_icon (KeyListBoxRow row)
    {
        SettingsModel model = modifications_handler.model;
        StyleContext context = row.get_style_context ();
        if (modifications_handler.key_has_planned_change (row.full_name))
        {
            context.add_class ("delayed");
            if (!model.key_has_schema (row.full_name))
            {
                if (modifications_handler.get_key_planned_value (row.full_name) == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
        {
            context.remove_class ("delayed");
            if (!model.key_has_schema (row.full_name) && model.is_key_ghost (row.full_name))
                context.add_class ("erase");
            else
                context.remove_class ("erase");
        }
    }

    /*\
    * * Keyboard calls
    \*/

    public bool show_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();

        if (row.right_click_popover_visible ())
            row.hide_right_click_popover ();
        else
        {
            row.show_right_click_popover (get_copy_text_variant (row));
            rows_possibly_with_popover.append (row);
        }
        return true;
    }

    public string? get_copy_text () // can compile with "private", but is public 1/2
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;

        return _get_copy_text ((ClickableListBoxRow) ((!) selected_row).get_child ());
    }
    private string _get_copy_text (ClickableListBoxRow row)
    {
        if (row is FolderListBoxRow)
            return row.full_name;
        // (row is KeyListBoxRow)
        SettingsModel model = modifications_handler.model;
        if (row is KeyListBoxRowEditable)
            return model.get_key_copy_text (row.full_name, ((KeyListBoxRowEditable) row).schema_id);
        // (row is KeyListBoxRowEditableNoSchema)
        return model.get_key_copy_text (row.full_name, ".dconf");
    }
    protected Variant get_copy_text_variant (ClickableListBoxRow row)
    {
        return new Variant.string (_get_copy_text (row));
    }

    public void toggle_boolean_key ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            return;

        ((KeyListBoxRow) ((!) selected_row).get_child ()).toggle_boolean_key ();
    }

    public void set_selected_to_default ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            assert_not_reached ();

        ((KeyListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).destroy_popover ();
    }
}

class RegistryView : RegistryList
{
    construct
    {
        placeholder.label = _("No keys in this path");
        key_list_box.set_header_func (update_row_header);
    }

    /*\
    * * Updating
    \*/

    public void set_key_model (GLib.ListStore key_model)
    {
        list_model = key_model;
        key_list_box.bind_model (list_model, new_list_box_row);
    }

    public bool check_reload (SettingObject [] fresh_key_model)
    {
        if (list_model.get_n_items () != fresh_key_model.length)
            return true;
        bool [] skip = new bool [fresh_key_model.length];
        for (uint i = 0; i < fresh_key_model.length; i++)
            skip [i] = false;
        for (uint i = 0; i < list_model.get_n_items (); i++)
        {
            SettingObject? setting_object = (SettingObject) list_model.get_item (i);
            if (setting_object == null)
                assert_not_reached ();
            bool found = false;
            for (uint j = 0; j < fresh_key_model.length; j++)
            {
                if (skip [j] == true)
                    continue;
                SettingObject fresh_setting_object = fresh_key_model [j];
                if (((!) setting_object).full_name != fresh_setting_object.full_name)
                    continue;
                // TODO compare other visible info (i.e. key type_string or summary [if not directories])
                if (SettingsModel.is_key_path (fresh_setting_object.full_name))
                {
                    if (((Key) (!) setting_object).type_string != ((Key) fresh_setting_object).type_string)
                        continue;
                }
                found = true;
                skip [j] = true;
                break;
            }
            if (!found)
                return true;
        }
        for (uint i = 0; i < fresh_key_model.length; i++)
            if (skip [i] == false)
                return true;
        return false;
    }

    public override void select_first_row ()
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            scroll_to_row ((!) row, true);
    }

    /*\
    * * Key ListBox
    \*/

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        string? label_text = null;
        if (row.get_child () is KeyListBoxRowEditable)
        {
            string schema_id = ((KeyListBoxRowEditable) row.get_child ()).schema_id;
            if (before == null
             || !(((!) before).get_child () is KeyListBoxRowEditable
               && ((KeyListBoxRowEditable) ((!) before).get_child ()).schema_id == schema_id))
                label_text = schema_id;
        }
        else if (row.get_child () is KeyListBoxRowEditableNoSchema)
        {
            if (before == null || !(((!) before).get_child () is KeyListBoxRowEditableNoSchema))
                label_text = _("Keys not defined by a schema");
        }

        ListBoxRowHeader header = new ListBoxRowHeader (before == null, label_text);
        row.set_header (header);
    }

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        string full_name = setting_object.full_name;

        if (!SettingsModel.is_key_path (setting_object.full_name))
        {
            row = new FolderListBoxRow (                    setting_object.name, full_name);
        }
        else
        {
            SettingsModel model = modifications_handler.model;
            Key key = (Key) setting_object;
            ulong key_value_changed_handler;
            if (setting_object is GSettingsKey)
            {
                GSettingsKey gkey = (GSettingsKey) key;
                bool key_default_value_if_bool = key.type_string == "b" ? gkey.default_value.get_boolean () : false;    // TODO better 1/6
                row = new KeyListBoxRowEditable (           key.type_string,
                                                            gkey,
                                                            gkey.schema_id,
                                                            modifications_handler,
                                                            setting_object.name, full_name);
                key_value_changed_handler = key.value_changed.connect (() => {
                        ((KeyListBoxRowEditable) row).update (model.get_key_value (key),
                                                              model.is_key_default (gkey),
                                                              key_default_value_if_bool,                                // TODO better 2/6
                                                              modifications_handler.get_current_delay_mode ());
                        row.destroy_popover ();
                    });
                ((KeyListBoxRowEditable) row).update (model.get_key_value (key),
                                                      model.is_key_default (gkey),
                                                      key_default_value_if_bool,                                        // TODO better 3/6
                                                      modifications_handler.get_current_delay_mode ());
            }
            else
            {
                DConfKey dkey = (DConfKey) setting_object;
                row = new KeyListBoxRowEditableNoSchema (   key.type_string,
                                                            dkey,
                                                            modifications_handler,
                                                            setting_object.name, full_name);
                key_value_changed_handler = key.value_changed.connect (() => {
                        if (model.is_key_ghost (full_name)) // fails with the ternary operator 1/4
                            ((KeyListBoxRowEditableNoSchema) row).update (null,
                                                                          modifications_handler.get_current_delay_mode ());
                        else
                            ((KeyListBoxRowEditableNoSchema) row).update (model.get_key_value (dkey),
                                                                          modifications_handler.get_current_delay_mode ());
                        row.destroy_popover ();
                    });
                if (model.is_key_ghost (full_name))         // fails with the ternary operator 2/4
                    ((KeyListBoxRowEditableNoSchema) row).update (null,
                                                                  modifications_handler.get_current_delay_mode ());
                else
                    ((KeyListBoxRowEditableNoSchema) row).update (model.get_key_value (dkey),
                                                                  modifications_handler.get_current_delay_mode ());
            }

            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            ulong delayed_modifications_changed_handler = modifications_handler.delayed_changes_changed.connect (() => set_delayed_icon (key_row));
            set_delayed_icon (key_row);
            row.destroy.connect (() => {
                    modifications_handler.disconnect (delayed_modifications_changed_handler);
                    key.disconnect (key_value_changed_handler);
                });
        }

        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);
        row.destroy.connect (() => row.disconnect (button_press_event_handler));

        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();

        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (row is FolderListBoxRow)
        {
            wrapper.get_style_context ().add_class ("folder-row");
            wrapper.action_name = "ui.open-folder";
            wrapper.set_action_target ("s", full_name);
        }
        else
        {
            wrapper.get_style_context ().add_class ("key-row");
            wrapper.action_name = "ui.open-object";
            string context = (setting_object is GSettingsKey) ? ((GSettingsKey) setting_object).schema_id : ".dconf";
            wrapper.set_action_target ("(ss)", full_name, context);
        }

        return wrapper;
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;

            int event_x = (int) event.x;
            if (event.window != widget.get_window ())   // boolean value switch
            {
                int widget_x, unused;
                event.window.get_position (out widget_x, out unused);
                event_x += widget_x;
            }

            row.show_right_click_popover (get_copy_text_variant (row), event_x);
            rows_possibly_with_popover.append (row);
        }

        return false;
    }

    public override bool up_or_down_pressed (bool is_down)
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        uint n_items = list_model.get_n_items ();

        if (selected_row != null)
        {
            Widget? row_content = ((!) selected_row).get_child ();
            if (row_content != null && ((ClickableListBoxRow) (!) row_content).right_click_popover_visible ())
                return false;

            int position = ((!) selected_row).get_index ();
            ListBoxRow? row = null;
            if (!is_down && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_down && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
                scroll_to_row ((!) row, true);

            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }
}
