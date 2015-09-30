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

public class SchemaKey : GLib.Object
{
    public string id;
    public SettingsSchemaKey settings_schema_key;

    public string name;
    public string? summary;
    public string? description;
    public Variant default_value;

    public string type;
    public string range_type;
    public Variant range_content;

    public SchemaKey (string _id, SettingsSchemaKey _settings_schema_key)
    {
        this.id = _id;
        this.settings_schema_key = _settings_schema_key;

        name = settings_schema_key.get_name ();
        summary = settings_schema_key.get_summary ();
        description = settings_schema_key.get_description ();
        default_value = settings_schema_key.get_default_value ();

        range_type = settings_schema_key.get_range ().get_child_value (0).get_string ();    // don’t put it in the switch, or it fails
        switch (range_type)
        {
            case "enum":    type = "<enum>"; break;  // <choices> or enum="", and hopefully <aliases>
            case "flags":   type = "as";     break;  // TODO better
            default:
            case "type":    type = (string) settings_schema_key.get_value_type ().peek_string (); break;
        }
        range_content = settings_schema_key.get_range ().get_child_value (1).get_child_value (0);
    }
}

public class Schema : GLib.Object
{
    public string? path;
    public GLib.HashTable<string, SchemaKey> keys = new GLib.HashTable<string, SchemaKey> (str_hash, str_equal);
}
