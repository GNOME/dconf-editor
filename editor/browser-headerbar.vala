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
private class BrowserHeaderBar : HeaderBar
{
    [GtkChild] private MenuButton info_button;
    [GtkChild] private PathWidget path_widget;

    private ViewType current_type = ViewType.FOLDER;
    private string current_path = "/";

    internal signal void search_changed ();
    internal signal void search_stopped ();
    internal signal void update_bookmarks_icons (Variant bookmarks_variant);

    internal bool extra_small_window    { set { path_widget.extra_small_window = value; }}

    internal bool search_mode_enabled   { get { return path_widget.search_mode_enabled; }}
    internal string complete_path       { get { return path_widget.complete_path; }}
    internal bool entry_has_focus       { get { return path_widget.entry_has_focus; }}
    internal string text                { get { return path_widget.text; }}

    internal void toggle_pathbar_menu ()    { path_widget.toggle_pathbar_menu (); }
    internal string [] get_bookmarks ()     { return path_widget.get_bookmarks (); }

    internal void update_bookmark_icon (string bookmark, BookmarkIcon icon) { path_widget.update_bookmark_icon (bookmark, icon); }
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
    }

    internal bool has_popover ()
    {
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

    internal void down_pressed ()
    {
        if (info_button.active)
            return;
        path_widget.down_pressed ();
    }

    internal void up_pressed ()
    {
        if (info_button.active)
            return;
        path_widget.up_pressed ();
    }

    internal void close_popovers ()
    {
        hide_hamburger_menu ();
        path_widget.close_popovers ();
    }

    internal void click_bookmarks_button ()
    {
        hide_hamburger_menu ();
        path_widget.click_bookmarks_button ();
    }

    internal void bookmark_current_path ()
    {
        hide_hamburger_menu ();
        path_widget.bookmark_current_path ();
    }

    internal void unbookmark_current_path ()
    {
        hide_hamburger_menu ();
        path_widget.unbookmark_current_path ();
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
        info_button.active = !info_button.active;
    }

    internal void update_hamburger_menu (bool delay_mode)
    {
        GLib.Menu menu = new GLib.Menu ();

/*        if (current_type == ViewType.OBJECT && !ModelUtils.is_folder_path (current_path))   // TODO a better way to copy various representations of a key name/value/path
        {
            Variant variant = new Variant.string (model.get_suggested_key_copy_text (current_path, browser_view.last_context_id));
            menu.append (_("Copy descriptor"), "app.copy(" + variant.print (false) + ")");
        }
        else if (current_type != ViewType.SEARCH) */

        append_or_not_delay_mode_section (delay_mode, current_type == ViewType.FOLDER, current_path, ref menu);
        append_app_actions_section (night_time, dark_theme, automatic_night_mode, ref menu);

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
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

    private static void append_app_actions_section (bool night_time, bool dark_theme, bool auto_night, ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();
        append_or_not_night_mode_entry (night_time, dark_theme, auto_night, ref section);
        section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
        section.append (_("About Dconf Editor"), "app.about");   // TODO move as "win."
        section.freeze ();
        menu.append_section (null, section);
    }

    private static void append_or_not_night_mode_entry (bool night_time, bool dark_theme, bool auto_night, ref GLib.Menu section)
    {
        if (!night_time)
            return;

        if (dark_theme)
            section.append (_("Pause night mode"), "app.set-use-night-mode(false)");
        else if (auto_night)
            section.append (_("Reuse night mode"), "app.set-use-night-mode(true)");
        else
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
