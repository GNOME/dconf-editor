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
        { "open-path", open_path, "s" },

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
/*    private ulong theme_changed_handler = 0; */
    private ulong small_keys_list_rows_handler = 0;
    private ulong small_bookmarks_rows_handler = 0;

    public DConfWindow ()
    {
        add_action_entries (action_entries, this);

        behaviour_changed_handler = settings.changed ["behaviour"].connect (registry_view.invalidate_popovers);

        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
        if (settings.get_boolean ("window-is-maximized"))
            maximize ();

        StyleContext context = get_style_context ();
/*        theme_changed_handler = settings.changed ["theme"].connect (() => {
                string theme = settings.get_string ("theme");
                if (theme == "non-symbolic-keys-list")
                {
                    if (!context.has_class ("non-symbolic")) context.add_class ("non-symbolic");
                }
                else if (context.has_class ("non-symbolic")) context.remove_class ("non-symbolic");
            }); */
        small_keys_list_rows_handler = settings.changed ["small-keys-list-rows"].connect (() => {
                if (settings.get_boolean ("small-keys-list-rows"))
                {
                    if (!context.has_class ("small-keys-list-rows")) context.add_class ("small-keys-list-rows");
                }
                else if (context.has_class ("small-keys-list-rows")) context.remove_class ("small-keys-list-rows");
            });
        small_bookmarks_rows_handler = settings.changed ["small-bookmarks-rows"].connect (() => {
                if (settings.get_boolean ("small-bookmarks-rows"))
                {
                    if (!context.has_class ("small-bookmarks-rows")) context.add_class ("small-bookmarks-rows");
                }
                else if (context.has_class ("small-bookmarks-rows")) context.remove_class ("small-bookmarks-rows");
            });
/*        if (settings.get_string ("theme") == "non-symbolic-keys-list")
            context.add_class ("non-symbolic"); */
        if (settings.get_boolean ("small-keys-list-rows"))
            context.add_class ("small-keys-list-rows");
        if (settings.get_boolean ("small-bookmarks-rows"))
            context.add_class ("small-bookmarks-rows");

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

    public static Widget _get_parent (Widget widget)
    {
        Widget? parent = widget.get_parent ();
        if (parent == null)
            assert_not_reached ();
        return (!) parent;
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
        dialog.format_secondary_text (_("Don’t forget that some options may break applications, so be careful."));
        dialog.add_buttons (_("I’ll be careful."), ResponseType.ACCEPT);

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
        int? _window_width = null;
        int? _window_height = null;
        get_size (out _window_width, out _window_height);
        if (_window_width == null || _window_height == null)
            return;
        window_width = (!) _window_width;
        window_height = (!) _window_height;
    }

    [GtkCallback]
    private void on_destroy ()
    {
        ((ConfigurationEditor) get_application ()).clean_copy_notification ();

        settings.disconnect (behaviour_changed_handler);
/*        settings.disconnect (theme_changed_handler); */
        settings.disconnect (small_keys_list_rows_handler);
        settings.disconnect (small_bookmarks_rows_handler);

        settings.delay ();
        settings.set_string ("saved-view", current_path);
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();

        base.destroy ();
    }

    /*\
    * * Path changing
    \*/

    [GtkCallback]
    private void request_path (string full_name)
    {
        registry_view.set_search_mode (false);  // TODO not useful when called from bookmark
        registry_view.path_requested (full_name, pathbar.get_selected_child (full_name));
    }

    public void update_path_elements ()
    {
        bookmarks_button.set_path (current_path);
        pathbar.set_path (current_path);
    }

    public void update_hamburger_menu ()
    {
        GLib.Menu section;

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

    /*\
    * * Action entries
    \*/

    private void open_path (SimpleAction action, Variant? path_variant)
        requires (path_variant != null)
    {
        request_path (((!) path_variant).get_string ());
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
        string name = (!) (Gdk.keyval_name (event.keyval) ?? "");

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
                    string? selected_row_text = registry_view.get_copy_text ();
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

        if (((event.state & Gdk.ModifierType.MOD1_MASK) != 0))
        {
            if (name == "Up")
            {
                if (current_path == "/")
                    return true;
                if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
                    request_path ("/");
                else if (current_path.has_suffix ("/"))
                    request_path (current_path.slice (0, current_path.slice (0, current_path.length - 1).last_index_of_char ('/') + 1));
                else
                    request_path (current_path.slice (0, current_path.last_index_of_char ('/') + 1));
                return true;
            }
            else if (name == "Down")
            {
                if ((event.state & Gdk.ModifierType.SHIFT_MASK) != 0)
                    return pathbar.open_child (null);
                else
                    return pathbar.open_child (current_path);
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

public interface PathElement
{
    public signal void request_path (string path);
}
