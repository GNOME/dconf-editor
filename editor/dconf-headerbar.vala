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

private class DConfHeaderBar : BrowserHeaderBar, AdaptativeWidget
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
        install_action_entries ();

        add_bookmarks_revealer              (out bookmarks_revealer,
                                             out bookmarks_button,              ref center_box);
        connect_bookmarks_signals ();
        add_bookmarks_controller            (out bookmarks_controller,          ref this);

        add_show_modifications_button       (out show_modifications_button,     ref quit_button_stack);
        add_modifications_actions_button    (out modifications_actions_button,  ref this);
        construct_changes_pending_menu      (out changes_pending_menu);
        construct_quit_delayed_mode_menu    (out quit_delayed_mode_menu);

        register_bookmarks_modes ();
        register_modifications_mode ();
    }

    internal static DConfHeaderBar (NightLightMonitor _night_light_monitor)
    {
        /* Translators: usual menu entry of the hamburger menu */
        Object (night_light_monitor: _night_light_monitor, about_action_label: _("About Dconf Editor"));
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = disable_popovers;

        base.set_window_size (new_size);

        if (disable_popovers != _disable_popovers)
            update_bookmarks_button_visibility ();
        update_modifications_button ();
    }

    private void update_bookmarks_button_visibility ()
    {
        if (disable_popovers || modifications_mode_on)
            hide_bookmarks_button (in_window_properties, ref bookmarks_revealer, ref bookmarks_button);
        else
            show_bookmarks_button (ref bookmarks_revealer, ref bookmarks_button);
    }
    private static inline void hide_bookmarks_button (bool no_transition, ref Revealer bookmarks_revealer, ref Bookmarks bookmarks_button)
    {
        bookmarks_button.active = false;

        bookmarks_button.sensitive = false;
        if (no_transition)
            bookmarks_revealer.set_transition_duration (0);
        bookmarks_revealer.set_reveal_child (false);
        if (no_transition)
            bookmarks_revealer.set_transition_duration (300);
    }
    private static inline void show_bookmarks_button (ref Revealer bookmarks_revealer, ref Bookmarks bookmarks_button)
    {
        bookmarks_button.sensitive = true;
        bookmarks_revealer.set_reveal_child (true);
    }

    /*\
    * * bookmarks widget
    \*/

    private Revealer            bookmarks_revealer;
    private Bookmarks           bookmarks_button;
    private BookmarksController bookmarks_controller;

    private static void add_bookmarks_revealer (out Revealer bookmarks_revealer, out Bookmarks bookmarks_button, ref Box center_box)
    {
        bookmarks_revealer = new Revealer ();
        bookmarks_revealer.transition_type = RevealerTransitionType.SLIDE_LEFT;
        bookmarks_revealer.reveal_child = true;
        bookmarks_revealer.get_style_context ().add_class ("headerbar-revealer");

        bookmarks_button = new Bookmarks ("/ca/desrt/dconf-editor/");
        bookmarks_button.valign = Align.CENTER;
        bookmarks_button.focus_on_click = false;
        bookmarks_button.get_style_context ().add_class ("image-button");   // TODO check https://bugzilla.gnome.org/show_bug.cgi?id=756731

        bookmarks_button.visible = true;
        bookmarks_revealer.add (bookmarks_button);
        bookmarks_revealer.visible = true;
        center_box.pack_end (bookmarks_revealer);
    }

    private static void add_bookmarks_controller (out BookmarksController bookmarks_controller, ref unowned DConfHeaderBar _this)
    {
        bookmarks_controller = new BookmarksController ("bmk", false);
        bookmarks_controller.hexpand = true;

        bookmarks_controller.visible = false;
        _this.pack_start (bookmarks_controller);
    }

    internal signal void update_bookmarks_icons (Variant bookmarks_variant);

    private inline void connect_bookmarks_signals ()
    {
        bookmarks_button.update_bookmarks_icons.connect (update_bookmarks_icons_cb);
    }

    private void update_bookmarks_icons_cb (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    /*\
    * * use-bookmarks mode
    \*/

    private uint8 use_bookmarks_mode_id = 0;
    private bool use_bookmarks_mode_on = false;

    internal void show_use_bookmarks_view ()
        requires (use_bookmarks_mode_id > 0)
    {
        change_mode (use_bookmarks_mode_id);
    }

    private void register_bookmarks_modes ()
    {
        use_bookmarks_mode_id = register_new_mode ();
        edit_bookmarks_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_bookmarks);
    }

    private static void mode_changed_bookmarks (BaseHeaderBar _this, uint8 requested_mode_id)
    {
        DConfHeaderBar real_this = (DConfHeaderBar) _this;
        mode_changed_use_bookmarks (real_this, requested_mode_id);
        mode_changed_edit_bookmarks (real_this, requested_mode_id);
    }

    private static void mode_changed_use_bookmarks (DConfHeaderBar _this, uint8 requested_mode_id)
        requires (_this.use_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (_this.use_bookmarks_mode_id, requested_mode_id, ref _this.use_bookmarks_mode_on))
        {
            _this.update_hamburger_menu ();   // should not be useful, but <Ctrl>c-ing a bookmarks calls somehow a menu update  1/2
            return;
        }

        _this.set_default_widgets_states (/* show go_back_button      */ true,
                                          /* show ltr_left_separator  */ false,
                                          /* title_label text or null */
                                          /* Translators: on really small windows, the bookmarks popover is replaced by an in-window view; here is the name of the view, displayed in the headerbar */
                                                                         _("Bookmarks"),
                                          /* show info_button         */ false,
                                          /* show ltr_right_separator */ false,
                                          /* show quit_button_stack   */ true);
    }

    /*\
    * * edit-bookmarks mode
    \*/

    private uint8 edit_bookmarks_mode_id = 0;
    private bool edit_bookmarks_mode_on = false;

    internal void show_edit_bookmarks_view ()
        requires (edit_bookmarks_mode_id > 0)
    {
        change_mode (edit_bookmarks_mode_id);
    }

    private static void mode_changed_edit_bookmarks (DConfHeaderBar _this, uint8 requested_mode_id)
        requires (_this.edit_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (_this.edit_bookmarks_mode_id, requested_mode_id, ref _this.edit_bookmarks_mode_on))
        {
            _this.bookmarks_controller.hide ();
            _this.update_hamburger_menu ();   // should not be useful, but <Ctrl>c-ing a bookmarks calls somehow a menu update  2/2
            return;
        }

        _this.set_default_widgets_states (/* show go_back_button      */ true,
                                          /* show ltr_left_separator  */ true,
                                          /* title_label text or null */ null,
                                          /* show info_button         */ false,
                                          /* show ltr_right_separator */ false,
                                          /* show quit_button_stack   */ true);
        _this.bookmarks_controller.show ();
    }

    /*\
    * * modifications buttons and actions
    \*/

    private Button      show_modifications_button;
    private MenuButton  modifications_actions_button;
    private GLib.Menu   changes_pending_menu;
    private GLib.Menu   quit_delayed_mode_menu;

    private static void add_show_modifications_button (out Button show_modifications_button, ref Stack quit_button_stack)
    {
        show_modifications_button = new Button.from_icon_name ("document-open-recent-symbolic");
        show_modifications_button.valign = Align.CENTER;
        show_modifications_button.action_name = "ui.show-in-window-modifications";
        show_modifications_button.get_style_context ().add_class ("titlebutton");

        show_modifications_button.visible = true;
        quit_button_stack.add (show_modifications_button);
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

    internal void set_apply_modifications_button_sensitive (bool new_value)
    {
        if (new_value)
            modifications_actions_button.set_menu_model (changes_pending_menu);
        else
            modifications_actions_button.set_menu_model (quit_delayed_mode_menu);
    }

    /*\
    * * bookmarks_button proxy calls
    \*/

    internal string [] get_bookmarks ()     { return bookmarks_button.get_bookmarks (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon) { bookmarks_button.update_bookmark_icon (bookmark, icon); }

    /*\
    * * should move back
    \*/

    private ViewType current_type = ViewType.FOLDER;
    private string current_path = "/";

    internal override void set_path (ViewType type, string path)
    {
        current_type = type;
        current_path = path;

        bookmarks_button.set_path (type, path);
        base.set_path (type, path);
    }

    internal void click_bookmarks_button ()
    {
        hide_hamburger_menu ();
        if (bookmarks_button.sensitive)
            bookmarks_button.clicked ();
    }

    internal void bookmark_current_path ()
    {
        hide_hamburger_menu ();
        bookmarks_button.bookmark_current_path ();
        update_hamburger_menu ();
    }

    internal void unbookmark_current_path ()
    {
        hide_hamburger_menu ();
        bookmarks_button.unbookmark_current_path ();
        update_hamburger_menu ();
    }

    /*\
    * * hamburger menu
    \*/

    internal override void toggle_hamburger_menu ()
    {
        if (modifications_actions_button.visible)
            modifications_actions_button.active = !modifications_actions_button.active;
        else
            base.toggle_hamburger_menu ();
    }

    protected override void populate_menu (ref GLib.Menu menu)
    {
        bool bookmarks_mode_on = use_bookmarks_mode_on || edit_bookmarks_mode_on;

        if (disable_popovers)
            append_bookmark_section (current_type, current_path, BookmarksList.get_bookmark_name (current_path, current_type) in get_bookmarks (), bookmarks_mode_on, ref menu);

        if (!bookmarks_mode_on)
            append_or_not_delay_mode_section (delay_mode, current_type == ViewType.FOLDER, current_path, ref menu);
    }

    private static void append_bookmark_section (ViewType current_type, string current_path, bool is_in_bookmarks, bool bookmarks_mode_on, ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();

        if (bookmarks_mode_on)
            /* Translators: hamburger menu entry on small windows (not used in current design) */
            section.append (_("Hide bookmarks"), "ui.empty");
        else
        {
            if (is_in_bookmarks)
                /* Translators: hamburger menu entry on small windows, to unbookmark the currently browsed path */
                section.append (_("Unbookmark"), "headerbar.unbookmark-current");
            else
                /* Translators: hamburger menu entry on small windows, to bookmark the currently browsed path */
                section.append (_("Bookmark"), "headerbar.bookmark-current");

            /* Translators: hamburger menu entry on small windows, to show the bookmarks list */
            section.append (_("Show bookmarks"), "ui.show-in-window-bookmarks");
        }
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void append_or_not_delay_mode_section (bool delay_mode, bool is_folder_view, string current_path, ref GLib.Menu menu)
    {
        if (delay_mode && !is_folder_view)
            return;

        GLib.Menu section = new GLib.Menu ();
        if (!delay_mode)
            /* Translators: hamburger menu entry, to enter in a special mode called "delay mode" where changes are not applied until validation */
            section.append (_("Enter delay mode"), "ui.enter-delay-mode");
        if (is_folder_view)
        {
            Variant variant = new Variant.string (current_path);

            /* Translators: hamburger menu entry that appears when browsing a folder path, to set to their default value all currently visible keys, not including keys in subfolders */
            section.append (_("Reset visible keys"), "ui.reset-visible(" + variant.print (false) + ")");

            /* Translators: hamburger menu entry that appears when browsing a folder path, to set to their default value all currently visible keys, and all keys in subfolders */
            section.append (_("Reset view recursively"), "ui.reset-recursive(" + variant.print (false) + ")");
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
            real_this.bookmarks_revealer.show ();
            real_this.update_bookmarks_button_visibility ();
            // if (path_widget.search_mode_enabled)
            //    path_widget.entry_grab_focus_without_selecting ();
            return;
        }

        real_this.set_default_widgets_states (/* show go_back_button      */ true,
                                              /* show ltr_left_separator  */ false,
                                              /* title_label text or null */
                                            /* Translators: on really small windows, the bottom bar that appears in "delay mode" or when there're pending changes is replaced by an in-window view; here is the name of the view, displayed in the headerbar */
                                                                             _("Pending"),
                                              /* show info_button         */ false,
                                              /* show ltr_right_separator */ false,
                                              /* show quit_button_stack   */ false);
        if (real_this.disable_action_bar && !real_this.disable_popovers)
        {
            real_this.bookmarks_button.sensitive = false;
            real_this.bookmarks_revealer.hide ();
        }
        real_this.modifications_actions_button.show ();
    }

    private void update_modifications_button ()
    {
        if (!disable_action_bar)
            return;

        if (modifications_mode_on)
        {
            quit_button_stack.hide ();
        }
        else
        {
            quit_button_stack.show ();
            if (delay_mode)
                quit_button_stack.set_visible_child (show_modifications_button);
            else
                quit_button_stack.set_visible_child_name ("quit-button");
        }
    }

    /*\
    * * action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("headerbar", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        {   "bookmark-current",   bookmark_current },
        { "unbookmark-current", unbookmark_current }
    };

    private void bookmark_current (/* SimpleAction action, Variant? variant */)
    {
        bookmark_current_path ();
    }

    private void unbookmark_current (/* SimpleAction action, Variant? variant */)
    {
        unbookmark_current_path ();
    }

    /*\
    * * keyboard calls
    \*/

    internal override bool next_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.next_match ();
        return base.next_match ();      // false
    }

    internal override bool previous_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.previous_match ();
        return base.previous_match ();  // false
    }

    internal bool handle_copy_text (out string copy_text)
    {
        if (bookmarks_button.active)
            return bookmarks_button.handle_copy_text (out copy_text);
        return BaseWindow.no_copy_text (out copy_text);
    }

    /*\
    * * popovers methods
    \*/

    internal override void close_popovers ()
    {
        base.close_popovers ();
        if (bookmarks_button.active)
            bookmarks_button.active = false;
    }

    internal override bool has_popover ()
    {
        if (base.has_popover ())
            return true;
        if (bookmarks_button.active)
            return true;
        return false;
    }
}
