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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/large-pathbar.ui")]
private class LargePathbar : Box, Pathbar
{
    [GtkChild] private unowned LargePathbarItem root_button;
    private LargePathbarItem active_button;

    private string complete_path = "";
    internal void get_complete_path (out string _complete_path)
    {
        _complete_path = complete_path;
    }
    private string fallback_path = "";
    internal void get_fallback_path_and_complete_path (out string _fallback_path, out string _complete_path)
    {
        if (fallback_path != "" && ModelUtils.is_folder_path (fallback_path) && complete_path.has_prefix (fallback_path))
            _fallback_path = fallback_path;
        else
            _fallback_path = complete_path;

        _complete_path = complete_path;
    }

    construct
    {
        active_button = root_button;
        add_slash_label ();
    }

    internal LargePathbar (string complete_path_or_empty, ViewType type, string path)
    {
        if (complete_path_or_empty != "")
        {
            complete_path = complete_path_or_empty;
            _set_path (ModelUtils.is_folder_path (complete_path_or_empty) ? ViewType.FOLDER : ViewType.OBJECT, complete_path_or_empty);
        }
        set_path (type, path);
    }

    /*\
    * * keyboard
    \*/

    internal bool has_popover ()
    {
        return active_button.has_popover ();
    }

    internal void close_menu ()
    {
        active_button.close_menu ();
    }

    internal void toggle_menu ()
    {
        active_button.toggle_menu ();
    }

    /*\
    * * main public calls
    \*/

    internal void set_path (ViewType type, string path)
    {
        if (type == ViewType.SEARCH)
            return;

        _set_path (type, path);
        update_active_button_cursor (type, ref active_button);
    }
    private void _set_path (ViewType type, string path)
    {
        update_config_style_class (type == ViewType.CONFIG, get_style_context ());  // TODO create gtk_style_context_toggle_class()

        activate_item (root_button, path == "/");

        complete_path = "";
        string [] split = path.split ("/", /* max tokens disabled */ 0);
        string last = split [split.length - 1];

        bool destroy_all = false;
        bool maintain_all = false;
        @foreach ((child) => {

                if (child is Label)
                {
                    if (destroy_all)
                        child.destroy ();
                    else
                        complete_path += "/";
                    return;
                }

                LargePathbarItem item = (LargePathbarItem) child;

                if (maintain_all)
                {
                    complete_path += item.text_string;
                    activate_item (item, false);
                    return;
                }

                if (item == root_button || (!destroy_all && item.text_string == split [0]))
                {
                    complete_path += split [0];
                    split = split [1:split.length];
                    if (split.length == 0 || (split.length == 1 && (type == ViewType.FOLDER || type == ViewType.CONFIG)))
                    {
                        activate_item (item, true);
                        maintain_all = true;
                    }
                    else
                        activate_item (item, false);
                    return;
                }

                child.destroy ();
                destroy_all = true;
            });

        if (split.length > 0)
        {
            /* add one item per folder */
            if (split.length > 1)
            {
                uint index = 0;
                foreach (string item in split [0:split.length - 1])
                {
                    complete_path += item + "/";
                    add_path_bar_item (item, complete_path, true, (type == ViewType.FOLDER || type == ViewType.CONFIG) && (index == split.length - 2));
                    add_slash_label ();
                    index++;
                }
            }

            /* if key path */
            if (type == ViewType.OBJECT)
            {
                complete_path += last;
                add_path_bar_item (last, complete_path, false, true);
            }
        }

        @foreach ((child) => child.show ());
    }
    private static inline void update_config_style_class (bool type_is_config, StyleContext context)
    {
        if (type_is_config)
            context.add_class ("config");
        else
            context.remove_class ("config");
    }

