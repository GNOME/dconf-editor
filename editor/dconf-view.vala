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

private class DConfView : BookmarksView, AdaptativeWidget
{
    private BrowserStack dconf_content;

    construct
    {
        install_action_entries ();
    }

    internal DConfView (ModificationsHandler modifications_handler)
    {
        BrowserStack _dconf_content = new BrowserStack (modifications_handler);
        _dconf_content.show ();
        Object (browser_content: (BrowserContent) _dconf_content, modifications_handler: modifications_handler);
        dconf_content = _dconf_content;
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);

        if (modifications_list_created)
            modifications_list.set_window_size (new_size);
    }

    private ModificationsHandler _modifications_handler;
    [CCode (notify = false)] public ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        internal construct
        {
            _modifications_handler = value;
            sorting_options = new SortingOptions (value.model);
            sorting_options.notify ["case-sensitive"].connect (on_case_sensitive_changed);
            _modifications_handler.delayed_changes_changed.connect (update_in_window_modifications);
        }
    }

    internal override bool is_in_in_window_mode ()
    {
        return (in_window_modifications || base.is_in_in_window_mode ());
    }

    internal override void show_default_view ()
    {
        if (in_window_modifications)
        {
            in_window_modifications = false;
            set_visible_child_name ("main-view");
        }
        else
            base.show_default_view ();
    }

    /*\
    * * Action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("view", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "set-key-value",               set_key_value,                 "(sqv)"  },
        { "set-to-default",              set_to_default,                "(sq)"   },
        { "delay-erase",                 delay_erase,                   "s"      },  // see also ui.erase(s)

        { "toggle-dconf-key-switch",     toggle_dconf_key_switch,       "(sb)"   },
        { "toggle-gsettings-key-switch", toggle_gsettings_key_switch,   "(sqbb)" }
    };

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
    * * modifications
    \*/

    [CCode (notify = false)] internal bool in_window_modifications           { internal get; private set; default = false; }

    private bool modifications_list_created = false;
    private ModificationsList modifications_list;

    private void create_modifications_list ()
    {
        modifications_list = new ModificationsList (/* needs shadows   */ false,
                                                    /* big placeholder */ true);
        modifications_list.set_window_size (saved_window_size);
        // modifications_list.selection_changed.connect (() => ...);
        modifications_list.show ();
        add (modifications_list);
        modifications_list_created = true;
    }

    internal void show_modifications_view ()
        requires (modifications_list_created == true)
    {
        if (in_window_bookmarks || in_window_about)
            show_default_view ();

        modifications_list.reset ();

        set_visible_child (modifications_list);
        in_window_modifications = true;
    }

    private void update_in_window_modifications ()
    {
        if (!modifications_list_created)
            create_modifications_list ();

        GLib.ListStore modifications_liststore = modifications_handler.get_delayed_settings ();
        modifications_list.bind_model (modifications_liststore, delayed_setting_row_create);

        if (in_window_modifications && modifications_handler.mode == ModificationsMode.NONE)
            show_default_view ();
    }

    private Widget delayed_setting_row_create (Object object)
    {
        SimpleSettingObject sso = (SimpleSettingObject) object;
        return ModificationsRevealer.create_delayed_setting_row (modifications_handler, sso.name, sso.full_name, sso.context_id);
    }

    /*\
    * * views
    \*/

    internal override void set_path (ViewType type, string path)
    {
        dconf_content.set_path (type, path);
        modifications_handler.path_changed ();
        invalidate_popovers ();
    }

    /*\
    * * reload
    \*/

    internal void set_search_parameters (bool local_search, string current_path, string [] bookmarks)
    {
        hide_reload_warning ();
        dconf_content.set_search_parameters (local_search, current_path, last_context_id, bookmarks, sorting_options);
    }

    internal bool check_reload (ViewType type, string path, bool show_infobar)
    {
        SettingsModel model = modifications_handler.model;

        if (type == ViewType.FOLDER || (type == ViewType.CONFIG && ModelUtils.is_folder_path (path)))
        {
            if (!dconf_content.check_reload_folder (model.get_children (path)))
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
                if (!dconf_content.check_reload_object (properties_hash))
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

    internal void hide_or_show_toggles (bool show) { dconf_content.hide_or_show_toggles (show); }

    // keyboard
    internal override bool next_match ()
    {
        if (in_window_modifications)
            return modifications_list.next_match ();
        return base.next_match ();
    }

    internal override bool previous_match ()
    {
        if (in_window_modifications)
            return modifications_list.previous_match ();
        return base.previous_match ();
    }

    internal void toggle_boolean_key ()      { dconf_content.toggle_boolean_key ();      }
    internal void set_selected_to_default () { dconf_content.set_selected_to_default (); }

    // current row property
    internal override bool handle_copy_text (out string copy_text)
    {
        if (in_window_modifications)
            return modifications_list.handle_copy_text (out copy_text);
        return base.handle_copy_text (out copy_text);
    }

    // values changes
    internal void gkey_value_push (string full_name, uint16 context_id, Variant key_value, bool is_key_default)
    {
        dconf_content.gkey_value_push (full_name, context_id, key_value, is_key_default);
    }
    internal void dkey_value_push (string full_name, Variant? key_value_or_null)
    {
        dconf_content.dkey_value_push (full_name, key_value_or_null);
    }
}
