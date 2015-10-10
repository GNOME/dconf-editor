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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    private string current_path = "/";
    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_fullscreen = false;

    private SettingsModel model;
    [GtkChild] private TreeView dir_tree_view;
    [GtkChild] private TreeSelection dir_tree_selection;
    [GtkChild] private ListBox key_list_box;

    private GLib.ListStore bookmarks_model;
    private GLib.Settings settings;
    [GtkChild] private Popover bookmarks_popover;
    [GtkChild] private ListBox bookmarks_list_box;

    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;
    [GtkChild] private Button search_next_button;

    public DConfWindow ()
    {
        settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-fullscreen"))
            fullscreen ();
        else if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        search_bar.connect_entry (search_entry);

        model = new SettingsModel ();
        dir_tree_view.set_model (model);

        settings.changed ["bookmarks"].connect (update_bookmarks);
        update_bookmarks ();

        current_path = settings.get_string ("saved-view");
        if (!settings.get_boolean ("restore-view") || current_path == "/" || current_path == "" || !scroll_to_path (current_path))
        {
            TreeIter iter;
            if (model.get_iter_first (out iter))
                dir_tree_selection.select_iter (iter);
        }
    }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private bool on_window_state_event (Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        if ((event.changed_mask & Gdk.WindowState.FULLSCREEN) != 0)
            window_is_fullscreen = (event.new_window_state & Gdk.WindowState.FULLSCREEN) != 0;

        return false;
    }

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        if (window_is_maximized || window_is_fullscreen)
            return;
        window_width = allocation.width;
        window_height = allocation.height;
    }

    public void save_settings ()
    {
        settings.set_string ("saved-view", current_path);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.set_boolean ("window-is-fullscreen", window_is_fullscreen);
    }

    /*\
    * * Dir TreeView
    \*/

    [GtkCallback]
    private void dir_selected_cb ()
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 1/2

        GLib.ListStore? key_model = null;

        TreeIter iter;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            key_model = model.get_directory (iter).key_model;
            current_path = model.get_directory (iter).full_name;
        }

        key_list_box.bind_model (key_model, new_list_box_row);
    }

    /*\
    * * Key ListBox
    \*/

    private Widget new_list_box_row (Object item)
    {
        Key key = (Key) item;
        if (key.has_schema)
        {
            KeyListBoxRowEditable key_list_box_row = new KeyListBoxRowEditable (key);
            key_list_box_row.button_press_event.connect (on_button_pressed);
            key_list_box_row.show_dialog.connect (() => {
                    KeyEditor key_editor = new KeyEditor (key);
                    key_editor.set_transient_for (this);
                    key_editor.run ();
                });
            return key_list_box_row;
        }
        else
        {
            KeyListBoxRowEditableNoSchema key_list_box_row = new KeyListBoxRowEditableNoSchema (key);
            key_list_box_row.button_press_event.connect (on_button_pressed);
            key_list_box_row.show_dialog.connect (() => {
                    KeyEditorNoSchema key_editor = new KeyEditorNoSchema (key);
                    key_editor.set_transient_for (this);
                    key_editor.run ();
                });
            return key_list_box_row;
        }
        // TODO bug: list_box_row is always activated after the dialog destruction if mouse is over at this time
    }

    private bool on_button_pressed (Widget widget, Gdk.EventButton event)
    {
        ListBoxRow list_box_row = (ListBoxRow) ((KeyListBoxRow) widget).get_parent ();
        key_list_box.select_row (list_box_row);
        list_box_row.grab_focus ();
        return false;
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((KeyListBoxRow) list_box_row.get_child ()).show_dialog ();
    }

    /*\
    * * Search box
    \*/

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)     // TODO better?
    {
        if (Gdk.keyval_name (event.keyval) == "f" && (event.state & Gdk.ModifierType.CONTROL_MASK) != 0)    // TODO better?
        {
            search_bar.set_search_mode (!search_bar.get_search_mode ());
            return true;
        }

        return search_bar.handle_event (event);
    }

    [GtkCallback]
    private void find_next_cb ()
    {
        if (!search_bar.get_search_mode ())     // TODO better; switches to next list_box_row when keyboard-activating an entry of the popover
            return;

        TreeIter iter;
        int position = 0;
        if (dir_tree_selection.get_selected (null, out iter))
        {
            ListBoxRow? selected_row = (ListBoxRow) key_list_box.get_selected_row ();
            if (selected_row != null)
                position = selected_row.get_index () + 1;
        }
        else if (!model.get_iter_first (out iter))      // TODO doesn't that reset iter?
            return;     // TODO better

        bool on_first_directory = true;
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
                Key key = (Key) key_model.get_object (position);
                if (key_matches (key, search_entry.text))
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
        dir_tree_view.scroll_to_cell (model.get_path (iter), null, false, 0, 0);
    }

    private bool key_matches (Key key, string text)
    {
        /* Check key name */
        if (key.name.index_of (text) >= 0)
            return true;

        /* Check key schema (description) */
        if (key.has_schema)
        {
            if (key.schema.summary != null && key.schema.summary.index_of (text) >= 0)
                return true;
            if (key.schema.description != null && key.schema.description.index_of (text) >= 0)
                return true;
        }

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

    /*\
    * * Bookmarks
    \*/

    private void update_bookmarks ()
    {
        bookmarks_model = new GLib.ListStore (typeof (Bookmark));
        string [] bookmarks = settings.get_strv ("bookmarks");
        foreach (string bookmark in bookmarks)
            bookmarks_model.append (new Bookmark (bookmark));
        bookmarks_list_box.bind_model (bookmarks_model, new_bookmark_row);
    }

    [GtkCallback]
    private void add_bookmark_cb ()
    {
        bookmarks_popover.closed ();

        TreeIter iter;
        if (!dir_tree_selection.get_selected (null, out iter))
            assert_not_reached ();
        Value full_path_value = Value (typeof (string));
        model.get_value (iter, 2, out full_path_value);
        string full_path = full_path_value.get_string ();

        string [] bookmarks = settings.get_strv ("bookmarks");
        bookmarks += full_path;
        settings.set_strv ("bookmarks", bookmarks);
    }

    private Widget new_bookmark_row (Object item)
    {
        return (Bookmark) item;
    }

    [GtkCallback]
    private void bookmark_activated_cb (ListBoxRow list_box_row)
    {
        if (scroll_to_path (((Bookmark) list_box_row.get_child ()).full_name))
            return;
        MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.ERROR, ButtonsType.OK, _("Oops! Cannot find something at this path."));
        dialog.run ();
        dialog.destroy ();
    }

    private bool scroll_to_path (string full_name)
    {
        TreeIter iter;
        if (model.get_iter_first (out iter))
        {
            do
            {
                Directory dir = model.get_directory (iter);

                if (dir.full_name == full_name)
                {
                    bookmarks_popover.closed ();
                    select_dir (iter);
                    return true;
                }
            }
            while (get_next_iter (ref iter));
        }
        return false;
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/bookmark.ui")]
private class Bookmark : Grid
{
    public string full_name;
    [GtkChild] private Label bookmark_label;

    public Bookmark (string _full_name)
    {
        this.full_name = _full_name;
        bookmark_label.set_label (_full_name);
    }

    [GtkCallback]
    private void remove_cb ()
    {
        GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");
        string [] old_bookmarks = settings.get_strv ("bookmarks");
        string [] new_bookmarks = new string [0];
        foreach (string bookmark in old_bookmarks)
            if (bookmark != full_name)
                new_bookmarks += bookmark;
        settings.set_strv ("bookmarks", new_bookmarks);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private class KeyListBoxRow : EventBox
{
    [GtkChild] protected Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;

    public signal void show_dialog ();

    protected ContextPopover? popover = null;
    protected virtual bool generate_popover () { return false; }

    public override bool button_press_event (Gdk.EventButton event)     // list_box_row selection is done elsewhere
    {
        if (event.button == Gdk.BUTTON_SECONDARY)
        {
            if (popover != null)            // TODO remove? put in generate_popover?
                popover.destroy ();
            if (!generate_popover ())
                return false;

            Gdk.Rectangle rect;
            popover.set_relative_to (this);
            popover.position = PositionType.BOTTOM;
            popover.get_pointing_to (out rect);
            rect.x = (int) (event.x - this.get_allocated_width () / 2.0);
            popover.set_pointing_to (rect);
            popover.show ();
        }

        return false;
    }
}

private class KeyListBoxRowEditableNoSchema : KeyListBoxRow
{
    public Key key { get; private set; }

    public KeyListBoxRowEditableNoSchema (Key _key)
    {
        this.key = _key;

        Pango.AttrList attr_list = new Pango.AttrList ();
        attr_list.insert (Pango.attr_weight_new (Pango.Weight.BOLD));   // TODO good?
        key_name_label.set_attributes (attr_list);
        key_value_label.set_attributes (attr_list);

        key_name_label.label = key.name;
        key_value_label.label = key.cool_text_value ();
        key_info_label.set_markup ("<i>" + _("No Schema Found") + "</i>");

        key.value_changed.connect (() => { key_value_label.label = key.cool_text_value (); if (popover != null) popover.destroy (); });
    }

    protected override bool generate_popover ()
    {
        popover = new ContextPopover ();
        popover.add_action_button (_("Customize…"), () => { show_dialog (); }, true);
        popover.add_action_button (_("Copy"), () => {
                Clipboard clipboard = Clipboard.get_default (Gdk.Display.get_default ());
                string copy = key.full_name + " " + key.value.print (false);
                clipboard.set_text (copy, copy.length);
            });

        if (key.type_string == "b" || key.type_string == "mb")
        {
            popover.add_separator ();
            popover.create_buttons_list (key, false);

            popover.value_changed.connect ((bytes) => { key.value = bytes == null ? new Variant.maybe (VariantType.BOOLEAN, null) : new Variant.from_bytes (key.value.get_type (), bytes, true); popover.destroy (); });
        }
        return true;
    }
}

private class KeyListBoxRowEditable : KeyListBoxRow
{
    public Key key { get; private set; }

    private Pango.AttrList attr_list = new Pango.AttrList ();

    public KeyListBoxRowEditable (Key _key)
    {
        this.key = _key;

        key_value_label.set_attributes (attr_list);
        update ();      // sets key_name_label attributes and key_value_label label
        key_name_label.label = key.name;

        string summary = key.schema.summary ?? "";
        key_info_label.label = summary.strip ();

        key.value_changed.connect (() => { update (); if (popover != null) popover.destroy (); });
    }

    protected override bool generate_popover ()
    {
        popover = new ContextPopover ();
        popover.add_action_button (_("Customize…"), () => { show_dialog (); }, true);
        popover.add_action_button (_("Copy"), () => {
                Clipboard clipboard = Clipboard.get_default (Gdk.Display.get_default ());
                string copy = key.schema.schema_id + " " + key.name + " " + key.value.print (false);
                clipboard.set_text (copy, copy.length);
            });

        if (key.type_string == "b" || key.type_string == "<enum>" || key.type_string == "mb")
        {
            popover.add_separator ();
            popover.create_buttons_list (key, true);

            popover.set_to_default.connect (() => { key.set_to_default (); popover.destroy (); });
            popover.value_changed.connect ((bytes) => { key.value = bytes == null ? new Variant.maybe (VariantType.BOOLEAN, null) : new Variant.from_bytes (key.value.get_type (), bytes, true); popover.destroy (); });
        }
        else if (!key.is_default)
        {
            popover.add_separator ();
            popover.add_action_button (_("Set to default"), () => { key.set_to_default (); });
        }
        return true;
    }

    private void update ()
    {
        attr_list.change (Pango.attr_weight_new (key.is_default ? Pango.Weight.NORMAL : Pango.Weight.BOLD));    // TODO good?
        key_name_label.set_attributes (attr_list);
        // TODO key_info_label.set_attributes (attr_list); ?

        key_value_label.label = key.cool_text_value ();
    }
}

private class ContextPopover : Popover
{
    public signal void set_to_default ();
    public signal void value_changed (Bytes? bytes);

    private static const string ACTION_NAME = "key_value";
    private static const string GROUP_PREFIX = "group";

    private Grid grid;

    public ContextPopover ()
    {
        grid = new Grid ();
        grid.orientation = Orientation.VERTICAL;
        grid.visible = true;
        // grid.width_request = 100;        // TODO
        grid.margin = 4;
        grid.row_spacing = 2;
        this.add (grid);
    }

    public delegate void button_action ();
    public void add_action_button (string label, button_action action, bool is_default = false)
    {
        ModelButton button = new ModelButton ();
        button.visible = true;
        button.text = label;
        button.clicked.connect (() => { action (); });
        grid.add (button);
        if (is_default)
            button.grab_focus ();
    }

    public void add_separator ()
    {
        Separator separator = new Separator (Orientation.HORIZONTAL);
        separator.visible = true;
        grid.add (separator);
    }

    public void create_buttons_list (Key key, bool nullable)
    {
        VariantType original_type = key.value.get_type ();
        VariantType nullable_type = new VariantType.maybe (original_type);
        Variant variant = new Variant.maybe (original_type, key.is_default ? null : key.value);

        SimpleAction simple_action = new SimpleAction.stateful (ACTION_NAME, nullable_type, variant);
        SimpleActionGroup group = new SimpleActionGroup ();
        ((ActionMap) group).add_action (simple_action);
        grid.insert_action_group (GROUP_PREFIX, group);

        if (nullable)
            add_model_button (_("Default value"), new Variant.maybe (original_type, null));

        switch (key.type_string)
        {
            case "b":
                add_model_button (Key.cool_boolean_text_value (true), new Variant.maybe (VariantType.BOOLEAN, new Variant.boolean (true)));
                add_model_button (Key.cool_boolean_text_value (false), new Variant.maybe (VariantType.BOOLEAN, new Variant.boolean (false)));
                break;
            case "<enum>":
                Variant range = key.schema.range_content;
                uint size = (uint) range.n_children ();
                if (size == 0)      // TODO special case also 1?
                    assert_not_reached ();
                VariantType type = range.get_child_value (0).get_type ();
                for (uint index = 0; index < size; index++)
                    add_model_button (range.get_child_value (index).print (false), new Variant.maybe (type, range.get_child_value (index)));
                break;
            case "mb":
                add_model_button (Key.cool_boolean_text_value (null), new Variant.maybe (original_type, new Variant.maybe (VariantType.BOOLEAN, null)));
                add_model_button (Key.cool_boolean_text_value (true), new Variant.maybe (original_type, new Variant.maybe (VariantType.BOOLEAN, new Variant.boolean (true))));
                add_model_button (Key.cool_boolean_text_value (false), new Variant.maybe (original_type, new Variant.maybe (VariantType.BOOLEAN, new Variant.boolean (false))));
                break;
        }

        group.action_state_changed [ACTION_NAME].connect ((unknown_string, tmp_variant) => {
                Variant? new_variant = tmp_variant.get_maybe ();
                if (new_variant == null)
                    set_to_default ();
                else if (new_variant.get_data () == null)
                    value_changed (null);
                else
                    value_changed (new_variant.get_data_as_bytes ());
            });
    }

    private void add_model_button (string text, Variant variant)
    {
        ModelButton button = new ModelButton ();
        button.visible = true;
        button.text = text;
        button.action_name = GROUP_PREFIX + "." + ACTION_NAME;
        button.action_target = variant;
        grid.add (button);
    }
}
