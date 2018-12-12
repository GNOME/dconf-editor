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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/base-headerbar.ui")]
private class BaseHeaderBar : NightTimeAwareHeaderBar, AdaptativeWidget
{
    [GtkChild] protected Box center_box;

    construct
    {
        center_box.valign = Align.FILL;

        register_default_mode ();
        register_about_mode ();
    }

    /*\
    * * properties
    \*/

    protected bool disable_popovers = false;
    protected bool disable_action_bar = false;
    protected virtual void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        disable_popovers   = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                          || AdaptativeWidget.WindowSize.is_extra_thin (new_size);

        disable_action_bar = disable_popovers
                          || AdaptativeWidget.WindowSize.is_extra_flat (new_size);

        update_hamburger_menu ();
    }

    /*\
    * * popovers methods
    \*/

    internal virtual void close_popovers ()
    {
        hide_hamburger_menu ();
    }

    protected inline void hide_hamburger_menu ()
    {
        if (info_button.active)
            info_button.active = false;
    }

    internal virtual bool has_popover ()
    {
        if (info_button.active)
            return true;
        return false;
    }

    /*\
    * * keyboard calls
    \*/

    internal virtual bool previous_match ()
    {
        return false;
    }

    internal virtual bool next_match ()
    {
        return false;
    }

    internal virtual void toggle_hamburger_menu ()
    {
        if (info_button.visible)
            info_button.active = !info_button.active;
    }

    /*\
    * * hamburger menu
    \*/

    [CCode (notify = false)] public string about_action_label { private get; protected construct; }

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
        append_or_not_keyboard_shortcuts_entry (!disable_popovers, ref section);
        append_about_entry (about_action_label, ref section);
        section.freeze ();
        menu.append_section (null, section);
    }

    private static inline void append_or_not_keyboard_shortcuts_entry (bool has_keyboard_shortcuts, ref GLib.Menu section)
    {
        if (has_keyboard_shortcuts)    // FIXME is used also for hiding keyboard shortcuts in small window
            section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");
    }

    private static inline void append_about_entry (string about_action_label, ref GLib.Menu section)
    {
        section.append (about_action_label, "browser.about");
    }

    /*\
    * * modes
    \*/

    protected signal void change_mode (uint8 mode_id);

    private uint8 last_mode_id = 0; // 0 is default mode
    protected uint8 register_new_mode ()
    {
        return ++last_mode_id;
    }

    protected bool is_not_requested_mode (uint8 mode_id, uint8 requested_mode_id, ref bool mode_is_active)
    {
        if (mode_id == requested_mode_id)
        {
            if (mode_is_active)
                assert_not_reached ();
            mode_is_active = true;
            return false;
        }
        else
        {
            mode_is_active = false;
            return true;
        }
    }

    /*\
    * * default widgets
    \*/

    [GtkChild] private Button       go_back_button;
    [GtkChild] private Separator    ltr_left_separator;
    [GtkChild] private Label        title_label;
    [GtkChild] private MenuButton   info_button;

    [GtkChild] protected Separator  ltr_right_separator;    // TODO make private
    [GtkChild] protected Stack      quit_button_stack;

    protected void set_default_widgets_states (bool     show_go_back_button,
                                               bool     show_ltr_left_separator,
                                               string?  title_label_text_or_null,
                                               bool     show_info_button,
                                               bool     show_ltr_right_separator,
                                               bool     show_quit_button_stack)
    {
        go_back_button.visible = show_go_back_button;
        ltr_left_separator.visible = show_ltr_left_separator;
        if (title_label_text_or_null == null)
        {
            title_label.set_label ("");
            title_label.hide ();
        }
        else
        {
            title_label.set_label ((!) title_label_text_or_null);
            title_label.show ();
        }
        info_button.visible = show_info_button;
        ltr_right_separator.visible = show_ltr_right_separator;
        quit_button_stack.visible = show_quit_button_stack;
    }

    /*\
    * * default mode
    \*/

    protected const uint8 default_mode_id = 0;
    private bool default_mode_on = true;

    internal void show_default_view ()
    {
        change_mode (default_mode_id);
    }

    private void register_default_mode ()
    {
        this.change_mode.connect (mode_changed_default);
    }

    private void mode_changed_default (uint8 requested_mode_id)
    {
        if (is_not_requested_mode (default_mode_id, requested_mode_id, ref default_mode_on))
            return;

        set_default_widgets_states (/* show go_back_button      */ false,
                                    /* show ltr_left_separator  */ false,
                                    /* title_label text or null */ null,
                                    /* show info_button         */ true,
                                    /* show ltr_right_separator */ disable_action_bar,
                                    /* show quit_button_stack   */ disable_action_bar);
    }

    /*\
    * * about mode
    \*/

    private uint8 about_mode_id = 0;
    protected bool about_mode_on = false;   // TODO make private

    internal void show_about_view ()
        requires (about_mode_id > 0)
    {
        change_mode (about_mode_id);
    }

    private void register_about_mode ()
    {
        about_mode_id = register_new_mode ();

        this.change_mode.connect (mode_changed_about);
    }

    private void mode_changed_about (uint8 requested_mode_id)
        requires (about_mode_id > 0)
    {
        if (is_not_requested_mode (about_mode_id, requested_mode_id, ref about_mode_on))
            return;

        set_default_widgets_states (/* show go_back_button      */ true,
                                    /* show ltr_left_separator  */ false,
                                    /* title_label text or null */ _("About"),
                                    /* show info_button         */ false,
                                    /* show ltr_right_separator */ false,
                                    /* show quit_button_stack   */ true);
    }
}
