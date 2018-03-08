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
class RegistryPlaceholder : Grid
{
    [GtkChild] private Label placeholder_label;
    [GtkChild] private Image placeholder_image;

    public string label { construct set { placeholder_label.label = value; }}
    public string icon_name { private get; construct; }
    public bool big { private get; construct; default = false; }

    construct
    {
        if (big)
        {
            placeholder_image.pixel_size = 72;
            get_style_context ().add_class ("big-popover");
        }
        else
            placeholder_image.pixel_size = 36;

        placeholder_image.icon_name = icon_name;
    }
}
