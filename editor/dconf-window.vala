/*
  This file is part of Dconf Editor

  Dconf Editor is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  Dconf Editor is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public License
  along with Dconf Editor; if not, write to the Free Software Foundation, Inc.,
  51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    private SettingsModel model;
    [GtkChild]
    private TreeView dir_tree_view;

    private TreeView key_tree_view;
    [GtkChild]
    private ScrolledWindow key_scrolledwindow;  // TODO used only for adding key_tree_view, a pseudo-TreeView

    [GtkChild]
    private Grid key_info_grid;
    [GtkChild]
    private Label schema_label;
    [GtkChild]
    private Label summary_label;
    [GtkChild]
    private Label description_label;
    [GtkChild]
    private Label type_label;
    [GtkChild]
    private Label default_label;

    [GtkChild]
    private Box search_box;
    [GtkChild]
    private Entry search_entry;
    [GtkChild]
    private Label search_label;

    private Key? selected_key;

    private const GLib.ActionEntry[] window_actions =
    {
        { "set-default", set_default_cb }
    };
    private SimpleAction set_default_action;

    public DConfWindow ()
    {
        add_action_entries (window_actions, this);
        set_default_action = (SimpleAction) lookup_action ("set-default");
        set_default_action.set_enabled (false);

        /* key tree */
        key_tree_view = new DConfKeyView ();
        key_tree_view.show ();
        key_tree_view.get_selection ().changed.connect (key_selected_cb);
        key_scrolledwindow.add (key_tree_view);

        /* dir tree */
        model = new SettingsModel ();
        dir_tree_view.set_model (model);

        TreeSelection selection = dir_tree_view.get_selection ();
        selection.changed.connect (dir_selected_cb);

        TreeIter iter;
        if (model.get_iter_first (out iter))
            selection.select_iter (iter);
    }

    /*\
    * * Dir TreeView
    \*/

    private void dir_selected_cb ()
    {
        KeyModel? key_model = null;

        TreeIter iter;
        if (dir_tree_view.get_selection ().get_selected (null, out iter))
            key_model = model.get_directory (iter).key_model;

        key_tree_view.set_model (key_model);

        /* Always select something */
        if (key_model != null && key_model.get_iter_first (out iter))
            key_tree_view.get_selection ().select_iter (iter);
    }

    /*\
    * * Key TreeView & informations
    \*/

    private string key_to_description (Key key)
    {
        switch (key.schema.type)
        {
        case "y":
        case "n":
        case "q":
        case "i":
        case "u":
        case "x":
        case "t":
            Variant min, max;
            if (key.schema.range != null)
            {
                min = key.schema.range.min;
                max = key.schema.range.max;
            }
            else
            {
                min = key.get_min ();
                max = key.get_max ();
            }
            return _("Integer [%s..%s]").printf (min.print (false), max.print (false));
        case "d":
            Variant min, max;
            if (key.schema.range != null)
            {
                min = key.schema.range.min;
                max = key.schema.range.max;
            }
            else
            {
                min = key.get_min ();
                max = key.get_max ();
            }
            return _("Double [%s..%s]").printf (min.print (false), max.print (false));
        case "b":
            return _("Boolean");
        case "s":
            return _("String");
        case "<enum>":
            return _("Enumeration");
        default:
            return key.schema.type;
        }
    }

    private void key_selected_cb ()
    {
        if (selected_key != null)
            selected_key.value_changed.disconnect (key_changed_cb);

        TreeIter iter;
        TreeModel model;
        if (key_tree_view.get_selection ().get_selected (out model, out iter))
        {
            var key_model = (KeyModel) model;
            selected_key = key_model.get_key (iter);
        }
        else
            selected_key = null;

        if (selected_key != null)
            selected_key.value_changed.connect (key_changed_cb);

        key_info_grid.sensitive = selected_key != null;
        set_default_action.set_enabled (selected_key != null && !selected_key.is_default);

        string schema_name = "", summary = "", description = "", type = "", default_value = "";

        if (selected_key != null)
        {
            if (selected_key.schema != null)
            {
                var gettext_domain = selected_key.schema.gettext_domain;
                schema_name = selected_key.schema.schema.id;

                if (selected_key.schema.summary != null)
                    summary = selected_key.schema.summary;
                if (gettext_domain != null && summary != "")
                    summary = dgettext (gettext_domain, summary);

                if (selected_key.schema.description != null)
                    description = selected_key.schema.description;
                if (gettext_domain != null && description != "")
                    description = dgettext (gettext_domain, description);

                type = key_to_description (selected_key);
                default_value = selected_key.schema.default_value.print (false);
            }
            else
            {
                schema_name = _("No schema");
            }
        }

        schema_label.set_text (schema_name);
        summary_label.set_text (summary.strip ());
        description_label.set_text (description.strip ());
        type_label.set_text (type);
        default_label.set_text (default_value);
    }

    /*\
    * * Set_default button
    \*/

    private void key_changed_cb (Key key)   /* TODO reuse */
    {
        set_default_action.set_enabled (selected_key != null && !selected_key.is_default);
    }

    private void set_default_cb ()
    {
        if (selected_key == null)
            return;
        selected_key.set_to_default ();
    }

    /*\
    * * Search box
    \*/

    public void find_cb ()
    {
        search_box.show ();
        search_entry.grab_focus ();
    }

    [GtkCallback]
    private bool on_key_press_event (Gdk.EventKey event)
    {
        if (event.keyval == Gdk.Key.Escape)
        {
            search_box.hide ();
            return true;
        }
        return false;
    }

    [GtkCallback]
    private void on_close_button_clicked ()
    {
        search_box.hide ();
    }

    [GtkCallback]
    private void find_next_cb ()
    {
        search_label.set_text ("");

        /* Get the current position in the tree */
        TreeIter iter;
        TreeIter key_iter = TreeIter ();
        var have_key_iter = false;
        if (dir_tree_view.get_selection ().get_selected (null, out iter))
        {
            if (key_tree_view.get_selection ().get_selected (null, out key_iter))
            {
                var dir = model.get_directory (iter);
                if (dir.key_model.iter_next (ref key_iter))
                    have_key_iter = true;
                else
                    get_next_iter (ref iter);
            }
        }
        else if (!model.get_iter_first (out iter))
            return;

        var on_first_directory = true;
        do
        {
            /* Select next directory that matches */
            var dir = model.get_directory (iter);
            if (!have_key_iter)
            {
                have_key_iter = dir.key_model.get_iter_first (out key_iter);
                if (!on_first_directory && dir.name.index_of (search_entry.text) >= 0)
                {
                    dir_tree_view.expand_to_path (model.get_path (iter));
                    dir_tree_view.get_selection ().select_iter (iter);
                    dir_tree_view.scroll_to_cell (model.get_path (iter), null, false, 0, 0);
                    return;
                }
            }
            on_first_directory = false;

            /* Select next key that matches */
            if (have_key_iter)
            {
                do
                {
                    var key = dir.key_model.get_key (key_iter);
                    if (key_matches (key, search_entry.text))
                    {
                        dir_tree_view.expand_to_path (model.get_path (iter));
                        dir_tree_view.get_selection ().select_iter (iter);
                        dir_tree_view.scroll_to_cell (model.get_path (iter), null, false, 0, 0);
                        key_tree_view.get_selection ().select_iter (key_iter);
                        key_tree_view.scroll_to_cell (dir.key_model.get_path (key_iter), null, false, 0, 0);
                        return;
                    }
                } while (dir.key_model.iter_next (ref key_iter));
            }
            have_key_iter = false;
        } while (get_next_iter (ref iter));

        search_label.set_text(_("Not found"));
    }

    private bool key_matches (Key key, string text)
    {
        /* Check key name */
        if (key.name.index_of (text) >= 0)
            return true;

        /* Check key schema (description) */
        if (key.schema != null)
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
