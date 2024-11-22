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

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/modifications-action-bar.ui")]
private class ModificationsActionBar : Box
{
    internal ModificationsHandler modifications_handler { get; set; }
    internal string label { get; set; default = ""; }

    public bool opened { get; set; }

    internal string action_bar_mode {
        get {
            if (opened)
                return "opened";
            else
                return "closed";
        }
    }

    construct
    {
        notify["modifications-handler"].connect (
            () => {
                modifications_handler.delayed_changes_changed.connect (update);
            }
        );

        notify["opened"].connect (
            () => {
                notify_property ("action-bar-mode");
            }
        );
    }

    private void update ()
    {
        if (modifications_handler.mode == ModificationsMode.NONE)
        {
            label = "";
            return;
        }

        uint total_changes_count = modifications_handler.dconf_changes_count + modifications_handler.gsettings_changes_count;
        if (modifications_handler.mode == ModificationsMode.TEMPORARY)
        {
            if (total_changes_count == 0)
            {
                // apply_button.sensitive = false;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key and enters in the entry or text view a value that cannot be parsed to the correct data type */
                label = _("The value is invalid.");
            }
            else if (total_changes_count != 1)
                assert_not_reached ();
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            {
                // apply_button.sensitive = true;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key (with the "always confirm explicit" behaviour) */
                label = _("The change will be dismissed if you quit this view without applying.");
            }
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || modifications_handler.behaviour == Behaviour.SAFE)
            {
                // apply_button.sensitive = true;
                /* Translators: displayed in the bottom bar in normal sized windows, when the user edits a key (with default "always confirm implicit" behaviour notably) */
                label = _("The change will be applied on such request or if you quit this view.");
            }
            else
                assert_not_reached ();
        }
        else // if (mode == Mode.DELAYED)
        {
            if (total_changes_count == 0)
                /* Translators: displayed in the bottom bar in normal sized windows, when the user tries to reset keys from/for a folder that has nothing to reset */
                label = _("Nothing to reset.");
                // FIXME appears twice
            // apply_button.sensitive = total_changes_count > 0;
            label = get_text (modifications_handler.dconf_changes_count, modifications_handler.gsettings_changes_count);
        }
    }

    private static string get_text (uint dconf, uint gsettings)     // TODO change text if current path is a key?
    {
        if (dconf == 0)
        {
            if (gsettings == 0)
            /* Translators: Text displayed in the bottom bar; displayed if there are no pending changes, to document what is the "delay mode". */
                return _("Changes will be delayed until you request it.");

            /* Translators: Text displayed in the bottom bar; "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One gsettings operation delayed.", "%u gsettings operations delayed.", gsettings).printf (gsettings);
        }
        if (gsettings == 0)
            /* Translators: Text displayed in the bottom bar; "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One dconf operation delayed.", "%u dconf operations delayed.", dconf).printf (dconf);

         /* Translators: Text displayed in the bottom bar. Hacky: I split a sentence like "One gsettings operation and 2 dconf operations delayed." in two parts, before the "and"; there is at least one gsettings operation and one dconf operation. So, you can either keep "%s%s" like that, and have the second part of the translation starting with a space (if that makes sense in your language), or you might use "%s %s" here. */
        return _("%s%s").printf (

         /* Translators: Text displayed in the bottom bar; beginning of a sentence like "One gsettings operation and 2 dconf operations delayed.", you could duplicate "delayed" if needed, as it refers to both the gsettings and dconf operations (at least one of each).
            Also, "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            ngettext ("One gsettings operation", "%u gsettings operations", gsettings).printf (gsettings),

         /* Translators: Text displayed in the bottom bar; second part (and end) of a sentence like "One gsettings operation and 2 dconf operations delayed.", so:
             * the space before the "and" is probably wanted, if you keeped the "%s%s" translation as-is, and
             * the "delayed" refers to both the gsettings and dconf operations (at least one of each).
            Also, "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            ngettext (" and one dconf operation delayed.", " and %u dconf operations delayed.", dconf).printf (dconf)
        );
    }
}
