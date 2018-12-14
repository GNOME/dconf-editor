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
    [GtkChild] protected Grid current_child_grid;

    internal virtual string? get_copy_text ()
    {
        if (in_window_about)
            return about_list.get_copy_text (); // TODO copying logo...
        return null;
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
    }

    /*\
    * * in-window modes
    \*/

    internal virtual void show_default_view ()
    {
        if (in_window_about)
        {
            in_window_about = false;
            set_visible_child (current_child_grid);
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

    private void create_about_list ()
    {
        about_list = new AboutList (/* needs shadows   */ false,
                                    /* big placeholder */ true);
        about_list.set_window_size (saved_window_size);
        about_list.show ();
        add (about_list);
        about_list_created = true;
    }

    internal void show_in_window_about ()
        requires (in_window_about == false)
    {
        if (about_list_created)
            about_list.reset ();
        else
            create_about_list ();

        set_visible_child (about_list);
        in_window_about = true;
    }
}
