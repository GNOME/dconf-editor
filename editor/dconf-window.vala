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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

using Gtk;

public enum Behaviour {
    UNSAFE,
    SAFE,
    ALWAYS_CONFIRM_IMPLICIT,
    ALWAYS_CONFIRM_EXPLICIT,
    ALWAYS_DELAY
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/dconf-editor.ui")]
class DConfWindow : ApplicationWindow
{
    private const GLib.ActionEntry [] action_entries =
    {
        { "reset-recursive", reset_recursively },
        { "reset-visible", reset },
        { "enter-delay-mode", enter_delay_mode }
    };

    public string current_path { private get; set; default = "/"; } // not synced bidi, needed for saving on destroy, even after child destruction

    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_tiled = false;

    private GLib.Settings settings = new GLib.Settings ("ca.desrt.dconf-editor.Settings");

    [GtkChild] private Bookmarks bookmarks_button;
    [GtkChild] private MenuButton info_button;
    [GtkChild] private PathBar pathbar;
    [GtkChild] private RegistryView registry_view;

    [GtkChild] private Revealer notification_revealer;
    [GtkChild] private Label notification_label;

    private ulong behaviour_changed_handler = 0;
    private ulong theme_changed_handler = 0;

    public DConfWindow ()
    {
        add_action_entries (action_entries, this);

        behaviour_changed_handler = settings.changed ["behaviour"].connect (invalidate_popovers);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        theme_changed_handler = settings.changed ["theme"].connect (() => {
                string theme = settings.get_string ("theme");
                StyleContext context = get_style_context ();    // TODO only check once?
                if (theme == "three-twenty-two" && context.has_class ("small-rows"))
                    context.remove_class ("small-rows");
                else if (theme == "small-rows" && !context.has_class ("small-rows"))
                    context.add_class ("small-rows");
            });
        if (settings.get_string ("theme") == "small-rows")
            get_style_context ().add_class ("small-rows");

        registry_view.bind_property ("current-path", this, "current-path");    // TODO in UI file?
        settings.bind ("behaviour", registry_view, "behaviour", SettingsBindFlags.GET|SettingsBindFlags.NO_SENSITIVITY);
        registry_view.init (settings.get_string ("saved-view"), settings.get_boolean ("restore-view"));  // TODO better?
    }

    public static string stripped_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return path.slice (0, path.last_index_of_char ('/') + 1);
    }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private void on_show ()
    {
        if (!settings.get_boolean ("show-warning"))
            return;

        Gtk.MessageDialog dialog = new MessageDialog (this, DialogFlags.MODAL, MessageType.INFO, ButtonsType.NONE, _("Thanks for using Dconf Editor for editing your settings!"));
        dialog.format_secondary_text (_("Don't forget that some options may break applications, so be careful."));
        dialog.add_buttons (_("I'll be careful."), ResponseType.ACCEPT);

        // TODO don't show box if the user explicitely said she wanted to see the dialog next time?
        Box box = (Box) dialog.get_message_area ();
        CheckButton checkbutton = new CheckButton.with_label (_("Show this dialog next time."));
        checkbutton.visible = true;
        checkbutton.active = true;
        checkbutton.margin_top = 5;
        box.add (checkbutton);

        ulong dialog_response_handler = dialog.response.connect (() => { if (!checkbutton.active) settings.set_boolean ("show-warning", false); });
        dialog.run ();
        dialog.disconnect (dialog_response_handler);
        dialog.destroy ();
    }

    [GtkCallback]
    private bool on_window_state_event (Widget widget, Gdk.EventWindowState event)
    {
        if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
            window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;
        /* We don’t save this state, but track it for saving size allocation */
        if ((event.changed_mask & Gdk.WindowState.TILED) != 0)
            window_is_tiled = (event.new_window_state & Gdk.WindowState.TILED) != 0;

        return false;
    }

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        /* responsive design */

        StyleContext context = get_style_context ();
        if (allocation.width > 1200)
        {
            context.add_class ("xxl");
            context.add_class ("xl");
            context.add_class ("large-window");
        }
        else if (allocation.width > 1100)
        {
            context.remove_class ("xxl");
            context.add_class ("xl");
            context.add_class ("large-window");
        }
        else if (allocation.width > 1000)
        {
            context.remove_class ("xxl");
            context.remove_class ("xl");
            context.add_class ("large-window");
        }
        else
        {
            context.remove_class ("xxl");
            context.remove_class ("xl");
            context.remove_class ("large-window");
        }

        /* save size */

