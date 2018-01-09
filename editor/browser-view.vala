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

public enum Behaviour {
    UNSAFE,
    SAFE,
    ALWAYS_CONFIRM_IMPLICIT,
    ALWAYS_CONFIRM_EXPLICIT,
    ALWAYS_DELAY
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-view.ui")]
class BrowserView : Grid
{
    public string current_path { get; private set; default = "/"; }

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");
    private Directory current_directory;

    [GtkChild] private BrowserInfoBar info_bar;

    [GtkChild] private Stack stack;
    [GtkChild] private RegistryView browse_view;
    [GtkChild] private RegistryInfo properties_view;
    [GtkChild] private RegistrySearch search_results_view;
    private Widget? pre_search_view = null;

    public SortingOptions sorting_options { get; private set; }

    public bool small_keys_list_rows
    {
        set
        {
            browse_view.small_keys_list_rows = value;
        }
    }

    [GtkChild] private ModificationsRevealer revealer;

    private ModificationsHandler _modifications_handler;
    public ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set {
            _modifications_handler = value;
            revealer.modifications_handler = value;
            browse_view.modifications_handler = value;
            properties_view.modifications_handler = value;
            search_results_view.modifications_handler = value;

            settings.bind ("behaviour", modifications_handler, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
            ulong modifications_handler_reload_handler = modifications_handler.reload.connect (invalidate_popovers);
            destroy.connect (() => {
                modifications_handler.disconnect (modifications_handler_reload_handler);
            });
        }
    }

    private DConfWindow? _main_window = null;
    private DConfWindow main_window {
        get {
            if (_main_window == null)
                _main_window = (DConfWindow) DConfWindow._get_parent (DConfWindow._get_parent (DConfWindow._get_parent (this)));
            return (!) _main_window;
        }
    }

