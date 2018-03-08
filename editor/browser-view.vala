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
class BrowserView : Grid
{
    public string last_context { get; private set; default = ""; }

    [GtkChild] private BrowserInfoBar info_bar;
    [GtkChild] private BrowserStack current_child;

    private SortingOptions sorting_options = new SortingOptions ();
    private GLib.ListStore? key_model = null;

    public bool small_keys_list_rows { set { current_child.small_keys_list_rows = value; }}

    private ModificationsHandler _modifications_handler;
    public ModificationsHandler modifications_handler
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

        { "set-key-value",  set_key_value,  "(ssv)" },
        { "set-to-default", set_to_default, "(ss)"  },  // see also ui.erase(s)

        { "toggle-dconf-key-switch",     toggle_dconf_key_switch,     "(sb)"   },
        { "toggle-gsettings-key-switch", toggle_gsettings_key_switch, "(ssbb)" }
    };

    private void refresh_folder (/* SimpleAction action, Variant? path_variant */)
        requires (key_model != null)
    {
        sorting_options.sort_key_model ((!) key_model);
        hide_reload_warning ();
    }

    private void set_key_value (SimpleAction action, Variant? value_variant)
        requires (value_variant != null)
    {
        string full_name;
        string context;
        Variant key_value_request;
        ((!) value_variant).@get ("(ssv)", out full_name, out context, out key_value_request);

        if (modifications_handler.get_current_delay_mode ())
            modifications_handler.add_delayed_setting (full_name, key_value_request);
        else if (context == ".dconf")
            modifications_handler.set_dconf_key_value (full_name, key_value_request);
        else
            modifications_handler.set_gsettings_key_value (full_name, context, key_value_request);
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

    public void prepare_folder_view (GLib.ListStore key_model, bool is_ancestor)
    {
        this.key_model = key_model;
        sorting_options.sort_key_model (key_model);
        current_child.prepare_folder_view (key_model, is_ancestor);
        hide_reload_warning ();
    }

    public void select_row (string selected)
        requires (current_view != ViewType.OBJECT)
    {
        current_child.select_row (selected, last_context);
    }

    public void prepare_object_view (Key key, bool is_parent)
    {
        current_child.prepare_object_view (key, is_parent);
        hide_reload_warning ();
        last_context = (key is GSettingsKey) ? ((GSettingsKey) key).schema_id : ".dconf";
    }

    public void set_path (ViewType type, string path)
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

    public void set_search_parameters (string current_path, string [] bookmarks)
    {
        hide_reload_warning ();
        current_child.set_search_parameters (current_path, bookmarks, sorting_options);
    }

    public bool check_reload (ViewType type, string path, bool show_infobar)
    {
        SettingsModel model = modifications_handler.model;

        if (type == ViewType.FOLDER)
        {
            GLib.ListStore? fresh_key_model = model.get_children (path);
            if (fresh_key_model != null && !current_child.check_reload_folder ((!) fresh_key_model))
                return false;
            if (show_infobar)
            {
                info_bar.show_warning ("hard-reload-folder");
                return false;
            }
        }
        else if (type == ViewType.OBJECT)
        {
            Variant? properties = model.get_key_properties (path, last_context);
            if (properties != null && !current_child.check_reload_object ((!) properties))
                return false;
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

    public ViewType current_view { get { return current_child.current_view; }}

    // popovers invalidation
    public void discard_row_popover () { current_child.discard_row_popover (); }
    public void invalidate_popovers () { current_child.invalidate_popovers (); }

    // keyboard
    public bool return_pressed ()   { return current_child.return_pressed ();   }
    public bool up_pressed ()       { return current_child.up_pressed ();       }
    public bool down_pressed ()     { return current_child.down_pressed ();     }

    public bool show_row_popover () { return current_child.show_row_popover (); }   // Menu

    public void toggle_boolean_key ()      { current_child.toggle_boolean_key ();      }
    public void set_selected_to_default () { current_child.set_selected_to_default (); }

    // current row property
    public string get_selected_row_name () { return current_child.get_selected_row_name (); }
    public string? get_copy_text ()        { return current_child.get_copy_text ();         }
    public string? get_copy_path_text ()   { return current_child.get_copy_path_text ();    }
}

/*\
* * Sorting
\*/

public class SortingOptions : Object
{
    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    public bool case_sensitive { get; set; default = false; }

    construct
    {
        settings.bind ("sort-case-sensitive", this, "case-sensitive", GLib.SettingsBindFlags.GET);
    }

    public SettingComparator get_comparator ()
    {
        if (case_sensitive)
            return new BySchemaCaseSensitive ();
        else
            return new BySchemaCaseInsensitive ();
    }

    public void sort_key_model (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        model.sort ((a, b) => comparator.compare ((SettingObject) a, (SettingObject) b));
    }

    public bool is_key_model_sorted (GLib.ListStore model)
    {
        SettingComparator comparator = get_comparator ();

        uint last = model.get_n_items () - 1;
        for (int i = 0; i < last; i++)
        {
            SettingObject item = (SettingObject) model.get_item (i);
            SettingObject next = (SettingObject) model.get_item (i + 1);
            if (comparator.compare (item, next) > 0)
                return false;
        }
        return true;
    }
}

/* Comparison functions */

public interface SettingComparator : Object
{
    public abstract int compare (SettingObject a, SettingObject b);

    protected virtual bool sort_directories_first (SettingObject a, SettingObject b, ref int return_value)
    {
        if (a is Directory && !(b is Directory))
            return_value = -1;
        else if (!(a is Directory) && b is Directory)
            return_value = 1;
        else
            return false;
        return true;
    }

    protected virtual bool sort_dconf_keys_second (SettingObject a, SettingObject b, ref int return_value)
    {
        if (a is DConfKey && !(b is DConfKey))
            return_value = -1;
        else if (!(a is DConfKey) && b is DConfKey)
            return_value = 1;
        else
            return false;
        return true;
    }

    protected virtual bool sort_by_schema_thirdly (SettingObject a, SettingObject b, ref int return_value)
    {
        if (!(a is GSettingsKey) || !(b is GSettingsKey))
            return false;
        return_value = strcmp (((GSettingsKey) a).schema_id, ((GSettingsKey) b).schema_id);
        return return_value != 0;
    }
}

class BySchemaCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
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

class BySchemaCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
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
