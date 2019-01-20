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
    private PathWidget path_widget;

    construct
    {
        init_path_widget ();

        register_properties_mode ();
    }

    private bool current_type_is_config = false;
    internal virtual void set_path (ViewType type, string path)
    {
        path_widget.set_path (type, path);

        if (current_type_is_config != (type == ViewType.CONFIG))
        {
            current_type_is_config = !current_type_is_config;
            update_properties_view ();
        }

        update_hamburger_menu ();
    }

    private bool is_extra_thin = false;
    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        if (is_extra_thin != AdaptativeWidget.WindowSize.is_extra_thin (new_size))
        {
            is_extra_thin = !is_extra_thin;
            update_properties_view ();
        }

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
    * * path_widget proxy calls
    \*/

    [CCode (notify = false)] internal bool search_mode_enabled   { get { return path_widget.search_mode_enabled; }}

    internal void get_complete_path (out string complete_path)   { path_widget.get_complete_path (out complete_path); }
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
        if (is_extra_thin && current_type_is_config)
            show_properties_view ();
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

        /* Translators: on really small windows, name of the view when showing a folder properties, displayed in the headerbar */
        real_this.set_default_widgets_states (_("Properties"),  /* title_label text or null */
                                              true,             /* show go_back_button      */
                                              false,            /* show ltr_left_separator  */
                                              false,            /* show info_button         */
                                              false,            /* show ltr_right_separator */
                                              true);            /* show quit_button_stack   */
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
        return base.has_popover () || path_widget.has_popover ();
    }
}
