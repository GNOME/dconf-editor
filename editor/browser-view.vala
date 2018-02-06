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
class BrowserView : Grid
{
    public string last_context { get; private set; default = ""; }

    [GtkChild] private BrowserInfoBar info_bar;

    [GtkChild] private Stack stack;
    [GtkChild] private RegistryView browse_view;
    [GtkChild] private RegistryInfo properties_view;
    [GtkChild] private RegistrySearch search_results_view;
    private Widget? pre_search_view = null;

    private SortingOptions sorting_options = new SortingOptions ();
    private GLib.ListStore? key_model = null;

    public bool small_keys_list_rows
    {
        set
        {
            browse_view.small_keys_list_rows = value;
            search_results_view.small_keys_list_rows = value;
        }
    }

    private ModificationsHandler _modifications_handler;
    public ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set {
            _modifications_handler = value;
            browse_view.modifications_handler = value;
            properties_view.modifications_handler = value;
            search_results_view.modifications_handler = value;
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
                if (!current_view_is_browse_view ())
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
        { "empty", empty , "*" },

        { "refresh-folder", refresh_folder },
        { "set-to-default", set_to_default, "(ss)" },

        { "toggle-dconf-key-switch",     toggle_dconf_key_switch,     "(sb)"   },
        { "toggle-gsettings-key-switch", toggle_gsettings_key_switch, "(ssbb)" }
    };

    private void empty (/* SimpleAction action, Variant? variant */) {}

    private void refresh_folder (/* SimpleAction action, Variant? path_variant */)
        requires (key_model != null)
    {
        sorting_options.sort_key_model ((!) key_model);
        hide_reload_warning ();
    }

    private void set_to_default (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        string context;
        ((!) path_variant).@get ("(ss)", out full_name, out context);
        modifications_handler.set_to_default (full_name, context);
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
        string context;
        bool key_value_request;
        bool key_default_value;
        ((!) value_variant).@get ("(ssbb)", out full_name, out context, out key_value_request, out key_default_value);

        if (key_value_request == key_default_value)
            modifications_handler.set_to_default (full_name, context);
        else
            modifications_handler.set_gsettings_key_value (full_name, context, new Variant.boolean (key_value_request));
    }

    /*\
    * * Views
    \*/

    public string get_selected_row_name ()
    {
        if (current_view_is_browse_view ())
            return browse_view.get_selected_row_name ();
        if (current_view_is_search_results_view ())
            return search_results_view.get_selected_row_name ();
        return "";
    }

