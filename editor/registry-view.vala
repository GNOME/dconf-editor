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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-view.ui")]
class RegistryView : Grid, PathElement, BrowsableView
{
    public Behaviour behaviour { private get; set; }

    [GtkChild] private Revealer multiple_schemas_warning_revealer;

    [GtkChild] private ScrolledWindow scrolled;

    [GtkChild] private ListBox key_list_box;
    private GLib.ListStore? key_model = null;

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    private bool _small_keys_list_rows;
    public bool small_keys_list_rows
    {
        set
        {
            _small_keys_list_rows = value;
            key_list_box.foreach((row) => {
                    Widget row_child = ((ListBoxRow) row).get_child ();
                    if (row_child is KeyListBoxRow)
                        ((KeyListBoxRow) row_child).small_keys_list_rows = value;
                });
        }
    }

    public ModificationsRevealer revealer { private get; set; }

    private BrowserView? _browser_view = null;
    private BrowserView browser_view {
        get {
            if (_browser_view == null)
                _browser_view = (BrowserView) DConfWindow._get_parent (DConfWindow._get_parent (this));
            return (!) _browser_view;
        }
    }

    construct
    {
        key_list_box.set_header_func (update_row_header);
    }

    /*\
    * * Updating
    \*/

    public void set_key_model (GLib.ListStore _key_model)
    {
        key_model = _key_model;
        key_list_box.bind_model (key_model, new_list_box_row);
    }

    public void show_multiple_schemas_warning (bool multiple_schemas_warning_needed)
    {
        multiple_schemas_warning_revealer.set_reveal_child (multiple_schemas_warning_needed);
    }

    public void focus_selected_row ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row != null)
            ((!) selected_row).grab_focus ();
    }
    public void select_row_named (string selected, bool grab_focus)
    {
        check_resize ();
        ListBoxRow? row = key_list_box.get_row_at_index (get_row_position (selected));
        if (row == null)
            assert_not_reached ();
        scroll_to_row ((!) row, grab_focus);
    }
    public void select_first_row (bool grab_focus)
    {
        ListBoxRow? row = key_list_box.get_row_at_index (0);
        if (row != null)
            scroll_to_row ((!) row, grab_focus);
    }
    private int get_row_position (string selected)
        requires (key_model != null)
    {
        uint position = 0;
        while (position < ((!) key_model).get_n_items ())
        {
            SettingObject object = (SettingObject) ((!) key_model).get_object (position);
            if (object.full_name == selected)
                return (int) position;
            position++;
        }
        assert_not_reached ();
    }
    private void scroll_to_row (ListBoxRow row, bool grab_focus)
    {
        key_list_box.select_row (row);
        if (grab_focus)
            row.grab_focus ();

        Allocation list_allocation, row_allocation;
        scrolled.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }

    /*\
    * * Key ListBox
    \*/

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        ListBoxRowHeader header = new ListBoxRowHeader (before == null);
        row.set_header (header);
    }

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        ulong on_delete_call_handler;

        if (setting_object is Directory)
        {
            row = new FolderListBoxRow (setting_object.name, setting_object.full_name);
            on_delete_call_handler = row.on_delete_call.connect (() => browser_view.reset_objects (((Directory) setting_object).key_model, true));
        }
        else
        {
            if (setting_object is GSettingsKey)
                row = new KeyListBoxRowEditable ((GSettingsKey) setting_object);
            else
                row = new KeyListBoxRowEditableNoSchema ((DConfKey) setting_object);

            Key key = (Key) setting_object;
            KeyListBoxRow key_row = (KeyListBoxRow) row;
            key_row.small_keys_list_rows = _small_keys_list_rows;

            on_delete_call_handler = row.on_delete_call.connect (() => set_key_value (key, null));
            ulong set_key_value_handler = key_row.set_key_value.connect ((variant) => { set_key_value (key, variant); });
            ulong change_dismissed_handler = key_row.change_dismissed.connect (() => revealer.dismiss_change (key));

            row.destroy.connect (() => {
                    key_row.disconnect (set_key_value_handler);
                    key_row.disconnect (change_dismissed_handler);
                });
        }

        ulong on_row_clicked_handler = row.on_row_clicked.connect (() => request_path (setting_object.full_name));
        ulong button_press_event_handler = row.button_press_event.connect (on_button_pressed);

        row.destroy.connect (() => {
                row.disconnect (on_delete_call_handler);
                row.disconnect (on_row_clicked_handler);
                row.disconnect (button_press_event_handler);
            });

        /* Wrapper ensures max width for rows */
        ListBoxRowWrapper wrapper = new ListBoxRowWrapper ();
        wrapper.set_halign (Align.CENTER);
        wrapper.add (row);
        if (row is FolderListBoxRow)
            wrapper.get_style_context ().add_class ("folder-row");
        else
            wrapper.get_style_context ().add_class ("key-row");
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

            row.show_right_click_popover (get_current_delay_mode (), event_x);
            rows_possibly_with_popover.append (row);
        }

        return false;
    }

    public bool up_or_down_pressed (bool grab_focus, bool is_down)
    {
        if (key_model == null)
            return false;

        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        uint n_items = ((!) key_model).get_n_items ();

        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            ListBoxRow? row = null;
            if (!is_down && (position >= 1))
                row = key_list_box.get_row_at_index (position - 1);
            if (is_down && (position < n_items - 1))
                row = key_list_box.get_row_at_index (position + 1);

            if (row != null)
                scroll_to_row ((!) row, grab_focus);

            return true;
        }
        else if (n_items >= 1)
        {
            key_list_box.select_row (key_list_box.get_row_at_index (is_down ? 0 : (int) n_items - 1));
            return true;
        }
        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        ((ClickableListBoxRow) list_box_row.get_child ()).on_row_clicked ();
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

    public string? get_selected_row_name ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            return ((SettingObject) ((!) key_model).get_object (position)).full_name;
        }
        else
            return null;
    }

    /*\
    * * Revealer stuff
    \*/

    public bool get_current_delay_mode ()
    {
        return browser_view.get_current_delay_mode ();
    }

    private void set_key_value (Key key, Variant? new_value)
    {
        if (get_current_delay_mode ())
            revealer.add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key is GSettingsKey)
            ((GSettingsKey) key).set_to_default ();
        else if (behaviour != Behaviour.UNSAFE)
        {
            browser_view.enter_delay_mode ();
            revealer.add_delayed_setting (key, null);
        }
        else
            ((DConfKey) key).erase ();
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
        row.show_right_click_popover (get_current_delay_mode ());
        rows_possibly_with_popover.append (row);
        return true;
    }

    public string? get_copy_text ()
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;
        else
            return ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
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

    public void set_to_default ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow?) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
    }
}
