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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/notifications-revealer.ui")]
private class NotificationsRevealer : Revealer, AdaptativeWidget
{
    [GtkChild] private unowned Label notification_label;

    construct
    {
        install_action_entries ();
    }

    /*\
    * * internal calls
    \*/

    internal void show_notification (string notification)
    {
        notification_label.set_text (notification);
        set_reveal_child (true);
    }

    private bool is_thin = false;
    private void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        bool _is_thin = AdaptativeWidget.WindowSize.is_quite_thin (new_size);
        if (is_thin == _is_thin)
            return;
        is_thin = _is_thin;

        if (_is_thin)
        {
            hexpand = true;
            halign = Align.FILL;
        }
        else
        {
            hexpand = false;
            halign = Align.CENTER;
        }
    }

    /*\
    * * action entries
    \*/

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("notification", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "hide", hide_notification }
    };

    internal void hide_notification (/* SimpleAction action, Variant? variant */)
    {
        set_reveal_child (false);
    }
}