    public void prepare_browse_view (GLib.ListStore key_model, bool is_ancestor)
    {
        this.key_model = key_model;
        sorting_options.sort_key_model (key_model);
        browse_view.set_key_model (key_model);

        stack.set_transition_type (is_ancestor && pre_search_view == null ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        pre_search_view = null;
        hide_reload_warning ();
    }

    public void select_row (string selected)
    {
        bool grab_focus = true;     // unused, for now
        if (selected != "")
            browse_view.select_row_named (selected, last_context, grab_focus);
        else
            browse_view.select_first_row (grab_focus);
        properties_view.clean ();
    }

    public void prepare_properties_view (Key key, bool is_parent)
    {
        properties_view.populate_properties_list_box (key);

        hide_reload_warning ();

        stack.set_transition_type (is_parent && pre_search_view == null ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        pre_search_view = null;

        last_context = (key is GSettingsKey) ? ((GSettingsKey) key).schema_id : ".dconf";
    }

    public void show_search_view (string term, string current_path, string [] bookmarks)
    {
        search_results_view.start_search (term, current_path, bookmarks, sorting_options);
        if (pre_search_view == null)
        {
            pre_search_view = stack.visible_child;
            stack.set_transition_type (StackTransitionType.NONE);
            stack.visible_child = search_results_view;
        }
    }

    public void hide_search_view ()
    {
        if (pre_search_view != null)
        {
            stack.set_transition_type (StackTransitionType.NONE);
            stack.visible_child = (!) pre_search_view;
            pre_search_view = null;

            if (stack.get_visible_child () == browse_view)
                browse_view.focus_selected_row ();
        }
        search_results_view.stop_search ();
    }

    public void set_path (string path)
    {
        if (path.has_suffix ("/"))
            stack.set_visible_child (browse_view);
        else
            stack.set_visible_child (properties_view);

        modifications_handler.path_changed ();
    }

    public string? get_copy_text ()
    {
        return ((BrowsableView) stack.get_visible_child ()).get_copy_text ();
    }

    public string? get_copy_path_text ()
    {
        if (current_view_is_search_results_view ())
            return search_results_view.get_copy_path_text ();

        warning ("BrowserView get_copy_path_text() called but current view is not search results view.");
        return null;
    }

    public bool show_row_popover ()
    {
        if (current_view_is_browse_view ())
            return browse_view.show_row_popover ();
        if (current_view_is_search_results_view ())
            return search_results_view.show_row_popover ();
        return false;
    }

    public void toggle_boolean_key ()
    {
        if (current_view_is_browse_view ())
            browse_view.toggle_boolean_key ();
        else if (current_view_is_search_results_view ())
            search_results_view.toggle_boolean_key ();
    }

    public void set_selected_to_default ()
    {
        if (current_view_is_browse_view ())
            browse_view.set_selected_to_default ();
        else if (current_view_is_search_results_view ())
            search_results_view.set_selected_to_default ();
    }

    public void discard_row_popover ()
    {
        if (current_view_is_browse_view ())
            browse_view.discard_row_popover ();
        else if (current_view_is_search_results_view ())
            search_results_view.discard_row_popover ();
    }

    public void invalidate_popovers ()
    {
        browse_view.invalidate_popovers ();
        search_results_view.invalidate_popovers ();
    }

    public bool current_view_is_browse_view ()
    {
        return stack.get_visible_child () == browse_view;
    }

    public bool current_view_is_properties_view ()
    {
        return stack.get_visible_child () == properties_view;
    }

    public bool current_view_is_search_results_view ()
    {
        return stack.get_visible_child () == search_results_view;
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

    private void show_hard_reload_warning ()
    {
        info_bar.show_warning (current_view_is_browse_view () ? "hard-reload-folder" : "hard-reload-object");
    }

    public void reload_search (string current_path, string [] bookmarks)
    {
        hide_reload_warning ();
        search_results_view.reload_search (current_path, bookmarks, sorting_options);
    }

    public bool check_reload (string path, bool show_infobar)
    {
        SettingsModel model = modifications_handler.model;

        if (current_view_is_browse_view ())
        {
            GLib.ListStore? fresh_key_model = model.get_children (path);
            if (fresh_key_model != null && !browse_view.check_reload ((!) fresh_key_model))
                return false;
        }
        else if (current_view_is_properties_view ())
        {
            Variant? properties = model.get_key_properties (path, last_context);
            if (properties != null && !properties_view.check_reload ((!) properties))
                return false;
        }

        if (show_infobar && !current_view_is_search_results_view ())
        {
            show_hard_reload_warning ();
            return false;
        }
        return true;
    }

    /*\
    * * Keyboard calls
    \*/

    public bool return_pressed ()
    {
        if (!current_view_is_search_results_view ())
            assert_not_reached ();

        return search_results_view.return_pressed ();
    }

    public bool up_pressed ()
    {
        if (current_view_is_browse_view ())
            return browse_view.up_or_down_pressed (false);
        else if (current_view_is_search_results_view ())
            return search_results_view.up_or_down_pressed (false);
        return false;
    }

    public bool down_pressed ()
    {
        if (current_view_is_browse_view ())
            return browse_view.up_or_down_pressed (true);
        else if (current_view_is_search_results_view ())
            return search_results_view.up_or_down_pressed (true);
        return false;
    }
}

public interface BrowsableView
{
    public abstract string? get_copy_text ();
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
