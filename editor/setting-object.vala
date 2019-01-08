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

private abstract class SettingObject : Object
{
    [CCode (notify = false)] public string name          { internal get; protected construct; }
    [CCode (notify = false)] public string full_name     { internal get; protected construct; }
}

private class Directory : SettingObject
{
    internal Directory (string _full_name, string _name)
    {
        Object (full_name: _full_name, name: _name);
    }
}

private abstract class Key : SettingObject
{
    [CCode (notify = false)] internal string type_string { get; protected set; default = "*"; }

    [CCode (notify = false)] internal uint key_hash { internal get; private set; default = 0; }
    [CCode (notify = false)] internal Variant? all_fixed_properties { internal get; private set; default = null; }
    internal static void generate_key_fixed_properties (Key key)
        requires (key.key_hash == 0)
        requires (key.all_fixed_properties == null)
    {
        RegistryVariantDict variantdict = new RegistryVariantDict ();
        get_key_fixed_properties (key, 0, ref variantdict);
        key.all_fixed_properties = variantdict.end ();
        key.key_hash = ((!) key.all_fixed_properties).get_data_as_bytes ().hash ();
    }
    internal static void get_key_fixed_properties (Key key, PropertyQuery query, ref RegistryVariantDict variantdict)
    {
        if (key is DConfKey)
            DConfKey._get_key_fixed_properties ((DConfKey) key, query, ref variantdict);
        else if (key is GSettingsKey)
            GSettingsKey._get_key_fixed_properties ((GSettingsKey) key, query, ref variantdict);
        else assert_not_reached ();
    }

    internal signal void value_changed ();
    internal ulong key_value_changed_handler = 0;

