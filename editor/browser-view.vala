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

private class SimpleSettingObject : Object
{
    public bool is_pinned           { internal get; internal construct; }

    public bool is_config           { internal get; private construct; }
    public bool is_search           { internal get; internal construct; }

    public uint16 context_id        { internal get; internal construct; }
    public string name              { internal get; internal construct; }
    public string full_name         { internal get; internal construct; }

    public string casefolded_name   { internal get; private construct; }

    construct
    {
        is_config = is_pinned && !is_search;
        casefolded_name = name.casefold ();
    }

    internal SimpleSettingObject.from_base_path (uint16 _context_id, string _name, string _base_path, bool _is_search = false, bool _is_config_or_is_pinned_search = false)
    {
        string _full_name = ModelUtils.recreate_full_name (_base_path, _name, ModelUtils.is_folder_context_id (_context_id));
        Object (context_id: _context_id, name: _name, full_name: _full_name, is_search: _is_search, is_pinned: _is_config_or_is_pinned_search);
    }

    internal SimpleSettingObject.from_full_name (uint16 _context_id, string _name, string _full_name, bool _is_search = false, bool _is_config_or_is_pinned_search = false)
    {
        Object (context_id: _context_id, name: _name, full_name: _full_name, is_search: _is_search, is_pinned: _is_config_or_is_pinned_search);
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-view.ui")]
private class BrowserView : Stack, AdaptativeWidget
{
    internal uint16 last_context_id { get; private set; default = ModelUtils.undefined_context_id; }

    [GtkChild] private BrowserInfoBar info_bar;
    [GtkChild] private BrowserStack current_child;

    private SortingOptions sorting_options;
    private GLib.ListStore? key_model = null;

    internal bool small_keys_list_rows { set { current_child.small_keys_list_rows = value; }}

    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        current_child.set_window_size (new_size);
        bookmarks_list.set_window_size (new_size);
        modifications_list.set_window_size (new_size);
        about_list.set_window_size (new_size);
    }

    private ModificationsHandler _modifications_handler;
    internal ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set {
            _modifications_handler = value;
            current_child.modifications_handler = value;
            sorting_options = new SortingOptions (value.model);
            sorting_options.notify ["case-sensitive"].connect (on_case_sensitive_changed);
            _modifications_handler.delayed_changes_changed.connect (update_in_window_modifications);
        }
    }
    private void on_case_sensitive_changed ()
    {
        if (current_view != ViewType.FOLDER)
            return;

        if (key_model != null && !sorting_options.is_key_model_sorted ((!) key_model))
            show_soft_reload_warning ();
        // TODO reload search results too
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

        { "set-key-value",               set_key_value,                 "(sqv)"  },
        { "set-to-default",              set_to_default,                "(sq)"   },
        { "delay-erase",                 delay_erase,                   "s"      },  // see also ui.erase(s)

        { "toggle-dconf-key-switch",     toggle_dconf_key_switch,       "(sb)"   },
        { "toggle-gsettings-key-switch", toggle_gsettings_key_switch,   "(sqbb)" }
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
        uint16 context_id;
        Variant key_value_request;
        ((!) value_variant).@get ("(sqv)", out full_name, out context_id, out key_value_request);

        if (modifications_handler.get_current_delay_mode ())
            modifications_handler.add_delayed_setting (full_name, key_value_request, context_id);
        else if (!ModelUtils.is_dconf_context_id (context_id))
            modifications_handler.set_gsettings_key_value (full_name, context_id, key_value_request);
        else
            modifications_handler.set_dconf_key_value (full_name, key_value_request);
    }

    private void delay_erase (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name_or_empty = ((!) path_variant).get_string ();
        if (full_name_or_empty == "")
            return;
        modifications_handler.enter_delay_mode ();
        modifications_handler.add_delayed_setting (full_name_or_empty, null, ModelUtils.dconf_context_id);
    }

