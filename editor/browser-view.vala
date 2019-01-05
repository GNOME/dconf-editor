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
    [CCode (notify = false)] public bool is_pinned           { internal get; internal construct; }
    [CCode (notify = false)] public bool is_search           { internal get; internal construct; }

    [CCode (notify = false)] public uint16 context_id        { internal get; internal construct; }
    [CCode (notify = false)] public string name              { internal get; internal construct; }
    [CCode (notify = false)] public string full_name         { internal get; internal construct; }

    [CCode (notify = false)] public string casefolded_name   { internal get; private construct; }

    construct
    {
        casefolded_name = name.casefold ();
    }

    internal SimpleSettingObject.from_base_path (uint16 _context_id, string _name, string _base_path, bool _is_search = false, bool _is_pinned = false)
    {
        string _full_name = ModelUtils.recreate_full_name (_base_path, _name, ModelUtils.is_folder_context_id (_context_id));
        Object (context_id: _context_id, name: _name, full_name: _full_name, is_search: _is_search, is_pinned: _is_pinned);
    }

    internal SimpleSettingObject.from_full_name (uint16 _context_id, string _name, string _full_name, bool _is_search = false, bool _is_pinned = false)
    {
        Object (context_id: _context_id, name: _name, full_name: _full_name, is_search: _is_search, is_pinned: _is_pinned);
    }
}

private class BrowserView : BaseView, AdaptativeWidget
{
    [CCode (notify = false)] internal uint16 last_context_id { internal get; private set; default = ModelUtils.undefined_context_id; }

    [CCode (notify = false)] public BrowserContent browser_content { private get; construct; }

    protected BrowserInfoBar info_bar;
    protected SortingOptions sorting_options;

    private GLib.ListStore? key_model = null;

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);
        browser_content.set_window_size (new_size);
    }

    protected void on_case_sensitive_changed ()
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

        info_bar = new BrowserInfoBar ();
        /* Translators: text of an infobar to sort again the keys list ("refresh" only, no "reload") */
        info_bar.add_label ("soft-reload-folder", _("Sort preferences have changed. Do you want to refresh the view?"),

        /* Translators: button of an infobar to sort again the keys list ("refresh" only, no "reload") */
                                                  _("Refresh"), "bro.refresh-folder");

        /* Translators: text of an infobar to reload the keys list because of a new key (for example) */
        info_bar.add_label ("hard-reload-folder", _("This folder content has changed. Do you want to reload the view?"),

        /* Translators: button of an infobar to reload the keys list because of a new key (for example) */
                                                  _("Reload"), "browser.reload-folder");

        /* Translators: text of an infobar to reload the key properties because something has changed */
        info_bar.add_label ("hard-reload-object", _("This key’s properties have changed. Do you want to reload the view?"),

        /* Translators: button of an infobar to reload the key properties because something has changed */
                                                  _("Reload"), "browser.reload-object");
        // TODO use the same for key removing?

        info_bar.show ();
        main_grid.add (info_bar);

        main_grid.add (browser_content);
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
        { "refresh-folder", refresh_folder }
    };

    private void refresh_folder (/* SimpleAction action, Variant? path_variant */)
        requires (key_model != null)
    {
        sorting_options.sort_key_model ((!) key_model);
        hide_reload_warning ();
    }

    /*\
    * * Views
    \*/

    internal void prepare_folder_view (GLib.ListStore _key_model, bool is_ancestor)
    {
        key_model = _key_model;
        sorting_options.sort_key_model ((!) key_model);

        browser_content.prepare_folder_view ((!) key_model, is_ancestor);
        hide_reload_warning ();
    }

    internal void select_row (string selected_or_empty)
        requires (ViewType.displays_objects_list (current_view))
    {
        if (selected_or_empty == "")
            browser_content.select_first_row ();
        else
            browser_content.select_row_named (selected_or_empty, last_context_id, !is_in_in_window_mode ());
    }

    internal void prepare_object_view (string full_name, uint16 context_id, Variant properties, bool is_parent)
    {
        browser_content.prepare_object_view (full_name, context_id, properties, is_parent);
        hide_reload_warning ();
        last_context_id = context_id;
    }

    internal virtual void set_path (ViewType type, string path)
    {
        browser_content.set_path (type, path);
        invalidate_popovers ();
    }

    /*\
    * * Reload
    \*/

    protected void hide_reload_warning ()
    {
        info_bar.hide_warning ();
    }

    private void show_soft_reload_warning ()
    {
        if (!info_bar.is_shown ("hard-reload-folder") && !info_bar.is_shown ("hard-reload-object"))
            info_bar.show_warning ("soft-reload-folder");
    }

    /*\
    * * Proxy calls
    \*/

    internal void row_grab_focus ()
    {
        browser_content.row_grab_focus ();
    }

    [CCode (notify = false)] internal ViewType current_view { get { return browser_content.current_view; }}

    // popovers invalidation
    internal override void close_popovers () { browser_content.discard_row_popover (); }
    internal void invalidate_popovers ()     { browser_content.invalidate_popovers (); }

    // keyboard
    internal bool return_pressed ()   { return browser_content.return_pressed ();   }
    internal virtual bool next_match ()
    {
        if (in_window_about)
            return false;       // TODO scroll down at last line
        else
            return browser_content.next_match ();
    }
    internal virtual bool previous_match ()
    {
        if (in_window_about)
            return false;
        else
            return browser_content.previous_match ();
    }

    internal virtual bool toggle_row_popover ()     // Menu
    {
        return browser_content.toggle_row_popover ();
    }

    // current row property
    internal string get_selected_row_name () { return browser_content.get_selected_row_name (); }
    internal override bool handle_copy_text (out string copy_text)
    {
        if (base.handle_copy_text (out copy_text))
            return true;
        return browser_content.handle_copy_text (out copy_text);
    }
    internal bool handle_alt_copy_text (out string copy_text)
    {
        return browser_content.handle_alt_copy_text (out copy_text);
    }
}

/*\
* * Sorting
\*/

private class SortingOptions : Object
{
    [CCode (notify = false)] public SettingsModel model { private get; construct; }
    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    [CCode (notify = true)] internal bool case_sensitive { get; set; default = false; }

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
