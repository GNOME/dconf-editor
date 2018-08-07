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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-view.ui")]
private class BrowserView : Grid
{
    internal string last_context { get; private set; default = ""; }

    [GtkChild] private BrowserInfoBar info_bar;
    [GtkChild] private BrowserStack current_child;

    private SortingOptions sorting_options = new SortingOptions ();
    private GLib.ListStore? key_model = null;

    internal bool small_keys_list_rows { set { current_child.small_keys_list_rows = value; }}

    private ModificationsHandler _modifications_handler;
    internal ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set {
            _modifications_handler = value;
            current_child.modifications_handler = value;
        }
    }

    construct
    {
        install_action_entries ();

        info_bar.add_label ("soft-reload-folder", _("Sort preferences have changed. Do you want to refresh the view?"),
                                                  _("Refresh"), "bro.refresh-folder");
        info_bar.add_label ("hard-reload-folder", _("This folder content has changed. Do you want to reload the view?"),
                                                  _("Reload"), "ui.reload-folder");
        info_bar.add_label ("hard-reload-object", _("This key’s properties have changed. Do you want to reload the view?"),
                                                  _("Reload"), "ui.reload-object");   // TODO also for key removing?

        sorting_options.notify.connect (() => {
                if (current_view != ViewType.FOLDER)
                    return;

                if (key_model != null && !sorting_options.is_key_model_sorted ((!) key_model))
                    show_soft_reload_warning ();
                // TODO reload search results too
            });
    }

    /*\
    * * Action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("bro", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "refresh-folder", refresh_folder },

        { "set-gsettings-key-value",    set_gsettings_key_value,        "(ssv)"  },
        { "set-dconf-key-value",        set_dconf_key_value,            "(ssv)"  },
        { "set-to-default",             set_to_default,                 "(ss)"   },  // see also ui.erase(s)

        { "toggle-dconf-key-switch",     toggle_dconf_key_switch,       "(sb)"   },
        { "toggle-gsettings-key-switch", toggle_gsettings_key_switch,   "(ssbb)" }
    };

    private void refresh_folder (/* SimpleAction action, Variant? path_variant */)
        requires (key_model != null)
    {
        sorting_options.sort_key_model ((!) key_model);
        hide_reload_warning ();
    }

    private void set_gsettings_key_value (SimpleAction action, Variant? value_variant)
        requires (value_variant != null)
    {
        string full_name;
        string schema_id;
        Variant key_value_request;
        ((!) value_variant).@get ("(ssv)", out full_name, out schema_id, out key_value_request);

        if (modifications_handler.get_current_delay_mode ())
            modifications_handler.add_delayed_setting (full_name, key_value_request, true, schema_id);
        else
            modifications_handler.set_gsettings_key_value (full_name, schema_id, key_value_request);
    }

    private void set_dconf_key_value (SimpleAction action, Variant? value_variant)
        requires (value_variant != null)
    {
        string full_name;
        Variant key_value_request;
        ((!) value_variant).@get ("(sv)", out full_name, out key_value_request);

        if (modifications_handler.get_current_delay_mode ())
            modifications_handler.add_delayed_setting (full_name, key_value_request, false);
        else
            modifications_handler.set_dconf_key_value (full_name, key_value_request);
    }

    private void set_to_default (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        string schema_id;
        ((!) path_variant).@get ("(ss)", out full_name, out schema_id);
        modifications_handler.set_to_default (full_name, schema_id);
        invalidate_popovers ();
    }

    private void toggle_dconf_key_switch (SimpleAction action, Variant? value_variant)
        requires (value_variant != null)
    {
        if (modifications_handler.get_current_delay_mode ())
            assert_not_reached ();

        string full_name;
        bool key_value_request;
        ((!) value_variant).@get ("(sb)", out full_name, out key_value_request);

        modifications_handler.set_dconf_key_value (full_name, key_value_request);
    }

    private void toggle_gsettings_key_switch (SimpleAction action, Variant? value_variant)
        requires (value_variant != null)
    {
        if (modifications_handler.get_current_delay_mode ())
            assert_not_reached ();

        string full_name;
        string schema_id;
        bool key_value_request;
        bool key_default_value;
        ((!) value_variant).@get ("(ssbb)", out full_name, out schema_id, out key_value_request, out key_default_value);

        if (key_value_request == key_default_value)
            modifications_handler.set_to_default (full_name, schema_id);
        else
            modifications_handler.set_gsettings_key_value (full_name, schema_id, new Variant.boolean (key_value_request));
    }

    /*\
    * * Views
    \*/

    internal void prepare_folder_view (string base_path, Variant? children, bool is_ancestor)
    {
        key_model = new GLib.ListStore (typeof (SimpleSettingObject));
        if (children != null)
        {
            VariantIter iter = new VariantIter ((!) children);
            bool is_folder;
            string context, name;
            while (iter.next ("(bss)", out is_folder, out context, out name))
            {
                SimpleSettingObject sso = new SimpleSettingObject.from_base_path (is_folder, context, name, base_path);
                ((!) key_model).append (sso);
            }
        }

        sorting_options.sort_key_model ((!) key_model);
        current_child.prepare_folder_view ((!) key_model, is_ancestor);
        hide_reload_warning ();
    }

    internal void select_row (string selected)
        requires (current_view != ViewType.OBJECT)
    {
        current_child.select_row (selected, last_context);
    }

    internal void prepare_object_view (string full_name, string context, Variant properties, bool is_parent)
    {
        current_child.prepare_object_view (full_name, context, properties, is_parent);
        hide_reload_warning ();
        last_context = context;
    }

    internal void set_path (ViewType type, string path)
    {
        current_child.set_path (type, path);
        modifications_handler.path_changed ();
    }

    /*\
    * * Reload
    \*/

    private void hide_reload_warning ()
    {
        info_bar.hide_warning ();
    }

    private void show_soft_reload_warning ()
    {
        if (!info_bar.is_shown ("hard-reload-folder") && !info_bar.is_shown ("hard-reload-object"))
            info_bar.show_warning ("soft-reload-folder");
    }

    internal void set_search_parameters (string current_path, string [] bookmarks)
    {
        hide_reload_warning ();
        current_child.set_search_parameters (current_path, bookmarks, sorting_options);
    }

    internal bool check_reload (ViewType type, string path, bool show_infobar)
    {
        SettingsModel model = modifications_handler.model;

        if (type == ViewType.FOLDER)
        {
            if (!current_child.check_reload_folder (model.get_children (path)))
                return false;
            if (show_infobar)
            {
                info_bar.show_warning ("hard-reload-folder");
                return false;
            }
        }
        else if (type == ViewType.OBJECT)
        {
            if (model.key_exists (path, last_context))
            {
                RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (path, last_context, (uint16) PropertyQuery.HASH));
                uint properties_hash;
                if (!properties.lookup (PropertyQuery.HASH, "u", out properties_hash))
                    assert_not_reached ();
                if (!current_child.check_reload_object (properties_hash))
                    return false;
            }
            if (show_infobar)
            {
                info_bar.show_warning ("hard-reload-object");
                return false;
            }
        }
        else // (type == ViewType.SEARCH)
            assert_not_reached ();
        return true;
    }

    /*\
    * * Proxy calls
    \*/

    internal ViewType current_view { get { return current_child.current_view; }}

    // popovers invalidation and toggles hiding/revealing
    internal void discard_row_popover () { current_child.discard_row_popover (); }
    internal void invalidate_popovers () { current_child.invalidate_popovers (); }

    internal void hide_or_show_toggles (bool show) { current_child.hide_or_show_toggles (show); }

    // keyboard
    internal bool return_pressed ()   { return current_child.return_pressed ();   }
    internal bool up_pressed ()       { return current_child.up_pressed ();       }
    internal bool down_pressed ()     { return current_child.down_pressed ();     }

    internal bool toggle_row_popover () { return current_child.toggle_row_popover (); }   // Menu

    internal void toggle_boolean_key ()      { current_child.toggle_boolean_key ();      }
    internal void set_selected_to_default () { current_child.set_selected_to_default (); }

    // current row property
    internal string get_selected_row_name () { return current_child.get_selected_row_name (); }
    internal string? get_copy_text ()        { return current_child.get_copy_text ();         }
    internal string? get_copy_path_text ()   { return current_child.get_copy_path_text ();    }

    // values changes
    internal void gkey_value_push (string full_name, string schema_id, Variant key_value, bool is_key_default)
    {
        current_child.gkey_value_push (full_name, schema_id, key_value, is_key_default);
    }
    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        current_child.dkey_value_push (full_name, key_value_or_null);
    }
}

