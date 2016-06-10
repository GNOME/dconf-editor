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
    [GtkChild] private Label label;

    private DConf.Client dconf_client = new DConf.Client ();

    private HashTable<string, DConfKey>         dconf_keys_awaiting_hashtable = new HashTable<string, DConfKey>     (str_hash, str_equal);
    private HashTable<string, GSettingsKey> gsettings_keys_awaiting_hashtable = new HashTable<string, GSettingsKey> (str_hash, str_equal);

    /*\
    * * Public calls
    \*/

    public void add_delayed_dconf_settings (DConfKey key, Variant? new_value)
    {
        key.planned_value = new_value;
        dconf_keys_awaiting_hashtable.insert (key.full_name, key);

        update ();
    }

    public void add_delayed_glib_settings (GSettingsKey key, Variant? new_value)
    {
        key.planned_value = new_value;
        gsettings_keys_awaiting_hashtable.insert (key.descriptor, key);

        update ();
    }

    /*\
    * * Buttons callbacks
    \*/

    [GtkCallback]
    private void apply_delayed_settings ()
    {
        set_reveal_child (false);

        /* GSettings stuff */

        HashTable<string, GLib.Settings> delayed_settings_hashtable = new HashTable<string, GLib.Settings> (str_hash, str_equal);
        gsettings_keys_awaiting_hashtable.foreach_remove ((full_name, key) => {
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

                return true;
            });

        delayed_settings_hashtable.foreach_remove ((schema_id, schema_settings) => { schema_settings.apply (); return true; });

        /* DConf stuff */

        DConf.Changeset dconf_changeset = new DConf.Changeset ();
        dconf_keys_awaiting_hashtable.foreach_remove ((full_name, key) => {
                dconf_changeset.set (full_name, key.planned_value);

                if (key.planned_value == null)
                    key.is_ghost = true;

                return true;
            });

        try {
            dconf_client.change_sync (dconf_changeset);
        } catch (Error error) {
            warning (error.message);
        }
    }

    [GtkCallback]
    private void dismiss_delayed_settings ()
    {
        set_reveal_child (false);

        gsettings_keys_awaiting_hashtable.remove_all ();
        dconf_keys_awaiting_hashtable.remove_all ();
    }

    /*\
    * * Utilities
    \*/

    private void update ()
        requires (dconf_keys_awaiting_hashtable.length != 0 || gsettings_keys_awaiting_hashtable.length != 0)
    {
        if (dconf_keys_awaiting_hashtable.length == 0)
            label.set_text (_("%u gsettings operations awaiting.").printf (gsettings_keys_awaiting_hashtable.length));
        else if (gsettings_keys_awaiting_hashtable.length == 0)
            label.set_text (_("%u dconf operations awaiting.").printf (dconf_keys_awaiting_hashtable.length));
        else
            label.set_text (_("%u gsettings operations and %u dconf operations awaiting.").printf (gsettings_keys_awaiting_hashtable.length, dconf_keys_awaiting_hashtable.length));

        set_reveal_child (true);
    }
}
