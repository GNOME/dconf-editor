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
class RegistryView : Grid
{
    public string current_path { get; private set; }
    public bool show_search_bar { get; set; }
    public bool delayed_apply_menu { get; set; }
    public bool planned_change { get { return revealer.get_reveal_child (); }}

    private SettingsModel model = new SettingsModel ();
    [GtkChild] private TreeView dir_tree_view;
    [GtkChild] private TreeSelection dir_tree_selection;

    [GtkChild] private Revealer no_schema_warning;
    [GtkChild] private Stack stack;
    [GtkChild] private ListBox properties_list_box;

    [GtkChild] private ListBox key_list_box;
    private GLib.ListStore? key_model = null;

    private GLib.ListStore rows_possibly_with_popover = new GLib.ListStore (typeof (ClickableListBoxRow));

    [GtkChild] private ModificationsRevealer revealer;

    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;
    [GtkChild] private Button search_next_button;

    construct
    {
        revealer.reload.connect (invalidate_popovers);

        search_entry.get_buffer ().deleted_text.connect (() => { search_next_button.set_sensitive (true); });
        search_bar.connect_entry (search_entry);
        bind_property ("show-search-bar", search_bar, "search-mode-enabled", BindingFlags.BIDIRECTIONAL);   // TODO in UI file?
    }

    public void init (string path, bool restore_view)
    {
        dir_tree_view.set_model (model);

        current_path = path;
        if (!restore_view || current_path == "" || !scroll_to_path (current_path))
        {
            current_path = "/";
            if (!scroll_to_path ("/"))
                assert_not_reached ();
        }
    }

    private void update_current_path (string path)
    {
        current_path = path;
        ((DConfWindow) this.get_parent ()).update_current_path ();
    }

    /*\
    * * Dir TreeView
    \*/

    [GtkCallback]
    private void dir_selected_cb ()
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 1/2

        key_model = null;

        TreeIter iter;
        Directory dir;
        if (dir_tree_selection.get_selected (null, out iter))
            dir = model.get_directory (iter);
        else
            dir = model.get_root_directory ();

        key_model = dir.key_model;
        update_current_path (dir.full_name);

