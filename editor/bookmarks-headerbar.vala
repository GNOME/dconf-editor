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

private abstract class BookmarksHeaderBar : BrowserHeaderBar, AdaptativeWidget
{
    construct
    {
        install_action_entries ();

        add_bookmarks_revealer              (out bookmarks_revealer,
                                             out bookmarks_button,              center_box);
        connect_bookmarks_signals ();
        add_bookmarks_controller            (out bookmarks_controller,          ref this);

        register_bookmarks_modes ();
    }

    private string bookmark_name = "/";
    internal override void set_path (ViewType type, string path)
    {
        bookmark_name = BookmarksList.get_bookmark_name (type, path);

        bookmarks_button.set_path (type, path);
        base.set_path (type, path);
    }

    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = disable_popovers;

        base.set_window_size (new_size);

        if (disable_popovers != _disable_popovers)
            update_bookmarks_button_visibility (/* run transitions */ true);
    }

    /*\
    * * bookmarks widget
    \*/

    private Revealer            bookmarks_revealer;
    private Bookmarks           bookmarks_button;
    private BookmarksController bookmarks_controller;

    private static void add_bookmarks_revealer (out Revealer bookmarks_revealer, out Bookmarks bookmarks_button, Box center_box)
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

    private static void add_bookmarks_controller (out BookmarksController bookmarks_controller, ref unowned BookmarksHeaderBar _this)
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

    private void update_bookmarks_button_visibility (bool transition)
    {
        bookmarks_revealer.set_transition_duration (transition ? 300 : 0);

        if (!disable_popovers && no_in_window_mode)
            set_bookmarks_button_visibility (/* visibility */ true, ref bookmarks_revealer, ref bookmarks_button);
        else
        {
            bookmarks_button.active = false;
            set_bookmarks_button_visibility (/* visibility */ false, ref bookmarks_revealer, ref bookmarks_button);
        }
    }
    private static inline void set_bookmarks_button_visibility (bool visibility,
                                                            ref Revealer bookmarks_revealer,
                                                            ref Bookmarks bookmarks_button)
    {
        bookmarks_button.sensitive = visibility;
        bookmarks_revealer.set_reveal_child (visibility);
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
        BookmarksHeaderBar real_this = (BookmarksHeaderBar) _this;
        mode_changed_use_bookmarks (real_this, requested_mode_id);
        mode_changed_edit_bookmarks (real_this, requested_mode_id);
        real_this.update_bookmarks_button_visibility (/* run transitions */ false);
    }

    private static void mode_changed_use_bookmarks (BookmarksHeaderBar _this, uint8 requested_mode_id)
        requires (_this.use_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (_this.use_bookmarks_mode_id, requested_mode_id, ref _this.use_bookmarks_mode_on))
        {
            _this.update_hamburger_menu ();   // should not be useful, but <Ctrl>c-ing a bookmarks calls somehow a menu update  1/2
            return;
        }

        /* Translators: on really small windows, the bookmarks popover is replaced by an in-window view; here is the name of the view, displayed in the headerbar */
        _this.set_default_widgets_states (_("Bookmarks"),   /* title_label text or null */
                                          true,             /* show go_back_button      */
                                          false,            /* show ltr_left_separator  */
                                          false,            /* show info_button         */
                                          false,            /* show ltr_right_separator */
                                          true);            /* show quit_button_stack   */
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

    private static void mode_changed_edit_bookmarks (BookmarksHeaderBar _this, uint8 requested_mode_id)
        requires (_this.edit_bookmarks_mode_id > 0)
    {
        if (is_not_requested_mode (_this.edit_bookmarks_mode_id, requested_mode_id, ref _this.edit_bookmarks_mode_on))
        {
            _this.bookmarks_controller.hide ();
            _this.update_hamburger_menu ();   // should not be useful, but <Ctrl>c-ing a bookmarks calls somehow a menu update  2/2
            return;
        }

        _this.set_default_widgets_states (/* title_label text or null */ null,
                                          /* show go_back_button      */ true,
                                          /* show ltr_left_separator  */ true,
                                          /* show info_button         */ false,
                                          /* show ltr_right_separator */ false,
                                          /* show quit_button_stack   */ true);
        _this.bookmarks_controller.show ();
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
    * * bookmarks_button proxy calls
    \*/

    internal string [] get_bookmarks ()     { return bookmarks_button.get_bookmarks (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon) { bookmarks_button.update_bookmark_icon (bookmark, icon); }

    /*\
    * * hamburger menu
    \*/

    protected override void populate_menu (ref GLib.Menu menu)
    {
        base.populate_menu (ref menu);  // does nothing for now

        bool bookmarks_mode_on = use_bookmarks_mode_on || edit_bookmarks_mode_on;

        if (disable_popovers)
            append_bookmark_section (bookmark_name in get_bookmarks (), bookmarks_mode_on, ref menu);
    }

    private static void append_bookmark_section (bool is_in_bookmarks, bool bookmarks_mode_on, ref GLib.Menu menu)
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
            section.append (_("Show bookmarks"), "bw.show-in-window-bookmarks");
        }
        section.freeze ();
        menu.append_section (null, section);
    }

    /*\
    * * keyboard calls
    \*/

    internal virtual bool next_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.next_match ();
        return false;
    }

    internal virtual bool previous_match ()
    {
        if (bookmarks_button.active)
            return bookmarks_button.previous_match ();
        return false;
    }

    internal bool handle_copy_text (out string copy_text)
    {
        if (bookmarks_button.active)
            return bookmarks_button.handle_copy_text (out copy_text);
        return BaseWindow.no_copy_text (out copy_text);
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
        return bookmarks_button.active || base.has_popover ();
    }
}
