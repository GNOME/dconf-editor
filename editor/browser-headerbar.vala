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
private abstract class BrowserHeaderBar : AdaptativeHeaderBar, AdaptativeWidget
{
    [GtkChild] protected MenuButton info_button;
    [GtkChild] protected PathWidget path_widget;

    [GtkChild] protected Box        center_box;
    [GtkChild] protected Stack      title_stack;
    [GtkChild] protected Label      title_label;

    [GtkChild] protected Button     go_back_button;
    [GtkChild] protected Separator  ltr_left_separator;
    [GtkChild] protected Separator  ltr_right_separator;

    [GtkChild] protected Button     quit_button;

    protected ViewType current_type = ViewType.FOLDER;
    protected string current_path = "/";

    internal signal void search_changed ();
    internal signal void search_stopped ();

    protected bool disable_popovers = false;
    protected bool disable_action_bar = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            disable_popovers_changed ();
        }

        disable_action_bar = _disable_popovers
                          || AdaptativeWidget.WindowSize.is_extra_flat (new_size);

        update_hamburger_menu ();
        update_modifications_button ();

        path_widget.set_window_size (new_size);
    }
    protected virtual void disable_popovers_changed () {}
    protected abstract void update_modifications_button ();

    internal bool search_mode_enabled   { get { return path_widget.search_mode_enabled; }}
    internal bool entry_has_focus       { get { return path_widget.entry_has_focus; }}
    internal string text                { get { return path_widget.text; }}

    internal string get_complete_path ()    { return path_widget.get_complete_path (); }
    internal void get_fallback_path_and_complete_path (out string fallback_path, out string complete_path)
    {
        path_widget.get_fallback_path_and_complete_path (out fallback_path, out complete_path);
    }
    internal void toggle_pathbar_menu ()    { path_widget.toggle_pathbar_menu (); }

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

    internal bool handle_event (Gdk.EventKey event)
    {
        return path_widget.handle_event (event);
    }

    construct
    {
        center_box.valign = Align.FILL;
    }

    /*\
    * * in-window about
    \*/

    protected bool in_window_about = false;

    protected virtual void close_in_window_panels () {}
    internal void show_in_window_about ()
    {
        close_in_window_panels ();

        in_window_about = true;
        update_modifications_button ();
        info_button.hide ();
        go_back_button.set_action_name ("browser.hide-in-window-about");
        go_back_button.show ();
        title_label.set_label (_("About"));
        title_stack.set_visible_child (title_label);
    }

    internal void hide_in_window_about ()
        requires (in_window_about == true)
    {
        go_back_button.hide ();
        in_window_about = false;
        title_stack.set_visible_child (path_widget);
        if (disable_action_bar)
            ltr_right_separator.show ();
        info_button.show ();
        if (path_widget.search_mode_enabled)
            path_widget.entry_grab_focus_without_selecting ();
    }

    /*\
    * * hamburger menu
    \*/

    protected inline void hide_hamburger_menu ()
    {
        if (info_button.active)
            info_button.active = false;
    }

    protected override void update_hamburger_menu ()
    {
        GLib.Menu menu = new GLib.Menu ();

/*        if (current_type == ViewType.OBJECT && !ModelUtils.is_folder_path (current_path))   // TODO a better way to copy various representations of a key name/value/path
        {
            Variant variant = new Variant.string (model.get_suggested_key_copy_text (current_path, browser_view.last_context_id));
            menu.append (_("Copy descriptor"), "app.copy(" + variant.print (false) + ")");
        }
        else if (current_type != ViewType.SEARCH) */

        populate_menu (ref menu);

        append_app_actions_section (ref menu);

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
    }

    protected virtual void populate_menu (ref GLib.Menu menu) {}

    private void append_app_actions_section (ref GLib.Menu menu)
    {
        GLib.Menu section = new GLib.Menu ();
        append_or_not_night_mode_entry (ref section);
        _append_app_actions_section (!disable_popovers, ref section);
        section.freeze ();
        menu.append_section (null, section);
    }
    private static void _append_app_actions_section (bool has_keyboard_shortcuts, ref GLib.Menu section)
    {
        if (has_keyboard_shortcuts)    // FIXME is used also for hiding keyboard shortcuts in small window
            section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
        section.append (_("About Dconf Editor"), "browser.about");
    }

    /*\
    * * proxy callbacks
    \*/

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

    /*\
    * *
    \*/

    internal virtual void close_popovers ()
    {
        hide_hamburger_menu ();
        path_widget.close_popovers ();
    }

    internal virtual bool has_popover ()
    {
        if (info_button.active)
            return true;
        if (path_widget.has_popover ())
            return true;
        return false;
    }

    internal virtual bool previous_match ()
    {
        return false;
    }

    internal virtual bool next_match ()
    {
        return false;
    }

    internal virtual void set_path (ViewType type, string path)
    {
        current_type = type;
        current_path = path;

        path_widget.set_path (type, path);

        update_hamburger_menu ();
    }

    internal virtual void toggle_hamburger_menu ()
    {
        if (info_button.visible)
            info_button.active = !info_button.active;
    }
}
