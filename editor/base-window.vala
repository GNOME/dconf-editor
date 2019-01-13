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

private interface BaseApplication : Gtk.Application
{
    internal abstract void copy (string text);
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/base-window.ui")]
private class BaseWindow : AdaptativeWindow, AdaptativeWidget
{
    private BaseView main_view;
    [CCode (notify = false)] public BaseView base_view
    {
        protected get { return main_view; }
        protected construct
        {
            BaseView? _value = value;
            if (_value == null)
                assert_not_reached ();

            main_view = value;
            value.vexpand = true;
            value.visible = true;
            add_to_main_grid (value);
        }
    }

    private BaseHeaderBar headerbar;

    construct
    {
        headerbar = (BaseHeaderBar) nta_headerbar;

        install_action_entries ();

        add_adaptative_child (headerbar);
        add_adaptative_child (main_view);
        add_adaptative_child (this);
    }

    /*\
    * * main grid
    \*/

    [GtkChild] private Grid main_grid;

    protected void add_to_main_grid (Widget widget)
    {
        main_grid.add (widget);
    }

    /*\
    * * action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("base", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "copy",               copy                },  // <P>c
        { "copy-alt",           copy_alt            },  // <P>C

        { "paste",              paste               },  // <P>v
        { "paste-alt",          paste_alt           },  // <P>V

        { "toggle-hamburger",   toggle_hamburger    },  // F10
        { "menu",               menu_pressed        },  // Menu

        { "show-default-view",  show_default_view },
        { "about",              about }
    };

    /*\
    * * keyboard copy actions
    \*/

    protected virtual bool handle_copy_text (out string copy_text)
    {
        return main_view.handle_copy_text (out copy_text);
    }
    protected virtual bool get_alt_copy_text (out string copy_text)
    {
        return no_copy_text (out copy_text);
    }
    internal static bool no_copy_text (out string copy_text)
    {
        copy_text = "";
        return false;
    }
    internal static bool copy_clipboard_text (out string copy_text)
    {
        string? nullable_selection = Clipboard.@get (Gdk.SELECTION_PRIMARY).wait_for_text ();
        if (nullable_selection != null)
        {
             string selection = ((!) nullable_selection).dup ();
             if (selection != "")
             {
                copy_text = selection;
                return true;
             }
        }
        return no_copy_text (out copy_text);
    }
    internal static inline bool is_empty_text (string text)
    {
        return text == "";
    }

    private void copy (/* SimpleAction action, Variant? path_variant */)
    {
        Widget? focus = get_focus ();
        if (focus != null)
        {
            if ((!) focus is Editable)  // GtkEntry, GtkSearchEntry, GtkSpinButton
            {
                int garbage1, garbage2;
                if (((Editable) (!) focus).get_selection_bounds (out garbage1, out garbage2))
                {
                    ((Editable) (!) focus).copy_clipboard ();
                    return;
                }
            }
            else if ((!) focus is TextView)
            {
                if (((TextView) (!) focus).get_buffer ().get_has_selection ())
                {
                    ((TextView) (!) focus).copy_clipboard ();
                    return;
                }
            }
            else if ((!) focus is Label)
            {
                int garbage1, garbage2;
                if (((Label) (!) focus).get_selection_bounds (out garbage1, out garbage2))
                {
                    ((Label) (!) focus).copy_clipboard ();
                    return;
                }
            }
        }

        main_view.close_popovers ();

        string text;
        if (handle_copy_text (out text))
            copy_text (text);
    }

    private void copy_alt (/* SimpleAction action, Variant? path_variant */)
    {
        if (main_view.is_in_in_window_mode ())        // TODO better
            return;

        main_view.close_popovers ();

        string text;
        if (get_alt_copy_text (out text))
            copy_text (text);
    }

    private inline void copy_text (string text)
        requires (!is_empty_text (text))
    {
        ((BaseApplication) get_application ()).copy ((!) text);
    }

    /*\
    * * keyboard paste actions
    \*/

    protected virtual void paste_text (string? text) {}