    private void set_to_default (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        string full_name;
        uint16 context_id;
        ((!) path_variant).@get ("(sq)", out full_name, out context_id);
        modifications_handler.set_to_default (full_name, context_id);
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
        uint16 context_id;
        bool key_value_request;
        bool key_default_value;
        ((!) value_variant).@get ("(sqbb)", out full_name, out context_id, out key_value_request, out key_default_value);

        if (key_value_request == key_default_value)
            modifications_handler.set_to_default (full_name, context_id);
        else
            modifications_handler.set_gsettings_key_value (full_name, context_id, new Variant.boolean (key_value_request));
    }

    /*\
    * * in-window about
    \*/

    internal bool in_window_about                   { internal get; private set; default = false; }

    [GtkChild] private AboutList about_list;

    internal void show_in_window_about ()
    {
        if (in_window_bookmarks)
            hide_in_window_bookmarks ();
        else if (in_window_modifications)
            hide_in_window_modifications ();

        about_list.reset ();
        set_visible_child (about_list);
        in_window_about = true;
    }

    internal void hide_in_window_about ()
        requires (in_window_about == true)
    {
        in_window_about = false;
        set_visible_child (current_child_grid);
    }

    /*\
    * * modifications
    \*/

    internal bool in_window_modifications           { internal get; private set; default = false; }

    [GtkChild] private ModificationsList modifications_list;

    internal void show_in_window_modifications ()
    {
        if (in_window_bookmarks)
            hide_in_window_bookmarks ();
        else if (in_window_about)
            hide_in_window_about ();

        set_visible_child (modifications_list);
        in_window_modifications = true;
    }

    internal void hide_in_window_modifications ()
        requires (in_window_modifications == true)
    {
        in_window_modifications = false;
        set_visible_child (current_child_grid);
    }

    private void update_in_window_modifications ()
    {
        GLib.ListStore modifications_liststore = modifications_handler.get_delayed_settings ();
        modifications_list.bind_model (modifications_liststore, delayed_setting_row_create);

        if (in_window_modifications && modifications_handler.mode == ModificationsMode.NONE)
            hide_in_window_modifications ();
    }
    private Widget delayed_setting_row_create (Object object)
    {
        SimpleSettingObject sso = (SimpleSettingObject) object;
        return ModificationsRevealer.create_delayed_setting_row (modifications_handler, sso.name, sso.full_name, sso.context_id);
    }

    [GtkCallback]
    private void on_modifications_selection_changed ()
    {
    }

    /*\
    * * bookmarks
    \*/

    internal bool in_window_bookmarks           { internal get; private set; default = false; }
    internal bool in_window_bookmarks_edit_mode { internal get; private set; default = false; }

    [GtkChild] private BookmarksList bookmarks_list;
    [GtkChild] private Grid          current_child_grid;

    private string [] old_bookmarks = new string [0];

