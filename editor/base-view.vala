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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/base-view.ui")]
private class BaseView : Stack, AdaptativeWidget
{
    [GtkChild] protected unowned Grid main_grid;

    internal virtual bool handle_copy_text (out string copy_text)
    {
        if (in_window_about)
            return about_list.handle_copy_text (out copy_text); // TODO copying logo...
        else
            return BaseWindow.no_copy_text (out copy_text);
    }

    internal virtual void close_popovers () {}

    /*\
    * * adaptative stuff
    \*/

    protected AdaptativeWidget.WindowSize saved_window_size { protected get; private set; default = AdaptativeWidget.WindowSize.START_SIZE; }
    protected virtual void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        saved_window_size = new_size;
        if (about_list_created)
            about_list.set_window_size (new_size);
        if (notifications_revealer_created)
            notifications_revealer.set_window_size (new_size);
    }

    /*\
    * * in-window modes
    \*/

    internal virtual void show_default_view ()
    {
        if (in_window_about)
        {
            in_window_about = false;
            set_visible_child (notifications_overlay);   // or set_visible_child_name ("main-view");
        }
        else
            assert_not_reached ();
    }

    internal virtual bool is_in_in_window_mode ()
    {
        return in_window_about;
    }

    /*\
    * * in-window about
    \*/

    protected bool in_window_about { protected get; private set; default = false; }

    private bool about_list_created = false;
    private AboutList about_list;

    internal void create_about_list (ref string [] artists,
                                     ref string [] authors,
                                     ref string    comments,
                                     ref string    copyright,
                                     ref string [] documenters,
                                     ref string    logo_icon_name,
                                     ref string    program_name,
                                     ref string    translator_credits,
                                     ref string    version,
                                     ref string    website,
                                     ref string    website_label)
    {
        about_list = new AboutList (/* needs shadows   */ false,
                                    /* big placeholder */ true,
                                    ref artists, ref authors, ref comments, ref copyright, ref documenters, ref logo_icon_name, ref program_name, ref translator_credits, ref version, ref website, ref website_label);
        about_list.set_window_size (saved_window_size);
        about_list.show ();
        add (about_list);
        about_list_created = true;
    }

    internal void show_about_view ()
        requires (about_list_created == true)
        requires (in_window_about == false)
    {
        about_list.reset ();
        set_visible_child (about_list);
        in_window_about = true;
    }

    /*\
    * * notifications
    \*/

    [GtkChild] private unowned Overlay notifications_overlay;

    private bool notifications_revealer_created = false;
    private NotificationsRevealer notifications_revealer;

    private void create_notifications_revealer ()
    {
        notifications_revealer = new NotificationsRevealer ();
        notifications_revealer.set_window_size (saved_window_size);
        notifications_revealer.show ();
        notifications_overlay.add_overlay (notifications_revealer);
        notifications_overlay.set_overlay_pass_through (notifications_revealer, true);
        notifications_revealer_created = true;
    }

    internal void show_notification (string notification)
    {
        if (!notifications_revealer_created)
            create_notifications_revealer ();

        notifications_revealer.show_notification (notification);
    }

    internal void hide_notification ()
    {
        if (!notifications_revealer_created)
            return;

        notifications_revealer.hide_notification ();
    }
}