    protected static void get_min_and_max_string (out string min, out string max, string type_string)
    {
        switch (type_string)
        {
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                min = "%hhu".printf (uint8.MIN);    // TODO format as in
                max = "%hhu".printf (uint8.MAX);    //   cool_text_value_from_variant()
                return;
            case "n":
                string? nullable_min = "%'hi".printf (int16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hi".printf (int16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hi".printf (int16.MIN));
                max = (!) (nullable_max ?? "%hi".printf (int16.MAX));
                return;
            case "q":
                string? nullable_min = "%'hu".printf (uint16.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'hu".printf (uint16.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%hu".printf (uint16.MIN));
                max = (!) (nullable_max ?? "%hu".printf (uint16.MAX));
                return;
            case "i":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;     // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_min = "%'u".printf (uint32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'u".printf (uint32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%u".printf (uint32.MIN));
                max = (!) (nullable_max ?? "%u".printf (uint32.MAX));
                return;     // TODO is 'lu' failing also?
            case "x":
                string? nullable_min = "%'lli".printf (int64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'lli".printf (int64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%lli".printf (int64.MIN));
                max = (!) (nullable_max ?? "%lli".printf (int64.MAX));
                return;
            case "t":
                string? nullable_min = "%'llu".printf (uint64.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'llu".printf (uint64.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%llu".printf (uint64.MIN));
                max = (!) (nullable_max ?? "%llu".printf (uint64.MAX));
                return;
            case "d":
                string? nullable_min = "%'g".printf (-double.MAX).locale_to_utf8 (-1, null, null, null);    // see after
                string? nullable_max = "%'g".printf (double.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%g".printf (-double.MAX));  // https://gitlab.gnome.org/GNOME/vala/issues/680
                max = (!) (nullable_max ?? "%g".printf (double.MAX));
                return;
            case "h":
                string? nullable_min = "%'i".printf (int32.MIN).locale_to_utf8 (-1, null, null, null);
                string? nullable_max = "%'i".printf (int32.MAX).locale_to_utf8 (-1, null, null, null);
                min = (!) (nullable_min ?? "%i".printf (int32.MIN));
                max = (!) (nullable_max ?? "%i".printf (int32.MAX));
                return;
            default: assert_not_reached ();
        }
    }

    internal static string cool_text_value_from_variant (Variant variant)        // called from subclasses and from KeyListBoxRow
    {
        string type = variant.get_type_string ();
        switch (type)
        {
            case "b":
                return cool_boolean_text_value (variant.get_boolean (), false);
            // TODO %I'xx everywhere! but would need support from the spinbutton…
            case "y":
                return "%hhu (%s)".printf (variant.get_byte (), variant.print (false));     // TODO i18n problem here
            case "n":
                string? nullable_text = "%'hi".printf (variant.get_int16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hi".printf (variant.get_int16 ()));
            case "q":
                string? nullable_text = "%'hu".printf (variant.get_uint16 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%hu".printf (variant.get_uint16 ()));
            case "i":
                string? nullable_text = "%'i".printf (variant.get_int32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));           // TODO why is 'li' failing to display '-'?
            case "u":
                string? nullable_text = "%'u".printf (variant.get_uint32 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%u".printf (variant.get_uint32 ()));
            case "x":
                string? nullable_text = "%'lli".printf (variant.get_int64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%lli".printf (variant.get_int64 ()));
            case "t":
                string? nullable_text = "%'llu".printf (variant.get_uint64 ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%llu".printf (variant.get_uint64 ()));
            case "d":
                string? nullable_text = "%'.12g".printf (variant.get_double ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%g".printf (variant.get_double ()));
            case "h":
                string? nullable_text = "%'i".printf (variant.get_handle ()).locale_to_utf8 (-1, null, null, null);
                return (!) (nullable_text ?? "%i".printf (variant.get_int32 ()));
            default: break;
        }
        if (type.has_prefix ("m"))
        {
            Variant? maybe_variant = variant.get_maybe ();
            if (maybe_variant == null)
                return cool_boolean_text_value (null, false);
            if (type == "mb")
                return cool_boolean_text_value (((!) maybe_variant).get_boolean (), false);
        }
        return variant.print (false);
    }

    internal static string cool_boolean_text_value (bool? nullable_boolean, bool capitalized = true)
    {
        if (capitalized)
        {
            if (nullable_boolean == true)
                /* Translators: the boolean "true" value; capitalized (if that makes sense) */
                return _("True");

            if (nullable_boolean == false)
                /* Translators: the boolean "false" value; capitalized (if that makes sense) */
                return _("False");

            /* Translators: "nothing" value of a nullable key; capitalized (if that makes sense); "nothing" here is a keyword, but you do not need to show it in your translation, that will be done with the non-capitalized version of the word */
            return _("Nothing");
        }
        else
        {
            if (nullable_boolean == true)
                /* Translators: the boolean "true" value; non capitalized (if that makes sense) */
                return _("true");

            if (nullable_boolean == false)
                /* Translators: the boolean "false" value; non capitalized (if that makes sense) */
                return _("false");


            /* Translators: "nothing" value of a nullable key; non capitalized (if that makes sense); the %s is replaced by the text "nothing" (as a technical keyword); it isn't introduced with quotation marks around it, but you might want to add some, depending of your language typographic rules */
            string nothing = _("nothing (%s)").printf ("nothing");
            if (nothing != "nothing (nothing)")
                return nothing;

            /* Translators: "nothing" value of a nullable key; non capitalized (if that makes sense) */
            return _("nothing");    // it has been asked to translate that as "atranslation (nothing)"
        }
    }

    protected static bool show_min_and_max (string type_code)
    {
        return (type_code == "d" || type_code == "y"    // double and unsigned 8 bits; not the handle type
             || type_code == "i" || type_code == "u"    // signed and unsigned 32 bits
             || type_code == "n" || type_code == "q"    // signed and unsigned 16 bits
             || type_code == "x" || type_code == "t");  // signed and unsigned 64 bits
    }

    internal static uint64 get_variant_as_uint64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.BYTE:    return (int64) variant.get_byte ();
            case Variant.Class.UINT16:  return (int64) variant.get_uint16 ();
            case Variant.Class.UINT32:  return (int64) variant.get_uint32 ();
            case Variant.Class.UINT64:  return variant.get_uint64 ();
            default: assert_not_reached ();
        }
    }

    internal static int64 get_variant_as_int64 (Variant variant)
    {
        switch (variant.classify ())
        {
            case Variant.Class.INT16:   return (int64) variant.get_int16 ();
            case Variant.Class.INT32:   return (int64) variant.get_int32 ();
            case Variant.Class.INT64:   return variant.get_int64 ();
            case Variant.Class.HANDLE:  return (int64) variant.get_handle ();
            default: assert_not_reached ();
        }
    }
}

private class DConfKey : Key
{
    internal DConfKey (string full_name, string name, string type_string)
    {
        Object (full_name: full_name, name: name, type_string: type_string);
    }

    private ulong client_changed_handler = 0;
    internal void connect_client (DConf.Client client)
//        requires (client_changed_handler == 0)
    {
        if (client_changed_handler != 0)    // FIXME happens since editable paths 1/3
            return;

        client_changed_handler = client.changed.connect ((client, prefix, changes, tag) => {
                foreach (string item in changes)
                    if (prefix + item == full_name)
                    {
                        value_changed ();
                        return;
                    }
            });
    }
    internal void disconnect_client (DConf.Client client)
//        requires (client_changed_handler != 0)
    {
        if (client_changed_handler == 0)    // FIXME happens since editable paths 2/3
            return;

        client.disconnect (client_changed_handler);
        client_changed_handler = 0;
    }

    internal static void _get_key_fixed_properties (DConfKey dkey, PropertyQuery query, ref RegistryVariantDict variantdict)
    {
        bool all_properties_queried = query == 0;

        if (all_properties_queried || PropertyQuery.HAS_SCHEMA      in query)
            variantdict.insert_value (PropertyQuery.HAS_SCHEMA,                 new Variant.boolean (false));
        if (all_properties_queried || PropertyQuery.KEY_NAME        in query)
            variantdict.insert_value (PropertyQuery.KEY_NAME,                   new Variant.string (dkey.name));
        if (all_properties_queried || PropertyQuery.TYPE_CODE       in query)
            variantdict.insert_value (PropertyQuery.TYPE_CODE,                  new Variant.string (dkey.type_string));

        if (show_min_and_max (dkey.type_string)
         && (all_properties_queried || PropertyQuery.MINIMUM in query || PropertyQuery.MAXIMUM in query))
        {
            string min, max;
            get_min_and_max_string (out min, out max, dkey.type_string);

            variantdict.insert_value (PropertyQuery.MINIMUM,                    new Variant.string (min));
            variantdict.insert_value (PropertyQuery.MAXIMUM,                    new Variant.string (max));
        }
    }
}

private class GSettingsKey : Key
{
    internal KeyConflict key_conflict = KeyConflict.NONE;

    [CCode (notify = false)] public string? schema_path      { private get; internal construct; }
    [CCode (notify = false)] public string summary           { private get; internal construct; }
    [CCode (notify = false)] public string description       { private get; internal construct; }
    [CCode (notify = false)] public string schema_id        { internal get; internal construct; }
    [CCode (notify = false)] public Variant default_value   { internal get; internal construct; }
    [CCode (notify = false)] public RangeType range_type    { internal get; internal construct; }
    [CCode (notify = false)] public Variant range_content   { internal get; internal construct; }

    [CCode (notify = false)] public GLib.Settings settings  { internal get; internal construct; }

    [CCode (notify = false)] internal string descriptor {
        owned get {
            string parent_path;
            if (full_name.length < 2)
                parent_path = "/";
            else
            {
                string tmp_string = full_name.slice (0, full_name.last_index_of_char ('/'));

                if (full_name.has_suffix ("/"))
                    parent_path = full_name.slice (0, tmp_string.last_index_of_char ('/') + 1);
                else
                    parent_path = tmp_string + "/";
            }

            if (schema_path == null)
                return @"$schema_id:$parent_path $name";
            return @"$schema_id $name";
        }
    }

    internal GSettingsKey (string parent_full_name, string name, GLib.Settings settings, string schema_id, string? schema_path, string summary, string description, string type_string, Variant default_value, RangeType range_type, Variant range_content)
    {
        string? summary_nullable = summary.locale_to_utf8 (-1, null, null, null);
        summary = summary_nullable ?? summary;

        string? description_nullable = description.locale_to_utf8 (-1, null, null, null);
        description = description_nullable ?? description;

        Object (schema_id: schema_id,
                full_name: parent_full_name + name,
                name: name,
                settings : settings,
                // schema infos
                schema_path: schema_path,
                summary: summary,
                description: description,
                type_string: type_string,
                default_value: default_value,       // TODO devel default/admin default
                range_type: range_type,
                range_content: range_content);
    }

    private ulong settings_changed_handler = 0;
    internal void connect_settings ()
        requires (settings_changed_handler == 0)
    {
        settings_changed_handler = settings.changed [name].connect (() => value_changed ());
    }
    internal void disconnect_settings ()
        requires (settings_changed_handler != 0)
    {
        settings.disconnect (settings_changed_handler);
        settings_changed_handler = 0;
    }

    internal static void _get_key_fixed_properties (GSettingsKey gkey, PropertyQuery query, ref RegistryVariantDict variantdict)
    {
        bool all_properties_queried = query == 0;

        if (all_properties_queried || PropertyQuery.HAS_SCHEMA      in query)
            variantdict.insert_value (PropertyQuery.HAS_SCHEMA,                 new Variant.boolean (true));
        if (all_properties_queried || PropertyQuery.KEY_NAME        in query)
            variantdict.insert_value (PropertyQuery.KEY_NAME,                   new Variant.string (gkey.name));
        if (all_properties_queried || PropertyQuery.TYPE_CODE       in query)
            variantdict.insert_value (PropertyQuery.TYPE_CODE,                  new Variant.string (gkey.type_string));

        if (all_properties_queried || PropertyQuery.FIXED_SCHEMA    in query)
            variantdict.insert_value (PropertyQuery.FIXED_SCHEMA,               new Variant.boolean (gkey.schema_path != null));
        if (all_properties_queried || PropertyQuery.SUMMARY         in query)
            variantdict.insert_value (PropertyQuery.SUMMARY,                    new Variant.string (gkey.summary));
        if (all_properties_queried || PropertyQuery.DESCRIPTION     in query)
            variantdict.insert_value (PropertyQuery.DESCRIPTION,                new Variant.string (gkey.description));
        if (all_properties_queried || PropertyQuery.SCHEMA_ID       in query)
            variantdict.insert_value (PropertyQuery.SCHEMA_ID,                  new Variant.string (gkey.schema_id));
        if (all_properties_queried || PropertyQuery.DEFAULT_VALUE   in query)
            variantdict.insert_value (PropertyQuery.DEFAULT_VALUE,              new Variant.string (cool_text_value_from_variant (gkey.default_value)));
        if (all_properties_queried || PropertyQuery.RANGE_TYPE      in query)
            variantdict.insert_value (PropertyQuery.RANGE_TYPE,                 new Variant.byte ((uint8) gkey.range_type));
        if (all_properties_queried || PropertyQuery.RANGE_CONTENT   in query)
            variantdict.insert_value (PropertyQuery.RANGE_CONTENT,              new Variant.variant (gkey.range_content));

        if (show_min_and_max (gkey.type_string)
         && (all_properties_queried || PropertyQuery.MINIMUM in query || PropertyQuery.MAXIMUM in query))
        {
            string min, max;
            if (gkey.range_type == RangeType.RANGE)     // TODO test more; and what happen if only min/max is in range?
            {
                min = cool_text_value_from_variant (gkey.range_content.get_child_value (0));
                max = cool_text_value_from_variant (gkey.range_content.get_child_value (1));
            }
            else
                get_min_and_max_string (out min, out max, gkey.type_string);

            variantdict.insert_value (PropertyQuery.MINIMUM,                    new Variant.string (min));
            variantdict.insert_value (PropertyQuery.MAXIMUM,                    new Variant.string (max));
        }
    }
}

private string get_defined_by (bool has_schema, bool fixed_schema = false)
{
    if (fixed_schema)
        /* Translators: field content when displaying key properties; the field description is "Defined by", this text is displayed if the key is defined by a schema, and if this schema has a fixed path (it is not relocatable) */
        return _("Schema with path");

    if (has_schema)
        /* Translators: field content when displaying key properties; the field description is "Defined by", this text is displayed if the key is defined by a schema, and if this schema is relocatable (it has not a fixed path) */
        return _("Relocatable schema");

    /* Translators: field content when displaying key properties; the field description is "Defined by", this text is displayed if the key is not defined by a schema (the value is given by dconf but cannot be used by the GSettings functions) */
    return _("DConf backend");
}