    internal void update_ghosts (string non_ghost_path, bool is_search)
    {
        fallback_path = non_ghost_path;
        string action_target = "";
        @foreach ((child) => {
                StyleContext context = child.get_style_context ();
                if (child is LargePathbarItem)
                {
                    LargePathbarItem item = (LargePathbarItem) child;
                    Variant? variant = item.get_action_target_value ();
                    if (variant == null)
                        assert_not_reached ();
                    if (((!) variant).get_type_string () == "s")    // directory
                        action_target = ((!) variant).get_string ();
                    else
                    {
                        uint16 unused;
                        ((!) variant).@get ("(sq)", out action_target, out unused);
                    }

                    if (item.is_active)
                    {
                        if (is_search)
                        {
                            item.set_cursor_type (LargePathbarItem.CursorType.POINTER);
                            item.set_detailed_action_name (item.default_action);
                        }
                        else
                        {
                            item.set_cursor_type (LargePathbarItem.CursorType.CONTEXT);
                            item.set_action_name ("browser.empty");
                        }
                        if (non_ghost_path.has_prefix (action_target))
                            context.remove_class ("inexistent");
                        else
                            context.add_class ("inexistent");
                    }
                    else if (non_ghost_path.has_prefix (action_target))
                    {
                        item.set_cursor_type (LargePathbarItem.CursorType.POINTER);
                        item.set_detailed_action_name (item.default_action);
                        context.remove_class ("inexistent");
                    }
                    else
                    {
                        item.set_cursor_type (LargePathbarItem.CursorType.DEFAULT);
                        item.set_detailed_action_name (item.alternative_action);
                        context.add_class ("inexistent");
                    }
                }
                else if (non_ghost_path.has_prefix (action_target))
                    context.remove_class ("inexistent");
                else
                    context.add_class ("inexistent");
            });
    }

    private static inline void update_active_button_cursor (ViewType type, ref LargePathbarItem active_button)
    {
        if (type == ViewType.CONFIG)
        {
            active_button.set_cursor_type (LargePathbarItem.CursorType.POINTER);
            active_button.set_detailed_action_name (active_button.default_action);
        }
        else
        {
            active_button.set_cursor_type (LargePathbarItem.CursorType.CONTEXT);
            active_button.set_action_name ("browser.empty");
        }
    }

    /*\
    * * widgets management
    \*/

    private void add_slash_label ()
    {
        add (new Label ("/"));
    }

    private void add_path_bar_item (string label, string complete_path, bool is_folder, bool block)
    {
        LargePathbarItem path_bar_item = create_path_bar_item (label, complete_path, is_folder);
        add (path_bar_item);
        activate_item (path_bar_item, block);   // has to be after add()
    }
    private static inline LargePathbarItem create_path_bar_item (string label, string complete_path, bool is_folder)
    {
        LargePathbarItem path_bar_item;
        if (is_folder)
            init_folder_path_bar_item (label, complete_path, out path_bar_item);
        else
            init_object_path_bar_item (label, complete_path, out path_bar_item);
        return path_bar_item;
    }
    private static inline void init_folder_path_bar_item (string label, string complete_path, out LargePathbarItem path_bar_item)
    {
        Variant variant = new Variant.string (complete_path);
        string _variant = variant.print (false);
        path_bar_item = new LargePathbarItem (label, "browser.open-folder(" + _variant + ")", "ui.notify-folder-emptied(" + _variant + ")", true);
    }
    private static inline void init_object_path_bar_item (string label, string complete_path, out LargePathbarItem path_bar_item)
    {
        Variant variant = new Variant ("(sq)", complete_path, ModelUtils.undefined_context_id);
        string _variant = variant.print (true);
        path_bar_item = new LargePathbarItem (label, "browser.open-object(" + _variant + ")", "ui.notify-object-deleted(" + _variant + ")", false);
    }