        if (window_is_maximized || window_is_tiled)
            return;
        get_size (out window_width, out window_height);
    }

    [GtkCallback]
    private void on_destroy ()
    {
        get_application ().withdraw_notification ("copy");

        settings.disconnect (behaviour_changed_handler);
        settings.disconnect (theme_changed_handler);

        settings.delay ();
        settings.set_string ("saved-view", current_path);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();

        base.destroy ();
    }

    /*\
    * *
    \*/

    private void invalidate_popovers ()
    {
        registry_view.invalidate_popovers ();
    }

    [GtkCallback]
    private bool scroll_to_path_without_transition (string full_name)
    {
        registry_view.enable_transition (false);
        bool return_value = registry_view.scroll_to_path (full_name);
        registry_view.enable_transition (true);
        return return_value;
    }
    [GtkCallback]
    private bool scroll_to_path (string full_name)
    {
        registry_view.set_search_mode (false);
        return registry_view.scroll_to_path (full_name);
    }

    /*\
    * * Action entries
    \*/

    public void update_hamburger_menu ()
    {
        GLib.Menu section;

        bookmarks_button.set_path (current_path);
        pathbar.set_path (current_path);

        GLib.Menu menu = new GLib.Menu ();
        menu.append (_("Copy current path"), "app.copy(\"" + current_path.escape ("") + "\")");

        if (current_path.has_suffix ("/"))
        {
            section = new GLib.Menu ();
            section.append (_("Reset visible keys"), "win.reset-visible");
            section.append (_("Reset recursively"), "win.reset-recursive");
            section.freeze ();
            menu.append_section (null, section);
        }

        if (!registry_view.get_current_delay_mode ())
        {
            section = new GLib.Menu ();
            section.append (_("Enter delay mode"), "win.enter-delay-mode");
            section.freeze ();
            menu.append_section (null, section);
        }

        menu.freeze ();
        info_button.set_menu_model ((MenuModel) menu);
    }

    private void reset ()
    {
        registry_view.reset (false);
    }

    private void reset_recursively ()
    {
        registry_view.reset (true);
    }

    private void enter_delay_mode ()
    {
        registry_view.enter_delay_mode ();
    }

    /*\
    * * Other callbacks
    \*/

    [GtkCallback]
    private bool on_key_press_event (Widget widget, Gdk.EventKey event)     // TODO better?
    {
        string name = Gdk.keyval_name (event.keyval) ?? "";

        if ((event.state & Gdk.ModifierType.CONTROL_MASK) != 0)
        {
            switch (name)
            {
                case "b":
                    if (info_button.active)
                        info_button.active = false;
                    registry_view.discard_row_popover ();
                    bookmarks_button.clicked ();
                    return true;
                case "d":
                    if (info_button.active)
                        info_button.active = false;
                    registry_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (true);
                    return true;
                case "D":
                    if (info_button.active)
                        info_button.active = false;
                    registry_view.discard_row_popover ();
                    bookmarks_button.set_bookmarked (false);
                    return true;
                case "f":
                    if (bookmarks_button.active)
                        bookmarks_button.active = false;
                    if (info_button.active)
                        info_button.active = false;
                    registry_view.discard_row_popover ();
                    registry_view.set_search_mode (null);
                    return true;
                case "c":
                    registry_view.discard_row_popover (); // TODO avoid duplicate get_selected_row () call
                    string? selected_row_text = registry_view.get_selected_row_text ();
                    ConfigurationEditor application = (ConfigurationEditor) get_application ();
                    application.copy (selected_row_text == null ? current_path : (!) selected_row_text);
                    return true;
                case "C":
                    registry_view.discard_row_popover ();
                    ((ConfigurationEditor) get_application ()).copy (current_path);
                    return true;
                case "F1":
                    registry_view.discard_row_popover ();
                    if ((event.state & Gdk.ModifierType.SHIFT_MASK) == 0)
                        return false;   // help overlay
                    ((ConfigurationEditor) get_application ()).about_cb ();
                    return true;
                default:
                    break;  // TODO make <ctrl>v work; https://bugzilla.gnome.org/show_bug.cgi?id=762257 is WONTFIX
            }
        }

        /* don't use "else if", or some widgets will not be hidden on <ctrl>F10 or such things */
        if (name == "F10")
        {
            registry_view.discard_row_popover ();
            if (bookmarks_button.active)
                bookmarks_button.active = false;
            return false;
        }
        else if (name == "Menu")
        {
            if (registry_view.show_row_popover ())
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                if (info_button.active)
                    info_button.active = false;
            }
            else if (info_button.active == false)
            {
                if (bookmarks_button.active)
                    bookmarks_button.active = false;
                info_button.active = true;
            }
            else
                info_button.active = false;
            return true;
        }

        if (bookmarks_button.active || info_button.active)      // TODO open bug about modal popovers and search_bar
            return false;

        return registry_view.handle_search_event (event);
    }

    [GtkCallback]
    private void on_menu_button_clicked ()
    {
        registry_view.discard_row_popover ();
        registry_view.set_search_mode (false);
    }

    /*\
    * * Non-existant path notifications
    \*/

    public void show_notification (string notification)
    {
        notification_label.set_text (notification);
        notification_revealer.set_reveal_child (true);
    }

    [GtkCallback]
    private void hide_notification ()
    {
        notification_revealer.set_reveal_child (false);
    }
}
