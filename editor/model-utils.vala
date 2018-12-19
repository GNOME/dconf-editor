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
    HASH,           /* uint32  */
    HAS_SCHEMA,     /* bool    */
    KEY_NAME,       /* string  */
    TYPE_CODE,      /* string  */

    // variable properties
    KEY_VALUE,      /* variant */

    // GSettingsKey only fixed properties
    FIXED_SCHEMA,   /* bool    */
    SCHEMA_ID,      /* string  */
    SUMMARY,        /* string  */
    DESCRIPTION,    /* string  */
    DEFAULT_VALUE,  /* string! */
    RANGE_TYPE,     /* byte    */
    RANGE_CONTENT,  /* variant */
    MAXIMUM,        /* string! */
    MINIMUM,        /* string! */

    // GSettingsKey only variable properties
    KEY_CONFLICT,   /* byte    */
    IS_DEFAULT      /* bool    */
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

    internal const string undefined_context_id_string = "0";
    internal const string folder_context_id_string    = "1";
    internal const string dconf_context_id_string     = "2";

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

    internal static string get_name_or_empty (string path)
    {
        return path.slice (path.last_index_of_char ('/') + 1, path.length);
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

    /*\
    * * Types translations
    \*/

    internal static string key_to_description (string type, bool capitalized)
    {
        string untranslated1 = key_to_untranslated_description (type, capitalized);
        string test = _(untranslated1);
        if (test != untranslated1)
            return test;

        string untranslated2 = key_to_untranslated_description (type, !capitalized);
        test = _(untranslated2);
        if (test != untranslated2)
            return test;

        return untranslated1;
    }

    private static string key_to_untranslated_description (string type, bool capitalized)
    {
        switch (type)   // TODO byte, bytestring, bytestring array
        {
            case "b":       return capitalized ? "Boolean"      : "boolean";
            case "s":       return capitalized ? "String"       : "string";
            case "as":      return capitalized ? "String array" : "string array";
            case "<enum>":  return capitalized ? "Enumeration"  : "enumeration";
            case "<flags>": return capitalized ? "Flags"        : "flags";
            case "d":       return capitalized ? "Double"       : "double";
            case "h":       return "D-Bus handle type";
            case "o":       return "D-Bus object path";
            case "ao":      return "D-Bus object path array";
            case "g":       return "D-Bus signature";
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":       return capitalized ? "Integer"      : "integer";
            case "v":       return capitalized ? "Variant"      : "variant";
            case "()":      return capitalized ? "Empty tuple"  : "empty tuple";
            default:
                return type;
        }
    }

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _B_ = _("Boolean");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _b_ = _("boolean");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _S_ = _("String");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _s_ = _("string");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _As_ = _("String array");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _as_ = _("string array");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _Enum_ = _("Enumeration");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _enum_ = _("enumeration");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _Flags_ = _("Flags");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _flags_ = _("flags");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _D_ = _("Double");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _d_ = _("double");

    /* Translators: that's the name of a data type; capitalized (if that makes sense); this handle type is an index; you may maintain the word "handle" */
    private const string _H_ = _("D-Bus handle type");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense); this handle type is an index; you may maintain the word "handle" */
    private const string _h_ = _("D-Bus handle type");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _O_ = _("D-Bus object path");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _o_ = _("D-Bus object path");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _Ao_ = _("D-Bus object path array");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _ao_ = _("D-Bus object path array");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _G_ = _("D-Bus signature");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _g_ = _("D-Bus signature");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _Integer_ = _("Integer");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _integer_ = _("integer");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _V_ = _("Variant");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _v_ = _("variant");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
    private const string _Empty_tuple_ = _("Empty tuple");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
    private const string _empty_tuple_ = _("empty tuple");
}
