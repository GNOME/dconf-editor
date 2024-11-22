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

/* FIXME: This widget is essentially a quick and dirty AdwStatusPage without a
 *        scrolled window. As soon as libadwaita provides such a widget, replace
 *        all uses of this widget with that one.
 *        <https://gitlab.gnome.org/GNOME/libadwaita/-/issues/852> */

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/registry-placeholder.ui")]
private class RegistryPlaceholder : Adw.Bin
{
    [GtkChild] private unowned Label title_label;

    public string icon_name { get; set; }
    public string title { get; set; }
    public string description { get; set; }
    public bool compact { get; set; }
    protected int icon_pixel_size {
        get {
            return compact ? 36 : 72;
        }
    }
    protected string title_css_class {
        get {
            return compact ? "title-2" : "title-1";
        }
    }

    construct
    {
        notify["compact"].connect (
            () => {
                notify_property ("icon-pixel-size");
                notify_property ("title-css-class");
            }
        );
        notify["title-css-class"].connect (update_title_css_class);

        update_title_css_class ();
    }

    private void update_title_css_class ()
    {
        title_label.remove_css_class ("title-1");
        title_label.remove_css_class ("title-2");
        title_label.add_css_class (title_css_class);
    }
}
