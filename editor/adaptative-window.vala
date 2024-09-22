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

private interface AdaptativeWidget : Object
{
}

private const int LARGE_WINDOW_SIZE = 1042;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/adaptative-window.ui")]
private abstract class AdaptativeWindow : Adw.ApplicationWindow
{
    private BaseHeaderBar headerbar;
    [CCode (notify = false)] public BaseHeaderBar nta_headerbar
    {
        protected get { return headerbar; }
        protected construct
        {
            BaseHeaderBar? _value = value;
            if (_value == null)
                assert_not_reached ();

            headerbar = value;
        }
    }

    [CCode (notify = false)] public string window_title
    {
        protected construct
        {
            string? _value = value;
            if (_value == null)
                assert_not_reached ();

            title = value;
        }
    }

    private StyleContext window_style_context;
    [CCode (notify = false)] public string specific_css_class_or_empty
    {
        protected construct
        {
            string? _value = value;
            if (_value == null)
                assert_not_reached ();

            window_style_context = get_style_context ();
            if (value != "")
                window_style_context.add_class (value);
        }
    }

    construct
    {
        // window_style_context is created by specific_css_class_or_empty
        window_style_context.add_class ("startup");

        manage_high_contrast ();

        load_window_state ();

        Timeout.add (300, () => { window_style_context.remove_class ("startup"); return Source.REMOVE; });
    }

    /*\
    * * callbacks
    \*/

    // [GtkCallback]
    // private bool on_window_state_event (Widget widget, Gdk.EventWindowState event)
    // {
    //     if ((event.changed_mask & Gdk.WindowState.MAXIMIZED) != 0)
    //         window_is_maximized = (event.new_window_state & Gdk.WindowState.MAXIMIZED) != 0;

    //     /* We don’t save this state, but track it for saving size allocation */
    //     Gdk.WindowState tiled_state = Gdk.WindowState.TILED
    //                                 | Gdk.WindowState.TOP_TILED
    //                                 | Gdk.WindowState.BOTTOM_TILED
    //                                 | Gdk.WindowState.LEFT_TILED
    //                                 | Gdk.WindowState.RIGHT_TILED;
    //     if ((event.changed_mask & tiled_state) != 0)
    //         window_is_tiled = (event.new_window_state & tiled_state) != 0;

    //     return false;
    // }

    // [GtkCallback]
    // private void on_size_allocate (Allocation allocation)
    // {
    //     int height = allocation.height;
    //     int width = allocation.width;

    //     update_adaptative_children (ref width, ref height);
    //     update_window_state ();
    // }

    // [GtkCallback]
    // private void on_destroy ()
    // {
    //     before_destroy ();
    //     save_window_state ();
    //     base.destroy ();
    // }

    protected virtual void before_destroy () {}

    /*\
    * * adaptative stuff
    \*/

    // private AdaptativeWidget.WindowSize window_size = AdaptativeWidget.WindowSize.START_SIZE;

    private List<AdaptativeWidget> adaptative_children = new List<AdaptativeWidget> ();
    protected void add_adaptative_child (AdaptativeWidget child)
    {
        adaptative_children.append (child);
    }

    [CCode (notify = false)] public string schema_path
    {
        protected construct
        {
            string? _value = value;
            if (_value == null)
                assert_not_reached ();

            settings = new GLib.Settings.with_path ("ca.desrt.dconf-editor.Lib", value);
        }
    }
    private GLib.Settings settings;

    private int window_width = 0;
    private int window_height = 0;
    private bool window_is_maximized = false;
    private bool window_is_tiled = false;

    private void load_window_state ()   // called on construct
    {
        if (settings.get_boolean ("window-is-maximized"))
            maximize ();
        set_default_size (settings.get_int ("window-width"), settings.get_int ("window-height"));
    }

    private void update_window_state () // called on size-allocate
    {
        if (window_is_maximized || window_is_tiled)
            return;
        int? _window_width = null;
        int? _window_height = null;
        // FIXME: Why are we even doing this?
        get_default_size (out _window_width, out _window_height);
        if (_window_width == null || _window_height == null)
            return;
        window_width = (!) _window_width;
        window_height = (!) _window_height;
    }

    private void save_window_state ()   // called on destroy
    {
        settings.delay ();
        settings.set_int ("window-width", window_width);
        settings.set_int ("window-height", window_height);
        settings.set_boolean ("window-is-maximized", window_is_maximized);
        settings.apply ();
    }

    /*\
    * * manage high-constrast
    \*/

    internal signal void gtk_theme_changed ();

    private void manage_high_contrast ()
    {
        Gtk.Settings? nullable_gtk_settings = Gtk.Settings.get_default ();
        if (nullable_gtk_settings == null)
            return;

        Gtk.Settings gtk_settings = (!) nullable_gtk_settings;
        gtk_settings.notify ["gtk-theme-name"].connect (update_highcontrast_state);
        _update_highcontrast_state (gtk_settings.gtk_theme_name);
    }

    private void update_highcontrast_state (Object gtk_settings, ParamSpec unused)
    {
        _update_highcontrast_state (((Gtk.Settings) gtk_settings).gtk_theme_name);
        gtk_theme_changed ();
    }

    private bool highcontrast_state = false;
    private void _update_highcontrast_state (string theme_name)
    {
        bool highcontrast_new_state = "HighContrast" in theme_name;
        if (highcontrast_new_state == highcontrast_state)
            return;
        highcontrast_state = highcontrast_new_state;
        headerbar.update_hamburger_menu ();

        if (highcontrast_new_state)
            window_style_context.add_class ("hc-theme");
        else
            window_style_context.remove_class ("hc-theme");
    }
}
