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

private class DConfHeaderBar : BookmarksHeaderBar, AdaptativeWidget
{
    private bool _delay_mode = false;
    [CCode (notify = false)] internal bool delay_mode
    {
        private  get { return _delay_mode; }
        internal set
        {
            if (_delay_mode == value)
                return;
            _delay_mode = value;
            update_modifications_button ();
            update_hamburger_menu ();
        }
    }

    construct
    {
        // delay mode quit_button_stack buttons
        add_show_modifications_button ();
        add_modification_actions_button ();

        // modifications view three-dots button
        add_modifications_actions_button    (out modifications_actions_button, ref this);
        construct_changes_pending_menu      (out changes_pending_menu);
        construct_quit_delayed_mode_menu    (out quit_delayed_mode_menu);

        register_modifications_mode ();
    }

    internal DConfHeaderBar ()
    {
        /* Translators: usual menu entry of the hamburger menu */
        Object (about_action_label:     _("About Dconf Editor"),
                has_help:               false,
                has_keyboard_shortcuts: true);
    }

    private bool is_folder_view = true;
    internal override void set_path (ViewType type, string path)
    {
        is_folder_view = type == ViewType.FOLDER;

        base.set_path (type, path);
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);

        update_modifications_button ();
    }

    /*\
    * * modifications buttons and actions
    \*/

    private MenuButton  modifications_actions_button;
    private GLib.Menu   changes_pending_menu;           // for selecting as menu only
    private GLib.Menu   quit_delayed_mode_menu;         // for selecting as menu only

    private inline void add_show_modifications_button ()
    {
        Button show_modifications_button;
        create_show_modifications_button (out show_modifications_button);
        add_named_widget_to_quit_button_stack (show_modifications_button, "show-modifications");
    }
    private static inline void create_show_modifications_button (out Button show_modifications_button)
    {
        show_modifications_button = new Button.from_icon_name ("document-open-recent-symbolic");
        show_modifications_button.valign = Align.CENTER;
        show_modifications_button.action_name = "ui.show-in-window-modifications";
        show_modifications_button.get_style_context ().add_class ("titlebutton");

        show_modifications_button.visible = true;
    }

    private inline void add_modification_actions_button ()
    {
        MenuButton modification_actions_button;
        create_modification_actions_button (out modification_actions_button);
        add_named_widget_to_quit_button_stack (modification_actions_button, "modification-actions");
    }
    private static inline void create_modification_actions_button (out MenuButton modification_actions_button)
    {
        modification_actions_button = new MenuButton ();
        Image view_more_image = new Image.from_icon_name ("document-open-recent-symbolic", IconSize.BUTTON);
        modification_actions_button.set_image (view_more_image);
        modification_actions_button.valign = Align.CENTER;
        modification_actions_button.get_style_context ().add_class ("titlebutton");

        GLib.Menu change_pending_menu = new GLib.Menu ();
        /* Translators: when a change is requested, on a small window, entry of the menu of the "delayed settings button" that appears in place of the close button */
        change_pending_menu.append (_("Apply"), "ui.apply-delayed-settings");

        /* Translators: when a change is requested, on a small window, entry of the menu of the "delayed settings button" that appears in place of the close button */
        change_pending_menu.append (_("Dismiss"), "ui.dismiss-delayed-settings");
        change_pending_menu.freeze ();

        modification_actions_button.set_menu_model (change_pending_menu);

        modification_actions_button.visible = true;
    }

    private static void add_modifications_actions_button (out MenuButton modifications_actions_button, ref unowned DConfHeaderBar _this)
    {
        modifications_actions_button = new MenuButton ();
        Image view_more_image = new Image.from_icon_name ("view-more-symbolic", IconSize.BUTTON);
        modifications_actions_button.set_image (view_more_image);
        modifications_actions_button.valign = Align.CENTER;
        modifications_actions_button.get_style_context ().add_class ("image-button");

        modifications_actions_button.visible = false;
        _this.pack_end (modifications_actions_button);
    }

    private static void construct_changes_pending_menu (out GLib.Menu changes_pending_menu)
    {
        changes_pending_menu = new GLib.Menu ();
        /* Translators: when in delayed mode, on a small window, entry of the "three-dots menu" that appears when showing the pending changes list (if there is pending changes) */
        changes_pending_menu.append (_("Apply all"), "ui.apply-delayed-settings");

        /* Translators: when in delayed mode, on a small window, entry of the "three-dots menu" that appears when showing the pending changes list (if there is pending changes) */
        changes_pending_menu.append (_("Dismiss all"), "ui.dismiss-delayed-settings");
        changes_pending_menu.freeze ();
    }

    private static void construct_quit_delayed_mode_menu (out GLib.Menu quit_delayed_mode_menu)
    {
        quit_delayed_mode_menu = new GLib.Menu ();
        /* Translators: when in delayed mode, on a small window, entry of the "three-dots menu" that appears when showing the pending changes list (if there is no pending changes) */
        quit_delayed_mode_menu.append (_("Quit mode"), "ui.dismiss-delayed-settings");
        quit_delayed_mode_menu.freeze ();
    }

    private bool has_pending_changes = false;
    internal void set_has_pending_changes (bool new_value, bool mode_is_temporary)
    {
        has_pending_changes = new_value;
        if (new_value)
        {
            modifications_actions_button.set_menu_model (changes_pending_menu);
            if (mode_is_temporary)
                set_quit_button_stack_child ("modification-actions");
        }
        else
        {
            modifications_actions_button.set_menu_model (quit_delayed_mode_menu);
            if (mode_is_temporary)
                set_quit_button_stack_child ("quit-button");
        }
    }

    /*\
    * * hamburger menu
    \*/

    protected override void toggle_view_menu ()
    {
        if (modifications_actions_button.visible)
            modifications_actions_button.active = !modifications_actions_button.active;
        else
            base.toggle_view_menu ();
    }

    protected override void populate_menu (ref GLib.Menu menu)
    {
        base.populate_menu (ref menu);

        append_or_not_delay_mode_section (delay_mode, is_folder_view, ref menu);
    }

    private static void append_or_not_delay_mode_section (bool delay_mode, bool is_folder_view, ref GLib.Menu menu)
    {
        if (delay_mode && !is_folder_view)
            return;

        GLib.Menu section = new GLib.Menu ();
        if (!delay_mode)
            /* Translators: hamburger menu entry, to enter in a special mode called "delay mode" where changes are not applied until validation */
            section.append (_("Enter delay mode"), "ui.enter-delay-mode");
        if (is_folder_view)
        {
            /* Translators: hamburger menu entry that appears when browsing a folder path, to set to their default value all currently visible keys, not including keys in subfolders */
            section.append (_("Reset visible keys"), "ui.reset-current-non-recursively");

            /* Translators: hamburger menu entry that appears when browsing a folder path, to set to their default value all currently visible keys, and all keys in subfolders */
            section.append (_("Reset view recursively"), "ui.reset-current-recursively");
        }
        section.freeze ();
        menu.append_section (null, section);
    }

    /*\
    * * in-window modifications
    \*/

    private uint8 modifications_mode_id = 0;
    private bool modifications_mode_on = false;

    internal void show_modifications_view ()
        requires (modifications_mode_id > 0)
    {
        change_mode (modifications_mode_id);
    }

    private void register_modifications_mode ()
    {
        modifications_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_modifications);
    }

    private static void mode_changed_modifications (BaseHeaderBar _this, uint8 requested_mode_id)
    {
        DConfHeaderBar real_this = (DConfHeaderBar) _this;
        if (is_not_requested_mode (real_this.modifications_mode_id, requested_mode_id, ref real_this.modifications_mode_on))
        {
            real_this.modifications_actions_button.hide ();
            // if (path_widget.search_mode_enabled)
            //    path_widget.entry_grab_focus_without_selecting ();
            return;
        }

        /* Translators: on really small windows, the bottom bar that appears in "delay mode" or when there're pending changes is replaced by an in-window view; here is the name of the view, displayed in the headerbar */
        real_this.set_default_widgets_states (_("Pending"), /* title_label text or null */
                                              true,         /* show go_back_button      */
                                              false,        /* show ltr_left_separator  */
                                              false,        /* show info_button         */
                                              false,        /* show ltr_right_separator */
                                              false);       /* show quit_button_stack   */
        real_this.modifications_actions_button.show ();
    }

    private void update_modifications_button ()
    {
        if (!disable_action_bar)
            return;

        if (modifications_mode_on)
        {
            set_quit_button_stack_visibility (false);
        }
        else
        {
            set_quit_button_stack_visibility (true);
            if (delay_mode)
                set_quit_button_stack_child ("show-modifications");
            else if (has_pending_changes)
                set_quit_button_stack_child ("modification-actions");
            else
                set_quit_button_stack_child ("quit-button");
        }
    }
}