/*\
* * Sorting
\*/

private class SortingOptions : Object
{
    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    internal bool case_sensitive { get; set; default = false; }

    construct
    {
        settings.bind ("sort-case-sensitive", this, "case-sensitive", GLib.SettingsBindFlags.GET);
    }

    internal SettingComparator get_comparator ()
    {
        if (case_sensitive)
            return new BySchemaCaseSensitive ();
        else
            return new BySchemaCaseInsensitive ();
    }

    internal void sort_key_model (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        model.sort ((a, b) => comparator.compare ((SimpleSettingObject) a, (SimpleSettingObject) b));
    }

    internal bool is_key_model_sorted (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        uint last = model.get_n_items () - 1;
        for (int i = 0; i < last; i++)
        {
            SimpleSettingObject item = (SimpleSettingObject) model.get_item (i);
            SimpleSettingObject next = (SimpleSettingObject) model.get_item (i + 1);
            if (comparator.compare (item, next) > 0)
                return false;
        }
        return true;
    }
}

/* Comparison functions */

private interface SettingComparator : Object
{
    internal abstract int compare (SimpleSettingObject a, SimpleSettingObject b);

    protected virtual bool sort_directories_first (SimpleSettingObject a, SimpleSettingObject b, ref int return_value)
    {
        if (a.is_folder && !b.is_folder)
            return_value = -1;
        else if (!a.is_folder && b.is_folder)
            return_value = 1;
        else
            return false;
        return true;
    }

