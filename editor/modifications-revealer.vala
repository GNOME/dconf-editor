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
    private enum Mode {
        NONE,
        TEMPORARY,
        DELAYED
    }
    private Mode mode = Mode.NONE;

    [GtkChild] private Label label;
    [GtkChild] private ModelButton apply_button;

    private ThemedIcon apply_button_icon = new ThemedIcon.from_names ({"object-select-symbolic"});

    private DConf.Client dconf_client = new DConf.Client ();

    private HashTable<string, DConfKey>         dconf_keys_awaiting_hashtable = new HashTable<string, DConfKey>     (str_hash, str_equal);
    private HashTable<string, GSettingsKey> gsettings_keys_awaiting_hashtable = new HashTable<string, GSettingsKey> (str_hash, str_equal);

    public signal void reload ();

    public Behaviour behaviour { get; set; }

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
    * * Public calls
    \*/

    public bool get_current_delay_mode ()
    {
        return mode == Mode.DELAYED || behaviour == Behaviour.ALWAYS_DELAY;
    }

    public bool should_delay_apply (string type_string)
    {
        if (get_current_delay_mode () || behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            return true;
        if (behaviour == Behaviour.UNSAFE)
            return false;
        if (behaviour == Behaviour.SAFE)
            return type_string != "b" && type_string != "mb" && type_string != "<enum>" && type_string != "<flags>";
        assert_not_reached ();
    }

    public void enter_delay_mode ()
    {
        mode = Mode.DELAYED;
        apply_button.sensitive = dconf_keys_awaiting_hashtable.length + gsettings_keys_awaiting_hashtable.length != 0;
        update ();
    }

    public void add_delayed_setting (Key key, Variant? new_value)
    {
        key.planned_change = true;
        key.planned_value = new_value;

        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.insert (key.descriptor, (GSettingsKey) key);
        else
            dconf_keys_awaiting_hashtable.insert (key.descriptor, (DConfKey) key);

        mode = get_current_delay_mode () ? Mode.DELAYED : Mode.TEMPORARY;

        apply_button.sensitive = true;
        update ();
    }

    public void dismiss_change (Key key)
    {
        if (mode == Mode.NONE)
            mode = behaviour == Behaviour.ALWAYS_DELAY ? Mode.DELAYED : Mode.TEMPORARY;

        key.planned_change = false;
        key.planned_value = null;

        if (key is GSettingsKey)
            gsettings_keys_awaiting_hashtable.remove (key.descriptor);
        else
            dconf_keys_awaiting_hashtable.remove (key.descriptor);

        apply_button.sensitive = (mode != Mode.TEMPORARY) && (dconf_keys_awaiting_hashtable.length + gsettings_keys_awaiting_hashtable.length != 0);
        update ();
    }

    public void path_changed ()
    {
        if (mode != Mode.TEMPORARY)
            return;
        if (behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.SAFE)
            apply_delayed_settings ();
        else if (behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
            dismiss_delayed_settings ();
        else
            assert_not_reached ();
    }

    public void warn_if_no_planned_changes ()
    {
        if (dconf_keys_awaiting_hashtable.length == 0 && gsettings_keys_awaiting_hashtable.length == 0)
            label.set_text (_("Nothing to reset."));
    }

    /*\
    * * Buttons callbacks
    \*/

    [GtkCallback]
    public void apply_delayed_settings ()
    {
        mode = Mode.NONE;
        update ();

        /* GSettings stuff */

        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        gsettings_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                GLib.Settings? settings = delayed_settings_hashtable.lookup (key.schema_id);
                if (settings == null)
                {
                    settings = new GLib.Settings (key.schema_id);
                    ((!) settings).delay ();
                    delayed_settings_hashtable.insert (key.schema_id, (!) settings);
                }

                if (key.planned_value == null)
                    ((!) settings).reset (key.name);
                else
                    ((!) settings).set_value (key.name, (!) key.planned_value);
                key.planned_change = false;

                return true;
            });

        delayed_settings_hashtable.foreach_remove ((schema_id, schema_settings) => { schema_settings.apply (); return true; });

        /* DConf stuff */

        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        dconf_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                dconf_changeset.set (key.full_name, key.planned_value);

                if (key.planned_value == null)
                    key.is_ghost = true;
                key.planned_change = false;

                return true;
            });

        try {
            dconf_client.change_sync (dconf_changeset);
        } catch (Error error) {
            warning (error.message);
        }

        /* reload the hamburger menu */

        reload ();
    }

    [GtkCallback]
    private void dismiss_delayed_settings ()
    {
        mode = Mode.NONE;
        update ();

        /* GSettings stuff */

        gsettings_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                key.planned_change = false;
                return true;
            });

        /* DConf stuff */

        dconf_keys_awaiting_hashtable.foreach_remove ((descriptor, key) => {
                key.planned_change = false;
                return true;
            });

        /* reload notably key_editor_child */

        reload ();
    }

    /*\
    * * Utilities
    \*/

    private void update ()
    {
        if (mode == Mode.NONE)
        {
            set_reveal_child (false);
            label.set_text ("");
        }
        else if (mode == Mode.TEMPORARY)
        {
            uint length = dconf_keys_awaiting_hashtable.length + gsettings_keys_awaiting_hashtable.length;
            if (length == 0)
                label.set_text (_("The value is invalid."));
            else if (length != 1)
                assert_not_reached ();
            else if (behaviour == Behaviour.ALWAYS_CONFIRM_EXPLICIT)
                label.set_text (_("The change will be dismissed if you quit this view without applying."));
            else if (behaviour == Behaviour.ALWAYS_CONFIRM_IMPLICIT || behaviour == Behaviour.SAFE)
                label.set_text (_("The change will be applied on such request or if you quit this view."));
            else
                assert_not_reached ();
            set_reveal_child (true);
        }
        else // if (mode == Mode.DELAYED)
        {
            label.set_text (get_text (dconf_keys_awaiting_hashtable.length, gsettings_keys_awaiting_hashtable.length));
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
