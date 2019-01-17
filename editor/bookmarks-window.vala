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

private abstract class BookmarksWindow : BrowserWindow, AdaptativeWidget
{
    private BookmarksHeaderBar  headerbar;
    private BookmarksView       main_view;

    private ulong bookmarks_selection_changed_handler = 0;
    private ulong headerbar_update_bookmarks_icons_handler = 0;
    private ulong main_view_update_bookmarks_icons_handler = 0;

    construct
    {
        headerbar = (BookmarksHeaderBar) nta_headerbar;
        main_view = (BookmarksView) base_view;

        install_bw_action_entries ();
        install_bmk_action_entries ();

        bookmarks_selection_changed_handler = main_view.bookmarks_selection_changed.connect (on_bookmarks_selection_changed);
        headerbar_update_bookmarks_icons_handler = headerbar.update_bookmarks_icons.connect (update_bookmarks_icons_from_variant);
        main_view_update_bookmarks_icons_handler = main_view.update_bookmarks_icons.connect (update_bookmarks_icons_from_variant);
    }

    protected override void before_destroy ()
    {
        base.before_destroy ();

        main_view.disconnect (bookmarks_selection_changed_handler);
        headerbar.disconnect (headerbar_update_bookmarks_icons_handler);
        main_view.disconnect (main_view_update_bookmarks_icons_handler);
    }

    /*\
    * * Main UI action entries
    \*/

