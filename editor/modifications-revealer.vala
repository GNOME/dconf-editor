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
  along with Dconf Editor.  If not, see <http://www.gnu.org/licenses/>.
*/

using Gtk;

[GtkTemplate (ui = "/ca/desrt/dconf-editor/ui/modifications-revealer.ui")]
class ModificationsRevealer : Revealer
{
    private ModificationsHandler _modifications_handler;
    public ModificationsHandler modifications_handler
    {
        private get { return _modifications_handler; }
        set
        {
            _modifications_handler = value;
            _modifications_handler.delayed_changes_changed.connect (() => {
                    update ();
                });
            _modifications_handler.reload.connect (() => {
                    reload ();
                });
        }
    }

    [GtkChild] private Label label;
    [GtkChild] private ModelButton apply_button;

    private ThemedIcon apply_button_icon = new ThemedIcon.from_names ({"object-select-symbolic"});

    public signal void reload ();

    public Behaviour behaviour { set { modifications_handler.behaviour = value; } }

    /*\
    * * Window management callbacks
    \*/

    [GtkCallback]
    private void on_size_allocate (Allocation allocation)
    {
        StyleContext context = apply_button.get_style_context ();
        if (allocation.width < 900)
        {
            context.remove_class ("text-button");
            apply_button.icon = apply_button_icon;
            context.add_class ("image-button");
        }
        else
        {
            context.remove_class ("image-button");
            apply_button.icon = null;
            context.add_class ("text-button");
        }
    }

    /*\
    * * Action entries
    \*/

    construct
    {
        SimpleActionGroup action_group = new SimpleActionGroup ();
        action_group.add_action_entries (action_entries, this);
        insert_action_group ("mod", action_group);
    }

    private const GLib.ActionEntry [] action_entries =
    {
        { "apply-delayed-settings", apply_delayed_settings },
        { "dismiss-delayed-settings", dismiss_delayed_settings }
    };

    private void apply_delayed_settings ()
    {
        modifications_handler.apply_delayed_settings ();
    }

    private void dismiss_delayed_settings ()
    {
        modifications_handler.dismiss_delayed_settings ();
    }

    /*\
    * * Reseting objects
    \*/

    public void reset_objects (GLib.ListStore? objects, bool recursively)
    {
        _reset_objects (objects, recursively);
        warn_if_no_planned_changes ();
    }

    private void _reset_objects (GLib.ListStore? objects, bool recursively)
    {
        SettingsModel model = modifications_handler.model;
        if (objects == null)
            return;

        for (uint position = 0;; position++)
        {
            Object? object = ((!) objects).get_object (position);
            if (object == null)
                return;

            SettingObject setting_object = (SettingObject) ((!) object);
            if (setting_object is Directory)
            {
                if (recursively) {
                    GLib.ListStore? children = model.get_children ((Directory) setting_object);
                    if (children != null)
                        _reset_objects ((!) children, true);
                }
                continue;
            }
            if (setting_object is DConfKey)
            {
                if (!model.is_key_ghost ((DConfKey) setting_object))
                    modifications_handler.add_delayed_setting ((Key) setting_object, null);
            }
            else if (!model.is_key_default ((GSettingsKey) setting_object))
                modifications_handler.add_delayed_setting ((Key) setting_object, null);
        }
    }

    private void warn_if_no_planned_changes ()
    {
        if (modifications_handler.dconf_changes_count == 0 && modifications_handler.gsettings_changes_count == 0)
            label.set_text (_("Nothing to reset."));
    }

    /*\
    * * Utilities
    \*/

    private void update ()
    {
        if (modifications_handler.mode == ModificationsMode.NONE)
        {
            set_reveal_child (false);
            label.set_text ("");
            return;
        }
        uint total_changes_count = modifications_handler.dconf_changes_count + modifications_handler.gsettings_changes_count;
        if (modifications_handler.mode == ModificationsMode.TEMPORARY)
        {
            if (total_changes_count == 0)
                label.set_text (_("The value is invalid."));
            else if (total_changes_count != 1)
                assert_not_reached ();
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
                label.set_text (_("The change will be dismissed if you quit this view without applying."));
            else if (modifications_handler.behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || modifications_handler.behaviour == Behaviour.SAFE)
                label.set_text (_("The change will be applied on such request or if you quit this view."));
            else
                assert_not_reached ();
            set_reveal_child (true);
        }
        else // if (mode == Mode.DELAYED)
        {
            if (total_changes_count == 0)
                label.set_text (_("Nothing to reset."));
            apply_button.sensitive = total_changes_count > 0;
            label.set_text (get_text (modifications_handler.dconf_changes_count, modifications_handler.gsettings_changes_count));
            set_reveal_child (true);
        }
    }

    private static string get_text (uint dconf, uint gsettings)     // TODO change text if current path is a key?
    {
        if (dconf == 0)
        {
            if (gsettings == 0)
                return _("Changes will be delayed until you request it.");
            /* Translators: "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One gsettings operation delayed.", "%u gsettings operations delayed.", gsettings).printf (gsettings);
        }
        if (gsettings == 0)
            /* Translators: "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
            return ngettext ("One dconf operation delayed.", "%u dconf operations delayed.", dconf).printf (dconf);
            /* Translators: Beginning of a sentence like "One gsettings operation and 2 dconf operations delayed.", you could duplicate "delayed" if needed, as it refers to both the gsettings and dconf operations (at least one of each).
                            Also, "gsettings" is a technical term, notably a shell command, so you probably should not translate it. */
        return _("%s%s").printf (ngettext ("One gsettings operation", "%u gsettings operations", gsettings).printf (gsettings),
            /* Translators: Second part (and end) of a sentence like "One gsettings operation and 2 dconf operations delayed.", so:
                             * the space before the "and" is probably wanted, and
                             * the "delayed" refers to both the gsettings and dconf operations (at least one of each).
                            Also, "dconf" is a technical term, notably a shell command, so you probably should not translate it. */
                                 ngettext (" and one dconf operation delayed.", " and %u dconf operations delayed.", dconf).printf (dconf));
    }
}
