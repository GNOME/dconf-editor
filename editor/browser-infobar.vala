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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/browser-infobar.ui")]
private class BrowserInfoBar : Box
{
    [GtkChild] private unowned Revealer revealer;
    [GtkChild] private unowned Stack content;

    public bool reveal_child {get; set; default = false; }

    construct
    {
        bind_property ("reveal-child", revealer, "reveal-child", BindingFlags.SYNC_CREATE);
    }

    internal void add_label (string name, string text_label, string? button_label = null, string button_action = "")
    {
        RegistryWarning grid = new RegistryWarning ();

        Label label = new Label (text_label);
        label.hexpand = true;
        label.max_width_chars = 40;
        label.wrap = true;

        if (button_label != null)
        {
            if (button_action == "")
                assert_not_reached ();

            Button button = new Button ();
            button.label = (!) button_label;
            button.set_detailed_action_name (button_action);

            label.set_xalign ((float) 0.0);
            grid.attach (label, 0, 0, 1, 1);
            grid.attach (button, 1, 0, 1, 1);
        }
        else
        {
            label.set_xalign ((float) 0.5);
            grid.attach (label, 0, 0, 1, 1);
        }

        // grid.show ();
        content.add_named (grid, name);
    }

    // public void set_reveal_child (bool _value)
    // {
    //     reveal_child = _value;
    // }

    // public bool get_reveal_child ()
    // {
    //     return reveal_child;
    // }

    internal void hide_warning ()
    {
        reveal_child = false;
    }

    internal bool is_shown (string name)
    {
        return revealer.get_child_revealed () && (content.get_visible_child_name () == name);
    }

    internal void show_warning (string name)
    {
        if (!revealer.get_child_revealed ())
        {
            content.set_transition_type (StackTransitionType.NONE);
            content.set_visible_child_name (name);
            revealer.set_reveal_child (true);
        }
        else if (content.get_visible_child_name () != name)
        {
            content.set_transition_type (StackTransitionType.SLIDE_DOWN);
            content.set_visible_child_name (name);
        }
    }
}
