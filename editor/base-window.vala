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
        { "show-default-view",  show_default_view },
        { "about",              about }
    };

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
        base_view.show_in_window_about ();
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

    [GtkChild] private Overlay main_overlay;

    private bool notifications_revealer_created = false;
    private NotificationsRevealer notifications_revealer;

    private void create_notifications_revealer ()
    {
        notifications_revealer = new NotificationsRevealer ();
        add_adaptative_child (notifications_revealer);
        notifications_revealer.set_window_size (window_size);
        notifications_revealer.show ();
        main_overlay.add_overlay (notifications_revealer);
        notifications_revealer_created = true;
    }

    protected void show_notification (string notification)
    {
        if (!notifications_revealer_created)
            create_notifications_revealer ();

        notifications_revealer.show_notification (notification);
    }

    protected void hide_notification ()
    {
        if (!notifications_revealer_created)
            return;

        notifications_revealer.hide_notification ();
    }
}
