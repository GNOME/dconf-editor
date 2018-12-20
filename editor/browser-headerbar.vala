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

private abstract class BrowserHeaderBar : BaseHeaderBar, AdaptativeWidget
{
    protected PathWidget path_widget;

    construct
    {
        init_path_widget ();

        register_properties_mode ();
    }

    private ViewType current_type = ViewType.FOLDER;
    internal virtual void set_path (ViewType type, string path)
    {
        path_widget.set_path (type, path);

        current_type = type;
        update_properties_view ();  // takes care of the hamburger menu
    }

    private bool is_extra_thin = false;
    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        is_extra_thin = AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        update_properties_view ();

        base.set_window_size (new_size);

        path_widget.set_window_size (new_size);
    }

    /*\
    * * path_widget creation
    \*/

    private void init_path_widget ()
    {
        add_path_widget ();

        this.change_mode.connect (mode_changed_browser);
    }

    private void add_path_widget ()
    {
        path_widget = new PathWidget ();
        path_widget.hexpand = false;

        connect_path_widget_signals ();

        path_widget.visible = true;
        center_box.add (path_widget);
    }

    private static void mode_changed_browser (BaseHeaderBar _this, uint8 mode_id)
    {
        if (mode_id == default_mode_id)
        {
            PathWidget path_widget = ((BrowserHeaderBar) _this).path_widget;
            path_widget.show ();
            if (path_widget.search_mode_enabled)
                path_widget.entry_grab_focus_without_selecting ();
        }
        else
            ((BrowserHeaderBar) _this).path_widget.hide ();
    }

    /*\
    * * path_widget proxy signals
    \*/

    internal signal void search_changed ();
    internal signal void search_stopped ();

    private void connect_path_widget_signals ()
    {
        path_widget.search_changed.connect (search_changed_cb);
        path_widget.search_stopped.connect (search_stopped_cb);
    }

    private void search_changed_cb ()
    {
        search_changed ();
    }

    private void search_stopped_cb ()
    {
        search_stopped ();
    }

    /*\
    * * path_widget proxy calls
    \*/

    [CCode (notify = false)] internal bool search_mode_enabled   { get { return path_widget.search_mode_enabled; }}
    [CCode (notify = false)] internal bool entry_has_focus       { get { return path_widget.entry_has_focus; }}
    [CCode (notify = false)] internal string text                { get { return path_widget.text; }}

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

    /*\
    * * properties mode
    \*/

    private uint8 properties_mode_id = 0;
    private bool properties_mode_on = false;
    internal bool in_window_properties { get { return properties_mode_on; }}

    private void update_properties_view ()
    {
        if (is_extra_thin)
        {
            if (current_type == ViewType.CONFIG)
                show_properties_view ();
            else
                hide_properties_view ();
        }
        else
            hide_properties_view ();
    }

    private void show_properties_view ()
        requires (properties_mode_id > 0)
    {
        if (!properties_mode_on)
            change_mode (properties_mode_id);
    }

    private void hide_properties_view ()
    {
        if (properties_mode_on)
            change_mode (default_mode_id);
        update_hamburger_menu ();
    }

    private void register_properties_mode ()
    {
        properties_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_properties);
    }

    private static void mode_changed_properties (BaseHeaderBar _this, uint8 requested_mode_id)
    {
        BrowserHeaderBar real_this = (BrowserHeaderBar) _this;
        if (is_not_requested_mode (real_this.properties_mode_id, requested_mode_id, ref real_this.properties_mode_on))
            return;

        real_this.set_default_widgets_states (/* show go_back_button      */ true,
                                              /* show ltr_left_separator  */ false,
                                              /* title_label text or null */ _("Properties"),
                                              /* show info_button         */ false,
                                              /* show ltr_right_separator */ false,
                                              /* show quit_button_stack   */ true);
    }

    /*\
    * * keyboard calls
    \*/

    internal virtual bool next_match ()
    {
        return false;
    }

    internal virtual bool previous_match ()
    {
        return false;
    }

    /*\
    * * popovers methods
    \*/

    internal override void close_popovers ()
    {
        base.close_popovers ();
        path_widget.close_popovers ();
    }

    internal override bool has_popover ()
    {
        if (base.has_popover ())
            return true;
        if (path_widget.has_popover ())
            return true;
        return false;
    }
}
