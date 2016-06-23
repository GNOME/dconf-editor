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

    public signal void invalidate_popovers ();

    /*\
    * * Public calls
    \*/

    public void add_delayed_setting (Key key, Variant? new_value)
    {
        key.planned_change = true;
        key.planned_value = new_value;

        if (key.has_schema)
            gsettings_keys_awaiting_hashtable.insert (key.descriptor, (GSettingsKey) key);
        else
            dconf_keys_awaiting_hashtable.insert (key.descriptor, (DConfKey) key);

        update ();
    }

    public void dismiss_change (Key key)
    {
        key.planned_change = false;
        key.planned_value = null;

        if (key.has_schema)
            gsettings_keys_awaiting_hashtable.remove (key.descriptor);
        else
            dconf_keys_awaiting_hashtable.remove (key.descriptor);

        update ();
    }

    /*\
    * * Buttons callbacks
    \*/

    [GtkCallback]
    private void apply_delayed_settings ()
    {
        set_reveal_child (false);
        invalidate_popovers ();

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
    }

    [GtkCallback]
    private void dismiss_delayed_settings ()
    {
        set_reveal_child (false);
        invalidate_popovers ();

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
    }

    /*\
    * * Utilities
    \*/

    private void update ()
    {
        if (dconf_keys_awaiting_hashtable.length == 0 && gsettings_keys_awaiting_hashtable.length == 0)
        {
            set_reveal_child (false);
            label.set_text ("");
            return;
        }

        label.set_text (get_text (dconf_keys_awaiting_hashtable.length, gsettings_keys_awaiting_hashtable.length));
        set_reveal_child (true);
    }

    private static string get_text (uint dconf, uint gsettings)     // TODO change text if current path is a key?
        requires (dconf > 0 || gsettings > 0)
    {
        if (dconf == 0) return _("%u gsettings operations awaiting.").printf (gsettings);
        if (gsettings == 0) return _("%u dconf operations awaiting.").printf (dconf);
        return _("%u gsettings operations and %u dconf operations awaiting.").printf (gsettings, dconf);
    }
}
