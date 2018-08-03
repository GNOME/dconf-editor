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
internal enum PropertyQuery {   // transformed as uint32 // TODO might finish at uint16
    HAS_SCHEMA,
    DEFINED_BY, // TODO something
    KEY_NAME,
    TYPE_CODE,

    // variable properties
    KEY_VALUE,

    // GSettingsKey only fixed properties
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
    private HashTable<uint, Variant> hash_table = new HashTable<uint, Variant> ((a) => { return a; }, (a, b) => { return a == b; });

    internal RegistryVariantDict ()
    {
    }

    internal RegistryVariantDict.from_auv (Variant variant)
    {
        if (variant.get_type_string () != "a{uv}")
            assert_not_reached ();

        VariantIter iter = new VariantIter (variant);

        uint key;
        Variant content;
        while (iter.next ("{uv}", out key, out content))
            hash_table.insert (key, content);
    }

    internal bool lookup (uint key, string format_string, ...)
    {
        Variant? variant = hash_table.lookup (key);

        if (variant == null || !((!) variant).check_format_string (format_string, false))
            return false;

        va_list list = va_list ();
        ((!) variant).get_va (format_string, null, &list);
        return true;
    }

    internal Variant? lookup_value (uint key, VariantType expected_type)
    {
        Variant? result = hash_table.lookup (key);
        if (result == null && !((!) result).is_of_type (expected_type))
            return null;
        return (!) result;
    }

    internal bool contains (uint key)
    {
        return hash_table.contains (key);
    }

    internal void insert_value (uint key, Variant variant)
    {
        // TODO g_hash_table_insert returns a boolean now
        hash_table.insert (key, variant);
    }

    internal bool remove (uint key)
    {
        return hash_table.remove (key);
    }

    internal void clear ()
    {
        hash_table.remove_all ();
    }

    internal Variant end ()
    {
        VariantBuilder builder = new VariantBuilder (new VariantType ("a{uv}"));
        hash_table.@foreach ((key, variant) => builder.add ("{uv}", key, variant));
        clear ();
        return builder.end ();
    }
}
