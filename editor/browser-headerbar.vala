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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-headerbar.ui")]
private class BrowserHeaderBar : HeaderBar, AdaptativeWidget
{
    [GtkChild] private MenuButton   info_button;
    [GtkChild] private PathWidget   path_widget;

    [GtkChild] private Revealer     bookmarks_revealer;
    [GtkChild] private Bookmarks    bookmarks_button;

    [GtkChild] private Stack        title_stack;

    private ViewType current_type = ViewType.FOLDER;
    private string current_path = "/";

    internal signal void search_changed ();
    internal signal void search_stopped ();
    internal signal void update_bookmarks_icons (Variant bookmarks_variant);

    private bool disable_popovers = false;
    private bool disable_action_bar = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (_disable_popovers)
            {
                bookmarks_button.active = false;

                bookmarks_button.sensitive = false;
                bookmarks_revealer.set_reveal_child (false);
            }
            else
            {
                bookmarks_button.sensitive = true;
                if (!in_window_modifications)
                    bookmarks_button.show ();
                bookmarks_revealer.set_reveal_child (true);
            }
        }

        disable_action_bar = _disable_popovers
                          || AdaptativeWidget.WindowSize.is_extra_flat (new_size);

        update_hamburger_menu (delay_mode);
        update_modifications_button ();

        path_widget.set_window_size (new_size);
    }

    internal bool search_mode_enabled   { get { return path_widget.search_mode_enabled; }}
    internal bool entry_has_focus       { get { return path_widget.entry_has_focus; }}
    internal string text                { get { return path_widget.text; }}

    internal string get_complete_path ()    { return path_widget.get_complete_path (); }
    internal void toggle_pathbar_menu ()    { path_widget.toggle_pathbar_menu (); }
    internal string [] get_bookmarks ()     { return bookmarks_button.get_bookmarks (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon) { bookmarks_button.update_bookmark_icon (bookmark, icon); }
    internal void update_ghosts (string fallback_path)                      { path_widget.update_ghosts (fallback_path); }
    internal void prepare_search (PathEntry.SearchMode mode, string? search){ path_widget.prepare_search (mode, search); }
    internal string get_selected_child (string fallback_path)               { return path_widget.get_selected_child (fallback_path); }

    internal void entry_grab_focus (bool select)
    {
        if (select)
            path_widget.entry_grab_focus ();
        else
            path_widget.entry_grab_focus_without_selecting ();
    }

    internal void set_path (ViewType type, string path)
    {
        current_type = type;
        current_path = path;

        path_widget.set_path (type, path);
        bookmarks_button.set_path (type, path);
    }

    internal bool has_popover ()
    {
        if (bookmarks_button.active)
            return true;
        if (info_button.active)
            return true;
        if (path_widget.has_popover ())
            return true;
        return false;
    }

    internal bool handle_event (Gdk.EventKey event)
    {
        return path_widget.handle_event (event);
    }

    internal void next_match ()
    {
        if (info_button.active)
            return;
        if (bookmarks_button.active)
            bookmarks_button.next_match ();
    }

    internal void previous_match ()
    {
        if (info_button.active)
            return;
        if (bookmarks_button.active)
            bookmarks_button.previous_match ();
    }

    internal void close_popovers ()
    {
        hide_hamburger_menu ();
        if (bookmarks_button.active)
            bookmarks_button.active = false;
        path_widget.close_popovers ();
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

    construct
    {
        install_action_entries ();
        construct_modifications_actions_button_menu ();
    }

    /*\
    * * in-window about
    \*/

    [GtkChild] private Label    about_label;
    [GtkChild] private Button   hide_about_button;

    bool in_window_about = false;

    internal void show_in_window_about ()
    {
        if (in_window_bookmarks)
            hide_in_window_bookmarks ();
        else if (in_window_modifications)
            hide_in_window_modifications ();

        in_window_about = true;
        update_modifications_button ();
        info_button.hide ();
        hide_about_button.show ();
        bookmarks_stack.hexpand = false;    // hack 1/7
        title_stack.set_visible_child (about_label);
    }

    internal void hide_in_window_about ()
        requires (in_window_about == true)
    {
        hide_about_button.hide ();
        bookmarks_stack.hexpand = false;    // hack 2/7
        title_stack.set_visible_child (path_widget);
        in_window_about = false;
        if (disable_action_bar)
            modifications_separator.show ();
        info_button.show ();
    }

    /*\
    * * in-window modifications
    \*/

    [GtkChild] private Label        modifications_label;
    [GtkChild] private Separator    modifications_separator;
    [GtkChild] private Button       show_modifications_button;
    [GtkChild] private Button       hide_modifications_button;
    [GtkChild] private Button       quit_button;
    [GtkChild] private MenuButton   modifications_actions_button;

    bool in_window_modifications = false;

    GLib.Menu changes_pending_menu;
    GLib.Menu quit_delayed_mode_menu;
    private void construct_modifications_actions_button_menu ()
    {
        changes_pending_menu = new GLib.Menu ();
        changes_pending_menu.append (_("Apply all"), "ui.apply-delayed-settings");
        changes_pending_menu.append (_("Dismiss all"), "ui.dismiss-delayed-settings");
        changes_pending_menu.freeze ();

        quit_delayed_mode_menu = new GLib.Menu ();
        quit_delayed_mode_menu.append (_("Quit mode"), "ui.dismiss-delayed-settings");
        quit_delayed_mode_menu.freeze ();

        modifications_actions_button.set_menu_model (changes_pending_menu);
    }

    private void update_modifications_button ()
    {
        if (disable_action_bar)
        {
            set_show_close_button (false);
            if (in_window_modifications)
            {
                quit_button.hide ();
                show_modifications_button.hide ();
                modifications_separator.hide ();
            }
            else
            {
                if (delay_mode)
                {
                    quit_button.hide ();
                    show_modifications_button.show ();
                }
                else
                {
                    show_modifications_button.hide ();
                    quit_button.show ();
                }

                if (in_window_bookmarks || in_window_about)
                    modifications_separator.hide ();
                else
                    modifications_separator.show ();
            }
        }
        else
        {
            if (in_window_modifications)
                hide_in_window_modifications ();
            quit_button.hide ();
            show_modifications_button.hide ();
            modifications_separator.hide ();
            set_show_close_button (true);
        }
    }

    internal void show_in_window_modifications ()
    {
        if (in_window_bookmarks)
            hide_in_window_bookmarks ();
        else if (in_window_about)
            hide_in_window_about ();

        in_window_modifications = true;
        info_button.hide ();
        modifications_separator.hide ();
        show_modifications_button.hide ();
        if (disable_action_bar && !disable_popovers)
            bookmarks_button.hide ();
        modifications_actions_button.show ();
        hide_modifications_button.show ();
        bookmarks_stack.hexpand = false;    // hack 3/7
        title_stack.set_visible_child (modifications_label);
    }

    internal void hide_in_window_modifications ()
        requires (in_window_modifications == true)
    {
        hide_modifications_button.hide ();
        modifications_actions_button.hide ();
        if (disable_action_bar)
        {
            show_modifications_button.show ();
            modifications_separator.show ();
        }
        if (!disable_popovers)
            bookmarks_button.show ();
        bookmarks_stack.hexpand = false;    // hack 4/7
        title_stack.set_visible_child (path_widget);
        in_window_modifications = false;
        info_button.show ();
    }

    internal void set_apply_modifications_button_sensitive (bool new_value)
    {
        if (new_value)
            modifications_actions_button.set_menu_model (changes_pending_menu);
        else
            modifications_actions_button.set_menu_model (quit_delayed_mode_menu);
    }

    /*\
    * * in-window bookmarks
    \*/

    [GtkChild] private Stack                bookmarks_stack;
    [GtkChild] private Label                bookmarks_label;
    [GtkChild] private BookmarksController  bookmarks_controller;
    [GtkChild] private Button               hide_in_window_bookmarks_button;
    [GtkChild] private Separator            bookmarks_actions_separator;

    bool in_window_bookmarks = false;

    internal void show_in_window_bookmarks ()
    {
        if (in_window_modifications)
            hide_in_window_modifications ();
        else if (in_window_about)
            hide_in_window_about ();

        in_window_bookmarks = true;
        update_modifications_button ();
        info_button.hide ();
        bookmarks_actions_separator.hide ();
        bookmarks_stack.hexpand = false;    // hack 5/7
        title_stack.set_visible_child (bookmarks_stack);
        bookmarks_stack.set_visible_child (bookmarks_label);
        hide_in_window_bookmarks_button.show ();
    }

    internal void hide_in_window_bookmarks ()
        requires (in_window_bookmarks == true)
    {
        hide_in_window_bookmarks_button.hide ();
        bookmarks_actions_separator.hide ();
        in_window_bookmarks = false;
        update_modifications_button ();
        bookmarks_stack.hexpand = false;    // hack 6/7
        title_stack.set_visible_child (path_widget);
        bookmarks_stack.set_visible_child (bookmarks_label);
        info_button.show ();
        update_hamburger_menu ();
    }

    internal void edit_in_window_bookmarks ()
        requires (in_window_bookmarks == true)
    {
        bookmarks_stack.hexpand = true;     // hack 7/7
        bookmarks_actions_separator.show ();
        bookmarks_stack.set_visible_child (bookmarks_controller);
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
    * * hamburger menu
    \*/

    internal bool night_time            { private get; internal set; default = false; }    // no need to use NightTime here (that allows an "Unknown" value)
    internal bool dark_theme            { private get; internal set; default = false; }
    internal bool automatic_night_mode  { private get; internal set; default = false; }

    private inline void hide_hamburger_menu ()
    {
        if (info_button.active)
            info_button.active = false;
    }

    internal void toggle_hamburger_menu ()
    {
        if (modifications_actions_button.visible)
            modifications_actions_button.active = !modifications_actions_button.active;
        else if (info_button.visible)
            info_button.active = !info_button.active;
    }

    private bool delay_mode = false;
    internal void update_hamburger_menu (bool? new_delay_mode = null)
    {
        if (new_delay_mode != null)
        {
            delay_mode = (!) new_delay_mode;
            update_modifications_button ();
        }

        GLib.Menu menu = new GLib.Menu ();

/*        if (current_type == ViewType.OBJECT && !ModelUtils.is_folder_path (current_path))   // TODO a better way to copy various representations of a key name/value/path
        {
            Variant variant = new Variant.string (model.get_suggested_key_copy_text (current_path, browser_view.last_context_id));
            menu.append (_("Copy descriptor"), "app.copy(" + variant.print (false) + ")");
        }
        else if (current_type != ViewType.SEARCH) */

        if (disable_popovers)
            append_bookmark_section (current_type, current_path, BookmarksList.get_bookmark_name (current_path, current_type) in get_bookmarks (), in_window_bookmarks, ref menu);

        if (!in_window_bookmarks)
            append_or_not_delay_mode_section (delay_mode, current_type == ViewType.FOLDER, current_path, ref menu);

        append_app_actions_section (night_time, dark_theme, automatic_night_mode, disable_popovers, ref menu);

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
    }

    private static void append_bookmark_section (ViewType current_type, string current_path, bool is_in_bookmarks, bool in_window_bookmarks, ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();

        if (in_window_bookmarks)
            section.append (_("Hide bookmarks"), "ui.hide-in-window-bookmarks");    // button hidden in current design
        else
        {
            if (is_in_bookmarks)
                section.append (_("Unbookmark"), "headerbar.unbookmark-current");
            else
                section.append (_("Bookmark"), "headerbar.bookmark-current");

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
            section.append (_("Enter delay mode"), "ui.enter-delay-mode");
        if (is_folder_view)
        {
            Variant variant = new Variant.string (current_path);
            section.append (_("Reset visible keys"), "ui.reset-visible(" + variant.print (false) + ")");
            section.append (_("Reset view recursively"), "ui.reset-recursive(" + variant.print (false) + ")");
        }
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void append_app_actions_section (bool night_time, bool dark_theme, bool auto_night, bool disable_popovers, ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();
        append_or_not_night_mode_entry (night_time, dark_theme, auto_night, ref section);
        if (!disable_popovers)    // TODO else...
            section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
        section.append (_("About Dconf Editor"), "ui.about");
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void append_or_not_night_mode_entry (bool night_time, bool dark_theme, bool auto_night, ref GLib.Menu section)
    {
        if (!night_time)
            return;

        if (dark_theme)
            /* Translators: there are three related actions: "use", "reuse" and "pause" */
            section.append (_("Pause night mode"), "app.set-use-night-mode(false)");

        else if (auto_night)
            /* Translators: there are three related actions: "use", "reuse" and "pause" */
            section.append (_("Reuse night mode"), "app.set-use-night-mode(true)");

        else
            /* Translators: there are three related actions: "use", "reuse" and "pause" */
            section.append (_("Use night mode"), "app.set-use-night-mode(true)");
    }

    /*\
    * * proxy callbacks
    \*/

    [GtkCallback]
    private void update_bookmarks_icons_cb (Variant bookmarks_variant)
    {
        update_bookmarks_icons (bookmarks_variant);
    }

    [GtkCallback]
    private void search_changed_cb ()
    {
        search_changed ();
    }
    [GtkCallback]
    private void search_stopped_cb ()
    {
        search_stopped ();
    }
}