    construct
    {
        info_bar.add_label ("soft-reload", _("Sort preferences have changed. Do you want to reload the view?"),
                                           _("Refresh"), "ui.reload");
        info_bar.add_label ("hard-reload", _("This content has changed. Do you want to reload the view?"),
                                           _("Reload"), "ui.reload");

        ulong behaviour_changed_handler = settings.changed ["behaviour"].connect (invalidate_popovers);
        settings.bind ("behaviour", browse_view, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        sorting_options = new SortingOptions ();
        settings.bind ("sort-case-sensitive", sorting_options, "case-sensitive", GLib.SettingsBindFlags.GET);
        settings.bind ("sort-folders", sorting_options, "sort-folders", GLib.SettingsBindFlags.GET);

        sorting_options.notify.connect (() => {
                if (!current_view_is_browse_view ())
                    return;
                GLib.ListStore? key_model = browse_view.get_key_model ();
                if (key_model != null && !sorting_options.is_key_model_sorted ((!) key_model))
                    show_soft_reload_warning ();
                // TODO reload search results too
            });

        destroy.connect (() => {
                settings.disconnect (behaviour_changed_handler);
                base.destroy ();
            });
    }

    public string? get_selected_row_name ()
    {
        if (current_view_is_browse_view ())
            return browse_view.get_selected_row_name ();
        if (current_view_is_search_results_view ())
            return search_results_view.get_selected_row_name ();
        return null;
    }

    public void set_directory (Directory directory, string? selected)
    {
        SettingsModel model = modifications_handler.model;
        GLib.ListStore? key_model = model.get_children (directory);
        if (key_model != null)
        {
            current_directory = directory;
            sorting_options.sort_key_model ((!) key_model);

            browse_view.set_key_model ((!) key_model);

            show_browse_view (directory.full_name, selected);
            properties_view.clean ();
        }
    }

    private void show_browse_view (string path, string? selected)
    {
        _show_browse_view (path);
        select_row (selected);
    }
    private void _show_browse_view (string path)
    {
        stack.set_transition_type (current_path.has_prefix (path) && pre_search_view == null ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        pre_search_view = null;
        hide_reload_warning ();
        browse_view.show_multiple_schemas_warning (current_directory.warning_multiple_schemas);

        update_current_path (path);
        stack.set_visible_child (browse_view);
    }
    private void select_row (string? selected)
    {
        bool grab_focus = true;     // unused, for now
        if (selected != null)
            browse_view.select_row_named ((!) selected, grab_focus);
        else
            browse_view.select_first_row (grab_focus);
    }

    public void show_properties_view (Key key, string path, bool warning_multiple_schemas)
    {
        properties_view.populate_properties_list_box (key, warning_multiple_schemas);

        hide_reload_warning ();
        browse_view.show_multiple_schemas_warning (false);

        stack.set_transition_type (current_path == SettingsModel.get_parent_path (path) && pre_search_view == null ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        pre_search_view = null;
        update_current_path (path);
        stack.set_visible_child (properties_view);
    }

    public void show_search_view (string term)
    {
        search_results_view.start_search (term);
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

    private void update_current_path (string path)
    {
        modifications_handler.path_changed ();
        current_path = path;
        main_window.update_path_elements ();
        invalidate_popovers ();
    }

    public string? get_copy_text ()
    {
        return ((BrowsableView) stack.get_visible_child ()).get_copy_text ();
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

    public void set_to_default ()
    {
        if (current_view_is_browse_view ())
            browse_view.set_to_default ();
        else if (current_view_is_search_results_view ())
            search_results_view.set_to_default ();
    }

    public void discard_row_popover ()
    {
        if (current_view_is_browse_view ())
            browse_view.discard_row_popover ();
        else if (current_view_is_search_results_view ())
            search_results_view.discard_row_popover ();
    }

    private void invalidate_popovers ()
    {
        browse_view.invalidate_popovers ();
        search_results_view.invalidate_popovers ();
        main_window.update_hamburger_menu ();
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
        if (!info_bar.is_shown ("hard-reload"))
            info_bar.show_warning ("soft-reload");
    }

    public void show_hard_reload_warning ()
    {
        info_bar.show_warning ("hard-reload");
    }

    public void reload_search ()
    {
        hide_reload_warning ();
        search_results_view.reload_search ();
    }

    public bool check_reload ()
    {
        SettingsModel model = modifications_handler.model;
        if (current_view_is_properties_view ())
        {
            Key? fresh_key = (Key?) model.get_object (current_path);
            if (fresh_key != null && !properties_view.check_reload ((!) fresh_key, model.get_key_value ((!) fresh_key)))
                return false;
        }
        else if (current_view_is_browse_view ())
        {
            Directory? fresh_dir = (Directory?) model.get_directory (current_path);
            GLib.ListStore? fresh_key_model = model.get_children (fresh_dir);
            if (fresh_key_model != null && !browse_view.check_reload ((!) fresh_dir, (!) fresh_key_model))
                return false;
        } // search_results_view always reloads
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

    public bool up_pressed (bool grab_focus)
    {
        if (current_view_is_browse_view ())
            return browse_view.up_or_down_pressed (grab_focus, false);
        else if (current_view_is_search_results_view ())
            return search_results_view.up_or_down_pressed (grab_focus, false);
        return false;
    }

    public bool down_pressed (bool grab_focus)
    {
        if (current_view_is_browse_view ())
            return browse_view.up_or_down_pressed (grab_focus, true);
        else if (current_view_is_search_results_view ())
            return search_results_view.up_or_down_pressed (grab_focus, true);
        return false;
    }

    /*\
    * * Delay mode actions
    \*/

    public void reset_objects (GLib.ListStore? objects, bool recursively)
    {
        enter_delay_mode ();
        reset_generic (objects, recursively);
        revealer.warn_if_no_planned_changes ();
    }

    private void reset_generic (GLib.ListStore? objects, bool recursively)
    {
        SettingsModel model = modifications_handler.model;
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
                if (recursively) {
                    GLib.ListStore? children = model.get_children ((Directory) setting_object);
                    if (children != null)
                        reset_generic ((!) children, true);
                }
                continue;
            }
            if (setting_object is DConfKey)
            {
                if (!model.is_key_ghost ((DConfKey) setting_object))
                    modifications_handler.add_delayed_setting ((Key) setting_object, null);
            }
            else if (!model.is_key_default ((GSettingsKey) setting_object))
                modifications_handler.add_delayed_setting ((Key) setting_object, null);
        }
    }

    public void enter_delay_mode ()
    {
        modifications_handler.enter_delay_mode ();
        invalidate_popovers ();
    }
}

public interface BrowsableView
{
    public abstract string? get_copy_text ();
}

/*\
* * Sorting
\*/

public enum MergeType {
    MIXED,
    FIRST,
    LAST
}

public class SortingOptions : Object
{
    public bool case_sensitive { get; set; default = false; }
    public MergeType sort_folders { get; set; default = MergeType.MIXED; }

    public SettingComparator get_comparator ()
    {
        if (sort_folders == MergeType.FIRST)
        {
            if (case_sensitive)
                return new FoldersFirstCaseSensitive ();
            else
                return new FoldersFirstCaseInsensitive ();
        }
        else if (sort_folders == MergeType.LAST)
        {
            if (case_sensitive)
                return new FoldersLastCaseSensitive ();
            else
                return new FoldersLastCaseInsensitive ();
        }
        else // if (sort_folders == MergeType.MIXED)
        {
            if (case_sensitive)
                return new FoldersMixedCaseSensitive ();
            else
                return new FoldersMixedCaseInsensitive ();
        }
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
}

class FoldersMixedCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersMixedCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        return strcmp (a.name, b.name);
    }
}

class FoldersFirstCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return -1;
        if (!(a is Directory) && b is Directory)
            return 1;
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersFirstCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return -1;
        if (!(a is Directory) && b is Directory)
            return 1;
        return strcmp (a.name, b.name);
    }
}

class FoldersLastCaseInsensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return 1;
        if (!(a is Directory) && b is Directory)
            return -1;
        return a.casefolded_name.collate (b.casefolded_name);
    }
}

class FoldersLastCaseSensitive : Object, SettingComparator
{
    public int compare (SettingObject a, SettingObject b)
    {
        if (a is Directory && !(b is Directory))
            return 1;
        if (!(a is Directory) && b is Directory)
            return -1;
        return strcmp (a.name, b.name);
    }
}
