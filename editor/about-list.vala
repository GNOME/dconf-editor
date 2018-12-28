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

private class AboutList : OverlayedList
{
    construct
    {
        install_action_entries ();

        main_list_box.selection_mode = SelectionMode.NONE;
        get_style_context ().add_class ("about-list");

        /* Translators: on really small windows, the about dialog is replaced by an in-window view; here are the two buttons that have the same role as the stack switcher in the usual about dialog */
        first_mode_name = _("About"); second_mode_name = _("Credits");
        change_editability (true);

        show_apropos (ref main_list_store);
    }

    internal AboutList (bool needs_shadows, bool big_placeholder)
    {
        Object (needs_shadows           : needs_shadows,
                big_placeholder         : big_placeholder,
                edit_mode_action_prefix : "about");
    }

    internal override void reset ()
    {
        edit_mode_action.set_state (false);
        show_apropos (ref main_list_store);
        scroll_top ();
    }

    /*\
    * * Action entries
    \*/

    SimpleAction edit_mode_action;

    private void install_action_entries ()
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("about", action_group);

        edit_mode_action = (SimpleAction) action_group.lookup_action ("set-edit-mode");
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "set-edit-mode", set_edit_mode, "b", "false" }
    };

    private void set_edit_mode (SimpleAction action, Variant? variant)
        requires (variant != null)
    {
        bool new_state = ((!) variant).get_boolean ();
        action.set_state (new_state);

        if (new_state)
            show_credits (ref main_list_store);
        else
            show_apropos (ref main_list_store);
    }

    private static inline void show_apropos (ref GLib.ListStore main_list_store)
    {
        main_list_store.remove_all ();
        main_list_store.append (new AboutListItem.from_icon_name    (AboutDialogInfos.logo_icon_name, AboutDialogInfos.program_name));
        AboutListItem program = new AboutListItem.from_label        (AboutDialogInfos.program_name, "bold-label");
        main_list_store.append (program);
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.version));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.comments));
        main_list_store.append (new AboutListItem.from_link         (AboutDialogInfos.website,
                                                                     AboutDialogInfos.website_label));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.copyright, "small-label"));

        if (AboutDialogInfos.license_type != License.GPL_3_0)   // TODO support all licenses type
            assert_not_reached ();

        /* Translators: on really small windows, the about dialog is replaced by an in-window view; here is the label of the link to the GPL license; TODO better text, as in the usual about dialog */
        main_list_store.append (new AboutListItem.from_link         ("https://www.gnu.org/licenses/gpl-3.0.html", _("GNU General Public License\nversion 3 or later")));

        program.grab_focus ();
    }

    private static inline void show_credits (ref GLib.ListStore main_list_store)
    {
        main_list_store.remove_all ();
        main_list_store.append (new AboutListItem.from_icon_name    (AboutDialogInfos.logo_icon_name, AboutDialogInfos.program_name));
        AboutListItem program = new AboutListItem.from_label        (AboutDialogInfos.program_name, "bold-label");
        main_list_store.append (program);

        string authors = "";
        uint position = 0;
        uint max_position = AboutDialogInfos.authors.length - 1;
        foreach (string author in AboutDialogInfos.authors)
        {
            authors += author;
            if (position < max_position)
                authors += "\n";
            position++;
        }
        /* Translators: on really small windows, the about dialog is replaced by an in-window view; here is the header of the programmers names */
        main_list_store.append (new AboutListItem.with_title        (authors, _("Creators")));


        /* Translators: on really small windows, the about dialog is replaced by an in-window view; here is the header of the translators names */
        main_list_store.append (new AboutListItem.with_title        (AboutDialogInfos.translator_credits, _("Translators")));

        program.grab_focus ();
    }
}

private class AboutListItem : OverlayedListRow
{
    [CCode (notify = false)] public string copy_text { internal get; construct; default = ""; }

    internal override bool handle_copy_text (out string text)
    {
        text = copy_text;
        return true;
    }

    internal AboutListItem.from_label (string text, string? css_class = null)
    {
        Object (copy_text: text);

        Label label = new Label (text);
        label.visible = true;
        label.hexpand = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.justify = Justification.CENTER;
        label.selectable = true;
        label.can_focus = false;
        if (css_class != null)
            label.get_style_context ().add_class ((!) css_class);
        add (label);
    }

    internal AboutListItem.from_icon_name (string icon_name, string copy_text)
    {
        Object (copy_text: copy_text);

        Image image = new Image.from_icon_name (icon_name, IconSize.DIALOG);
        image.pixel_size = 128;
        image.visible = true;
        image.hexpand = true;
        add (image);
    }

    internal AboutListItem.from_link (string link, string text) // TODO do not allow button focus, and activate it on row activation
    {
        Object (copy_text: link);

        LinkButton button = new LinkButton.with_label (link, text);
        button.visible = true;
        button.hexpand = true;

        Widget? widget = button.get_child ();
        if (widget == null || !(((!) widget) is Label))
            assert_not_reached ();
        Label label = (Label) (!) widget;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.justify = Justification.CENTER;

        add (button);
    }

    internal AboutListItem.with_title (string text, string title)
    {
        Object (copy_text: text);

        Grid grid = new Grid ();
        grid.orientation = Orientation.VERTICAL;
        grid.visible = true;
        add (grid);

        Label label = new Label (title);
        label.visible = true;
        label.hexpand = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.get_style_context ().add_class ("bold-label");
        grid.add (label);

        label = new Label (text);
        label.visible = true;
        label.hexpand = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.selectable = true;
        label.get_style_context ().add_class ("small-label");
        label.justify = Justification.CENTER;
        grid.add (label);
    }
}