        key_list_box.bind_model (key_model, new_list_box_row);
    }

    public bool scroll_to_path (string _full_name)      // TODO for now we assume full_name is a folder; also, don't do all the selection work if the folder didn't change
    {
        string full_name = _full_name.dup ();

        if (!full_name.has_suffix ("/"))
            full_name = DConfWindow.stripped_path (full_name);

        update_current_path (full_name);

        no_schema_warning.set_reveal_child (false);
        stack.set_visible_child_name ("browse-view");

        invalidate_popovers ();

        if (full_name == "/")
        {
            dir_tree_selection.unselect_all ();
            return true;
        }

        TreeIter iter;
        if (model.get_iter_first (out iter))
        {
            do
            {
                Directory dir = model.get_directory (iter);

                if (dir.full_name == full_name)
                {
                    select_dir (iter);
                    return true;
                }
            }
            while (get_next_iter (ref iter));
        }
        MessageDialog dialog = new MessageDialog ((Window) this.get_parent (), DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK, _("Oops! Cannot find something at this path."));
        dialog.run ();
        dialog.destroy ();
        return false;
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        ClickableListBoxRow row;
        if (((SettingObject) item).is_view)
        {
            row = new FolderListBoxRow (((SettingObject) item).name, ((SettingObject) item).full_name);
            row.on_row_clicked.connect (() => {
                    if (!scroll_to_path (((SettingObject) item).full_name))
                        warning ("Something got wrong with this folder.");
                });
        }
        else
        {
            Key key = (Key) item;
            if (key.has_schema)
                row = new KeyListBoxRowEditable ((GSettingsKey) key);
            else
                row = new KeyListBoxRowEditableNoSchema ((DConfKey) key);

            ((KeyListBoxRow) row).set_key_value.connect ((variant) => { set_key_value (key, variant); });
            ((KeyListBoxRow) row).change_dismissed.connect (() => { revealer.dismiss_change (key); });

            row.on_row_clicked.connect (() => {
                    if (!key.has_schema && ((DConfKey) key).is_ghost)
                        return;

                    properties_list_box.@foreach ((widget) => { widget.destroy (); });
                    populate_properties_list_box (key);

                    stack.set_visible_child_name ("properties-view");

                    update_current_path (key.full_name);

                    no_schema_warning.set_reveal_child (!key.has_schema);
                });
            // TODO bug: row is always visually activated after the dialog destruction if mouse is over at this time
        }
        row.button_press_event.connect (on_button_pressed);
        return row;
    }

    private void populate_properties_list_box (Key key)
    {
        bool has_schema;
        unowned Variant [] dict_container;
        key.properties.get ("(ba{ss})", out has_schema, out dict_container);
        Variant dict = dict_container [0];

        // TODO use VariantDict
        string key_name, tmp_string;

        if (!dict.lookup ("key-name",     "s", out key_name))   assert_not_reached ();
        if (!dict.lookup ("parent-path",  "s", out tmp_string)) assert_not_reached ();

        if (dict.lookup ("schema-id",     "s", out tmp_string)) add_row_from_label (_("Schema"),      tmp_string);
        if (dict.lookup ("summary",       "s", out tmp_string)) add_row_from_label (_("Summary"),     tmp_string);
        if (dict.lookup ("description",   "s", out tmp_string)) add_row_from_label (_("Description"), tmp_string);
        /* Translators: as in datatype (integer, boolean, string, etc.) */
        if (dict.lookup ("type-name",     "s", out tmp_string)) add_row_from_label (_("Type"),        tmp_string);
        else assert_not_reached ();
        if (dict.lookup ("minimum",       "s", out tmp_string)) add_row_from_label (_("Minimum"),     tmp_string);
        if (dict.lookup ("maximum",       "s", out tmp_string)) add_row_from_label (_("Maximum"),     tmp_string);
        if (dict.lookup ("default-value", "s", out tmp_string)) add_row_from_label (_("Default"),     tmp_string);

        if (!dict.lookup ("type-code",    "s", out tmp_string)) assert_not_reached ();

        bool disable_revealer_for_value = false;
        KeyEditorChild key_editor_child = create_child (key);
        if (has_schema)
        {
            Switch custom_value_switch = new Switch ();
            custom_value_switch.halign = Align.END;
            custom_value_switch.hexpand = true;
            custom_value_switch.show ();
            add_row_from_widget (_("Use default value"), custom_value_switch, null);

            custom_value_switch.bind_property ("active", key_editor_child, "sensitive", BindingFlags.SYNC_CREATE | BindingFlags.INVERT_BOOLEAN);

            bool disable_revealer_for_switch = false;
            GSettingsKey gkey = (GSettingsKey) key;
            revealer.reload.connect (() => {
                    disable_revealer_for_switch = true;
                    custom_value_switch.set_active (gkey.is_default);
                    disable_revealer_for_switch = false;    // TODO bad but needed
                });
            custom_value_switch.set_active (key.planned_change ? key.planned_value == null : gkey.is_default);
            custom_value_switch.notify ["active"].connect (() => {
                    if (disable_revealer_for_switch)
                        disable_revealer_for_switch = false;
                    else if (custom_value_switch.get_active ())
                        revealer.add_delayed_setting (key, null);
                    else
                    {
                        Variant tmp_variant = key.planned_change && (key.planned_value != null) ? key.planned_value : key.value;
                        revealer.add_delayed_setting (key, tmp_variant);
                        key_editor_child.reload (tmp_variant);
                    }
                });
        }
        key_editor_child.value_has_changed.connect ((enable_revealer, is_valid) => {
                if (disable_revealer_for_value)
                    disable_revealer_for_value = false;
                else if (enable_revealer && is_valid)
                    revealer.add_delayed_setting (key, key_editor_child.get_variant ());
                else if (enable_revealer && !is_valid)
                    revealer.dismiss_change (key);
            });
        key_editor_child.child_activated.connect (() => { revealer.apply_delayed_settings (); });  // TODO "only" used for string-based and spin widgets
        revealer.reload.connect (() => {
                disable_revealer_for_value = true;
                key_editor_child.reload (key.value);
                if (tmp_string == "<flags>")
                    key.planned_value = key.value;
            });
        add_row_from_widget (_("Custom value"), key_editor_child, tmp_string);
    }

    private static KeyEditorChild create_child (Key key)
    {
        switch (key.type_string)
        {
            case "<enum>":
                return (KeyEditorChild) new KeyEditorChildEnum (key);
            case "<flags>":
                return (KeyEditorChild) new KeyEditorChildFlags ((GSettingsKey) key);
            case "b":
                return (KeyEditorChild) new KeyEditorChildBool (key.planned_change && (key.planned_value != null) ? ((!) key.planned_value).get_boolean () : key.value.get_boolean ());
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "h":   // TODO "x" and "t" are not working in spinbuttons (double-based)
                return (KeyEditorChild) new KeyEditorChildNumberInt (key);
            case "d":
                return (KeyEditorChild) new KeyEditorChildNumberDouble (key);
            case "mb":
                return (KeyEditorChild) new KeyEditorChildNullableBool (key);
            default:
                return (KeyEditorChild) new KeyEditorChildDefault (key.type_string, key.planned_change && (key.planned_value != null) ? key.planned_value : key.value);
        }
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) widget.get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();

        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            ClickableListBoxRow row = (ClickableListBoxRow) widget;
            row.show_right_click_popover (delayed_apply_menu || planned_change, (int) (event.x - row.get_allocated_width () / 2.0));
            rows_possibly_with_popover.append (row);
        }

        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((ClickableListBoxRow) list_box_row.get_child ()).on_row_clicked ();
    }

    public void invalidate_popovers ()
    {
        uint position = 0;
        ClickableListBoxRow? row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (0);
        while (row != null)
        {
            row.destroy_popover ();
            position++;
            row = (ClickableListBoxRow?) rows_possibly_with_popover.get_item (position);
        }
        rows_possibly_with_popover.remove_all ();
    }

    /*\
    * * Properties listbox
    \*/

    private void add_row_from_label (string property_name, string property_value)
    {
        properties_list_box.add (new PropertyRow.from_label (property_name, property_value));
    }

    private void add_row_from_widget (string property_name, Widget widget, string? type)
    {
        properties_list_box.add (new PropertyRow.from_widgets (property_name, widget, type != null ? add_warning ((!) type) : null));
    }

    private static Widget? add_warning (string type)
    {
        if (type != "<flags>" && ((type != "s" && "s" in type) || (type != "g" && "g" in type)) || (type != "o" && "o" in type))
        {
            if ("m" in type)
                /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
                return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value. Strings, signatures and object paths should be surrounded by quotation marks."));
            else
                return warning_label (_("Strings, signatures and object paths should be surrounded by quotation marks."));
        }
        else if (type != "m" && type != "mb" && type != "<enum>" && "m" in type)
            /* Translators: neither the "nothing" keyword nor the "m" type should be translated; a "maybe type" is a type of variant that is nullable. */
            return warning_label (_("Use the keyword “nothing” to set a maybe type (beginning with “m”) to its empty value."));
        return null;
    }
    private static Widget warning_label (string text)
    {
        Label label = new Label (text);
        label.visible = true;
        label.max_width_chars = 59;
        label.wrap = true;
        label.halign = Align.START;
        label.get_style_context ().add_class ("italic-label");
        return (Widget) label;
    }

    /*\
    * * Revealer stuff
    \*/

    private void set_key_value (Key key, Variant? new_value)
    {
        if (delayed_apply_menu || planned_change)
            revealer.add_delayed_setting (key, new_value);
        else if (new_value != null)
            key.value = (!) new_value;
        else if (key.has_schema)
            ((GSettingsKey) key).set_to_default ();
        else
            assert_not_reached ();
    }

    /*\
    * * Action entries
    \*/

    public void reset (bool recursively)
    {
        reset_generic (key_model, recursively);
        invalidate_popovers ();
    }

    private void reset_generic (GLib.ListStore? objects, bool recursively)   // TODO notification if nothing to reset
    {
        if (objects == null)
            return;

        for (uint position = 0;; position++)
        {
            Object? object = ((!) objects).get_object (position);
            if (object == null)
                return;

            SettingObject setting_object = (SettingObject) ((!) object);
            if (setting_object.is_view)
            {
                if (recursively)
                    reset_generic (((Directory) setting_object).key_model, true);
                continue;
            }
            if (!((Key) setting_object).has_schema)
            {
                if (!((DConfKey) setting_object).is_ghost)
                    revealer.add_delayed_setting ((Key) setting_object, null);
            }
            else if (!((GSettingsKey) setting_object).is_default)
                revealer.add_delayed_setting ((Key) setting_object, null);
        }
    }

    /*\
    * * Search box
    \*/

    [GtkCallback]
    private void show_browse_view ()
    {
        if (stack.get_visible_child_name () != "browse-view")
            stack.set_visible_child_name ("browse-view");
    }

    public void set_search_mode (bool? mode)    // mode is never 'true'...
    {
        if (mode == null)
            search_bar.set_search_mode (!search_bar.get_search_mode ());
        else
            search_bar.set_search_mode ((!) mode);
    }

    public bool handle_search_event (Gdk.EventKey event)
    {
        if (stack.get_visible_child_name () != "browse-view")
            return false;

        return search_bar.handle_event (event);
    }

    public bool show_row_popover ()
    {
        if (stack.get_visible_child_name () != "browse-view")
            return false;

        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        if (selected_row == null)
            return false;

        ClickableListBoxRow row = (ClickableListBoxRow) ((!) selected_row).get_child ();
        row.show_right_click_popover (delayed_apply_menu || planned_change);
        rows_possibly_with_popover.append (row);
        return true;
    }

    public string? get_selected_row_text ()
    {
        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        return selected_row == null ? null : ((ClickableListBoxRow) ((!) selected_row).get_child ()).get_text ();
    }

    public void discard_row_popover ()
    {
        ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
        if (selected_row == null)
            return;
        ((ClickableListBoxRow) ((!) selected_row).get_child ()).hide_right_click_popover ();
    }

    [GtkCallback]
    private void find_next_cb ()
    {
        if (!search_bar.get_search_mode ())     // TODO better; switches to next list_box_row when keyboard-activating an entry of the popover
            return;

        TreeIter iter;
        bool on_first_directory;
        int position = 0;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
            if (selected_row != null)
                position = ((!) selected_row).get_index () + 1;

            on_first_directory = true;
        }
        else if (model.get_iter_first (out iter))
            on_first_directory = false;
        else
            return;     // TODO better

        do
        {
            Directory dir = model.get_directory (iter);

            if (!on_first_directory && dir.name.index_of (search_entry.text) >= 0)
            {
                select_dir (iter);
                return;
            }
            on_first_directory = false;

            /* Select next key that matches */
            GLib.ListStore key_model = dir.key_model;
            while (position < key_model.get_n_items ())
            {
                SettingObject object = (SettingObject) key_model.get_object (position);
                if (object.name.index_of (search_entry.text) >= 0 || 
                    (!object.is_view && key_matches ((Key) object, search_entry.text)))
                {
                    select_dir (iter);
                    key_list_box.select_row (key_list_box.get_row_at_index (position));
                    // TODO select key in ListBox
                    return;
                }
                position++;
            }

            position = 0;
        }
        while (get_next_iter (ref iter));

        search_next_button.set_sensitive (false);
    }

    private void select_dir (TreeIter iter)
    {
        dir_tree_view.expand_to_path (model.get_path (iter));
        dir_tree_selection.select_iter (iter);
    }

    private bool key_matches (Key key, string text)
    {
        /* Check in key's metadata */
        if (key.has_schema && ((GSettingsKey) key).search_for (text))
            return true;

        /* Check key value */
        if (key.value.is_of_type (VariantType.STRING) && key.value.get_string ().index_of (text) >= 0)
            return true;

        return false;
    }

    private bool get_next_iter (ref TreeIter iter)
    {
        /* Search children next */
        if (model.iter_has_child (iter))
        {
            model.iter_nth_child (out iter, iter, 0);
            return true;
        }

        /* Move to the next branch */
        while (!model.iter_next (ref iter))
        {
            /* Otherwise move to the parent and onto the next iter */
            if (!model.iter_parent (out iter, iter))
                return false;
        }

        return true;
    }
}