    private void activate_item (LargePathbarItem item, bool state)   // never called when current_view is search
    {
        if (state)
            active_button = item;
        _activate_item (item, state);
    }
    private static inline void _activate_item (LargePathbarItem item, bool state)
    {
        if (state == item.is_active)
            return;
        if (state)
        {
            item.is_active = true;
            item.set_cursor_type (LargePathbarItem.CursorType.CONTEXT);
            item.set_action_name ("browser.empty");
            item.get_style_context ().add_class ("active");
        }
        else
        {
            item.is_active = false;
            item.set_cursor_type (LargePathbarItem.CursorType.POINTER);
            item.set_detailed_action_name (item.default_action);
            item.get_style_context ().remove_class ("active");
        }
    }
}

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/large-pathbar-item.ui")]
private class LargePathbarItem : Button
{
    [CCode (notify = false)] public bool is_active { internal get; internal set; default = false; }

    [CCode (notify = false)] public string alternative_action { internal get; internal construct; }
    [CCode (notify = false)] public string default_action     { internal get; internal construct; }
    [CCode (notify = false)] public string text_string        { internal get; internal construct; }
    [CCode (notify = false)] public bool   has_config_menu    { private get;  internal construct; }

    [GtkChild] private unowned Label text_label;
    private Popover? popover = null;

    internal enum CursorType {
        DEFAULT,
        POINTER,
        CONTEXT
    }
    private CursorType cursor_type = CursorType.POINTER;

    private bool hover = false; // there’s probably a function for that

    construct
    {
        enter_notify_event.connect (() => { hover = true;  set_new_cursor_type (cursor_type); });
        leave_notify_event.connect (() => { hover = false; set_new_cursor_type (CursorType.DEFAULT); });
    }

    internal void set_cursor_type (CursorType cursor_type)
    {
        this.cursor_type = cursor_type;
        if (hover)
            set_new_cursor_type (cursor_type);
    }

    private void set_new_cursor_type (CursorType new_cursor_type)
    {
        Gdk.Window? gdk_window = get_window ();
        Gdk.Display? display = Gdk.Display.get_default ();
        if (gdk_window == null || display == null)
            return;

        Gdk.Cursor? cursor = null;
        switch (new_cursor_type)
        {
            case CursorType.DEFAULT: cursor = null; break;
            case CursorType.POINTER: cursor = new Gdk.Cursor.from_name ((!) display, "pointer"); break;
            case CursorType.CONTEXT: cursor = new Gdk.Cursor.from_name ((!) display, "context-menu"); break;
        }
        ((!) gdk_window).set_cursor (cursor);
    }

    [GtkCallback]
    private void update_cursor ()
    {
        StyleContext context = get_style_context ();
        if (context.has_class ("inexistent") && !context.has_class ("active"))  // TODO use is_active when sanitized
            return;

        if (cursor_type != CursorType.CONTEXT)
        {
            cursor_type = CursorType.CONTEXT;
            set_new_cursor_type (cursor_type);
            return;
        }

        generate_popover ();
        ((!) popover).popup ();
    }

    internal LargePathbarItem (string label, string _default_action, string _alternative_action, bool _has_config_menu)
    {
        Object (text_string: label, default_action: _default_action, alternative_action: _alternative_action, has_config_menu: _has_config_menu);
        text_label.set_text (label);
        set_detailed_action_name (_default_action);
    }

    internal bool has_popover ()
    {
        return popover != null && ((!) popover).get_mapped ();
    }

    internal void close_menu ()
    {
        if (has_popover ())
            ((!) popover).popdown ();
    }

    internal void toggle_menu ()
    {
        if (popover == null)
            generate_popover ();

        if (((!) popover).get_mapped ())
            ((!) popover).popdown ();
        else
            ((!) popover).popup ();
    }

    private void generate_popover ()
    {
        GLib.Menu menu = new GLib.Menu ();
        Pathbar.populate_pathbar_menu (/* is folder */ has_config_menu, ref menu);
        menu.freeze ();

        popover = new Popover.from_model (this, (MenuModel) menu);
    }
}
