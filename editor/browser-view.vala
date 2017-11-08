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
class BrowserView : Grid, PathElement
{
    public string current_path { get; private set; }

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");
    private Directory current_directory;

    [GtkChild] private Revealer need_reload_warning_revealer;

    [GtkChild] private Stack stack;
    [GtkChild] private RegistryView browse_view;
    [GtkChild] private RegistryInfo properties_view;

    private SortingOptions sorting_options;

    public bool small_keys_list_rows
    {
        set
        {
            browse_view.small_keys_list_rows = value;
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

        ulong behaviour_changed_handler = settings.changed ["behaviour"].connect (invalidate_popovers);
        settings.bind ("behaviour", revealer, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        settings.bind ("behaviour", browse_view, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);

        sorting_options = new SortingOptions ();
        settings.bind ("sort-case-sensitive", sorting_options, "case-sensitive", GLib.SettingsBindFlags.GET);
        settings.bind ("sort-folders", sorting_options, "sort-folders", GLib.SettingsBindFlags.GET);

        sorting_options.notify.connect (() => {
                if (!is_not_browsing_view () && current_directory.need_sorting (sorting_options))
                    need_reload_warning_revealer.set_reveal_child (true);
            });

        destroy.connect (() => {
                settings.disconnect (behaviour_changed_handler);
                revealer.disconnect (revealer_reload_handler);
                base.destroy ();
            });
    }

    public void init (string path, bool restore_view)   // TODO check path format
    {
        current_path = (restore_view && path != "" && path [0] == '/') ? path : "/";
    }

    [GtkCallback]
    private void request_path_test (string test)
    {
        request_path (test);
    }

    public void set_directory (Directory directory, string? selected)
    {
        current_directory = directory;
        current_directory.sort_key_model (sorting_options);

        browse_view.set_key_model (directory.key_model);

        show_browse_view (directory.full_name, selected);
        properties_view.clean ();
    }

    private void show_browse_view (string path, string? selected)
    {
        _show_browse_view (path);
        select_row (selected);
    }
    private void _show_browse_view (string path)
    {
        stack.set_transition_type (current_path.has_prefix (path) ? StackTransitionType.CROSSFADE : StackTransitionType.NONE);
        need_reload_warning_revealer.set_reveal_child (false);
        browse_view.show_multiple_schemas_warning (current_directory.warning_multiple_schemas);

        update_current_path (path);
        stack.set_visible_child_name ("browse-view");
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

        need_reload_warning_revealer.set_reveal_child (false);
        browse_view.show_multiple_schemas_warning (false);

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

    public bool get_current_delay_mode ()
    {
        return revealer.get_current_delay_mode ();
    }

    public string? get_copy_text ()
    {
        return ((BrowsableView) stack.get_visible_child ()).get_copy_text ();
    }

    public bool show_row_popover ()
    {
        if (is_not_browsing_view ())
            return false;
        return browse_view.show_row_popover ();
    }

    public void toggle_boolean_key ()
    {
        if (is_not_browsing_view ())
            return;                         // TODO something, probably
        browse_view.toggle_boolean_key ();
    }

    public void set_to_default ()
    {
        if (is_not_browsing_view ())
            return;
        browse_view.set_to_default ();
    }

    public void discard_row_popover ()
    {
        if (is_not_browsing_view ())
            return;
        browse_view.discard_row_popover ();
    }

    private void invalidate_popovers ()
    {
        browse_view.invalidate_popovers ();
        window.update_hamburger_menu ();
    }

    private bool is_not_browsing_view ()
    {
        string? visible_child_name = stack.get_visible_child_name ();
        return (visible_child_name == null || ((!) visible_child_name) != "browse-view");
    }

    /*\
    * * Action entries
    \*/

    public void reset (bool recursively)
    {
        reset_objects (current_directory.key_model, recursively);
    }

    public void reset_objects (GLib.ListStore? objects, bool recursively)
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

    public void enter_delay_mode ()
    {
        revealer.enter_delay_mode ();
        invalidate_popovers ();
    }

    [GtkCallback]
    private void reload ()
    {
        string? saved_selection = browse_view.get_selected_row_name ();
        current_directory.sort_key_model (sorting_options);    // TODO duplicate in set_directory
        show_browse_view (current_path, saved_selection);
    }
}

public interface BrowsableView
{
    public abstract string? get_copy_text ();
}