    internal void show_in_window_bookmarks (string [] bookmarks)
    {
        if (in_window_modifications)
            hide_in_window_modifications ();
        else if (in_window_about)
            hide_in_window_about ();

        if (bookmarks != old_bookmarks)
        {
            Variant variant = new Variant.strv (bookmarks);
            bookmarks_list.create_bookmark_rows (variant);

            old_bookmarks = bookmarks;
        }
        set_visible_child (bookmarks_list);
        in_window_bookmarks = true;
    }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        bookmarks_list.update_bookmark_icon (bookmark, icon);
    }

    internal void hide_in_window_bookmarks ()
        requires (in_window_bookmarks == true)
    {
        if (in_window_bookmarks_edit_mode)
            leave_bookmarks_edit_mode ();
        in_window_bookmarks = false;
        set_visible_child (current_child_grid);
    }

    internal void enter_bookmarks_edit_mode ()
        requires (in_window_bookmarks == true)
    {
        bookmarks_list.enter_edit_mode ();
        in_window_bookmarks_edit_mode = true;
    }

    internal bool leave_bookmarks_edit_mode ()
        requires (in_window_bookmarks == true)
    {
        in_window_bookmarks_edit_mode = false;
        return bookmarks_list.leave_edit_mode ();
    }

    internal OverlayedList.SelectionState get_bookmarks_selection_state ()
    {
        return bookmarks_list.get_selection_state ();
    }

    internal void trash_bookmark ()
    {
        bookmarks_list.trash_bookmark ();
    }

    internal void move_top ()
    {
        bookmarks_list.move_top ();
    }

    internal void move_up ()
    {
        bookmarks_list.move_up ();
    }

    internal void move_down ()
    {
        bookmarks_list.move_down ();
    }

    internal void move_bottom ()
    {
        bookmarks_list.move_bottom ();
    }

    [GtkCallback]
    private void on_bookmarks_selection_changed ()
    {
        if (!in_window_bookmarks)
            return;
        bookmarks_selection_changed ();
    }

    internal signal void bookmarks_selection_changed ();

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);
    [GtkCallback]
    private void on_update_bookmarks_icons (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    /*\
    * * Views
    \*/

    internal void prepare_folder_view (GLib.ListStore _key_model, bool is_ancestor)
    {
        key_model = _key_model;
        sorting_options.sort_key_model ((!) key_model);

        current_child.prepare_folder_view ((!) key_model, is_ancestor);
        hide_reload_warning ();
    }

    internal void select_row (string selected)
        requires (ViewType.displays_objects_list (current_view))
    {
        current_child.select_row (selected, last_context_id);
    }

    internal void prepare_object_view (string full_name, uint16 context_id, Variant properties, bool is_parent)
    {
        current_child.prepare_object_view (full_name, context_id, properties, is_parent);
        hide_reload_warning ();
        last_context_id = context_id;
    }

    internal void set_path (ViewType type, string path)
    {
        current_child.set_path (type, path);
        modifications_handler.path_changed ();
        invalidate_popovers ();
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
        current_child.set_search_parameters (current_path, last_context_id, bookmarks, sorting_options);
    }

    internal bool check_reload (ViewType type, string path, bool show_infobar)
    {
        SettingsModel model = modifications_handler.model;

        if (type == ViewType.FOLDER || (type == ViewType.CONFIG && ModelUtils.is_folder_path (path)))
        {
            if (!current_child.check_reload_folder (model.get_children (path)))
                return false;
            if (show_infobar)
            {
                info_bar.show_warning ("hard-reload-folder");
                return false;
            }
        }
        else if (type == ViewType.OBJECT || type == ViewType.CONFIG)
        {
            if (model.key_exists (path, last_context_id))
            {
                RegistryVariantDict properties = new RegistryVariantDict.from_aqv (model.get_key_properties (path, last_context_id, (uint16) PropertyQuery.HASH));
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
        else if (type == ViewType.SEARCH)
            assert_not_reached ();
        else
            assert_not_reached ();
        return true;
    }

    /*\
    * * Proxy calls
    \*/

    internal void row_grab_focus ()
    {
        current_child.row_grab_focus ();
    }

    internal ViewType current_view { get { return current_child.current_view; }}

    // popovers invalidation and toggles hiding/revealing
    internal void discard_row_popover () { current_child.discard_row_popover (); }
    internal void invalidate_popovers () { current_child.invalidate_popovers (); }

    internal void hide_or_show_toggles (bool show) { current_child.hide_or_show_toggles (show); }

    // keyboard
    internal bool return_pressed ()   { return current_child.return_pressed ();   }
    internal bool up_pressed ()
    {
        if (in_window_bookmarks)
        {
            bookmarks_list.up_pressed ();
            return true;
        }
        else
            return current_child.up_pressed ();
    }
    internal bool down_pressed ()
    {
        if (in_window_bookmarks)
        {
            bookmarks_list.down_pressed ();
            return true;
        }
        else
            return current_child.down_pressed ();
    }

    internal bool toggle_row_popover ()     // Menu
    {
        if (in_window_bookmarks)
            return false;
        return current_child.toggle_row_popover ();
    }

    internal void toggle_boolean_key ()      { current_child.toggle_boolean_key ();      }
    internal void set_selected_to_default () { current_child.set_selected_to_default (); }

    // current row property
    internal string get_selected_row_name () { return current_child.get_selected_row_name (); }
    internal string? get_copy_text ()
    {
        if (in_window_bookmarks)
            return bookmarks_list.get_copy_text ();
        if (in_window_modifications)
            return modifications_list.get_copy_text ();
        if (in_window_about)
            return about_list.get_copy_text (); // TODO copying logo...
        else
            return current_child.get_copy_text ();
    }
    internal string? get_copy_path_text ()   { return current_child.get_copy_path_text ();    }

    // values changes
    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        current_child.gkey_value_push (full_name, context_id, key_value, is_key_default);
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
    public SettingsModel model { private get; construct; }
    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    internal bool case_sensitive { get; set; default = false; }

    construct
    {
        settings.bind ("sort-case-sensitive", this, "case-sensitive", GLib.SettingsBindFlags.GET);
    }

    internal SortingOptions (SettingsModel _model)
    {
        Object (model: _model);
    }

    internal SettingComparator get_comparator ()
    {
        return new SettingComparator (model.get_sorted_context_id (case_sensitive), case_sensitive);
    }

    internal void sort_key_model (GLib.ListStore key_model)
    {
        SettingComparator comparator = get_comparator ();

        key_model.sort ((a, b) => comparator.compare ((SimpleSettingObject) a, (SimpleSettingObject) b));
    }

    internal bool is_key_model_sorted (GLib.ListStore key_model)
    {
        SettingComparator comparator = get_comparator ();

        uint last = key_model.get_n_items () - 1;
        for (int i = 0; i < last; i++)
        {
            SimpleSettingObject item = (SimpleSettingObject) key_model.get_item (i);
            SimpleSettingObject next = (SimpleSettingObject) key_model.get_item (i + 1);
            if (comparator.compare (item, next) > 0)
                return false;
        }
        return true;
    }
}

/* Comparison functions */

private class SettingComparator : Object
{
    private uint16 [] sorted_context_id;
    private bool case_sensitive;

    internal SettingComparator (uint16 [] _sorted_context_id, bool _case_sensitive)
    {
        sorted_context_id = _sorted_context_id;
        case_sensitive = _case_sensitive;
    }

    internal int compare (SimpleSettingObject a, SimpleSettingObject b)
    {
        if (a.is_pinned)
            return -1;
        if (b.is_pinned)
            return 1;

        if (a.context_id != b.context_id)
        {
            int sort_hint = 0;
            if (sort_directories_first (a, b, ref sort_hint))
                return sort_hint;
            if (sort_dconf_keys_second (a, b, ref sort_hint))
                return sort_hint;
            return sort_by_schema_thirdly (a, b, sorted_context_id);
        }
        else
        {
            if (case_sensitive)
                return strcmp (a.name, b.name);
            else
                return (a.casefolded_name).collate (b.casefolded_name);
        }
    }

    private static bool sort_directories_first (SimpleSettingObject a, SimpleSettingObject b, ref int sort_hint)
    {
        if (ModelUtils.is_folder_context_id (a.context_id)) // !ModelUtils.is_folder_context_id (b.context_id)
        {
            sort_hint = -1;
            return true;
        }
        if (ModelUtils.is_folder_context_id (b.context_id)) // !ModelUtils.is_folder_context_id (a.context_id)
        {
            sort_hint = 1;
            return true;
        }
        return false;
    }

    private static bool sort_dconf_keys_second (SimpleSettingObject a, SimpleSettingObject b, ref int sort_hint)
    {
        if (ModelUtils.is_dconf_context_id (a.context_id))  // && !ModelUtils.is_dconf_context_id (b.context_id)
        {
            sort_hint = -1;
            return true;
        }
        if (ModelUtils.is_dconf_context_id (b.context_id))  // && !ModelUtils.is_dconf_context_id (a.context_id)
        {
            sort_hint = 1;
            return true;
        }
        return false;
    }

    private static int sort_by_schema_thirdly (SimpleSettingObject a, SimpleSettingObject b, uint16 [] sorted_context_id)
    {
        uint16 a_place = sorted_context_id [a.context_id - ModelUtils.special_context_id_number];
        uint16 b_place = sorted_context_id [b.context_id - ModelUtils.special_context_id_number];
        if (a_place == b_place) // FIXME assert_not_reached() should be good, but crash happens if opening app on a key from a folder with
            return 0;           // multiple schemas installed (e.g. '/ca/desrt/dconf-editor/bookmarks'), and immediately opening search
        return a_place < b_place ? -1 : 1;
    }
}
