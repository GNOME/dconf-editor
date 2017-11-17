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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-view.ui")]
class BrowserView : Grid, PathElement
{
    public string current_path { get; private set; }
    public Behaviour behaviour { get; set; }

    private GLib.Settings application_settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");
    [GtkChild] private Revealer need_reload_warning_revealer;
    [GtkChild] private Revealer multiple_schemas_warning_revealer;
    private bool multiple_schemas_warning_needed;

    private Directory current_directory;

    [GtkChild] private Stack stack;
    [GtkChild] private RegistryInfo properties_view;

    [GtkChild] private ListBox key_list_box;
    private GLib.ListStore? key_model = null;
    private SortingOptions sorting_options;

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

    [GtkChild] private ModificationsRevealer revealer;

    private DConfWindow? _window = null;
    private DConfWindow window {
        get {
            if (_window == null)
                _window = (DConfWindow) DConfWindow._get_parent (DConfWindow._get_parent (this));
            return (!) _window;
        }
    }

    construct
    {
        ulong revealer_reload_handler = revealer.reload.connect (invalidate_popovers);

        bind_property ("behaviour", revealer, "behaviour", BindingFlags.BIDIRECTIONAL|BindingFlags.SYNC_CREATE);

        sorting_options = new SortingOptions ();
        application_settings.bind ("sort-case-sensitive", sorting_options, "case-sensitive", GLib.SettingsBindFlags.GET);
        application_settings.bind ("sort-folders", sorting_options, "sort-folders", GLib.SettingsBindFlags.GET);

        key_list_box.set_header_func (update_row_header);

        destroy.connect (() => {
                revealer.disconnect (revealer_reload_handler);
                base.destroy ();
            });
    }

    public void init (string path, bool restore_view)   // TODO check path format
    {
        current_path = (restore_view && path != "" && path [0] == '/') ? path : "/";

        sorting_options.notify.connect (() => {
                if (!is_not_browsing_view () && current_directory.need_sorting (sorting_options))
                    need_reload_warning_revealer.set_reveal_child (true);
            });
    }

    /*\
    * * Stack switching
    \*/

    public void set_directory (Directory directory, string? selected)
    {
        current_directory = directory;

        current_directory.sort_key_model (sorting_options);
        key_model = current_directory.key_model;

        multiple_schemas_warning_needed = current_directory.warning_multiple_schemas;

        key_list_box.bind_model (key_model, new_list_box_row);

        show_browse_view (directory.full_name, selected);
    }