    protected virtual bool sort_dconf_keys_second (SimpleSettingObject a, SimpleSettingObject b, ref int return_value)
    {
        if (a.context == ".dconf" && b.context != ".dconf")
            return_value = -1;
        else if (a.context != ".dconf" && b.context == ".dconf")
            return_value = 1;
        else
            return false;
        return true;
    }

    protected virtual bool sort_by_schema_thirdly (SimpleSettingObject a, SimpleSettingObject b, ref int return_value)
    {
        return_value = strcmp (a.context, b.context);
        return return_value != 0;
    }
}

private class BySchemaCaseInsensitive : Object, SettingComparator
{
    internal int compare (SimpleSettingObject a, SimpleSettingObject b)
    {
        int return_value = 0;
        if (sort_directories_first (a, b, ref return_value))
            return return_value;
        if (sort_dconf_keys_second (a, b, ref return_value))
            return return_value;
        if (sort_by_schema_thirdly (a, b, ref return_value))
            return return_value;

        return a.casefolded_name.collate (b.casefolded_name);
    }
}

private class BySchemaCaseSensitive : Object, SettingComparator
{
    internal int compare (SimpleSettingObject a, SimpleSettingObject b)
    {
        int return_value = 0;
        if (sort_directories_first (a, b, ref return_value))
            return return_value;
        if (sort_dconf_keys_second (a, b, ref return_value))
            return return_value;
        if (sort_by_schema_thirdly (a, b, ref return_value))
            return return_value;

        return strcmp (a.name, b.name);
    }
}
