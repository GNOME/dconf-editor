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

    internal static string key_to_short_description (string type)
    {
        string translation;

        // if untranslated_description and translation are equal, either there is no translation, or we're in an English-based locale
        string non_capitalized_untranslated_short_description;
        get_type_non_capitalized_short_description (type, out non_capitalized_untranslated_short_description, out translation);
        if (translation != non_capitalized_untranslated_short_description)
            return translation;

        // fallback to the type capitalized short description; should also fail if we're in an English-based locale
        string capitalized_untranslated_short_description;
        get_type_capitalized_short_description (type, out capitalized_untranslated_short_description, out translation);
        if (translation != capitalized_untranslated_short_description)
            return translation;

        // either there is no translation at all (and then we show the type description untranslated), or we're in an English-based locale
        if (non_capitalized_untranslated_short_description != _garbage_)
            return non_capitalized_untranslated_short_description;
        else if (capitalized_untranslated_short_description != _garbage_)
            assert_not_reached ();
        else
            return type;
    }

    internal static string key_to_long_description (string type)
    {
        string translation;

        // if untranslated_description and translation are equal, either there is no translation, or we're in an English-based locale
        string untranslated_long_description;
        get_type_capitalized_long_description (type, out untranslated_long_description, out translation);
        if (translation != untranslated_long_description)
            return translation;

        // fallback to the type capitalized short description; should fail if we're in an English-based locale
        string capitalized_untranslated_short_description;
        get_type_capitalized_short_description (type, out capitalized_untranslated_short_description, out translation);
        if (translation != capitalized_untranslated_short_description)
            return translation;

        // fallback to the type non-capitalized short description; should also fail if we're in an English-based locale
        string non_capitalized_untranslated_short_description;
        get_type_non_capitalized_short_description (type, out non_capitalized_untranslated_short_description, out translation);
        if (translation != non_capitalized_untranslated_short_description)
            return translation;

        // either there is no translation at all (and then we show the type description untranslated), or we're in an English-based locale
        if (untranslated_long_description != _garbage_)
            return untranslated_long_description;
        else if (capitalized_untranslated_short_description != _garbage_)
            return capitalized_untranslated_short_description;
        else if (non_capitalized_untranslated_short_description != _garbage_)
            assert_not_reached ();
        else
            return type;
    }

    private static void get_type_capitalized_long_description (string type,
                                                           out string untranslated_description,
                                                           out string translated_description)
    {
        switch (type)   // TODO double, byte, bytestring, bytestring array, dict-entry?, dictionary?, vardict, mb...
        {
            // large integers
            case "n":       untranslated_description = "Signed 16-bit integer";     translated_description = _desc_N_;      return;
            case "q":       untranslated_description = "Unsigned 16-bit integer";   translated_description = _desc_Q_;      return;
            case "i":       untranslated_description = "Signed 32-bit integer";     translated_description = _desc_I_;      return;
            case "u":       untranslated_description = "Unsigned 32-bit integer";   translated_description = _desc_U_;      return;
            case "x":       untranslated_description = "Signed 64-bit integer";     translated_description = _desc_X_;      return;
            case "t":       untranslated_description = "Unsigned 64-bit integer";   translated_description = _desc_T_;      return;
            // garbage
            default:        untranslated_description = _garbage_;                   translated_description = _garbage_;     return;
        }
    }

    private static void get_type_capitalized_short_description (string type,
                                                            out string untranslated_description,
                                                            out string translated_description)
    {
        switch (type)   // TODO bytestring, bytestring array, better for byte, dict-entry?, dictionary?, vardict?, D-Bus things?
        {
            case "b":       untranslated_description = "Boolean";                   translated_description = _B_;           return;
            case "s":       untranslated_description = "String";                    translated_description = _S_;           return;
            case "as":      untranslated_description = "String array";              translated_description = _As_;          return;
            case "<enum>":  untranslated_description = "Enumeration";               translated_description = _Enum_;        return;
            case "<flags>": untranslated_description = "Flags";                     translated_description = _Flags_;       return;
            case "d":       untranslated_description = "Double";                    translated_description = _D_;           return;
            /* Translators: that's the name of a data type; capitalized (if that makes sense); this handle type is an index; you may maintain the word "handle" */
            case "h":         translated_description = C_("capitalized", "D-Bus handle type");
                            untranslated_description =                   "D-Bus handle type" ;                              return;

            /* Translators: that's the name of a data type; capitalized (if that makes sense) */
            case "o":         translated_description = C_("capitalized", "D-Bus object path");
                            untranslated_description =                   "D-Bus object path" ;                              return;

            /* Translators: that's the name of a data type; capitalized (if that makes sense) */
            case "ao":        translated_description = C_("capitalized", "D-Bus object path array");
                            untranslated_description =                   "D-Bus object path array" ;                        return;

            /* Translators: that's the name of a data type; capitalized (if that makes sense) */
            case "g":         translated_description = C_("capitalized", "D-Bus signature");
                            untranslated_description =                   "D-Bus signature" ;                                return;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":       untranslated_description = "Integer";                   translated_description = _Integer_;     return;
            case "v":       untranslated_description = "Variant";                   translated_description = _V_;           return;
            case "()":      untranslated_description = "Empty tuple";               translated_description = _Empty_tuple_; return;
            // garbage
            default:        untranslated_description = _garbage_;                   translated_description = _garbage_;     return;
        }
    }

    private static void get_type_non_capitalized_short_description (string type,
                                                                out string untranslated_description,
                                                                out string translated_description)
    {
        switch (type)   // TODO bytestring, bytestring array, better for byte, dict-entry?, dictionary?, vardict?, D-Bus things?
        {
            case "b":       untranslated_description = "boolean";                   translated_description = _b_;           return;
            case "s":       untranslated_description = "string";                    translated_description = _s_;           return;
            case "as":      untranslated_description = "string array";              translated_description = _as_;          return;
            case "<enum>":  untranslated_description = "enumeration";               translated_description = _enum_;        return;
            case "<flags>": untranslated_description = "flags";                     translated_description = _flags_;       return;
            case "d":       untranslated_description = "double";                    translated_description = _d_;           return;
            /* Translators: that's the name of a data type; non capitalized (if that makes sense); this handle type is an index; you may maintain the word "handle" */
            case "h":         translated_description = C_("non-capitalized", "D-Bus handle type");
                            untranslated_description =                       "D-Bus handle type" ;                          return;

            /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
            case "o":         translated_description = C_("non-capitalized", "D-Bus object path");
                            untranslated_description =                       "D-Bus object path" ;                          return;

            /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
            case "ao":        translated_description = C_("non-capitalized", "D-Bus object path array");
                            untranslated_description =                       "D-Bus object path array" ;                    return;

            /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
            case "g":         translated_description = C_("non-capitalized", "D-Bus signature");
                            untranslated_description =                       "D-Bus signature" ;                            return;
            case "y":
            case "n":
            case "q":
            case "i":
            case "u":
            case "x":
            case "t":       untranslated_description = "integer";                   translated_description = _integer_;     return;
            case "v":       untranslated_description = "variant";                   translated_description = _v_;           return;
            case "()":      untranslated_description = "empty tuple";               translated_description = _empty_tuple_; return;
            // garbage
            default:        untranslated_description = _garbage_;                   translated_description = _garbage_;     return;
        }
    }

    private const string _garbage_ = "";

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_N_ = _("Signed 16-bit integer");

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_Q_ = _("Unsigned 16-bit integer");

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_I_ = _("Signed 32-bit integer");

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_U_ = _("Unsigned 32-bit integer");

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_X_ = _("Signed 64-bit integer");

    /* Translators: that's a name of a data type; capitalized (if that makes sense) */
    private const string _desc_T_ = _("Unsigned 64-bit integer");

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
//  private const string _H_ = C_("capitalized", "D-Bus handle type");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense); this handle type is an index; you may maintain the word "handle" */
//  private const string _h_ = C_("non-capitalized", "D-Bus handle type");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
//  private const string _O_ = C_("capitalized", "D-Bus object path");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
//  private const string _o_ = C_("non-capitalized", "D-Bus object path");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
//  private const string _Ao_ = C_("capitalized", "D-Bus object path array");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
//  private const string _ao_ = C_("non-capitalized", "D-Bus object path array");

    /* Translators: that's the name of a data type; capitalized (if that makes sense) */
//  private const string _G_ = C_("capitalized", "D-Bus signature");

    /* Translators: that's the name of a data type; non capitalized (if that makes sense) */
//  private const string _g_ = C_("non-capitalized", "D-Bus signature");

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
