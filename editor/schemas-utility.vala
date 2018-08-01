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

private class SchemasUtility : Object
{
    private SettingsSchemaSource? settings_schema_source = SettingsSchemaSource.get_default ();
    private string [] non_relocatable_schemas = {};
    private string [] relocatable_schemas = {};

    construct
    {
        if (settings_schema_source != null)
            ((!) settings_schema_source).list_schemas (true, out non_relocatable_schemas, out relocatable_schemas);
    }

    internal bool is_relocatable_schema (string id)
    {
        return (id in relocatable_schemas);
    }

    internal bool is_non_relocatable_schema (string id)
    {
        return (id in non_relocatable_schemas);
    }

    internal string? get_schema_path (string id)
    {
        if (settings_schema_source == null)
            return null;   // TODO better?

        SettingsSchema? schema = ((!) settings_schema_source).lookup (id, true);
        if (schema == null)
            return null;

        return ((!) schema).get_path ();
    }
}
