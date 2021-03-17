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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-placeholder.ui")]
private class RegistryPlaceholder : Grid
{
    [GtkChild] private unowned Label placeholder_label;
    [GtkChild] private unowned Image placeholder_image;

    [CCode (notify = false)] public string label     { internal construct set { placeholder_label.label = value; }}
    [CCode (notify = false)] public string icon_name { private get; internal construct; }
    [CCode (notify = false)] public bool big
    {
        internal construct set
        {
            if (value)
            {
                placeholder_image.pixel_size = 72;
                get_style_context ().add_class ("big-popover");
            }
            else
            {
                placeholder_image.pixel_size = 36;
                get_style_context ().remove_class ("big-popover");
            }
        }
    }

    construct
    {
        placeholder_image.icon_name = icon_name;
    }

    internal RegistryPlaceholder (string _icon_name, string _label, bool _big)
    {
        Object (icon_name:_icon_name, label: _label, big: _big);
    }
}