    private void paste (/* SimpleAction action, Variant? variant */)
    {
        if (main_view.is_in_in_window_mode ())
            return;

        Widget? focus = get_focus ();
        if (focus != null)
        {
            if ((!) focus is Entry)
            {
                ((Entry) (!) focus).paste_clipboard ();
                return;
            }
            if ((!) focus is TextView)
            {
                ((TextView) (!) focus).paste_clipboard ();
                return;
            }
        }

        paste_clipboard_content ();
    }

    private void paste_alt (/* SimpleAction action, Variant? variant */)
    {
        close_in_window_panels ();

        paste_clipboard_content ();
    }

    private void paste_clipboard_content ()
    {
        Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null)    // ?
            return;

        string? clipboard_content;
        if (get_clipboard_content (out clipboard_content))
            paste_text (clipboard_content);
    }

    private static inline bool get_clipboard_content (out string? clipboard_content)
    {
        Gdk.Display? display = Gdk.Display.get_default ();
        if (display == null)            // ?
        {
            clipboard_content = null;   // garbage
            return false;
        }

        clipboard_content = Clipboard.get_default ((!) display).wait_for_text ();
        return true;
    }

    /*\
    * * keyboard open menus actions
    \*/

    private void toggle_hamburger (/* SimpleAction action, Variant? variant */)
    {
        headerbar.toggle_hamburger_menu ();
        main_view.close_popovers ();
    }

    protected virtual void menu_pressed (/* SimpleAction action, Variant? variant */)
    {
        headerbar.toggle_hamburger_menu ();
        main_view.close_popovers ();
    }

    /*\
    * * global callbacks
    \*/

    [GtkCallback]
    protected virtual bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        return _on_key_press_event (widget, event);
    }
    private static bool _on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        if (name == "F1") // TODO fix dance done with the F1 & <Primary>F1 shortcuts that show help overlay
        {
            BaseWindow _this = (BaseWindow) widget;

            _this.headerbar.close_popovers ();
            _this.main_view.close_popovers ();
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                return false;   // help overlay
            _this.about ();
            return true;
        }

        return false;
    }

    /*\
    * * adaptative stuff
    \*/

    private bool disable_popovers = false;
    protected virtual void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (in_window_about)
                show_default_view ();
        }
    }

    /*\
    * * in-window panels
    \*/

    protected virtual void close_in_window_panels ()
    {
        hide_notification ();
        headerbar.close_popovers ();
        if (in_window_about)
            show_default_view ();
    }

    /*\
    * * about action and dialog
    \*/

    private void about (/* SimpleAction action, Variant? path_variant */)
    {
        if (disable_popovers)
            toggle_in_window_about ();
        else
            show_about_dialog ();       // TODO hide the dialog if visible
    }

    private void show_about_dialog ()
    {
        string [] authors = AboutDialogInfos.authors;
        Gtk.show_about_dialog (this,
                               "program-name",          AboutDialogInfos.program_name,
                               "version",               AboutDialogInfos.version,
                               "comments",              AboutDialogInfos.comments,
                               "copyright",             AboutDialogInfos.copyright,
                               "license-type",          AboutDialogInfos.license_type,
                               "wrap-license", true,
                               "authors",               authors,
                               "translator-credits",    AboutDialogInfos.translator_credits,
                               "logo-icon-name",        AboutDialogInfos.logo_icon_name,
                               "website",               AboutDialogInfos.website,
                               "website-label",         AboutDialogInfos.website_label,
                               null);
    }

    /*\
    * * in-window about
    \*/

    [CCode (notify = false)] protected bool in_window_about { protected get; private set; default = false; }

    private void toggle_in_window_about ()
    {
        if (in_window_about)
            show_default_view ();
        else
            show_about_view ();
    }

    private inline void show_about_view ()
        requires (in_window_about == false)
    {
        close_in_window_panels ();

        in_window_about = true;
        headerbar.show_about_view ();
        main_view.show_about_view ();
        set_focus_visible (false);  // about-list grabs focus
    }

    protected virtual void show_default_view (/* SimpleAction action, Variant? path_variant */)
    {
        if (in_window_about)
        {
            in_window_about = false;
            headerbar.show_default_view ();
            main_view.show_default_view ();
        }
        else
            assert_not_reached ();
    }

    /*\
    * * notifications
    \*/

    protected void show_notification (string notification)
    {
        main_view.show_notification (notification);
    }

    protected void hide_notification ()
    {
        main_view.hide_notification ();
    }
}
