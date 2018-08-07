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

internal enum RangeType {       // transformed as uint8
    TYPE,
    ENUM,
    FLAGS,
    RANGE,
    OTHER;

    internal static RangeType get_from_string (string str)
    {
        switch (str)
        {
            case "type":    return RangeType.TYPE;
            case "enum":    return RangeType.ENUM;
            case "flags":   return RangeType.FLAGS;
            case "range":   return RangeType.RANGE;
            default:        return RangeType.OTHER;
        }
    }
}

internal enum KeyConflict {     // transformed as uint8
    NONE,
    SOFT,
    HARD
}

[Flags]
internal enum PropertyQuery {   // transformed as uint16
    HASH,
    HAS_SCHEMA,
    KEY_NAME,
    TYPE_CODE,

    // variable properties
    KEY_VALUE,

    // GSettingsKey only fixed properties
    FIXED_SCHEMA,
    SCHEMA_ID,
    SUMMARY,
    DESCRIPTION,
    DEFAULT_VALUE,
    RANGE_TYPE,
    RANGE_CONTENT,
    MAXIMUM,
    MINIMUM,

    // GSettingsKey only variable properties
    KEY_CONFLICT,
    IS_DEFAULT
}

private class RegistryVariantDict : Object
{
    private HashTable<uint16, Variant> hash_table = new HashTable<uint16, Variant> ((a) => { return a; }, (a, b) => { return a == b; });

    internal RegistryVariantDict ()
    {
    }

    internal RegistryVariantDict.from_aqv (Variant variant)
    {
        if (variant.get_type_string () != "a{qv}")
            assert_not_reached ();

        VariantIter iter = new VariantIter (variant);

        uint16 key;
        Variant content;
        while (iter.next ("{qv}", out key, out content))
            hash_table.insert (key, content);
    }

    internal bool lookup (uint16 key, string format_string, ...)
    {
        Variant? variant = hash_table.lookup (key);

        if (variant == null || !((!) variant).check_format_string (format_string, false))
            return false;

        va_list list = va_list ();
        ((!) variant).get_va (format_string, null, &list);
        return true;
    }

    internal Variant? lookup_value (uint16 key, VariantType expected_type)
    {
        Variant? result = hash_table.lookup (key);
        if (result == null && !((!) result).is_of_type (expected_type))
            return null;
        return (!) result;
    }

    internal bool contains (uint16 key)
    {
        return hash_table.contains (key);
    }

    internal void insert_value (uint16 key, Variant variant)
    {
        // TODO g_hash_table_insert returns a boolean now
        hash_table.insert (key, variant);
    }

    internal bool remove (uint16 key)
    {
        return hash_table.remove (key);
    }

    internal void clear ()
    {
        hash_table.remove_all ();
    }

    internal Variant end ()
    {
        VariantBuilder builder = new VariantBuilder (new VariantType ("a{qv}"));
        hash_table.@foreach ((key, variant) => builder.add ("{qv}", key, variant));
        clear ();
        return builder.end ();
    }
}

namespace ModelUtils
{
    internal const uint16 special_context_id_number = 3;

    internal const uint16 undefined_context_id = 0;
    internal const uint16 folder_context_id    = 1;
    internal const uint16 dconf_context_id     = 2;

    internal static inline bool is_undefined_context_id (uint16 context_id) { return context_id == undefined_context_id; }
    internal static inline bool is_folder_context_id (uint16 context_id)    { return context_id == folder_context_id; }
    internal static inline bool is_dconf_context_id (uint16 context_id)     { return context_id == dconf_context_id; }

    /*\
    * * Path utilities
    \*/

    internal static inline bool is_key_path (string path)
    {
        return !path.has_suffix ("/");
    }

    internal static inline bool is_folder_path (string path)
    {
        return path.has_suffix ("/");
    }

    internal static string get_parent_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return get_base_path (is_key_path (path) ? path : path [0:-1]);
    }

    internal static string get_base_path (string path)
    {
        if (path.length <= 1)
            return "/";
        return path.slice (0, path.last_index_of_char ('/') + 1);
    }

    internal static string get_name (string path)
    {
        if (path.length <= 1)
            return "/";
        if (is_key_path (path))
            return path [path.last_index_of_char ('/') + 1 : path.length];
        string tmp = path [0:-1];
        return tmp [tmp.last_index_of_char ('/') + 1 : tmp.length];
    }

    internal static inline string recreate_full_name (string base_path, string name, bool is_folder)
    {
        if (is_folder)
            return base_path + name + "/";
        else
            return base_path + name;
    }
}
