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
private class BaseHeaderBar : HeaderBar, AdaptativeWidget
{
    [GtkChild] protected unowned Box center_box;

    construct
    {
        center_box.valign = Align.FILL;

        register_modes ();
    }

    /*\
    * * properties
    \*/

    private bool has_a_phone_size = false;
    protected bool disable_popovers = false;
    protected bool disable_action_bar = false;
    protected virtual void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        has_a_phone_size = AdaptativeWidget.WindowSize.is_phone_size (new_size);
        disable_popovers = has_a_phone_size
                        || AdaptativeWidget.WindowSize.is_extra_thin (new_size);

        bool _disable_action_bar = disable_popovers
                                || AdaptativeWidget.WindowSize.is_extra_flat (new_size);
        if (disable_action_bar != _disable_action_bar)
        {
            disable_action_bar = _disable_action_bar;
            if (disable_action_bar)
            {
                set_show_close_button (false);
                quit_button_stack.show ();
                ltr_right_separator.visible = current_mode_id == default_mode_id;
            }
            else
            {
                ltr_right_separator.hide ();
                quit_button_stack.hide ();
                set_show_close_button (true);
            }
        }

        update_hamburger_menu ();
    }

    /*\
    * * hamburger menu
    \*/

    [CCode (notify = false)] public string about_action_label     { internal get; protected construct; } // TODO add default = _("About");
    [CCode (notify = false)] public bool   has_help               { private  get; protected construct; default = false; }
    [CCode (notify = false)] public bool   has_keyboard_shortcuts { private  get; protected construct; default = false; }

    public void update_hamburger_menu ()
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

    private void append_app_actions_section (ref GLib.Menu menu)    // FIXME mnemonics?
    {
        GLib.Menu section = new GLib.Menu ();
        append_or_not_keyboard_shortcuts_entry (has_keyboard_shortcuts, !has_a_phone_size, ref section);
        append_or_not_help_entry (has_help, ref section);
        append_about_entry (about_action_label, ref section);
        section.freeze ();
        menu.append_section (null, section);
    }

    private static inline void append_or_not_keyboard_shortcuts_entry (bool      has_keyboard_shortcuts,
                                                                       bool      show_keyboard_shortcuts,
                                                                   ref GLib.Menu section)
    {
        // TODO something in small windows
        if (!has_keyboard_shortcuts || !show_keyboard_shortcuts)
            return;

        /* Translators: usual menu entry of the hamburger menu*/
        section.append (_("Keyboard Shortcuts"), "win.show-help-overlay");  // TODO mnemonic?
    }

    private static inline void append_or_not_help_entry (bool has_help, ref GLib.Menu section)
    {
        if (!has_help)
            return;

        /* Translators: usual menu entry of the hamburger menu (with a mnemonic that appears pressing Alt) */
     // section.append (_("_Help"), "app.help");    // FIXME uncomment, and choose mnemonic or not
    }

    private static inline void append_about_entry (string about_action_label, ref GLib.Menu section)
    {
        section.append (about_action_label, "base.about");
    }

    protected inline void hide_hamburger_menu ()
    {
        if (info_button.active)
            info_button.active = false;
    }

    internal void toggle_hamburger_menu ()
    {
        if (info_button.visible)
            info_button.active = !info_button.active;
        else
            toggle_view_menu ();
    }
    protected virtual void toggle_view_menu () {}

    /*\
    * * modes
    \*/

    protected signal void change_mode (uint8 mode_id);

    private uint8 last_mode_id = 0; // 0 is default mode
    protected uint8 register_new_mode ()
    {
        return ++last_mode_id;
    }

    protected static bool is_not_requested_mode (uint8 mode_id, uint8 requested_mode_id, ref bool mode_is_active)
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

    private uint8 current_mode_id = default_mode_id;
    private void register_modes ()
    {
        register_default_mode ();
        register_about_mode ();

        this.change_mode.connect (update_current_mode_id);
    }
    private static void update_current_mode_id (BaseHeaderBar _this, uint8 requested_mode_id)
    {
        _this.current_mode_id = requested_mode_id;
    }

    /*\
    * * quit button stack
    \*/

    [GtkChild] private unowned Stack quit_button_stack;

    protected void add_named_widget_to_quit_button_stack (Widget widget, string name)
    {
        quit_button_stack.add_named (widget, name);
    }

    protected void set_quit_button_stack_child (string name)
    {
        quit_button_stack.set_visible_child_name (name);
    }

    protected void set_quit_button_stack_visibility (bool visible)  // TODO better
    {
        if (visible)
            quit_button_stack.show ();
        else
            quit_button_stack.hide ();
    }

    /*\
    * * default widgets
    \*/

    [GtkChild] private unowned Button     go_back_button;
    [GtkChild] private unowned Separator  ltr_left_separator;
    [GtkChild] private unowned Label      title_label;
    [GtkChild] private unowned MenuButton info_button;
    [GtkChild] private unowned Separator  ltr_right_separator;

    protected void set_default_widgets_states (string?  title_label_text_or_null,
                                               bool     show_go_back_button,
                                               bool     show_ltr_left_separator,
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
    protected bool no_in_window_mode { get { return default_mode_on; }}

    internal void show_default_view ()
    {
        change_mode (default_mode_id);
    }

    private void register_default_mode ()
    {
        this.change_mode.connect (mode_changed_default);
    }

    private static void mode_changed_default (BaseHeaderBar _this, uint8 requested_mode_id)
    {
        if (is_not_requested_mode (default_mode_id, requested_mode_id, ref _this.default_mode_on))
            return;

        _this.set_default_widgets_default_states (_this);
    }

    protected virtual void set_default_widgets_default_states (BaseHeaderBar _this)
    {
        _this.set_default_widgets_states (/* title_label text or null */ null,
                                          /* show go_back_button      */ false,
                                          /* show ltr_left_separator  */ false,
                                          /* show info_button         */ true,
                                          /* show ltr_right_separator */ _this.disable_action_bar,
                                          /* show quit_button_stack   */ _this.disable_action_bar);
    }

    /*\
    * * about mode
    \*/

    private uint8 about_mode_id = 0;
    private bool about_mode_on = false;

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

    private static void mode_changed_about (BaseHeaderBar _this, uint8 requested_mode_id)
        requires (_this.about_mode_id > 0)
    {
        if (is_not_requested_mode (_this.about_mode_id, requested_mode_id, ref _this.about_mode_on))
            return;

        /* Translators: on really small windows, the about dialog is replaced by an in-window view; here is the name of the view, displayed in the headerbar */
        _this.set_default_widgets_states (_("About"),   /* title_label text or null */
                                          true,         /* show go_back_button      */
                                          false,        /* show ltr_left_separator  */
                                          false,        /* show info_button         */
                                          false,        /* show ltr_right_separator */
                                          true);        /* show quit_button_stack   */
    }

    /*\
    * * popovers methods
    \*/

    internal virtual void close_popovers ()
    {
        hide_hamburger_menu ();
    }

    internal virtual bool has_popover ()
    {
        return info_button.active;
    }
}