    private void install_bw_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (bw_action_entries, this);
        insert_action_group ("bw", action_group);
    }

    private const GLib.ActionEntry [] bw_action_entries =
    {
        // showing or hiding panels
        { "show-in-window-bookmarks", show_use_bookmarks_view },

        // updating bookmarks icons
        { "update-bookmarks-icons", update_bookmarks_icons, "as" },

        // keyboard
        { "toggle-bookmark",    toggle_bookmark     },  // <P>b & <P>B
        { "bookmark",           bookmark            },  // <P>d
        { "unbookmark",         unbookmark          }   // <P>D
    };

    /*\
    * * showing or hiding panels
    \*/

    protected override bool escape_pressed ()
    {
        if (main_view.in_window_bookmarks)
        {
            if (main_view.in_window_bookmarks_edit_mode)
                leave_edit_mode ();
            else
                show_default_view ();
            return true;
        }
        return base.escape_pressed ();
    }

    protected override void show_default_view ()
    {
        if (main_view.in_window_bookmarks)
        {
            if (main_view.in_window_bookmarks_edit_mode)
                leave_edit_mode ();     // TODO place after
            headerbar.show_default_view ();
            main_view.show_default_view ();

            if (current_type == ViewType.CONFIG)
                request_folder (current_path);
        }
        else
            base.show_default_view ();
    }

    private void show_use_bookmarks_view (/* SimpleAction action, Variant? path_variant */)
    {
        close_in_window_panels ();

        headerbar.show_use_bookmarks_view ();
        string [] bookmarks = headerbar.get_bookmarks ();
        main_view.show_bookmarks_view (bookmarks);
        update_bookmarks_icons_from_array (bookmarks);
    }

    /*\
    * * updating bookmarks icons
    \*/

    private void update_bookmarks_icons (SimpleAction action, Variant? bookmarks_variant)
        requires (bookmarks_variant != null)
    {
        update_bookmarks_icons_from_variant ((!) bookmarks_variant);
    }

    private void update_bookmarks_icons_from_variant (Variant variant)
    {
        update_bookmarks_icons_from_array (variant.get_strv ());
    }

    private void update_bookmarks_icons_from_array (string [] bookmarks)
    {
        if (bookmarks.length == 0)
            return;

        foreach (string bookmark in bookmarks)
        {
            if (bookmark.has_prefix ("?"))  // TODO broken search
            {
                update_bookmark_icon (bookmark, BookmarkIcon.SEARCH);
                continue;
            }
            if (BrowserWindow.is_path_invalid (bookmark)) // TODO broken folder and broken object
                continue;

            update_bookmark_icon (bookmark, get_bookmark_icon (ref bookmark));
        }
    }
    protected abstract BookmarkIcon get_bookmark_icon (ref string bookmark);

    private void update_bookmark_icon (string bookmark, BookmarkIcon icon)
    {
        if (disable_popovers)
            main_view.update_bookmark_icon (bookmark, icon);
        else
            headerbar.update_bookmark_icon (bookmark, icon);
    }

    /*\
    * * adaptative stuff
    \*/

    private bool disable_popovers = false;
    protected override void set_window_size (AdaptativeWidget.WindowSize new_size)
    {
        base.set_window_size (new_size);

        bool _disable_popovers = AdaptativeWidget.WindowSize.is_phone_size (new_size)
                              || AdaptativeWidget.WindowSize.is_extra_thin (new_size);
        if (disable_popovers != _disable_popovers)
        {
            disable_popovers = _disable_popovers;
            if (main_view.in_window_bookmarks)
                show_default_view ();
        }
    }

    /*\
    * * keyboard
    \*/

    private void toggle_bookmark (/* SimpleAction action, Variant? variant */)
    {
        main_view.close_popovers ();

        // use popover
        if (!disable_popovers)
        {
            toggle_bookmark_called ();
            headerbar.click_bookmarks_button ();
        }
        // use in-window
        else if (main_view.in_window_bookmarks)
            show_default_view ();
        else
            show_use_bookmarks_view ();
    }
    protected abstract void toggle_bookmark_called ();

    private void bookmark (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        main_view.close_popovers ();
        headerbar.bookmark_current_path ();
    }

    private void unbookmark (/* SimpleAction action, Variant? variant */)
    {
        if (is_in_in_window_mode ())        // TODO better
            return;

        main_view.close_popovers ();
        headerbar.unbookmark_current_path ();
    }

    /*\
    * * keyboard calls helpers
    \*/

    protected override bool intercept_next_match (out bool interception_result)
    {
        if (headerbar.has_popover ())                   // for bookmarks popover
        {
            interception_result = headerbar.next_match ();
            return true;
        }
        return base.intercept_next_match (out interception_result);
    }

    protected override bool intercept_previous_match (out bool interception_result)
    {
        if (headerbar.has_popover ())                   // for bookmarks popover
        {
            interception_result = headerbar.previous_match ();
            return true;
        }
        return base.intercept_previous_match (out interception_result);
    }

    /*\
    * * bookmarks action entries
    \*/

    bool actions_init_done = false;
    private SimpleAction move_top_action;
    private SimpleAction move_up_action;
    private SimpleAction move_down_action;
    private SimpleAction move_bottom_action;
    private SimpleAction trash_bookmark_action;
    private SimpleAction edit_mode_state_action;

    private void update_actions ()
        requires (actions_init_done)
    {
        Bookmarks._update_actions (main_view.get_bookmarks_selection_state (), ref move_top_action, ref move_up_action, ref move_down_action, ref move_bottom_action, ref trash_bookmark_action);
    }

    private void install_bmk_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (bmk_action_entries, this);
        insert_action_group ("bmk", action_group);

        move_top_action         = (SimpleAction) action_group.lookup_action ("move-top");
        move_up_action          = (SimpleAction) action_group.lookup_action ("move-up");
        move_down_action        = (SimpleAction) action_group.lookup_action ("move-down");
        move_bottom_action      = (SimpleAction) action_group.lookup_action ("move-bottom");
        trash_bookmark_action   = (SimpleAction) action_group.lookup_action ("trash-bookmark");
        edit_mode_state_action  = (SimpleAction) action_group.lookup_action ("set-edit-mode");
        actions_init_done = true;
    }

    private const GLib.ActionEntry [] bmk_action_entries =
    {
        { "set-edit-mode", set_edit_mode, "b", "false" },

        { "trash-bookmark", trash_bookmark },

        { "move-top",    move_top    },
        { "move-up",     move_up     },
        { "move-down",   move_down   },
        { "move-bottom", move_bottom }
    };

    private void set_edit_mode (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        bool new_state = ((!) variant).get_boolean ();
        action.set_state (new_state);

        if (new_state)
            enter_edit_mode ();
        else
            leave_edit_mode ();
    }

    private void enter_edit_mode ()
    {
        // edit_mode_state_action.change_state (true);

        update_actions ();

        headerbar.show_edit_bookmarks_view ();
        main_view.enter_bookmarks_edit_mode ();
    }

    private void leave_edit_mode ()
    {
        edit_mode_state_action.set_state (false);

        bool give_focus_to_info_button = main_view.leave_bookmarks_edit_mode ();
        headerbar.show_use_bookmarks_view ();

/*        if (give_focus_to_info_button)
            info_button.grab_focus (); */
    }

    private void trash_bookmark (/* SimpleAction action, Variant? variant */)
    {
        main_view.trash_bookmark ();
//        update_bookmarks_icons_from_array (new_bookmarks);
    }

    private void move_top       (/* SimpleAction action, Variant? variant */)
    {
        main_view.move_top ();
    }

    private void move_up        (/* SimpleAction action, Variant? variant */)
    {
        main_view.move_up ();
    }

    private void move_down      (/* SimpleAction action, Variant? variant */)
    {
        main_view.move_down ();
    }

    private void move_bottom    (/* SimpleAction action, Variant? variant */)
    {
        main_view.move_bottom ();
    }

    private void on_bookmarks_selection_changed ()
    {
        update_actions ();
    }
}
