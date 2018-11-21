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

        first_mode_name = _("About");
        second_mode_name = _("Credits");
        change_editability (true);

        show_apropos ();
    }

    internal void reset ()
    {
        edit_mode_action.set_state (false);
        show_apropos ();
    }

    internal string? get_copy_text ()
    {
        string? nullable_selection = Clipboard.@get (Gdk.SELECTION_PRIMARY).wait_for_text ();
        if (nullable_selection != null)
        {
             string selection = ((!) nullable_selection).dup ();
             if (selection != "")
                return selection;
        }

        Widget? focus_child = main_list_box.get_focus_child ();
        if (focus_child == null)
            return null;
        Widget? child = ((Bin) (!) focus_child).get_child ();
        if (child == null || !((!) child is AboutListItem))
            assert_not_reached ();

        string? copy_text = ((AboutListItem) (!) child).copy_text;
        if (copy_text == null)
            return null;
        return ((!) copy_text).dup ();
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
            show_credits ();
        else
            show_apropos ();
    }

    private void show_apropos ()
    {
        main_list_store.remove_all ();
        main_list_store.append (new AboutListItem.from_icon_name    (AboutDialogInfos.logo_icon_name));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.program_name, "bold-label"));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.version));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.comments));
        main_list_store.append (new AboutListItem.from_link         (AboutDialogInfos.website,
                                                                     AboutDialogInfos.website_label));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.copyright, "small-label"));

        if (AboutDialogInfos.license_type != License.GPL_3_0)
            assert_not_reached ();  // TODO support all licenses type
        main_list_store.append (new AboutListItem.from_link         ("https://www.gnu.org/licenses/gpl-3.0.html", _("GNU General Public License\nversion 3 or later")));    // TODO better
    }

    private void show_credits ()
    {
        main_list_store.remove_all ();
        main_list_store.append (new AboutListItem.from_icon_name    (AboutDialogInfos.logo_icon_name));
        main_list_store.append (new AboutListItem.from_label        (AboutDialogInfos.program_name, "bold-label"));

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
        main_list_store.append (new AboutListItem.with_title        (authors, _("Creators")));

        main_list_store.append (new AboutListItem.with_title        (AboutDialogInfos.translator_credits, _("Translators")));
    }
}

private class AboutListItem : Grid
{
    public string? copy_text { internal get; construct; default = null; }

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
        if (css_class != null)
            label.get_style_context ().add_class ((!) css_class);
        add (label);
    }

    internal AboutListItem.from_icon_name (string icon_name)
    {
        Image image = new Image.from_icon_name (icon_name, IconSize.DIALOG);
        image.pixel_size = 128;
        image.visible = true;
        image.hexpand = true;
        add (image);
    }

    internal AboutListItem.from_link (string link, string text)
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

        this.orientation = Orientation.VERTICAL;

        Label label = new Label (title);
        label.visible = true;
        label.hexpand = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.get_style_context ().add_class ("bold-label");
        add (label);

        label = new Label (text);
        label.visible = true;
        label.hexpand = true;
        label.wrap_mode = Pango.WrapMode.WORD_CHAR;
        label.wrap = true;
        label.selectable = true;
        label.get_style_context ().add_class ("small-label");
        label.justify = Justification.CENTER;
        add (label);
    }
}
