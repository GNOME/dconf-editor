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
    private SettingsModel model;
    [GtkChild] private TreeView dir_tree_view;
    [GtkChild] private TreeSelection dir_tree_selection;
    [GtkChild] private ListBox key_list_box;

    [GtkChild] private SearchBar search_bar;
    [GtkChild] private SearchEntry search_entry;
    [GtkChild] private Button search_next_button;

    public DConfWindow ()
    {
        search_bar.connect_entry (search_entry);

        model = new SettingsModel ();
        dir_tree_view.set_model (model);

        TreeIter iter;
        if (model.get_iter_first (out iter))
            dir_tree_selection.select_iter (iter);
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
            key_model = model.get_directory (iter).key_model;

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
            key.value_changed.connect (() => { key_list_box_row.update (); });
            return key_list_box_row;
        }
        else
            return new KeyListBoxRowNonEditable (key.name, key.cool_text_value ());
    }

    [GtkCallback]
    private void row_activated_cb (ListBoxRow list_box_row)
    {
        search_next_button.set_sensitive (true);        // TODO better, or maybe just hide search_bar 2/2

        ((KeyListBoxRow) list_box_row.get_child ()).show_dialog (this);
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
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/key-list-box-row.ui")]
private abstract class KeyListBoxRow : Grid
{
    [GtkChild] protected Label key_name_label;
    [GtkChild] protected Label key_value_label;
    [GtkChild] protected Label key_info_label;

    public abstract void show_dialog (ApplicationWindow window);
}

private class KeyListBoxRowNonEditable : KeyListBoxRow
{
    public KeyListBoxRowNonEditable (string key_name, string key_value)
    {
        key_name_label.label = key_name;
        key_value_label.label = key_value;
        key_info_label.set_markup ("<i>" + _("No Schema") + "</i>");
    }

    public override void show_dialog (ApplicationWindow window)
    {
        MessageDialog dialog = new MessageDialog (window, DialogFlags.MODAL, MessageType.WARNING, ButtonsType.OK, _("No Schema, cannot edit value."));  // TODO with or without punctuation?        // TODO insert key name/path/..?
        dialog.run ();
        dialog.destroy ();
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

        string? summary = key.schema.summary;
        if (summary == null || summary == "")
            return;

        string? gettext_domain = key.schema.gettext_domain;
        if (gettext_domain != null)
            summary = dgettext (gettext_domain, summary);
        key_info_label.label = summary.strip ();
    }

    public void update ()
    {
        attr_list.change (Pango.attr_weight_new (key.is_default ? Pango.Weight.NORMAL : Pango.Weight.BOLD));    // TODO good?
        key_name_label.set_attributes (attr_list);
        // TODO key_info_label.set_attributes (attr_list); ?

        key_value_label.label = key.cool_text_value ();
    }

    public override void show_dialog (ApplicationWindow window)
    {
        KeyEditor key_editor = new KeyEditor (key);
        key_editor.set_transient_for (window);
        key_editor.run ();
    }
}
