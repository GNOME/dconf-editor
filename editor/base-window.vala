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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/base-window.ui")]
private class BaseWindow : AdaptativeWindow, AdaptativeWidget
{
    [CCode (notify = false)] public BaseView base_view { protected get; protected construct; }

    private BaseHeaderBar headerbar;

    construct
    {
        headerbar = (BaseHeaderBar) nta_headerbar;

        base_view.vexpand = true;
        base_view.visible = true;
        add_to_main_grid (base_view);

        install_action_entries ();
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
        return base_view.handle_copy_text (out copy_text);
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

        base_view.close_popovers ();

        string text;
        if (handle_copy_text (out text))
            copy_text (text);
    }

    private void copy_alt (/* SimpleAction action, Variant? path_variant */)
    {
        if (base_view.is_in_in_window_mode ())        // TODO better
            return;

        base_view.close_popovers ();

        string text;
        if (get_alt_copy_text (out text))
            copy_text (text);
    }

    private inline void copy_text (string text)
        requires (!is_empty_text (text))
    {
        ((ConfigurationEditor) get_application ()).copy ((!) text);
    }

    /*\
    * * keyboard paste actions
    \*/

    protected virtual void paste_text (string? text) {}

    private void paste (/* SimpleAction action, Variant? variant */)
    {
        if (base_view.is_in_in_window_mode ())
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
        base_view.close_popovers ();
    }

    protected virtual void menu_pressed (/* SimpleAction action, Variant? variant */)
    {
        headerbar.toggle_hamburger_menu ();
        base_view.close_popovers ();
    }

    /*\
    * * global callbacks
    \*/

    [GtkCallback]
    private void on_destroy ()
    {
        before_destroy ();
        base.destroy ();
    }

    protected virtual void before_destroy () {}

    [GtkCallback]
    protected virtual bool on_key_press_event (Widget widget, Gdk.EventKey event)
    {
        uint keyval = event.keyval;
        string name = (!) (Gdk.keyval_name (keyval) ?? "");

        if (name == "F1") // TODO fix dance done with the F1 & <Primary>F1 shortcuts that show help overlay
        {
            headerbar.close_popovers ();
            base_view.close_popovers ();
            if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                return false;   // help overlay
            about ();
            return true;
        }

        return false;
    }

    /*\
    * * adaptative stuff
    \*/

    private bool disable_popovers = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (in_window_about)
                show_default_view ();
        }

        chain_set_window_size (new_size);
    }

    protected virtual void chain_set_window_size (AdaptativeWidget.WindowSize new_size) {}

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
        if (!AdaptativeWidget.WindowSize.is_phone_size (window_size)
         && !AdaptativeWidget.WindowSize.is_extra_thin (window_size))
            show_about_dialog ();       // TODO hide the dialog if visible
        else
            toggle_in_window_about ();
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
        base_view.show_about_view ();
    }

    protected virtual void show_default_view (/* SimpleAction action, Variant? path_variant */)
    {
        if (in_window_about)
        {
            in_window_about = false;
            headerbar.show_default_view ();
            base_view.show_default_view ();
        }
        else
            assert_not_reached ();
    }

    /*\
    * * notifications
    \*/

    protected void show_notification (string notification)
    {
        base_view.show_notification (notification);
    }

    protected void hide_notification ()
    {
        base_view.hide_notification ();
    }
}