    private void show_browse_view (string path, string? selected, bool grab_focus = true)
    {
        stack.set_transition_type (current_path.has_prefix (path) ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        need_reload_warning_revealer.set_reveal_child (false);
        multiple_schemas_warning_revealer.set_reveal_child (multiple_schemas_warning_needed);
        update_current_path (path);
        current_directory.sort_key_model (sorting_options);
        stack.set_visible_child_name ("browse-view");
        if (selected != null)
        {
            check_resize ();
            ListBoxRow? row = key_list_box.get_row_at_index (get_row_position ((!) selected));
            if (row == null)
                assert_not_reached ();
            scroll_to_row ((!) row, grab_focus);
        }
        else
        {
            ListBoxRow? row = key_list_box.get_row_at_index (0);
            if (row != null)
                scroll_to_row ((!) row, grab_focus);
        }
        properties_view.clean ();
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
        stack.get_allocation (out list_allocation);
        row.get_allocation (out row_allocation);
        key_list_box.get_adjustment ().set_value (row_allocation.y + (int) ((row_allocation.height - list_allocation.height) / 2.0));
    }

    public void show_properties_view (Key key, string path, bool warning_multiple_schemas)
    {
        properties_view.populate_properties_list_box (key, warning_multiple_schemas);

        need_reload_warning_revealer.set_reveal_child (false);
        multiple_schemas_warning_revealer.set_reveal_child (false);

        stack.set_transition_type (path.has_prefix (current_path) && current_path.length == path.last_index_of_char ('/') + 1 ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        update_current_path (path);
        stack.set_visible_child (properties_view);
    }

    private void update_current_path (string path)
    {
        revealer.path_changed ();
        current_path = path;
        window.update_path_elements ();
        invalidate_popovers ();
    }

    /*\
    * * Key ListBox
    \*/

    private void update_row_header (ListBoxRow row, ListBoxRow? before)
    {
        if (before != null)
        {
            ListBoxRowHeader header = new ListBoxRowHeader ();
            header.set_halign (Align.CENTER);
            header.show ();
            row.set_header (header);
        }
    }

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        SettingObject setting_object = (SettingObject) item;
        ulong on_delete_call_handler;

        if (setting_object is Directory)
        {
            row = new FolderListBoxRow (setting_object.name, setting_object.full_name);
            on_delete_call_handler = row.on_delete_call.connect (() => reset_objects (((Directory) setting_object).key_model, true));
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
            ulong set_key_value_handler = key_row.set_key_value.connect ((variant) => { set_key_value (key, variant); set_delayed_icon (row, key); });
            ulong change_dismissed_handler = key_row.change_dismissed.connect (() => revealer.dismiss_change (key));

            ulong key_planned_change_handler = key.notify ["planned-change"].connect (() => set_delayed_icon (row, key));
            ulong key_planned_value_handler = key.notify ["planned-value"].connect (() => set_delayed_icon (row, key));
            set_delayed_icon (row, key);

            row.destroy.connect (() => {
                    key_row.disconnect (set_key_value_handler);
                    key_row.disconnect (change_dismissed_handler);
                    key.disconnect (key_planned_change_handler);
                    key.disconnect (key_planned_value_handler);
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

    private void set_delayed_icon (ClickableListBoxRow row, Key key)
    {
        if (key.planned_change)
        {
            StyleContext context = row.get_style_context ();
            context.add_class ("delayed");
            if (key is DConfKey)
            {
                if (key.planned_value == null)
                    context.add_class ("erase");
                else
                    context.remove_class ("erase");
            }
        }
        else
            row.get_style_context ().remove_class ("delayed");
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
        window.update_hamburger_menu ();
    }

    [GtkCallback]
    private void reload ()
        requires (!is_not_browsing_view ())
    {
        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        string? saved_selection = null;
        if (selected_row != null)
        {
            int position = ((!) selected_row).get_index ();
            saved_selection = ((SettingObject) ((!) key_model).get_object (position)).full_name;
        }

        show_browse_view (current_path, saved_selection);
    }

    /*\
    * * Revealer stuff
    \*/

    public bool get_current_delay_mode ()
    {
        return revealer.get_current_delay_mode ();
    }

    public void enter_delay_mode ()
    {
        revealer.enter_delay_mode ();
        invalidate_popovers ();
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
            enter_delay_mode ();
            revealer.add_delayed_setting (key, null);
        }
        else
            ((DConfKey) key).erase ();
    }

    /*\
    * * Action entries
    \*/

    public void reset (bool recursively)
    {
        reset_objects (key_model, recursively);
    }

    private void reset_objects (GLib.ListStore? objects, bool recursively)
    {
        enter_delay_mode ();
        reset_generic (objects, recursively);
        revealer.warn_if_no_planned_changes ();
    }

    private void reset_generic (GLib.ListStore? objects, bool recursively)
    {
        if (objects == null)
            return;

        for (uint position = 0;; position++)
        {
            Object? object = ((!) objects).get_object (position);
            if (object == null)
                return;

            SettingObject setting_object = (SettingObject) ((!) object);
            if (setting_object is Directory)
            {
                if (recursively)
                    reset_generic (((Directory) setting_object).key_model, true);
                continue;
            }
            if (setting_object is DConfKey)
            {
                if (!((DConfKey) setting_object).is_ghost)
                    revealer.add_delayed_setting ((Key) setting_object, null);
            }
            else if (!((GSettingsKey) setting_object).is_default)
                revealer.add_delayed_setting ((Key) setting_object, null);
        }
    }

    /*\
    * * Keyboard calls
    \*/

/*    public void set_search_mode (bool? mode)    // mode is never 'true'...
    {
        if (mode == null)
            search_bar.set_search_mode (!search_bar.get_search_mode ());
        else
            search_bar.set_search_mode ((!) mode);
    }

    public bool handle_search_event (Gdk.EventKey event)
    {
        if (is_not_browsing_view ())
            return false;

        return search_bar.handle_event (event);
    } */

    public bool show_row_popover ()
    {
        ListBoxRow? selected_row = get_key_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();
        row.show_right_click_popover (get_current_delay_mode ());
        rows_possibly_with_popover.append (row);
        return true;
    }

    public string? get_copy_text ()
    {
        if (is_not_browsing_view ())
            return properties_view.get_copy_text ();

        ListBoxRow? selected_row = key_list_box.get_selected_row ();
        if (selected_row == null)
            return null;
        else
            return ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
    }

    public void toggle_boolean_key ()
    {
        ListBoxRow? selected_row = get_key_row ();
        if (selected_row == null)
            return;

        if (!(((!) selected_row).get_child () is KeyListBoxRow))
            return;

        ((KeyListBoxRow) ((!) selected_row).get_child ()).toggle_boolean_key ();
    }

    public void set_to_default ()
    {
        ListBoxRow? selected_row = get_key_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).on_delete_call ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = get_key_row ();
        if (selected_row == null)
            return;

        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
    }

    private bool is_not_browsing_view ()
    {
        string? visible_child_name = stack.get_visible_child_name ();
        return (visible_child_name == null || ((!) visible_child_name) != "browse-view");
    }

    private ListBoxRow? get_key_row ()
    {
        if (is_not_browsing_view ())
            return null;
        return (ListBoxRow?) key_list_box.get_selected_row ();
    }
}
